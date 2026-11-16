-- Manually evidenced certificate identity and ownership. No registry submission,
-- automatic issuance, inventory costing or conversion of modeled energy.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT 1 FROM security.epoch WHERE id=true FOR UPDATE;
SELECT pg_advisory_xact_lock(730849102);
INSERT INTO security.permissions VALUES('ReadRecInventory'),('RecordRecInventory'),('ConfigureRecInventory');

-- A registry is explicitly selected as an evidence source by a program. Sources
-- are never inferred to be registries merely because they exist in the catalog.
CREATE TABLE ref_data.rec_programs(
 catalog_id uuid NOT NULL,revision_id uuid NOT NULL,code ref_data.code NOT NULL,name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 120),
 registry_code ref_data.code NOT NULL,
 PRIMARY KEY(catalog_id,revision_id,code),UNIQUE(catalog_id,revision_id,code,registry_code),
 FOREIGN KEY(catalog_id,revision_id,registry_code) REFERENCES ref_data.sources(catalog_id,revision_id,code)
);
CREATE TABLE ref_data.rec_classes(
 catalog_id uuid NOT NULL,revision_id uuid NOT NULL,code ref_data.code NOT NULL,name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 120),
 program_code ref_data.code NOT NULL,
 PRIMARY KEY(catalog_id,revision_id,code),UNIQUE(catalog_id,revision_id,code,program_code),
 FOREIGN KEY(catalog_id,revision_id,program_code) REFERENCES ref_data.rec_programs(catalog_id,revision_id,code)
);
CREATE TABLE ref_data.rec_technologies(
 catalog_id uuid NOT NULL,revision_id uuid NOT NULL,code ref_data.code NOT NULL,name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 120),
 PRIMARY KEY(catalog_id,revision_id,code),FOREIGN KEY(catalog_id,revision_id) REFERENCES ref_data.revisions(catalog_id,id)
);
CREATE TABLE ref_data.rec_retirement_purposes(
 catalog_id uuid NOT NULL,revision_id uuid NOT NULL,code ref_data.code NOT NULL,name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 120),
 PRIMARY KEY(catalog_id,revision_id,code),FOREIGN KEY(catalog_id,revision_id) REFERENCES ref_data.revisions(catalog_id,id)
);
CREATE TABLE ref_data.rec_products(
 catalog_id uuid NOT NULL,revision_id uuid NOT NULL,code ref_data.code NOT NULL,name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 120),
 program_code ref_data.code NOT NULL,class_code ref_data.code NOT NULL,technology_code ref_data.code NOT NULL,
 geography_code ref_data.code NOT NULL,quantity_code ref_data.code NOT NULL,
 PRIMARY KEY(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,revision_id,class_code,program_code) REFERENCES ref_data.rec_classes(catalog_id,revision_id,code,program_code),
 FOREIGN KEY(catalog_id,revision_id,technology_code) REFERENCES ref_data.rec_technologies(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,revision_id,geography_code) REFERENCES ref_data.locations(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,revision_id,quantity_code) REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code)
);
CREATE FUNCTION ref_data.require_rec_product() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM ref_data.quantity_specifications q JOIN ref_data.dimensions d
  ON(d.catalog_id,d.revision_id,d.code)=(q.catalog_id,q.revision_id,q.dimension_code)
  WHERE(q.catalog_id,q.revision_id,q.code)=(NEW.catalog_id,NEW.revision_id,NEW.quantity_code) AND q.unit_code='rec'
  AND(d.mass_power,d.length_power,d.time_power,d.temperature_power,d.amount_power,d.current_power,d.luminous_power)=(0,0,0,0,0,0,0))
 THEN RAISE EXCEPTION 'rec_quantity';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER require_rec_product BEFORE INSERT ON ref_data.rec_products FOR EACH ROW EXECUTE FUNCTION ref_data.require_rec_product();
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['rec_programs','rec_classes','rec_technologies','rec_retirement_purposes','rec_products'] LOOP
  EXECUTE format('CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.%I FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition()',t);
  EXECUTE format('ALTER TABLE ref_data.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE ref_data.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY scoped_read ON ref_data.%I FOR SELECT TO openetrm_runtime USING(security.reference_access(catalog_id,''ReadMarketData'') AND security.reference_version_visible(catalog_id,revision_id))',t);
  EXECUTE format('CREATE POLICY scoped_insert ON ref_data.%I FOR INSERT TO openetrm_runtime WITH CHECK(security.reference_access(catalog_id,''WriteReferenceData''))',t);
  EXECUTE format('GRANT SELECT,INSERT ON ref_data.%I TO openetrm_runtime,openetrm_security_owner',t);
 END LOOP;
END$$;

-- The pricing contract's delivery period and the eligible generation vintage
-- are independent, explicitly selected relationships.
CREATE TABLE market_data.rec_valuation_assignments(
 catalog_id uuid NOT NULL,revision_id uuid NOT NULL,code ref_data.code NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,product_code ref_data.code NOT NULL,
 vintage_from date NOT NULL,vintage_to date NOT NULL,curve_code ref_data.code NOT NULL,contract_id uuid NOT NULL,
 implementation text NOT NULL CHECK(implementation='exact_product_vintage_flat_v1'),
 PRIMARY KEY(catalog_id,revision_id,code),
 UNIQUE(catalog_id,revision_id,code,reference_catalog_id,reference_revision_id,product_code,vintage_from,vintage_to),
 CHECK(vintage_from>=DATE '1901-01-01' AND vintage_to<=DATE '2199-12-31' AND vintage_from<vintage_to),
 FOREIGN KEY(catalog_id,revision_id,reference_catalog_id,reference_revision_id) REFERENCES market_data.revisions(catalog_id,id,reference_catalog_id,reference_revision_id),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,product_code) REFERENCES ref_data.rec_products(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,revision_id,curve_code,contract_id) REFERENCES market_data.curve_members(catalog_id,revision_id,curve_code,contract_id)
);
CREATE FUNCTION market_data.require_rec_assignment() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM ref_data.rec_products p JOIN market_data.curves c
  ON(c.catalog_id,c.revision_id,c.code)=(NEW.catalog_id,NEW.revision_id,NEW.curve_code)
  JOIN ref_data.quote_specifications q ON(q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code)
  WHERE(p.catalog_id,p.revision_id,p.code)=(NEW.reference_catalog_id,NEW.reference_revision_id,NEW.product_code)
   AND q.quantity_code=p.quantity_code AND q.kind='outright') THEN RAISE EXCEPTION 'rec_mark';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER require_assignment BEFORE INSERT ON market_data.rec_valuation_assignments FOR EACH ROW EXECUTE FUNCTION market_data.require_rec_assignment();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.rec_valuation_assignments FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
ALTER TABLE market_data.rec_valuation_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_data.rec_valuation_assignments FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON market_data.rec_valuation_assignments FOR SELECT TO openetrm_runtime
 USING(security.market_access(catalog_id,'ReadMarketData') AND security.market_fact_visible(catalog_id,revision_id,NULL));
CREATE POLICY scoped_insert ON market_data.rec_valuation_assignments FOR INSERT TO openetrm_runtime WITH CHECK(security.market_access(catalog_id,'WriteMarketDefinitions'));
GRANT SELECT,INSERT ON market_data.rec_valuation_assignments TO openetrm_runtime,openetrm_security_owner;

CREATE TABLE trading.rec_forward_instruments(
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,definition_revision_id uuid NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,assignment_code ref_data.code NOT NULL,product_code ref_data.code NOT NULL,
 vintage_from date NOT NULL,vintage_to date NOT NULL,delivery_from ref_data.instant NOT NULL,delivery_to ref_data.instant NOT NULL,
 consideration_quote_code ref_data.code NOT NULL,consideration_mode text NOT NULL CHECK(consideration_mode IN('fixed','selected_contract_flat_v1')),
 fixed_price ref_data.exact_number CHECK(abs(fixed_price)<1e12),consideration_curve_code ref_data.code,consideration_contract_id uuid,
 payment_rule jsonb NOT NULL,calendar_policy jsonb NOT NULL,discounting boolean NOT NULL CHECK(NOT discounting),terms jsonb NOT NULL,
 PRIMARY KEY(catalog_id,instrument_id),
 UNIQUE(catalog_id,instrument_id,reference_catalog_id,reference_revision_id,product_code,vintage_from,vintage_to,delivery_from,delivery_to),
 CHECK(delivery_to-delivery_from=interval '1 day' AND delivery_from=date_trunc('day',delivery_from AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'),
 CHECK((consideration_mode='fixed')=(fixed_price IS NOT NULL)),
 CHECK((consideration_curve_code IS NULL)=(consideration_contract_id IS NULL)),
 CHECK((consideration_mode='selected_contract_flat_v1')=(consideration_curve_code IS NOT NULL)),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.instruments(catalog_id,id),
 FOREIGN KEY(catalog_id,definition_revision_id,assignment_code,reference_catalog_id,reference_revision_id,product_code,vintage_from,vintage_to)
  REFERENCES market_data.rec_valuation_assignments(catalog_id,revision_id,code,reference_catalog_id,reference_revision_id,product_code,vintage_from,vintage_to),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,consideration_quote_code) REFERENCES ref_data.quote_specifications(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,definition_revision_id,consideration_curve_code,consideration_contract_id) REFERENCES market_data.curve_members(catalog_id,revision_id,curve_code,contract_id)
);
CREATE TABLE trading.rec_forward_memberships(
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,slot integer NOT NULL CHECK(slot IN(0,1)),side_id uuid NOT NULL,
 coefficient integer NOT NULL CHECK(coefficient IN(-1,1)),
 PRIMARY KEY(catalog_id,instrument_id,slot),UNIQUE(catalog_id,instrument_id,slot,side_id),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.rec_forward_instruments(catalog_id,instrument_id),
 FOREIGN KEY(catalog_id,side_id) REFERENCES trading.sides(catalog_id,id)
);
CREATE TABLE trading.rec_forward_trade_revisions(
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,revision integer NOT NULL CHECK(revision=1),instrument_id uuid NOT NULL,book_id uuid NOT NULL,
 operation_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),quantity ref_data.exact_number NOT NULL CHECK(quantity>0 AND quantity=trunc(quantity)),
 physical_direction integer NOT NULL CHECK(physical_direction IN(-1,1)),cash_direction integer NOT NULL,CHECK(cash_direction=-physical_direction),
 trade_date date NOT NULL,legal_entity_id uuid NOT NULL,legal_entity_revision integer NOT NULL,counterparty_id uuid NOT NULL,counterparty_revision integer NOT NULL,
 publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,trade_id,revision),UNIQUE(catalog_id,trade_id,revision,instrument_id),UNIQUE(catalog_id,operation_id),
 FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.trades(catalog_id,id),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.rec_forward_instruments(catalog_id,instrument_id),
 FOREIGN KEY(catalog_id,book_id) REFERENCES trading.books(catalog_id,id),
 FOREIGN KEY(catalog_id,legal_entity_id,legal_entity_revision) REFERENCES trading.legal_entities(catalog_id,id,revision),
 FOREIGN KEY(catalog_id,counterparty_id,counterparty_revision) REFERENCES trading.counterparties(catalog_id,id,revision),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.rec_deliveries(
 catalog_id uuid NOT NULL,id uuid NOT NULL,trade_id uuid NOT NULL,trade_revision integer NOT NULL,instrument_id uuid NOT NULL,
 slot integer NOT NULL CHECK(slot=0),side_id uuid NOT NULL,schedule_id uuid NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,product_code ref_data.code NOT NULL,
 vintage_from date NOT NULL,vintage_to date NOT NULL,quantity ref_data.exact_number NOT NULL CHECK(quantity>0 AND quantity=trunc(quantity)),
 delivery_from ref_data.instant NOT NULL,delivery_to ref_data.instant NOT NULL,physical_direction integer NOT NULL CHECK(physical_direction IN(-1,1)),
 PRIMARY KEY(catalog_id,id),UNIQUE(catalog_id,trade_id,trade_revision,slot),
 FOREIGN KEY(catalog_id,trade_id,trade_revision,instrument_id) REFERENCES trading.rec_forward_trade_revisions(catalog_id,trade_id,revision,instrument_id),
 FOREIGN KEY(catalog_id,instrument_id,slot,side_id) REFERENCES trading.rec_forward_memberships(catalog_id,instrument_id,slot,side_id),
 FOREIGN KEY(catalog_id,schedule_id) REFERENCES trading.side_schedules(catalog_id,id),
 FOREIGN KEY(catalog_id,instrument_id,slot) REFERENCES trading.instrument_side_schedules(catalog_id,instrument_id,slot) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(catalog_id,instrument_id,reference_catalog_id,reference_revision_id,product_code,vintage_from,vintage_to,delivery_from,delivery_to)
  REFERENCES trading.rec_forward_instruments(catalog_id,instrument_id,reference_catalog_id,reference_revision_id,product_code,vintage_from,vintage_to,delivery_from,delivery_to)
);
CREATE FUNCTION trading.require_rec_delivery_membership() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM trading.instrument_side_schedules s JOIN trading.rec_forward_trade_revisions r
  ON(r.catalog_id,r.trade_id,r.revision)=(NEW.catalog_id,NEW.trade_id,NEW.trade_revision)
  WHERE(s.catalog_id,s.instrument_id,s.slot,s.side_id,s.schedule_id)=(NEW.catalog_id,NEW.instrument_id,NEW.slot,NEW.side_id,NEW.schedule_id)
   AND(r.quantity,r.physical_direction)=(NEW.quantity,NEW.physical_direction)) THEN RAISE EXCEPTION 'rec_delivery_membership';END IF;
 RETURN NULL;
END$$;
CREATE CONSTRAINT TRIGGER require_delivery_membership AFTER INSERT ON trading.rec_deliveries DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION trading.require_rec_delivery_membership();
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['rec_forward_instruments','rec_forward_memberships','rec_forward_trade_revisions','rec_deliveries'] LOOP
  EXECUTE format('ALTER TABLE trading.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE trading.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON trading.%I FROM PUBLIC,openetrm_runtime',t);
  EXECUTE format('GRANT SELECT,INSERT ON trading.%I TO openetrm_security_owner',t);
  EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.%I FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt()',t);
 END LOOP;
END$$;

CREATE TABLE trading.rec_inventory_accounts(
 catalog_id uuid NOT NULL,id uuid NOT NULL,book_id uuid NOT NULL,legal_entity_id uuid NOT NULL,legal_entity_revision integer NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,registry_code ref_data.code NOT NULL,
 registry_account_reference text NOT NULL CHECK(length(registry_account_reference) BETWEEN 1 AND 128 AND registry_account_reference=btrim(registry_account_reference)),
 actor_id uuid NOT NULL REFERENCES security.principals(id),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),UNIQUE(catalog_id,reference_catalog_id,registry_code,registry_account_reference),
 FOREIGN KEY(catalog_id,book_id) REFERENCES trading.books(catalog_id,id),
 FOREIGN KEY(catalog_id,legal_entity_id,legal_entity_revision) REFERENCES trading.legal_entities(catalog_id,id,revision),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,registry_code) REFERENCES ref_data.sources(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.rec_inventory_destinations(
 catalog_id uuid NOT NULL,id uuid NOT NULL,counterparty_id uuid NOT NULL,counterparty_revision integer NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,registry_code ref_data.code NOT NULL,
 registry_account_reference text NOT NULL CHECK(length(registry_account_reference) BETWEEN 1 AND 128 AND registry_account_reference=btrim(registry_account_reference)),
 actor_id uuid NOT NULL REFERENCES security.principals(id),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),UNIQUE(catalog_id,reference_catalog_id,registry_code,registry_account_reference),
 FOREIGN KEY(catalog_id,counterparty_id,counterparty_revision) REFERENCES trading.counterparties(catalog_id,id,revision),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,registry_code) REFERENCES ref_data.sources(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.rec_inventory_commands(
 catalog_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),request_id uuid NOT NULL,
 account_id uuid,destination_id uuid,kind text NOT NULL,request jsonb NOT NULL CHECK(pg_column_size(request)<=32768),outcome jsonb NOT NULL,
 PRIMARY KEY(catalog_id,actor_id,request_id),
 FOREIGN KEY(catalog_id,account_id) REFERENCES trading.rec_inventory_accounts(catalog_id,id),
 FOREIGN KEY(catalog_id,destination_id) REFERENCES trading.rec_inventory_destinations(catalog_id,id),
 CHECK(num_nonnulls(account_id,destination_id)=1)
);
CREATE TABLE trading.rec_inventory_lots(
 catalog_id uuid NOT NULL,id uuid NOT NULL,reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,
 registry_code ref_data.code NOT NULL,registry_lot_reference text NOT NULL CHECK(length(registry_lot_reference) BETWEEN 1 AND 128 AND registry_lot_reference=btrim(registry_lot_reference)),
 product_code ref_data.code NOT NULL,vintage_from date NOT NULL,vintage_to date NOT NULL,
 publication_order integer NOT NULL,
 PRIMARY KEY(catalog_id,id),UNIQUE(catalog_id,reference_catalog_id,registry_code,registry_lot_reference),
 CHECK(vintage_from>=DATE '1901-01-01' AND vintage_to<=DATE '2199-12-31' AND vintage_from<vintage_to),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,product_code) REFERENCES ref_data.rec_products(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,registry_code) REFERENCES ref_data.sources(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.rec_inventory_facts(
 catalog_id uuid NOT NULL,account_id uuid NOT NULL,business_id uuid NOT NULL,revision integer NOT NULL CHECK(revision>0),
 generation integer NOT NULL CHECK(generation BETWEEN 1 AND 4096),first_publication integer NOT NULL,
 kind text NOT NULL CHECK(kind IN('receipt','allocate','release','transfer','retire')),lot_id uuid NOT NULL,
 serial_from bigint NOT NULL CHECK(serial_from>=0),serial_to bigint NOT NULL,CHECK(serial_from<serial_to),
 receipt_kind text CHECK(receipt_kind IN('issuance','incoming_transfer')),
 beneficiary_entity_id uuid,beneficiary_entity_revision integer,beneficiary_counterparty_id uuid,beneficiary_counterparty_revision integer,
 delivery_id uuid,allocation_id uuid,allocation_revision integer,destination_id uuid,
 purpose_code ref_data.code,evidence_source ref_data.code,evidence_reference text CHECK(length(evidence_reference) BETWEEN 1 AND 500 AND evidence_reference=btrim(evidence_reference)),
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),
 publication_order integer NOT NULL,publication_xid xid8 NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,account_id,business_id,revision),UNIQUE(catalog_id,account_id,generation),
 -- This command profile admits one fact per account/transaction. Atomic
 -- batches require a separately declared publication and replay contract.
 UNIQUE(catalog_id,account_id,publication_xid),
 CHECK((kind='receipt')=(receipt_kind IS NOT NULL)),
 CHECK((kind='allocate')=(delivery_id IS NOT NULL)),
 CHECK((kind IN('release','transfer'))=(allocation_id IS NOT NULL)),
 CHECK((allocation_id IS NULL)=(allocation_revision IS NULL)),
 CHECK((kind='transfer')=(destination_id IS NOT NULL)),
 CHECK((kind IN('receipt','transfer','retire'))=(evidence_source IS NOT NULL)),
 CHECK((evidence_source IS NULL)=(evidence_reference IS NULL)),
 CHECK((kind='retire')=(num_nonnulls(beneficiary_entity_id,beneficiary_counterparty_id)=1)),
 CHECK((beneficiary_entity_id IS NULL)=(beneficiary_entity_revision IS NULL)),
 CHECK((beneficiary_counterparty_id IS NULL)=(beneficiary_counterparty_revision IS NULL)),
 CHECK((kind='retire')=(purpose_code IS NOT NULL)),
 FOREIGN KEY(catalog_id,account_id) REFERENCES trading.rec_inventory_accounts(catalog_id,id),
 FOREIGN KEY(catalog_id,lot_id) REFERENCES trading.rec_inventory_lots(catalog_id,id),
 FOREIGN KEY(catalog_id,account_id,allocation_id,allocation_revision) REFERENCES trading.rec_inventory_facts(catalog_id,account_id,business_id,revision),
 FOREIGN KEY(catalog_id,delivery_id) REFERENCES trading.rec_deliveries(catalog_id,id),
 FOREIGN KEY(catalog_id,destination_id) REFERENCES trading.rec_inventory_destinations(catalog_id,id),
 FOREIGN KEY(catalog_id,beneficiary_entity_id,beneficiary_entity_revision) REFERENCES trading.legal_entities(catalog_id,id,revision),
 FOREIGN KEY(catalog_id,beneficiary_counterparty_id,beneficiary_counterparty_revision) REFERENCES trading.counterparties(catalog_id,id,revision),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,purpose_code) REFERENCES ref_data.rec_retirement_purposes(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,evidence_source) REFERENCES ref_data.sources(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order,publication_xid) REFERENCES trading.publications(catalog_id,publication_order,publication_xid),
 FOREIGN KEY(catalog_id,first_publication) REFERENCES trading.publications(catalog_id,publication_order)
);
ALTER TABLE trading.rec_inventory_commands ADD COLUMN fact_id uuid,ADD COLUMN fact_revision integer,
 ADD FOREIGN KEY(catalog_id,account_id,fact_id,fact_revision) REFERENCES trading.rec_inventory_facts(catalog_id,account_id,business_id,revision),
 ADD CHECK((fact_id IS NULL)=(fact_revision IS NULL));
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['rec_inventory_accounts','rec_inventory_destinations','rec_inventory_commands','rec_inventory_lots','rec_inventory_facts'] LOOP
  EXECUTE format('ALTER TABLE trading.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE trading.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON trading.%I FROM PUBLIC,openetrm_runtime',t);
  EXECUTE format('GRANT SELECT,INSERT ON trading.%I TO openetrm_security_owner',t);
  EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.%I FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt()',t);
 END LOOP;
END$$;

CREATE FUNCTION security.require_rec_inventory(catalog uuid,writing boolean,configuring boolean DEFAULT false) RETURNS uuid
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;BEGIN
 PERFORM 1 FROM security.epoch WHERE id=true FOR SHARE;
 IF security.trading_access(catalog,'ReadTrades') IS NOT TRUE OR security.trading_access(catalog,'ReadRecInventory') IS NOT TRUE
 OR(writing AND NOT configuring AND security.trading_access(catalog,'RecordRecInventory') IS NOT TRUE)
 OR(configuring AND security.trading_access(catalog,'ConfigureRecInventory') IS NOT TRUE)
 THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
 IF writing AND security.current_write_context() IS NOT TRUE THEN RAISE EXCEPTION 'historical_read_only';END IF;
 SELECT actor_id INTO actor FROM security.request_contexts q WHERE q.backend_pid=pg_backend_pid()
  AND q.transaction_id=pg_current_xact_id_if_assigned() AND q.runtime_login=session_user AND q.expires_at>clock_timestamp();
 IF actor IS NULL THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
 RETURN actor;
END$$;
CREATE FUNCTION trading.rec_keys(value jsonb,keys text[]) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_typeof(value)='object' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(value)k)=
  (SELECT array_agg(k ORDER BY k) FROM unnest(keys)k)
$$;
CREATE FUNCTION security.rec_inventory_owner(catalog uuid) RETURNS text
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM security.require_rec_inventory(catalog,false,false);
 RETURN presentation.preference_owner(security.presentation_actor(),'rec:'||catalog::text);
END$$;
CREATE FUNCTION security.configure_rec_account(catalog uuid,operation uuid,body jsonb,at_time timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;request jsonb;prior trading.rec_inventory_commands;a trading.rec_inventory_accounts;result jsonb;publication integer;BEGIN
 actor=security.require_rec_inventory(catalog,true,true);
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000' OR at_time IS NULL OR NOT isfinite(at_time) OR at_time>clock_timestamp()
 OR pg_column_size(body)>8192 OR trading.rec_keys(body,ARRAY['accountId','bookId','legalEntityId','legalEntityRevision','referenceCatalogId','referenceRevisionId','registryCode','registryAccountReference']) IS NOT TRUE
 OR EXISTS(SELECT 1 FROM jsonb_each(body)e WHERE jsonb_typeof(e.value) IS DISTINCT FROM CASE WHEN e.key='legalEntityRevision' THEN 'number' ELSE 'string' END)
 OR (body->>'accountId')::uuid='00000000-0000-0000-0000-000000000000'
 OR jsonb_typeof(body->'legalEntityRevision') IS DISTINCT FROM 'number' OR (body->>'legalEntityRevision')::integer<=0
 OR length(body->>'registryAccountReference') NOT BETWEEN 1 AND 128 OR body->>'registryAccountReference' IS DISTINCT FROM btrim(body->>'registryAccountReference')
 THEN RAISE EXCEPTION 'rec_account_input';END IF;
 -- UUID/instant spelling is canonical, while the external registry reference
 -- remains exact and case-sensitive rather than silently rewritten.
 request=jsonb_build_object('kind','account','accountId',(body->>'accountId')::uuid,'bookId',(body->>'bookId')::uuid,
  'legalEntityId',(body->>'legalEntityId')::uuid,'legalEntityRevision',(body->>'legalEntityRevision')::integer,
  'referenceCatalogId',(body->>'referenceCatalogId')::uuid,'referenceRevisionId',(body->>'referenceRevisionId')::uuid,
  'registryCode',body->>'registryCode','registryAccountReference',body->>'registryAccountReference','effectiveAt',extract(epoch FROM at_time));
 PERFORM pg_advisory_xact_lock(730849102);
 PERFORM security.require_rec_inventory(catalog,true,true);
 SELECT * INTO prior FROM trading.rec_inventory_commands c WHERE(c.catalog_id,c.actor_id,c.request_id)=(catalog,actor,operation);
 IF FOUND THEN
  IF prior.request IS DISTINCT FROM request THEN RAISE EXCEPTION 'rec_request_conflict';END IF;
  SELECT * INTO a FROM trading.rec_inventory_accounts x WHERE(x.catalog_id,x.id)=(catalog,prior.account_id);
  IF security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
  PERFORM security.require_rec_inventory(catalog,true,true);RETURN prior.outcome;
 END IF;
 IF security.reference_access((body->>'referenceCatalogId')::uuid,'ReadMarketData') IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM ref_data.revisions r
  WHERE(r.catalog_id,r.id)=((body->>'referenceCatalogId')::uuid,(body->>'referenceRevisionId')::uuid) AND r.state='sealed')
 OR NOT EXISTS(SELECT 1 FROM trading.books b WHERE(b.catalog_id,b.id)=(catalog,(body->>'bookId')::uuid) AND b.effective_at<=at_time)
 OR NOT EXISTS(SELECT 1 FROM trading.legal_entities e WHERE(e.catalog_id,e.id,e.revision)=(catalog,(body->>'legalEntityId')::uuid,(body->>'legalEntityRevision')::integer) AND e.effective_at<=at_time)
 OR NOT EXISTS(SELECT 1 FROM ref_data.rec_programs g WHERE(g.catalog_id,g.revision_id,g.registry_code)=
  ((body->>'referenceCatalogId')::uuid,(body->>'referenceRevisionId')::uuid,body->>'registryCode'))
 THEN RAISE EXCEPTION 'rec_account_reference';END IF;
 SELECT * INTO a FROM trading.rec_inventory_accounts x WHERE(x.catalog_id,x.reference_catalog_id,x.registry_code,x.registry_account_reference)=
  (catalog,(body->>'referenceCatalogId')::uuid,body->>'registryCode',body->>'registryAccountReference');
 IF FOUND THEN
  IF(a.book_id,a.legal_entity_id,a.legal_entity_revision,a.reference_revision_id,a.effective_at) IS DISTINCT FROM
   ((body->>'bookId')::uuid,(body->>'legalEntityId')::uuid,(body->>'legalEntityRevision')::integer,(body->>'referenceRevisionId')::uuid,at_time)
  THEN RAISE EXCEPTION 'rec_account_conflict';END IF;
  result=jsonb_build_object('requestId',operation,'accountId',a.id,'changed',false);
 ELSE
  SELECT coalesce(max(publication_order),0)+1 INTO publication FROM trading.publications p WHERE p.catalog_id=catalog;
  INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());
  INSERT INTO trading.rec_inventory_accounts VALUES(catalog,(body->>'accountId')::uuid,(body->>'bookId')::uuid,(body->>'legalEntityId')::uuid,
   (body->>'legalEntityRevision')::integer,(body->>'referenceCatalogId')::uuid,(body->>'referenceRevisionId')::uuid,body->>'registryCode',body->>'registryAccountReference',actor,publication,at_time) RETURNING * INTO a;
  result=jsonb_build_object('requestId',operation,'accountId',a.id,'changed',true);
 END IF;
 IF security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
 PERFORM security.require_rec_inventory(catalog,true,true);
 INSERT INTO trading.rec_inventory_commands(catalog_id,actor_id,request_id,account_id,kind,request,outcome) VALUES(catalog,actor,operation,a.id,'account',request,result);
 RETURN result;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation OR foreign_key_violation THEN RAISE EXCEPTION 'rec_account_input';
END$$;

CREATE FUNCTION security.configure_rec_destination(catalog uuid,operation uuid,body jsonb,at_time timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;request jsonb;prior trading.rec_inventory_commands;a trading.rec_inventory_destinations;result jsonb;publication integer;BEGIN
 actor=security.require_rec_inventory(catalog,true,true);
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000' OR at_time IS NULL OR NOT isfinite(at_time) OR at_time>clock_timestamp()
 OR pg_column_size(body)>8192 OR trading.rec_keys(body,ARRAY['destinationId','counterpartyId','counterpartyRevision','referenceCatalogId','referenceRevisionId','registryCode','registryAccountReference']) IS NOT TRUE
 OR EXISTS(SELECT 1 FROM jsonb_each(body)e WHERE jsonb_typeof(e.value) IS DISTINCT FROM CASE WHEN e.key='counterpartyRevision' THEN 'number' ELSE 'string' END)
 OR (body->>'destinationId')::uuid='00000000-0000-0000-0000-000000000000'
 OR jsonb_typeof(body->'counterpartyRevision') IS DISTINCT FROM 'number' OR (body->>'counterpartyRevision')::integer<=0
 OR length(body->>'registryAccountReference') NOT BETWEEN 1 AND 128 OR body->>'registryAccountReference' IS DISTINCT FROM btrim(body->>'registryAccountReference')
 THEN RAISE EXCEPTION 'rec_account_input';END IF;
 -- UUID/instant spelling is canonical, while the external registry reference
 -- remains exact and case-sensitive rather than silently rewritten.
 request=jsonb_build_object('kind','destination','destinationId',(body->>'destinationId')::uuid,
  'counterpartyId',(body->>'counterpartyId')::uuid,'counterpartyRevision',(body->>'counterpartyRevision')::integer,
  'referenceCatalogId',(body->>'referenceCatalogId')::uuid,'referenceRevisionId',(body->>'referenceRevisionId')::uuid,
  'registryCode',body->>'registryCode','registryAccountReference',body->>'registryAccountReference','effectiveAt',extract(epoch FROM at_time));
 PERFORM pg_advisory_xact_lock(730849102);
 PERFORM security.require_rec_inventory(catalog,true,true);
 SELECT * INTO prior FROM trading.rec_inventory_commands c WHERE(c.catalog_id,c.actor_id,c.request_id)=(catalog,actor,operation);
 IF FOUND THEN
  IF prior.request IS DISTINCT FROM request THEN RAISE EXCEPTION 'rec_request_conflict';END IF;
  SELECT * INTO a FROM trading.rec_inventory_destinations x WHERE(x.catalog_id,x.id)=(catalog,prior.destination_id);
  IF security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
  PERFORM security.require_rec_inventory(catalog,true,true);RETURN prior.outcome;
 END IF;
 IF security.reference_access((body->>'referenceCatalogId')::uuid,'ReadMarketData') IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM ref_data.revisions r
  WHERE(r.catalog_id,r.id)=((body->>'referenceCatalogId')::uuid,(body->>'referenceRevisionId')::uuid) AND r.state='sealed')

 OR NOT EXISTS(SELECT 1 FROM trading.counterparties e WHERE(e.catalog_id,e.id,e.revision)=(catalog,(body->>'counterpartyId')::uuid,(body->>'counterpartyRevision')::integer) AND e.effective_at<=at_time)
 OR NOT EXISTS(SELECT 1 FROM ref_data.rec_programs g WHERE(g.catalog_id,g.revision_id,g.registry_code)=
  ((body->>'referenceCatalogId')::uuid,(body->>'referenceRevisionId')::uuid,body->>'registryCode'))
 THEN RAISE EXCEPTION 'rec_account_reference';END IF;
 SELECT * INTO a FROM trading.rec_inventory_destinations x WHERE(x.catalog_id,x.reference_catalog_id,x.registry_code,x.registry_account_reference)=
  (catalog,(body->>'referenceCatalogId')::uuid,body->>'registryCode',body->>'registryAccountReference');
 IF FOUND THEN
  IF(a.counterparty_id,a.counterparty_revision,a.reference_revision_id,a.effective_at) IS DISTINCT FROM
   ((body->>'counterpartyId')::uuid,(body->>'counterpartyRevision')::integer,(body->>'referenceRevisionId')::uuid,at_time)
  THEN RAISE EXCEPTION 'rec_account_conflict';END IF;
  result=jsonb_build_object('requestId',operation,'destinationId',a.id,'changed',false);
 ELSE
  SELECT coalesce(max(publication_order),0)+1 INTO publication FROM trading.publications p WHERE p.catalog_id=catalog;
  INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());
  INSERT INTO trading.rec_inventory_destinations VALUES(catalog,(body->>'destinationId')::uuid,(body->>'counterpartyId')::uuid,
   (body->>'counterpartyRevision')::integer,(body->>'referenceCatalogId')::uuid,(body->>'referenceRevisionId')::uuid,body->>'registryCode',body->>'registryAccountReference',actor,publication,at_time) RETURNING * INTO a;
  result=jsonb_build_object('requestId',operation,'destinationId',a.id,'changed',true);
 END IF;
 IF security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
 PERFORM security.require_rec_inventory(catalog,true,true);
 INSERT INTO trading.rec_inventory_commands(catalog_id,actor_id,request_id,destination_id,kind,request,outcome) VALUES(catalog,actor,operation,a.id,'destination',request,result);
 RETURN result;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation OR foreign_key_violation THEN RAISE EXCEPTION 'rec_account_input';
END$$;

-- Independent relational conservation check. Native integer multiranges avoid
-- expanding a lot into individual certificate rows.
CREATE FUNCTION trading.rec_ranges(catalog uuid,account uuid,lot uuid,at_time timestamptz DEFAULT NULL,context uuid DEFAULT NULL)
 RETURNS TABLE(state text,allocation_id uuid,allocation_revision integer,serials int8multirange)
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE f record;r int8multirange;available int8multirange='{}';issued int8multirange='{}';retired int8multirange='{}';
 allocated jsonb='{}';transferred jsonb='{}';k text;v int8multirange;all_transferred int8multirange;BEGIN
 FOR f IN WITH selected AS(SELECT DISTINCT ON(business_id) x.* FROM trading.rec_inventory_facts x
  WHERE(x.catalog_id,x.account_id,x.lot_id)=(catalog,account,lot)
   AND(context IS NULL OR security.trading_visible(catalog,x.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00')) ORDER BY business_id,revision DESC)
  SELECT * FROM selected WHERE at_time IS NULL OR effective_at<=at_time ORDER BY effective_at,first_publication,business_id LOOP
  r=int8multirange(int8range(f.serial_from,f.serial_to,'[)'));
  IF f.kind='receipt' THEN
   IF issued&&r THEN
    SELECT coalesce(range_agg(z),'{}') INTO all_transferred FROM jsonb_each_text(transferred)e CROSS JOIN LATERAL unnest(e.value::int8multirange)z;
    IF f.receipt_kind<>'incoming_transfer' OR NOT r<@all_transferred THEN RAISE EXCEPTION 'rec_overlap';END IF;
    FOR k IN SELECT jsonb_object_keys(transferred) LOOP transferred=jsonb_set(transferred,ARRAY[k],to_jsonb((transferred->>k)::int8multirange-r));END LOOP;
   END IF;
   available=available+r;issued=issued+r;
  ELSIF f.kind='allocate' THEN
   IF NOT r<@available THEN RAISE EXCEPTION 'rec_unavailable';END IF;
   available=available-r;allocated=jsonb_set(allocated,ARRAY[f.business_id::text||'/'||f.revision::text],to_jsonb(r));
  ELSIF f.kind IN('release','transfer') THEN
   k=f.allocation_id::text||'/'||f.allocation_revision::text;
   v=coalesce((allocated->>k)::int8multirange,'{}');
   IF NOT r<@v THEN RAISE EXCEPTION 'rec_unavailable';END IF;
   allocated=jsonb_set(allocated,ARRAY[k],to_jsonb(v-r));
   IF f.kind='release' THEN available=available+r;
   ELSE transferred=jsonb_set(transferred,ARRAY[k],to_jsonb(coalesce((transferred->>k)::int8multirange,'{}')+r));END IF;
  ELSIF f.kind='retire' THEN
   IF NOT r<@available THEN RAISE EXCEPTION 'rec_unavailable';END IF;
   available=available-r;retired=retired+r;
  END IF;
 END LOOP;
 state='available';allocation_id=NULL;allocation_revision=NULL;serials=available;RETURN NEXT;
 state='retired';serials=retired;RETURN NEXT;
 FOR k IN SELECT jsonb_object_keys(allocated) LOOP
  state='allocated';allocation_id=split_part(k,'/',1)::uuid;allocation_revision=split_part(k,'/',2)::integer;serials=(allocated->>k)::int8multirange;RETURN NEXT;
 END LOOP;
 FOR k IN SELECT jsonb_object_keys(transferred) LOOP
  state='transferred';allocation_id=split_part(k,'/',1)::uuid;allocation_revision=split_part(k,'/',2)::integer;serials=(transferred->>k)::int8multirange;RETURN NEXT;
 END LOOP;
END$$;
CREATE FUNCTION trading.rec_available(catalog uuid,account uuid,lot uuid,at_time timestamptz DEFAULT NULL,context uuid DEFAULT NULL) RETURNS int8multirange
 LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT serials FROM trading.rec_ranges(catalog,account,lot,at_time,context) WHERE state='available'
$$;

CREATE FUNCTION security.require_rec_read(catalog uuid,context uuid,at_time timestamptz,until_at timestamptz) RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM security.require_rec_inventory(catalog,false,false);
 IF until_at IS NULL OR clock_timestamp()>=until_at OR security.trading_context_visible(catalog,context) IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM security.request_contexts q WHERE q.backend_pid=pg_backend_pid()
  AND q.transaction_id=pg_current_xact_id_if_assigned() AND q.runtime_login=session_user
  AND(q.market_catalog_id,q.market_context_id,q.trading_as_of)=(catalog,context,at_time) AND q.expires_at>clock_timestamp())
 THEN RAISE EXCEPTION 'rec_context' USING ERRCODE='42501';END IF;
END$$;
CREATE FUNCTION trading.rec_product_rows(ref_catalog uuid,ref_revision uuid) RETURNS jsonb
 LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('code',p.code,'name',p.name,'referenceCatalogId',p.catalog_id,'referenceRevisionId',p.revision_id,
  'registryCode',g.registry_code,'programCode',p.program_code,'classCode',p.class_code,'technologyCode',p.technology_code,'geographyCode',p.geography_code,
  'quantityCode',p.quantity_code,'unitCode',q.unit_code,'commodityCode',q.commodity_code,'basisCode',q.basis_code,'dimensionCode',q.dimension_code) ORDER BY p.code),'[]')
 FROM ref_data.rec_products p JOIN ref_data.rec_programs g ON(g.catalog_id,g.revision_id,g.code)=(p.catalog_id,p.revision_id,p.program_code)
 JOIN ref_data.quantity_specifications q ON(q.catalog_id,q.revision_id,q.code)=(p.catalog_id,p.revision_id,p.quantity_code)
 WHERE(p.catalog_id,p.revision_id)=(ref_catalog,ref_revision)
$$;
CREATE FUNCTION trading.rec_delivery_choices(catalog uuid,account uuid DEFAULT NULL) RETURNS jsonb
 LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 WITH selected AS(SELECT DISTINCT ON(account_id,business_id) f.* FROM trading.rec_inventory_facts f
  WHERE f.catalog_id=catalog AND security.trading_visible(catalog,f.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00') ORDER BY account_id,business_id,revision DESC),
 used AS(SELECT a.delivery_id,sum(a.serial_to-a.serial_from-coalesce((SELECT sum(r.serial_to-r.serial_from) FROM selected r
  WHERE(r.account_id,r.allocation_id,r.allocation_revision,r.kind)=(a.account_id,a.business_id,a.revision,'release') AND security.trading_visible(catalog,r.publication_order,r.effective_at)),0)) count
  FROM selected a WHERE a.kind='allocate' AND security.trading_visible(catalog,a.publication_order,a.effective_at) GROUP BY a.delivery_id)
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',d.id,'tradeId',d.trade_id,'tradeRevision',d.trade_revision,'sideSlot',d.slot,'scheduleId',d.schedule_id,
  'productCode',d.product_code,'vintageFrom',d.vintage_from,'vintageTo',d.vintage_to,'deliveryFrom',d.delivery_from,'deliveryTo',d.delivery_to,
  'quantityCount',d.quantity::text,'remainingCount',(d.quantity-coalesce(u.count,0))::text,'quantityCode',p.quantity_code,
  'counterpartyId',t.counterparty_id,'counterpartyRevision',t.counterparty_revision,'bookId',t.book_id,'referenceCatalogId',d.reference_catalog_id,'referenceRevisionId',d.reference_revision_id)
  ORDER BY d.delivery_from,d.id),'[]')
 FROM trading.rec_deliveries d JOIN trading.rec_forward_trade_revisions t ON(t.catalog_id,t.trade_id,t.revision)=(d.catalog_id,d.trade_id,d.trade_revision)
 JOIN ref_data.rec_products p ON(p.catalog_id,p.revision_id,p.code)=(d.reference_catalog_id,d.reference_revision_id,d.product_code)
 LEFT JOIN used u ON u.delivery_id=d.id
 WHERE d.catalog_id=catalog AND d.physical_direction=-1 AND security.trading_visible(catalog,t.publication_order,t.effective_at)
  AND security.reference_access(d.reference_catalog_id,'ReadMarketData') AND security.reference_version_visible(d.reference_catalog_id,d.reference_revision_id)
  AND(account IS NULL OR EXISTS(SELECT 1 FROM trading.rec_inventory_accounts a WHERE(a.catalog_id,a.id)=(catalog,account)
   AND(a.book_id,a.legal_entity_id,a.legal_entity_revision,a.reference_catalog_id,a.reference_revision_id)=(t.book_id,t.legal_entity_id,t.legal_entity_revision,d.reference_catalog_id,d.reference_revision_id)))
$$;
CREATE FUNCTION security.read_rec_inventory(catalog uuid,account uuid,context uuid,at_time timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE a trading.rec_inventory_accounts;result jsonb;until_at timestamptz;BEGIN
 until_at=least(security.authority_until('ReadMarketData'),security.authority_until('ReadTrades'),security.authority_until('ReadRecInventory'));
 PERFORM security.require_rec_read(catalog,context,at_time,until_at);
 SELECT * INTO a FROM trading.rec_inventory_accounts x WHERE(x.catalog_id,x.id)=(catalog,account)
  AND security.trading_visible(catalog,x.publication_order,x.effective_at);
 IF NOT FOUND THEN RAISE EXCEPTION 'rec_account';END IF;
 IF security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE
 OR security.reference_version_visible(a.reference_catalog_id,a.reference_revision_id) IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
 WITH facts AS(SELECT f.*,k.known_from FROM trading.rec_inventory_facts f JOIN trading.knowledge_receipts k ON(k.catalog_id,k.publication_order)=(f.catalog_id,f.publication_order)
  WHERE(f.catalog_id,f.account_id)=(catalog,account) AND security.trading_visible(catalog,f.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00')),
 lots AS(SELECT l.* FROM trading.rec_inventory_lots l WHERE l.catalog_id=catalog AND EXISTS(SELECT 1 FROM facts f WHERE f.lot_id=l.id)),
 balances AS(SELECT l.id,coalesce((SELECT sum(upper(r)-lower(r)) FROM unnest(trading.rec_available(catalog,account,l.id,at_time,context))r),0) available_count FROM lots l)
 SELECT jsonb_build_object('contextId',context,'at',at_time,'authorityUntil',until_at,
  'knownAt',(SELECT known_at FROM market_data.temporal_contexts t WHERE(t.catalog_id,t.id)=(catalog,context)),
  'account',to_jsonb(a),'generation',coalesce((SELECT max(generation) FROM facts),0),
  'products',trading.rec_product_rows(a.reference_catalog_id,a.reference_revision_id),
  'deliveryChoices',trading.rec_delivery_choices(catalog,account),
  'deliveries',coalesce((SELECT jsonb_agg(to_jsonb(d)||jsonb_build_object('definitionRevisionId',i.definition_revision_id)) FROM trading.rec_deliveries d JOIN trading.rec_forward_instruments i
   ON(i.catalog_id,i.instrument_id)=(d.catalog_id,d.instrument_id) WHERE d.catalog_id=catalog AND EXISTS(SELECT 1 FROM facts f WHERE f.delivery_id=d.id)),'[]'),
  'destinations',coalesce((SELECT jsonb_agg(to_jsonb(d)) FROM trading.rec_inventory_destinations d WHERE d.catalog_id=catalog AND EXISTS(SELECT 1 FROM facts f WHERE f.destination_id=d.id)),'[]'),
  'facts',coalesce((SELECT jsonb_agg(to_jsonb(f)||jsonb_build_object('knownAt',f.known_from) ORDER BY generation) FROM facts f),'[]'),
  'lots',coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.id) FROM lots l),'[]'),
  'lotBalances',coalesce((SELECT jsonb_agg(jsonb_build_object('lotId',b.id,'availableCount',b.available_count::text) ORDER BY b.id) FROM balances b),'[]')) INTO result;
 PERFORM security.require_rec_read(catalog,context,at_time,until_at);RETURN result;
END$$;

CREATE FUNCTION trading.require_rec_registry_conservation(catalog uuid,lot uuid) RETURNS void
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE moment timestamptz;account uuid;owned int8multirange;all_owned int8multirange;retired int8multirange;BEGIN
 IF EXISTS(WITH selected AS(SELECT DISTINCT ON(account_id,business_id) f.* FROM trading.rec_inventory_facts f
  WHERE(f.catalog_id,f.lot_id)=(catalog,lot) ORDER BY account_id,business_id,revision DESC)
  SELECT 1 FROM selected a JOIN selected b ON a.account_id<>b.account_id
  WHERE a.kind='receipt' AND b.kind='receipt' AND a.receipt_kind='issuance' AND b.receipt_kind='issuance'
   AND int8range(a.serial_from,a.serial_to,'[)')&&int8range(b.serial_from,b.serial_to,'[)'))
 THEN RAISE EXCEPTION 'rec_overlap';END IF;
 -- Check each effective boundary, not only the final balance: later outbound
 -- evidence cannot conceal an earlier interval of duplicated ownership.
 FOR moment IN SELECT DISTINCT effective_at FROM trading.rec_inventory_facts f WHERE(f.catalog_id,f.lot_id)=(catalog,lot) LOOP
  all_owned='{}';
  SELECT coalesce(range_agg(int8range(serial_from,serial_to,'[)')),'{}') INTO retired
   FROM(SELECT DISTINCT ON(account_id,business_id) f.* FROM trading.rec_inventory_facts f
    WHERE(f.catalog_id,f.lot_id)=(catalog,lot) ORDER BY account_id,business_id,revision DESC)s
   WHERE s.kind='retire' AND s.effective_at<=moment;
  FOR account IN SELECT DISTINCT account_id FROM trading.rec_inventory_facts f WHERE(f.catalog_id,f.lot_id)=(catalog,lot) LOOP
   SELECT coalesce(range_agg(r),'{}') INTO owned FROM trading.rec_ranges(catalog,account,lot,moment)s CROSS JOIN LATERAL unnest(s.serials)r WHERE s.state IN('available','allocated');
   IF owned&&all_owned OR owned&&retired THEN RAISE EXCEPTION 'rec_overlap';END IF;
   all_owned=all_owned+owned;
  END LOOP;
 END LOOP;
END$$;

CREATE FUNCTION trading.require_rec_delivery_capacity(catalog uuid) RETURNS void
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE moment timestamptz;BEGIN
 FOR moment IN SELECT DISTINCT effective_at FROM trading.rec_inventory_facts f WHERE f.catalog_id=catalog LOOP
  IF EXISTS(WITH selected AS(SELECT DISTINCT ON(account_id,business_id) f.* FROM trading.rec_inventory_facts f
   WHERE f.catalog_id=catalog ORDER BY account_id,business_id,revision DESC),
  commitments AS(SELECT a.delivery_id,sum(a.serial_to-a.serial_from-coalesce((SELECT sum(r.serial_to-r.serial_from) FROM selected r
    WHERE(r.account_id,r.allocation_id,r.allocation_revision,r.kind)=(a.account_id,a.business_id,a.revision,'release') AND r.effective_at<=moment),0)) used
   FROM selected a WHERE a.kind='allocate' AND a.effective_at<=moment GROUP BY a.delivery_id)
  SELECT 1 FROM commitments c JOIN trading.rec_deliveries d ON(d.catalog_id,d.id)=(catalog,c.delivery_id) WHERE c.used<0 OR c.used>d.quantity)
  THEN RAISE EXCEPTION 'rec_delivery_capacity';END IF;
 END LOOP;
END$$;

CREATE FUNCTION security.record_rec_inventory(catalog uuid,operation uuid,account uuid,business uuid,expected integer,at_time timestamptz,action jsonb) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;a trading.rec_inventory_accounts;l trading.rec_inventory_lots;prior trading.rec_inventory_commands;
 allocation trading.rec_inventory_facts;delivery trading.rec_deliveries;destination trading.rec_inventory_destinations;
 previous trading.rec_inventory_facts;same trading.rec_inventory_facts;f trading.rec_inventory_facts;
 request jsonb;result jsonb;keys text[];first_serial bigint;last_serial bigint;publication integer;head integer;next_revision integer;BEGIN
 actor=security.require_rec_inventory(catalog,true,false);
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000' OR account IS NULL OR business IS NULL OR business='00000000-0000-0000-0000-000000000000'
 OR expected IS NULL OR expected<0 OR at_time IS NULL OR NOT isfinite(at_time) OR at_time>clock_timestamp()
 OR pg_column_size(action)>8192 OR jsonb_typeof(action) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'rec_input';END IF;
 keys=ARRAY['kind','lotId','from','to'];
 IF action->>'kind' IN('receipt','transfer','retire') THEN keys=keys||ARRAY['evidenceSource','evidenceReference'];END IF;
 IF action->>'kind'='receipt' THEN keys=keys||ARRAY['productCode','registryLotReference','vintageFrom','vintageTo','receiptKind'];
 ELSIF action->>'kind'='allocate' THEN keys=keys||ARRAY['deliveryId'];
 ELSIF action->>'kind'='release' THEN keys=keys||ARRAY['allocationId','allocationRevision'];
 ELSIF action->>'kind'='transfer' THEN keys=keys||ARRAY['allocationId','allocationRevision','destinationId'];
 ELSIF action->>'kind'='retire' THEN keys=keys||ARRAY['beneficiaryKind','beneficiaryId','beneficiaryRevision','purposeCode'];
 ELSE RAISE EXCEPTION 'rec_action';END IF;
 IF trading.rec_keys(action,keys) IS NOT TRUE
 OR EXISTS(SELECT 1 FROM jsonb_each(action)e WHERE jsonb_typeof(e.value) IS DISTINCT FROM CASE WHEN e.key IN('beneficiaryRevision','allocationRevision') THEN 'number' ELSE 'string' END)
 OR action->>'from' !~ '^[0-9]{1,19}$' OR action->>'to' !~ '^[0-9]{1,19}$'
 OR(action->>'kind' IN('receipt','transfer','retire') AND(length(action->>'evidenceReference') NOT BETWEEN 1 AND 500 OR action->>'evidenceReference' IS DISTINCT FROM btrim(action->>'evidenceReference')))
 OR action->>'lotId' IS NULL OR(action->>'lotId')::uuid='00000000-0000-0000-0000-000000000000'
 THEN RAISE EXCEPTION 'rec_input';END IF;
 first_serial=(action->>'from')::bigint;last_serial=(action->>'to')::bigint;
 IF first_serial>=last_serial THEN RAISE EXCEPTION 'rec_range';END IF;
 action=action||jsonb_build_object('lotId',(action->>'lotId')::uuid,'from',first_serial::text,'to',last_serial::text);
 IF action?'deliveryId' THEN action=jsonb_set(action,'{deliveryId}',to_jsonb((action->>'deliveryId')::uuid));END IF;
 IF action?'allocationId' THEN action=action||jsonb_build_object('allocationId',(action->>'allocationId')::uuid,'allocationRevision',(action->>'allocationRevision')::integer);END IF;
 IF action?'destinationId' THEN action=jsonb_set(action,'{destinationId}',to_jsonb((action->>'destinationId')::uuid));END IF;
 IF action?'beneficiaryId' THEN action=action||jsonb_build_object('beneficiaryId',(action->>'beneficiaryId')::uuid,'beneficiaryRevision',(action->>'beneficiaryRevision')::integer);END IF;
 request=jsonb_build_object('kind','action','accountId',account,'businessId',business,'expectedGeneration',expected,'effectiveAt',extract(epoch FROM at_time),'action',action);
 PERFORM pg_advisory_xact_lock(730849102);PERFORM security.require_rec_inventory(catalog,true,false);
 SELECT * INTO a FROM trading.rec_inventory_accounts x WHERE(x.catalog_id,x.id)=(catalog,account);
 IF NOT FOUND OR a.effective_at>at_time OR security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_account';END IF;
 IF action->>'kind' IN('receipt','transfer','retire') AND NOT EXISTS(SELECT 1 FROM ref_data.sources s WHERE(s.catalog_id,s.revision_id,s.code)=(a.reference_catalog_id,a.reference_revision_id,action->>'evidenceSource'))
 THEN RAISE EXCEPTION 'rec_input';END IF;
 SELECT * INTO prior FROM trading.rec_inventory_commands c WHERE(c.catalog_id,c.actor_id,c.request_id)=(catalog,actor,operation);
 IF FOUND THEN
  IF prior.request IS DISTINCT FROM request THEN RAISE EXCEPTION 'rec_request_conflict';END IF;
  IF security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
  PERFORM security.require_rec_inventory(catalog,true,false);RETURN prior.outcome;
 END IF;
 IF action->>'kind'='receipt' THEN
  IF action->>'receiptKind' IS NULL OR action->>'receiptKind' NOT IN('issuance','incoming_transfer')
   OR length(action->>'registryLotReference') NOT BETWEEN 1 AND 128 OR action->>'registryLotReference' IS DISTINCT FROM btrim(action->>'registryLotReference')
   OR action->>'vintageFrom' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR action->>'vintageTo' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   OR NOT EXISTS(SELECT 1 FROM ref_data.rec_products p JOIN ref_data.rec_programs g
    ON(g.catalog_id,g.revision_id,g.code)=(p.catalog_id,p.revision_id,p.program_code)
    WHERE(p.catalog_id,p.revision_id,p.code,g.registry_code)=(a.reference_catalog_id,a.reference_revision_id,action->>'productCode',a.registry_code))
  THEN RAISE EXCEPTION 'rec_eligibility';END IF;
 ELSIF action->>'kind'='retire' THEN
  IF action->>'beneficiaryKind' NOT IN('legal_entity','counterparty') OR jsonb_typeof(action->'beneficiaryRevision') IS DISTINCT FROM 'number'
   OR(action->>'beneficiaryRevision')::integer<=0 THEN RAISE EXCEPTION 'rec_retirement';END IF;
 END IF;
 SELECT * INTO l FROM trading.rec_inventory_lots x WHERE(x.catalog_id,x.id)=(catalog,(action->>'lotId')::uuid);
 IF l.id IS NULL AND action->>'kind'='receipt' THEN
  SELECT * INTO l FROM trading.rec_inventory_lots x WHERE(x.catalog_id,x.reference_catalog_id,x.registry_code,x.registry_lot_reference)=
   (catalog,a.reference_catalog_id,a.registry_code,action->>'registryLotReference');
  IF l.id IS NOT NULL THEN action=jsonb_set(action,'{lotId}',to_jsonb(l.id));END IF;
 END IF;
 IF l.id IS NOT NULL AND(l.reference_catalog_id,l.reference_revision_id,l.registry_code) IS DISTINCT FROM(a.reference_catalog_id,a.reference_revision_id,a.registry_code)
 THEN RAISE EXCEPTION 'rec_eligibility';END IF;
 IF action->>'kind'='receipt' AND l.id IS NOT NULL AND(l.registry_lot_reference,l.product_code,l.vintage_from,l.vintage_to) IS DISTINCT FROM
  (action->>'registryLotReference',action->>'productCode',(action->>'vintageFrom')::date,(action->>'vintageTo')::date) THEN RAISE EXCEPTION 'rec_lot';END IF;
 IF action->>'kind'<>'receipt' AND l.id IS NULL THEN RAISE EXCEPTION 'rec_lot';END IF;
 IF action->>'kind'='retire' AND (NOT EXISTS(SELECT 1 FROM ref_data.rec_retirement_purposes p
  WHERE(p.catalog_id,p.revision_id,p.code)=(a.reference_catalog_id,a.reference_revision_id,action->>'purposeCode'))
  OR (action->>'beneficiaryKind'='legal_entity' AND NOT EXISTS(SELECT 1 FROM trading.legal_entities p
   WHERE(p.catalog_id,p.id,p.revision)=(catalog,(action->>'beneficiaryId')::uuid,(action->>'beneficiaryRevision')::integer) AND p.effective_at<=at_time))
  OR (action->>'beneficiaryKind'='counterparty' AND NOT EXISTS(SELECT 1 FROM trading.counterparties p
   WHERE(p.catalog_id,p.id,p.revision)=(catalog,(action->>'beneficiaryId')::uuid,(action->>'beneficiaryRevision')::integer) AND p.effective_at<=at_time)))
 THEN RAISE EXCEPTION 'rec_retirement';END IF;
 IF action->>'kind' IN('release','transfer') THEN
  SELECT * INTO allocation FROM trading.rec_inventory_facts af WHERE(af.catalog_id,af.account_id,af.business_id,af.revision)=
   (catalog,account,(action->>'allocationId')::uuid,(action->>'allocationRevision')::integer) AND af.kind='allocate' AND af.lot_id=l.id AND af.effective_at<=at_time;
  IF NOT FOUND THEN RAISE EXCEPTION 'rec_allocation';END IF;
 END IF;
 IF action->>'kind' IN('allocate','transfer') THEN
  SELECT d.* INTO delivery FROM trading.rec_deliveries d JOIN trading.rec_forward_trade_revisions t
   ON(t.catalog_id,t.trade_id,t.revision)=(d.catalog_id,d.trade_id,d.trade_revision)
   WHERE(d.catalog_id,d.id)=(catalog,coalesce((action->>'deliveryId')::uuid,allocation.delivery_id))
   AND t.book_id=a.book_id AND(t.legal_entity_id,t.legal_entity_revision)=(a.legal_entity_id,a.legal_entity_revision) AND t.effective_at<=at_time;
  IF NOT FOUND OR delivery.physical_direction<>-1 OR
   (delivery.reference_catalog_id,delivery.reference_revision_id,delivery.product_code) IS DISTINCT FROM(l.reference_catalog_id,l.reference_revision_id,l.product_code)
   OR l.vintage_from<delivery.vintage_from OR l.vintage_to>delivery.vintage_to THEN RAISE EXCEPTION 'rec_eligibility';END IF;
  IF action->>'kind'='transfer' THEN
   IF at_time<delivery.delivery_from OR at_time>=delivery.delivery_to THEN RAISE EXCEPTION 'rec_delivery_window';END IF;
   SELECT d.* INTO destination FROM trading.rec_inventory_destinations d JOIN trading.rec_forward_trade_revisions t
    ON(t.catalog_id,t.trade_id,t.revision)=(catalog,delivery.trade_id,delivery.trade_revision)
    WHERE(d.catalog_id,d.id)=(catalog,(action->>'destinationId')::uuid) AND d.effective_at<=at_time
    AND(d.counterparty_id,d.counterparty_revision)=(t.counterparty_id,t.counterparty_revision)
    AND(d.reference_catalog_id,d.reference_revision_id,d.registry_code)=(a.reference_catalog_id,a.reference_revision_id,a.registry_code);
   IF NOT FOUND OR destination.id=a.id OR destination.registry_account_reference=a.registry_account_reference THEN RAISE EXCEPTION 'rec_destination';END IF;
  END IF;
 END IF;
 SELECT coalesce(max(generation),0) INTO head FROM trading.rec_inventory_facts x WHERE(x.catalog_id,x.account_id)=(catalog,account);
 -- Compare the retained typed business fact. Candidate UUIDs and request
 -- witnesses are not the registry's natural certificate-lot identity.
 SELECT x.* INTO same FROM trading.rec_inventory_facts x
  WHERE(x.catalog_id,x.account_id,x.effective_at,x.kind,x.lot_id)=(catalog,account,at_time,action->>'kind',l.id)
  AND(x.serial_from,x.serial_to,x.receipt_kind,x.delivery_id,x.allocation_id,x.allocation_revision,x.destination_id,
   x.beneficiary_entity_id,x.beneficiary_entity_revision,x.beneficiary_counterparty_id,x.beneficiary_counterparty_revision,x.purpose_code)
  IS NOT DISTINCT FROM(first_serial,last_serial,action->>'receiptKind',(action->>'deliveryId')::uuid,(action->>'allocationId')::uuid,(action->>'allocationRevision')::integer,(action->>'destinationId')::uuid,
   CASE WHEN action->>'beneficiaryKind'='legal_entity' THEN(action->>'beneficiaryId')::uuid END,
   CASE WHEN action->>'beneficiaryKind'='legal_entity' THEN(action->>'beneficiaryRevision')::integer END,
   CASE WHEN action->>'beneficiaryKind'='counterparty' THEN(action->>'beneficiaryId')::uuid END,
   CASE WHEN action->>'beneficiaryKind'='counterparty' THEN(action->>'beneficiaryRevision')::integer END,action->>'purposeCode')
  ORDER BY x.generation LIMIT 1;
 IF same.business_id IS NOT NULL THEN
  result=jsonb_build_object('requestId',operation,'accountId',account,'factId',same.business_id,'revision',same.revision,'generation',head,'changed',false);
  INSERT INTO trading.rec_inventory_commands(catalog_id,actor_id,request_id,account_id,kind,request,outcome,fact_id,fact_revision)
   VALUES(catalog,actor,operation,account,'action',request,result,same.business_id,same.revision);
  IF security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
  PERFORM security.require_rec_inventory(catalog,true,false);RETURN result;
 END IF;
 IF head<>expected OR head>=4096 THEN RAISE EXCEPTION 'rec_generation_conflict';END IF;
 SELECT * INTO previous FROM trading.rec_inventory_facts x WHERE(x.catalog_id,x.account_id,x.business_id)=(catalog,account,business) ORDER BY revision DESC LIMIT 1;
 IF previous.business_id IS NOT NULL AND(previous.effective_at,previous.kind,previous.lot_id) IS DISTINCT FROM(at_time,action->>'kind',(action->>'lotId')::uuid)
 THEN RAISE EXCEPTION 'rec_correction';END IF;
 next_revision=coalesce(previous.revision,0)+1;
 SELECT coalesce(max(publication_order),0)+1 INTO publication FROM trading.publications p WHERE p.catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());
 IF l.id IS NULL THEN
  INSERT INTO trading.rec_inventory_lots VALUES(catalog,(action->>'lotId')::uuid,a.reference_catalog_id,a.reference_revision_id,a.registry_code,
   action->>'registryLotReference',action->>'productCode',(action->>'vintageFrom')::date,(action->>'vintageTo')::date,publication) RETURNING * INTO l;
 END IF;
 INSERT INTO trading.rec_inventory_facts(catalog_id,account_id,business_id,revision,generation,first_publication,kind,lot_id,serial_from,serial_to,receipt_kind,
  beneficiary_entity_id,beneficiary_entity_revision,beneficiary_counterparty_id,beneficiary_counterparty_revision,purpose_code,evidence_source,evidence_reference,
  reference_catalog_id,reference_revision_id,actor_id,publication_order,publication_xid,effective_at,delivery_id,allocation_id,allocation_revision,destination_id)
 VALUES(catalog,account,business,next_revision,head+1,coalesce(previous.first_publication,publication),action->>'kind',l.id,
  first_serial,last_serial,action->>'receiptKind',
  CASE WHEN action->>'beneficiaryKind'='legal_entity' THEN(action->>'beneficiaryId')::uuid END,
  CASE WHEN action->>'beneficiaryKind'='legal_entity' THEN(action->>'beneficiaryRevision')::integer END,
  CASE WHEN action->>'beneficiaryKind'='counterparty' THEN(action->>'beneficiaryId')::uuid END,
  CASE WHEN action->>'beneficiaryKind'='counterparty' THEN(action->>'beneficiaryRevision')::integer END,
  action->>'purposeCode',action->>'evidenceSource',action->>'evidenceReference',a.reference_catalog_id,a.reference_revision_id,actor,publication,pg_current_xact_id(),at_time,(action->>'deliveryId')::uuid,(action->>'allocationId')::uuid,(action->>'allocationRevision')::integer,(action->>'destinationId')::uuid) RETURNING * INTO f;
 -- Every lot is rechecked because a correction may invalidate later evidence.
 PERFORM trading.rec_available(catalog,account,x.lot_id) FROM(SELECT DISTINCT lot_id FROM trading.rec_inventory_facts x WHERE(x.catalog_id,x.account_id)=(catalog,account))x;
 PERFORM trading.require_rec_registry_conservation(catalog,l.id);
 PERFORM trading.require_rec_delivery_capacity(catalog);
 result=jsonb_build_object('requestId',operation,'accountId',account,'factId',business,'revision',next_revision,'generation',head+1,'changed',true);
 INSERT INTO trading.rec_inventory_commands(catalog_id,actor_id,request_id,account_id,kind,request,outcome,fact_id,fact_revision)
  VALUES(catalog,actor,operation,account,'action',request,result,business,next_revision);
 IF security.reference_access(a.reference_catalog_id,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
  PERFORM security.require_rec_inventory(catalog,true,false);RETURN result;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation OR foreign_key_violation OR datetime_field_overflow THEN RAISE EXCEPTION 'rec_input';
END$$;

CREATE FUNCTION security.rec_inventory_status(catalog uuid,operation uuid) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;c trading.rec_inventory_commands;ref_catalog uuid;BEGIN
 actor=security.require_rec_inventory(catalog,false,false);
 IF security.current_write_context() IS NOT TRUE THEN RAISE EXCEPTION 'historical_read_only';END IF;
 SELECT * INTO c FROM trading.rec_inventory_commands x WHERE(x.catalog_id,x.actor_id,x.request_id)=(catalog,actor,operation);
 IF NOT FOUND THEN RETURN jsonb_build_object('found',false);END IF;
 SELECT reference_catalog_id INTO ref_catalog FROM trading.rec_inventory_accounts a WHERE(a.catalog_id,a.id)=(catalog,c.account_id)
 UNION ALL SELECT reference_catalog_id FROM trading.rec_inventory_destinations a WHERE(a.catalog_id,a.id)=(catalog,c.destination_id);
 IF security.reference_access(ref_catalog,'ReadMarketData') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
 PERFORM security.require_rec_inventory(catalog,false,false);RETURN c.outcome;
END$$;
CREATE FUNCTION security.rec_products(catalog uuid,ref_catalog uuid,ref_revision uuid) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF security.trading_access(catalog,'ReadTrades') IS NOT TRUE OR security.reference_access(ref_catalog,'ReadMarketData') IS NOT TRUE
 OR security.reference_version_visible(ref_catalog,ref_revision) IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
 RETURN trading.rec_product_rows(ref_catalog,ref_revision);
END$$;
CREATE FUNCTION security.rec_trade_owner(catalog uuid) RETURNS text
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF security.trading_access(catalog,'ReadTrades') IS NOT TRUE THEN RAISE EXCEPTION 'rec_denied' USING ERRCODE='42501';END IF;
 RETURN presentation.preference_owner(security.presentation_actor(),'rec-trade:'||catalog::text);
END$$;
CREATE FUNCTION security.rec_inventory_directory(catalog uuid,context uuid,at_time timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;until_at timestamptz;BEGIN
 until_at=least(security.authority_until('ReadMarketData'),security.authority_until('ReadTrades'),security.authority_until('ReadRecInventory'));
 PERFORM security.require_rec_read(catalog,context,at_time,until_at);
 WITH refs AS(SELECT r.catalog_id,r.id FROM ref_data.revisions r WHERE r.state='sealed'
  AND security.reference_access(r.catalog_id,'ReadMarketData') AND security.reference_version_visible(r.catalog_id,r.id)),
 accounts AS(SELECT a.* FROM trading.rec_inventory_accounts a JOIN refs r ON(r.catalog_id,r.id)=(a.reference_catalog_id,a.reference_revision_id)
  WHERE a.catalog_id=catalog AND security.trading_visible(catalog,a.publication_order,a.effective_at)),
 destinations AS(SELECT a.* FROM trading.rec_inventory_destinations a JOIN refs r ON(r.catalog_id,r.id)=(a.reference_catalog_id,a.reference_revision_id)
  WHERE a.catalog_id=catalog AND security.trading_visible(catalog,a.publication_order,a.effective_at))
 SELECT jsonb_build_object('authorityUntil',until_at,'deliveryChoices',trading.rec_delivery_choices(catalog),'accounts',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM accounts a),'[]'),
  'destinations',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM destinations a),'[]'),
  'products',coalesce((SELECT jsonb_agg(p ORDER BY p->>'code') FROM refs r CROSS JOIN LATERAL jsonb_array_elements(trading.rec_product_rows(r.catalog_id,r.id))p),'[]'),
  'purposes',coalesce((SELECT jsonb_agg(jsonb_build_object('code',p.code,'label',p.name,'referenceCatalogId',p.catalog_id,'referenceRevisionId',p.revision_id) ORDER BY p.code)
   FROM ref_data.rec_retirement_purposes p JOIN refs r ON(r.catalog_id,r.id)=(p.catalog_id,p.revision_id)),'[]'),
  'registries',coalesce((SELECT jsonb_agg(jsonb_build_object('code',s.code,'label',s.code,'referenceCatalogId',s.catalog_id,'referenceRevisionId',s.revision_id) ORDER BY s.code)
   FROM ref_data.sources s JOIN refs r ON(r.catalog_id,r.id)=(s.catalog_id,s.revision_id) WHERE EXISTS(SELECT 1 FROM ref_data.rec_programs g WHERE(g.catalog_id,g.revision_id,g.registry_code)=(s.catalog_id,s.revision_id,s.code))),'[]'),
  'evidenceSources',coalesce((SELECT jsonb_agg(jsonb_build_object('code',s.code,'label',s.code,'referenceCatalogId',s.catalog_id,'referenceRevisionId',s.revision_id) ORDER BY s.code)
   FROM ref_data.sources s JOIN refs r ON(r.catalog_id,r.id)=(s.catalog_id,s.revision_id) WHERE EXISTS(SELECT 1 FROM ref_data.rec_programs g WHERE(g.catalog_id,g.revision_id)=(s.catalog_id,s.revision_id))),'[]')) INTO result;
 PERFORM security.require_rec_read(catalog,context,at_time,until_at);RETURN result;
END$$;

-- Admission binds the retained executable program to contractual terms. An
-- equal aggregate value cannot substitute a different quantity, date or source.
CREATE FUNCTION trading.require_rec_forward_program_shape(catalog uuid,schedule uuid,member_slot integer,instrument uuid) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE h trading.rec_forward_instruments;m trading.rec_forward_memberships;a market_data.rec_valuation_assignments;q ref_data.quote_specifications;
 price trading.side_schedule_rows;r trading.side_schedule_rows;payment timestamptz;selected_quote text;selected_curve text;contract uuid;fixed numeric;
 expected_operations text[];rule text;BEGIN
 SELECT * INTO STRICT h FROM trading.rec_forward_instruments x WHERE(x.catalog_id,x.instrument_id)=(catalog,instrument);
 SELECT * INTO STRICT m FROM trading.rec_forward_memberships x WHERE(x.catalog_id,x.instrument_id,x.slot)=(catalog,instrument,member_slot);
 SELECT * INTO STRICT a FROM market_data.rec_valuation_assignments x WHERE(x.catalog_id,x.revision_id,x.code)=(catalog,h.definition_revision_id,h.assignment_code);
 IF member_slot=0 THEN
  SELECT c.quote_code INTO STRICT selected_quote FROM market_data.curves c WHERE(c.catalog_id,c.revision_id,c.code)=(catalog,h.definition_revision_id,a.curve_code);
  selected_curve=a.curve_code;contract=a.contract_id;payment=h.delivery_to;
 ELSE
  selected_quote=h.consideration_quote_code;selected_curve=h.consideration_curve_code;contract=h.consideration_contract_id;fixed=h.fixed_price;
  payment=(date_trunc('month',h.delivery_from AT TIME ZONE 'UTC')+interval '1 month'-interval '1 day'+make_interval(days=>(h.payment_rule->>'days')::integer)) AT TIME ZONE 'UTC';
  IF payment<h.delivery_to THEN RAISE EXCEPTION 'rec_schedule_policy';END IF;
 END IF;
 SELECT * INTO STRICT q FROM ref_data.quote_specifications x WHERE(x.catalog_id,x.revision_id,x.code)=(h.reference_catalog_id,h.reference_revision_id,selected_quote);
 IF NOT EXISTS(SELECT 1 FROM trading.side_schedules s JOIN trading.sides d ON(d.catalog_id,d.id)=(s.catalog_id,s.side_id)
  WHERE(s.catalog_id,s.id,s.side_id,d.family,d.definition_revision_id,d.reference_catalog_id,d.reference_revision_id)=
   (catalog,schedule,m.side_id,'operating',h.definition_revision_id,h.reference_catalog_id,h.reference_revision_id))
 OR(SELECT count(*) FROM trading.side_schedule_rows x WHERE(x.catalog_id,x.schedule_id)=(catalog,schedule))<>7
 OR(SELECT count(*) FROM trading.side_schedule_edges x WHERE(x.catalog_id,x.schedule_id)=(catalog,schedule))<>7
 OR(SELECT count(*) FROM trading.side_schedule_roots x WHERE(x.catalog_id,x.schedule_id)=(catalog,schedule))<>4
 OR EXISTS(SELECT 1 FROM trading.side_schedule_grids x WHERE(x.catalog_id,x.schedule_id)=(catalog,schedule))
 OR EXISTS(SELECT 1 FROM trading.side_schedule_ports x WHERE(x.catalog_id,x.schedule_id)=(catalog,schedule))
 THEN RAISE EXCEPTION 'rec_schedule_shape';END IF;
 expected_operations=ARRAY['quantity_literal',CASE WHEN fixed IS NULL THEN 'operating_contract_price' ELSE 'constant_price' END,'amount','discount','pv','output_guard','sum'];
 rule=CASE WHEN member_slot=0 THEN 'not_applicable_delivery_v1' ELSE replace(jsonb_build_array('payment_rule','monthly_payment_date_rules_v1',1,1,(h.payment_rule->>'days')::integer,NULL,1,NULL,4,NULL)::text,' ','') END;
 FOR r IN SELECT * FROM trading.side_schedule_rows x WHERE(x.catalog_id,x.schedule_id)=(catalog,schedule) ORDER BY ordinal LOOP
  IF r.operation IS DISTINCT FROM expected_operations[r.ordinal+1] OR r.operation_version<>1
   OR(r.ordinal<6 AND(r.interval_from,r.interval_to,r.value_at,r.operating_date,r.hour_beginning,r.minute,r.occurrence,r.payment_ordinal) IS DISTINCT FROM
    (h.delivery_from,h.delivery_to,payment,(h.delivery_from AT TIME ZONE 'UTC')::date,0,0,1,0))
  THEN RAISE EXCEPTION 'rec_schedule_time';END IF;
  IF r.ordinal=0 AND((r.unit_catalog_id,r.unit_revision_id,r.unit_code) IS DISTINCT FROM(h.reference_catalog_id,h.reference_revision_id,q.quantity_code)
   OR(r.parameters->>'numerator')::numeric<>(r.parameters->>'denominator')::numeric OR(r.parameters->>'denominator')::numeric<=0) THEN RAISE EXCEPTION 'rec_schedule_quantity';END IF;
  IF r.ordinal=1 THEN
   price=r;
   IF(r.unit_catalog_id,r.unit_revision_id,r.unit_code,r.currency_catalog_id,r.currency_revision_id,r.currency_code,r.quote_multiplier) IS DISTINCT FROM
    (h.reference_catalog_id,h.reference_revision_id,q.quantity_code,h.reference_catalog_id,h.reference_revision_id,q.currency_code,q.multiplier)
   THEN RAISE EXCEPTION 'rec_schedule_price';END IF;
  END IF;
  IF r.ordinal=5 AND(r.parameters->>'measure',r.parameters->>'lifecycle',r.parameters->>'pricePolicy',r.parameters->>'paymentRule',r.parameters->>'averaging',r.parameters->>'firstFixingAt',r.parameters->>'unadjustedPayment')
   IS DISTINCT FROM('present_value_v1',CASE WHEN member_slot=0 THEN 'future_operating_delivery_v1' ELSE 'undue_payment_v1' END,'selected_context_v1',rule,'none','none',CASE WHEN member_slot=0 THEN 'none' ELSE to_char(payment AT TIME ZONE 'UTC','YYYY-MM-DD') END)
   THEN RAISE EXCEPTION 'rec_schedule_policy';END IF;
  IF r.ordinal IN(2,4,5,6) AND(r.currency_catalog_id,r.currency_revision_id,r.currency_code) IS DISTINCT FROM(h.reference_catalog_id,h.reference_revision_id,q.currency_code)
   THEN RAISE EXCEPTION 'rec_schedule_currency';END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM trading.side_schedule_edges e WHERE(e.catalog_id,e.schedule_id)=(catalog,schedule) AND
  (e.target,e.port,e.source,e.ordinal) NOT IN((2,'quantity',0,0),(2,'price',1,0),(4,'amount',2,0),(4,'discount',3,0),(5,'amount',2,0),(5,'discounted',4,0),(6,'input',5,0)))
 OR EXISTS(SELECT 1 FROM trading.side_schedule_roots x WHERE(x.catalog_id,x.schedule_id)=(catalog,schedule) AND
  (x.row_ordinal,x.measure) NOT IN((0,'schedule_quantity'),(2,CASE WHEN member_slot=0 THEN 'physical_value' ELSE 'contractual_amount' END),(5,'contribution_pv'),(6,'pv')))
 THEN RAISE EXCEPTION 'rec_schedule_shape';END IF;
 IF fixed IS NOT NULL THEN
  IF(price.parameters->>'numerator')::numeric<>fixed*(price.parameters->>'denominator')::numeric
   OR EXISTS(SELECT 1 FROM trading.side_schedule_bindings b WHERE(b.catalog_id,b.schedule_id)=(catalog,schedule)) THEN RAISE EXCEPTION 'rec_schedule_price';END IF;
 ELSE
  IF price.parameters->>'selection' IS DISTINCT FROM 'selected_contract_flat_v1'
   OR(SELECT count(*) FROM trading.side_schedule_bindings b WHERE(b.catalog_id,b.schedule_id)=(catalog,schedule))<>2
   OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_bindings b WHERE(b.catalog_id,b.schedule_id,b.row_ordinal,b.port,b.kind,b.source_catalog_id,b.definition_revision_id,b.curve_code,b.contract_id)=
    (catalog,schedule,1,'market','contract_price',catalog,h.definition_revision_id,selected_curve,contract))
   OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_bindings b WHERE(b.catalog_id,b.schedule_id,b.row_ordinal,b.port,b.kind,b.reference_catalog_id,b.reference_revision_id,b.quote_code)=
    (catalog,schedule,1,'quote','quote',h.reference_catalog_id,h.reference_revision_id,selected_quote))
  THEN RAISE EXCEPTION 'rec_schedule_price';END IF;
 END IF;
END$$;
DO $$DECLARE f regprocedure;BEGIN
 FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE(n.nspname='security' AND p.proname IN('require_rec_inventory','rec_inventory_owner','configure_rec_account','configure_rec_destination','record_rec_inventory','require_rec_read','read_rec_inventory','rec_inventory_status','rec_inventory_directory','rec_products','rec_trade_owner'))
  OR(n.nspname='trading' AND p.proname IN('rec_keys','rec_available','rec_ranges','require_rec_delivery_capacity','require_rec_registry_conservation','rec_product_rows','rec_delivery_choices','require_rec_forward_program_shape','require_rec_delivery_membership')) LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,openetrm_runtime',f);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION security.configure_rec_account(uuid,uuid,jsonb,timestamptz),security.configure_rec_destination(uuid,uuid,jsonb,timestamptz),security.rec_inventory_owner(uuid) TO openetrm_runtime;
GRANT EXECUTE ON FUNCTION security.record_rec_inventory(uuid,uuid,uuid,uuid,integer,timestamptz,jsonb) TO openetrm_runtime;
GRANT EXECUTE ON FUNCTION security.read_rec_inventory(uuid,uuid,uuid,timestamptz) TO openetrm_runtime;
GRANT EXECUTE ON FUNCTION security.rec_inventory_status(uuid,uuid),security.rec_inventory_directory(uuid,uuid,timestamptz),security.rec_products(uuid,uuid,uuid),security.rec_trade_owner(uuid),security.require_rec_read(uuid,uuid,timestamptz,timestamptz),security.require_rec_inventory(uuid,boolean,boolean) TO openetrm_runtime;
COMMIT;
