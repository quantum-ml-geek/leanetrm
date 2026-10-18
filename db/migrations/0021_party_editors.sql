-- Scoped append-only party maintenance. Trading consumers keep exact revisions.
BEGIN;
SELECT pg_advisory_xact_lock(730849102);
INSERT INTO security.permissions VALUES('ReadTradeParties'),('WriteTradeParties');
INSERT INTO security.role_permissions SELECT id,'ReadTradeParties' FROM security.roles WHERE code IN('trader','risk_analyst','market_data_editor');
INSERT INTO security.role_permissions SELECT id,'WriteTradeParties' FROM security.roles WHERE code='market_data_editor';

CREATE TABLE trading.party_operations (
 catalog_id uuid NOT NULL,operation_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),
 request jsonb NOT NULL,publication_order integer NOT NULL,
 legal_entity_id uuid,legal_entity_revision integer,counterparty_id uuid,counterparty_revision integer,
 PRIMARY KEY(catalog_id,operation_id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order),
 FOREIGN KEY(catalog_id,legal_entity_id,legal_entity_revision) REFERENCES trading.legal_entities(catalog_id,id,revision),
 FOREIGN KEY(catalog_id,counterparty_id,counterparty_revision) REFERENCES trading.counterparties(catalog_id,id,revision),
 CHECK((legal_entity_id IS NOT NULL AND legal_entity_revision IS NOT NULL AND counterparty_id IS NULL AND counterparty_revision IS NULL) OR
       (counterparty_id IS NOT NULL AND counterparty_revision IS NOT NULL AND legal_entity_id IS NULL AND legal_entity_revision IS NULL))
);
ALTER TABLE trading.party_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading.party_operations FORCE ROW LEVEL SECURITY;
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.party_operations FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
GRANT SELECT,INSERT ON trading.party_operations TO openetrm_security_owner;
GRANT INSERT ON trading.legal_entities,trading.counterparties TO openetrm_security_owner;

CREATE FUNCTION security.trade_party_versions(catalog uuid,kind text,as_of timestamptz) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTradeParties') THEN RAISE EXCEPTION 'No party read access' USING ERRCODE='42501'; END IF;
 IF kind IS NULL OR kind NOT IN('legal_entity','counterparty') OR as_of IS NULL OR NOT isfinite(as_of) THEN RAISE EXCEPTION 'party_input' USING ERRCODE='P0001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM security.request_contexts c
 JOIN market_data.temporal_contexts t ON(t.catalog_id,t.id)=(c.market_catalog_id,c.market_context_id)
 JOIN trading.contexts x ON(x.catalog_id,x.context_id)=(t.catalog_id,t.id)
 WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user
 AND t.catalog_id=catalog AND t.effective_on=(as_of AT TIME ZONE 'UTC')::date)
 THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'revision',p.revision,'code',p.code,'name',p.name,
   'effectiveAt',p.effective_at,'knownAt',k.known_from) ORDER BY p.code,p.revision DESC),'[]'::jsonb) INTO result
 FROM(SELECT * FROM trading.legal_entities WHERE kind='legal_entity' UNION ALL
      SELECT * FROM trading.counterparties WHERE kind='counterparty')p
 JOIN trading.knowledge_receipts k ON(k.catalog_id,k.publication_order)=(p.catalog_id,p.publication_order)
 JOIN security.request_contexts c ON c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user
 JOIN market_data.temporal_contexts t ON(t.catalog_id,t.id)=(c.market_catalog_id,c.market_context_id)
 JOIN trading.contexts x ON(x.catalog_id,x.context_id)=(t.catalog_id,t.id)
 WHERE p.catalog_id=catalog AND p.effective_at<=as_of AND p.publication_order<=x.known_through AND k.known_from<=t.known_at;
 RETURN result;
END $$;

CREATE FUNCTION security.save_trade_party(catalog uuid,operation uuid,kind text,party uuid,expected integer,code text,name text,effective timestamptz) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts;prior trading.party_operations;request_value jsonb;table_name text;
 head record;party_id uuid;version integer;ordinal integer;result jsonb;duplicate_code boolean;
BEGIN
 IF NOT security.trading_access(catalog,'WriteTradeParties') THEN RAISE EXCEPTION 'No party write access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF NOT security.trading_access(catalog,'WriteTradeParties') THEN RAISE EXCEPTION 'Party write access expired' USING ERRCODE='42501'; END IF;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR kind IS NULL OR kind NOT IN('legal_entity','counterparty') OR
   (party IS NULL)<>(expected IS NULL) OR expected<1 OR party='00000000-0000-0000-0000-000000000000'::uuid OR
   code IS NULL OR code !~ '^[a-z][a-z0-9_]{0,47}$' OR name IS NULL OR name<>btrim(name) OR length(name) NOT BETWEEN 1 AND 80 OR name ~ '[[:cntrl:]]' OR
   effective IS NULL OR NOT isfinite(effective) OR effective<TIMESTAMPTZ '1901-01-01' OR effective>=TIMESTAMPTZ '2200-01-01'
 THEN RAISE EXCEPTION 'party_input' USING ERRCODE='P0001'; END IF;
 request_value=jsonb_build_object('kind',kind,'id',party,'expectedRevision',expected,'code',code,'name',name,'effectiveAt',effective AT TIME ZONE 'UTC');
 table_name=CASE kind WHEN 'legal_entity' THEN 'legal_entities' ELSE 'counterparties' END;
 SELECT * INTO prior FROM trading.party_operations WHERE catalog_id=catalog AND operation_id=operation;
 IF FOUND THEN
  IF prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'party_conflict' USING ERRCODE='P0001'; END IF;
  party_id=coalesce(prior.legal_entity_id,prior.counterparty_id);version=coalesce(prior.legal_entity_revision,prior.counterparty_revision);
 ELSE
  party_id=coalesce(party,gen_random_uuid());version=1;
  IF party IS NOT NULL THEN
   EXECUTE format('SELECT * FROM trading.%I WHERE catalog_id=$1 AND id=$2 ORDER BY revision DESC LIMIT 1',table_name) INTO head USING catalog,party;
   IF head.id IS NULL OR head.revision<>expected OR head.code<>code THEN RAISE EXCEPTION 'party_conflict' USING ERRCODE='P0001'; END IF;
   IF effective<head.effective_at OR(head.name=name AND head.effective_at=effective) THEN RAISE EXCEPTION 'party_input' USING ERRCODE='P0001'; END IF;
   IF head.revision>=256 THEN RAISE EXCEPTION 'party_limit' USING ERRCODE='P0001'; END IF;
   version=head.revision+1;
  END IF;
  EXECUTE format('SELECT EXISTS(SELECT 1 FROM trading.%I WHERE catalog_id=$1 AND code=$2 AND id<>$3)',table_name) INTO duplicate_code USING catalog,code,party_id;
  IF duplicate_code THEN RAISE EXCEPTION 'party_conflict' USING ERRCODE='P0001'; END IF;
  EXECUTE format('SELECT count(*) FROM trading.%I WHERE catalog_id=$1',table_name) INTO ordinal USING catalog;
  IF ordinal>=4096 THEN RAISE EXCEPTION 'party_limit' USING ERRCODE='P0001'; END IF;
  SELECT coalesce(max(publication_order),0)+1 INTO ordinal FROM trading.publications WHERE catalog_id=catalog;
  INSERT INTO trading.publications VALUES(catalog,ordinal,pg_current_xact_id());
  EXECUTE format('INSERT INTO trading.%I VALUES($1,$2,$3,$4,$5,$6,$7)',table_name) USING catalog,party_id,version,code,name,ordinal,effective;
  INSERT INTO trading.party_operations VALUES(catalog,operation,c.actor_id,request_value,ordinal,
   CASE WHEN kind='legal_entity' THEN party_id END,CASE WHEN kind='legal_entity' THEN version END,
   CASE WHEN kind='counterparty' THEN party_id END,CASE WHEN kind='counterparty' THEN version END);
 END IF;
 EXECUTE format('SELECT jsonb_build_object(''id'',id,''revision'',revision,''code'',code,''name'',name,''effectiveAt'',effective_at) FROM trading.%I WHERE catalog_id=$1 AND id=$2 AND revision=$3',table_name)
 INTO result USING catalog,party_id,version;
 IF NOT security.trading_access(catalog,'WriteTradeParties') THEN RAISE EXCEPTION 'Party write access expired' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;
ALTER FUNCTION security.trade_party_versions(uuid,text,timestamptz) OWNER TO openetrm_security_owner;
ALTER FUNCTION security.save_trade_party(uuid,uuid,text,uuid,integer,text,text,timestamptz) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.trade_party_versions(uuid,text,timestamptz),security.save_trade_party(uuid,uuid,text,uuid,integer,text,text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.trade_party_versions(uuid,text,timestamptz),security.save_trade_party(uuid,uuid,text,uuid,integer,text,text,timestamptz) TO openetrm_runtime;
COMMIT;
