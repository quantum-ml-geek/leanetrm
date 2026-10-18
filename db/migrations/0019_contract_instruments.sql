-- Stop runtime write admission and drain calls before applying this migration.
-- Historical UUIDs/events stay unchanged. Derived exact reference bindings preserve
-- their original publication/effective coordinates; no market data is reinterpreted.
BEGIN;
SELECT pg_advisory_xact_lock(730849102);
LOCK TABLE trading.trade_revisions,trading.instruments IN SHARE ROW EXCLUSIVE MODE;
CREATE FUNCTION security.futures_contract_id(ref_catalog uuid,ref_revision uuid,series text) RETURNS uuid
 LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
 SELECT substr(encode(sha256(convert_to('futures_contract_v1:'||ref_catalog::text||':'||ref_revision::text||':'||series,'UTF8')),'hex'),1,32)::uuid;
$$;
ALTER TABLE trading.instruments ADD UNIQUE(catalog_id,id,publication_order,effective_at);
CREATE TABLE trading.futures_contract_references (
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,series_code ref_data.code NOT NULL,
 publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,instrument_id),
 UNIQUE(catalog_id,instrument_id,reference_catalog_id,reference_revision_id,series_code),
 FOREIGN KEY(catalog_id,instrument_id,publication_order,effective_at) REFERENCES trading.instruments(catalog_id,id,publication_order,effective_at),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,series_code) REFERENCES ref_data.futures_series(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
-- The economic definition itself is ref_data.futures_series with primary key
-- (catalog_id,revision_id,code). This is an alias/evidence table, not a second definition.
CREATE UNIQUE INDEX canonical_futures_contract_key ON trading.futures_contract_references
 (catalog_id,reference_catalog_id,reference_revision_id,series_code)
 WHERE instrument_id=security.futures_contract_id(reference_catalog_id,reference_revision_id,series_code);
INSERT INTO trading.futures_contract_references
 SELECT i.catalog_id,i.id,c.reference_catalog_id,c.reference_revision_id,c.futures_series_code,i.publication_order,i.effective_at
 FROM trading.instruments i JOIN trading.instrument_sides m ON(m.catalog_id,m.instrument_id)=(i.catalog_id,i.id)
 JOIN trading.futures_sides s ON(s.catalog_id,s.id)=(m.catalog_id,m.side_id)
 JOIN market_data.contracts c ON(c.catalog_id,c.revision_id,c.id)=(s.catalog_id,s.definition_revision_id,s.contract_id);
ALTER TABLE trading.trade_revisions ADD UNIQUE(catalog_id,trade_id,revision,instrument_id,publication_order,effective_at);
ALTER TABLE market_data.contracts ADD UNIQUE(catalog_id,revision_id,id,reference_catalog_id,reference_revision_id,futures_series_code);
CREATE TABLE trading.futures_revision_markets (
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,revision integer NOT NULL,instrument_id uuid NOT NULL,
 market_binding_id uuid NOT NULL,definition_revision_id uuid NOT NULL,curve_code ref_data.code NOT NULL,contract_id uuid NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,series_code ref_data.code NOT NULL,
 implementation text NOT NULL CHECK(implementation='fixed_total_cash_execution_pnl_v1'),
 publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,trade_id,revision),
 FOREIGN KEY(catalog_id,trade_id,revision,instrument_id,publication_order,effective_at) REFERENCES trading.trade_revisions(catalog_id,trade_id,revision,instrument_id,publication_order,effective_at),
 FOREIGN KEY(catalog_id,instrument_id,reference_catalog_id,reference_revision_id,series_code)
  REFERENCES trading.futures_contract_references(catalog_id,instrument_id,reference_catalog_id,reference_revision_id,series_code),
 FOREIGN KEY(catalog_id,definition_revision_id,curve_code,contract_id) REFERENCES market_data.curve_members(catalog_id,revision_id,curve_code,contract_id),
 FOREIGN KEY(catalog_id,definition_revision_id,contract_id,reference_catalog_id,reference_revision_id,series_code)
  REFERENCES market_data.contracts(catalog_id,revision_id,id,reference_catalog_id,reference_revision_id,futures_series_code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE INDEX futures_market_binding_lookup ON trading.futures_revision_markets
 (catalog_id,definition_revision_id,curve_code,contract_id,implementation) INCLUDE(market_binding_id);
INSERT INTO trading.futures_revision_markets
 SELECT r.catalog_id,r.trade_id,r.revision,r.instrument_id,s.id,s.definition_revision_id,s.curve_code,s.contract_id,
 c.reference_catalog_id,c.reference_revision_id,c.futures_series_code,s.implementation,r.publication_order,r.effective_at
 FROM trading.trade_revisions r JOIN trading.instrument_sides m ON(m.catalog_id,m.instrument_id)=(r.catalog_id,r.instrument_id)
 JOIN trading.futures_sides s ON(s.catalog_id,s.id)=(m.catalog_id,m.side_id)
 JOIN market_data.contracts c ON(c.catalog_id,c.revision_id,c.id)=(s.catalog_id,s.definition_revision_id,s.contract_id);
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['futures_contract_references','futures_revision_markets'] LOOP
  EXECUTE format('ALTER TABLE trading.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE trading.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY scoped_read ON trading.%I FOR SELECT TO openetrm_runtime USING(security.trading_visible(catalog_id,publication_order,effective_at))',t);
  EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.%I FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt()',t);
  EXECUTE format('GRANT SELECT,INSERT ON trading.%I TO openetrm_security_owner',t);
  EXECUTE format('GRANT SELECT ON trading.%I TO openetrm_runtime',t);
 END LOOP;
END $$;
CREATE FUNCTION security.retain_futures_market(catalog uuid,trade uuid,revision integer,instrument uuid,definition uuid,curve text,contract uuid,implementation text,ordinal integer,effective timestamptz)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE selected market_data.contracts;market_id uuid;
BEGIN
 SELECT * INTO STRICT selected FROM market_data.contracts c WHERE(c.catalog_id,c.revision_id,c.id)=(catalog,definition,contract);
 SELECT m.market_binding_id INTO market_id FROM trading.futures_revision_markets m
 WHERE(m.catalog_id,m.definition_revision_id,m.curve_code,m.contract_id,m.implementation)=(catalog,definition,curve,contract,retain_futures_market.implementation) LIMIT 1;
 INSERT INTO trading.futures_revision_markets VALUES(catalog,trade,revision,instrument,coalesce(market_id,gen_random_uuid()),definition,curve,contract,
 selected.reference_catalog_id,selected.reference_revision_id,selected.futures_series_code,implementation,ordinal,effective);
END $$;
CREATE OR REPLACE FUNCTION security.futures_booking_status(catalog uuid,operation uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb; actor uuid; pricing uuid;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'No trading access' USING ERRCODE='42501'; END IF;
 SELECT actor_id INTO actor FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 SELECT jsonb_build_object('operationId',t.operation_id,'tradeId',t.id,'bookId',t.book_id,'instrumentId',p.instrument_id,'bindingId',p.binding_id,
  'sideId',m.market_binding_id,'settlement',p.settlement_state,'controlState','current'),m.market_binding_id INTO result,pricing
 FROM trading.trades t JOIN trading.trade_instruments p ON(p.catalog_id,p.trade_id)=(t.catalog_id,t.id)
 LEFT JOIN trading.futures_revision_markets m ON(m.catalog_id,m.trade_id,m.revision)=(p.catalog_id,p.trade_id,1)
 WHERE t.catalog_id=catalog AND t.operation_id=operation AND t.actor_id=actor;
 IF result IS NOT NULL AND pricing IS NULL THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'Trading access expired' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION security.prepare_futures_binding(catalog uuid,book uuid,revision uuid,curve text,contract uuid,
 valuation timestamptz,executed timestamptz,lots numeric,execution numeric,implementation text,ordinal integer)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE q ref_data.quote_specifications;product ref_data.futures_products;series_row ref_data.futures_series;
 contract_row market_data.contracts;curve_row market_data.curves;definition_from timestamptz;starts timestamptz;ends timestamptz;side uuid;instrument uuid;
BEGIN
 IF executed IS NULL OR NOT isfinite(executed) OR valuation IS NULL OR NOT isfinite(valuation) OR implementation IS DISTINCT FROM 'fixed_total_cash_execution_pnl_v1'
 THEN RAISE EXCEPTION 'futures_input' USING ERRCODE='P0001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM trading.books b JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id) WHERE b.catalog_id=catalog AND b.id=book AND b.effective_at<=executed AND p.effective_at<=executed) THEN RAISE EXCEPTION 'futures_book' USING ERRCODE='P0001'; END IF;
 IF lots IS NULL OR lots<>trunc(lots) OR lots=0 OR abs(lots)>100000 THEN RAISE EXCEPTION 'futures_lots' USING ERRCODE='P0001'; END IF;
 SELECT * INTO contract_row FROM market_data.contracts WHERE catalog_id=catalog AND revision_id=revision AND id=contract;
 SELECT * INTO curve_row FROM market_data.curves WHERE catalog_id=catalog AND revision_id=revision AND code=curve;
 IF contract_row.kind IS DISTINCT FROM 'future' OR curve_row.rule IS DISTINCT FROM 'direct' OR curve_row.direct_role IS DISTINCT FROM 'daily_settlement' OR
  NOT EXISTS(SELECT 1 FROM market_data.curve_members WHERE catalog_id=catalog AND revision_id=revision AND curve_code=curve AND contract_id=contract) THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 SELECT p.* INTO product FROM ref_data.futures_series s JOIN ref_data.futures_products p ON(p.catalog_id,p.revision_id,p.code)=(s.catalog_id,s.revision_id,s.product_code)
 WHERE(s.catalog_id,s.revision_id,s.code)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code) AND s.definition_state='synthetic';
 IF product.definition_state IS DISTINCT FROM 'synthetic' OR product.settlement_method IS DISTINCT FROM 'cash' OR product.lot_basis IS DISTINCT FROM 'fixed_total' OR product.lot_unit_code IS DISTINCT FROM product.quote_unit_code THEN RAISE EXCEPTION 'futures_convention' USING ERRCODE='P0001'; END IF;
 SELECT * INTO series_row FROM ref_data.futures_series WHERE(catalog_id,revision_id,code)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code);
 IF series_row.delivery_from IS DISTINCT FROM contract_row.delivery_from OR series_row.delivery_to IS DISTINCT FROM contract_row.delivery_to OR
  curve_row.commodity_code IS DISTINCT FROM product.commodity_code OR curve_row.location_code IS DISTINCT FROM product.location_code THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 SELECT * INTO q FROM ref_data.quote_specifications WHERE(catalog_id,revision_id,code)=(curve_row.reference_catalog_id,curve_row.reference_revision_id,curve_row.quote_code);
 IF q.kind IS DISTINCT FROM 'outright' OR q.currency_code IS DISTINCT FROM product.quote_currency_code OR q.multiplier IS DISTINCT FROM product.quote_multiplier OR q.trading_tick IS DISTINCT FROM product.outright_tick_size OR
  (SELECT count(*) FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,commodity_code,unit_code)=(q.catalog_id,q.revision_id,product.commodity_code,product.quote_unit_code))<>1 OR
  NOT EXISTS(SELECT 1 FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code,commodity_code,unit_code)=(q.catalog_id,q.revision_id,q.quantity_code,product.commodity_code,product.quote_unit_code))
 THEN RAISE EXCEPTION 'futures_convention' USING ERRCODE='P0001'; END IF;
 SELECT event_at INTO starts FROM ref_data.futures_milestones WHERE(catalog_id,revision_id,series_code,milestone)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code,'first_trading') AND value_state='known';
 SELECT event_at INTO ends FROM ref_data.futures_milestones WHERE(catalog_id,revision_id,series_code,milestone)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code,'last_trading') AND value_state='known';
 IF ends IS DISTINCT FROM contract_row.expiry_at THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 IF starts IS NULL OR executed<starts OR executed>=ends OR executed>valuation OR valuation<starts OR valuation>=ends OR execution IS NULL OR execution<q.minimum OR execution>q.maximum OR mod(execution,product.outright_tick_size)<>0 THEN RAISE EXCEPTION 'futures_execution' USING ERRCODE='P0001'; END IF;
 SELECT (effective_from::timestamp AT TIME ZONE 'UTC') INTO definition_from FROM market_data.revision_periods WHERE catalog_id=catalog AND revision_id=revision AND effective_from<=(executed AT TIME ZONE 'UTC')::date AND(executed AT TIME ZONE 'UTC')::date<effective_to;
 IF definition_from IS NULL OR NOT EXISTS(SELECT 1 FROM market_data.revisions WHERE catalog_id=catalog AND id=revision AND state='sealed') THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 instrument=security.futures_contract_id(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code);
 IF EXISTS(SELECT 1 FROM trading.instruments i WHERE i.catalog_id=catalog AND i.id=instrument) THEN
  IF NOT EXISTS(SELECT 1 FROM trading.futures_contract_references f WHERE f.catalog_id=catalog AND f.instrument_id=instrument
   AND(f.reference_catalog_id,f.reference_revision_id,f.series_code)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code))
  THEN RAISE EXCEPTION 'futures_identity' USING ERRCODE='P0001'; END IF;
 ELSE
  INSERT INTO trading.instruments VALUES(catalog,instrument,ordinal,definition_from);
  INSERT INTO trading.futures_contract_references VALUES(catalog,instrument,contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code,ordinal,definition_from);
 END IF;
 RETURN instrument;
END $$;
CREATE OR REPLACE FUNCTION security.book_futures_with_parties(catalog uuid,operation uuid,book uuid,revision uuid,curve text,contract uuid,
 valuation timestamptz,executed timestamptz,lots numeric,execution numeric,implementation text,trader uuid,trader_revision integer,memo text,booking jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts; prior trading.trades; request_value jsonb; ordinal integer; instrument uuid; trade uuid; binding uuid;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'No booking access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'Booking access expired' USING ERRCODE='42501'; END IF;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR executed IS NULL OR NOT isfinite(executed) OR valuation IS NULL OR NOT isfinite(valuation) OR implementation IS DISTINCT FROM 'fixed_total_cash_execution_pnl_v1' THEN RAISE EXCEPTION 'futures_input' USING ERRCODE='P0001'; END IF;
 request_value=jsonb_build_object('book',book,'revision',revision,'curve',curve,'contract',contract,'valuation',valuation AT TIME ZONE 'UTC','executed',executed AT TIME ZONE 'UTC','lots',lots,'execution',execution,'implementation',implementation);
 request_value=request_value||jsonb_build_object('booking',booking);
 IF trader IS NOT NULL OR trader_revision IS NOT NULL OR memo IS NOT NULL THEN request_value=request_value||jsonb_build_object('trader',trader,'traderRevision',trader_revision,'memo',memo);END IF;
 SELECT * INTO prior FROM trading.trades WHERE catalog_id=catalog AND operation_id=operation;
 IF FOUND THEN
  IF prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.futures_booking_status(catalog,operation);
 END IF;
 IF EXISTS(SELECT 1 FROM trading.trade_revisions WHERE catalog_id=catalog AND operation_id=operation) THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
 PERFORM security.require_trade_annotation(catalog,trader,trader_revision,memo,executed);
 PERFORM security.require_trade_parties(catalog,booking,executed);
 IF(SELECT count(*) FROM trading.trades WHERE catalog_id=catalog)>=256 THEN RAISE EXCEPTION 'futures_limit' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO ordinal FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,ordinal,pg_current_xact_id());
 instrument=security.prepare_futures_binding(catalog,book,revision,curve,contract,valuation,executed,lots,execution,implementation,ordinal);
 trade=gen_random_uuid();binding=gen_random_uuid();
 INSERT INTO trading.trades VALUES(catalog,trade,book,operation,c.actor_id,request_value,ordinal,executed);
 INSERT INTO trading.trade_instruments VALUES(catalog,trade,binding,instrument,lots,execution,'unprocessed',ordinal,executed);
 INSERT INTO trading.trade_revisions VALUES(catalog,trade,1,NULL,gen_random_uuid(),'futures_booking_state_v2','booked',book,binding,instrument,lots,execution,executed,executed,'unprocessed',operation,c.actor_id,'Initial booking',request_value,ordinal,trader,trader_revision,memo,(booking->>'tradeDate')::date,(booking->>'legalEntityId')::uuid,(booking->>'legalEntityRevision')::integer,(booking->>'counterpartyId')::uuid,(booking->>'counterpartyRevision')::integer);
 PERFORM security.retain_futures_market(catalog,trade,1,instrument,revision,curve,contract,implementation,ordinal,executed);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'Booking access expired' USING ERRCODE='42501'; END IF;
 RETURN security.futures_booking_status(catalog,operation);
END $$;

CREATE OR REPLACE FUNCTION security.amend_futures_with_parties(catalog uuid,operation uuid,trade uuid,expected integer,book uuid,definition uuid,curve text,contract uuid,
 valuation timestamptz,effective timestamptz,executed timestamptz,lots numeric,execution numeric,reason text,implementation text,convention text,trader uuid,trader_revision integer,memo text,booking jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts;head trading.trade_revisions;prior trading.trade_revisions;request_value jsonb;ordinal integer;instrument uuid;binding uuid;old_side trading.futures_revision_markets;old_currency record;new_currency record;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'AmendTrade') THEN RAISE EXCEPTION 'No amendment access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF NOT security.trading_access(catalog,'AmendTrade') THEN RAISE EXCEPTION 'Amendment access expired' USING ERRCODE='42501'; END IF;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR expected IS NULL OR expected<1 OR
  reason IS NULL OR length(btrim(reason)) NOT BETWEEN 1 AND 500 OR reason ~ '^[[:space:]]*$' OR effective IS NULL OR NOT isfinite(effective) OR effective IS DISTINCT FROM valuation OR
  convention IS DISTINCT FROM 'unprocessed_futures_booking_amendment_v1' THEN RAISE EXCEPTION 'futures_amendment' USING ERRCODE='P0001'; END IF;
 request_value=jsonb_build_object('trade',trade,'expected',expected,'book',book,'definition',definition,'curve',curve,'contract',contract,
 'valuation',valuation AT TIME ZONE 'UTC','effective',effective AT TIME ZONE 'UTC','executed',executed AT TIME ZONE 'UTC',
 'lots',lots,'execution',execution,'reason',reason,'implementation',implementation,'convention',convention);
 request_value=request_value||jsonb_build_object('booking',booking);
 IF trader IS NOT NULL OR trader_revision IS NOT NULL OR memo IS NOT NULL THEN request_value=request_value||jsonb_build_object('trader',trader,'traderRevision',trader_revision,'memo',memo);END IF;
 SELECT * INTO prior FROM trading.trade_revisions r WHERE r.catalog_id=catalog AND r.operation_id=operation;
 IF FOUND THEN
  IF prior.event_kind<>'amended' OR prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.futures_operation_status(catalog,operation);
 END IF;
 PERFORM security.require_trade_annotation(catalog,trader,trader_revision,memo,executed);
 PERFORM security.require_trade_parties(catalog,booking,executed);
 SELECT * INTO head FROM trading.trade_revisions r WHERE r.catalog_id=catalog AND r.trade_id=trade ORDER BY r.revision DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'futures_trade' USING ERRCODE='P0001'; END IF;
 IF head.revision<>expected THEN RAISE EXCEPTION 'futures_revision_conflict' USING ERRCODE='P0001'; END IF;
 IF head.revision>=256 THEN RAISE EXCEPTION 'futures_limit' USING ERRCODE='P0001'; END IF;
 IF effective<head.effective_at OR head.settlement_state<>'unprocessed' THEN RAISE EXCEPTION 'futures_amendment' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO ordinal FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,ordinal,pg_current_xact_id());
 SELECT * INTO STRICT old_side FROM trading.futures_revision_markets m WHERE(m.catalog_id,m.trade_id,m.revision)=(catalog,trade,head.revision);
 IF old_side.definition_revision_id IS DISTINCT FROM definition THEN RAISE EXCEPTION 'futures_amendment' USING ERRCODE='P0001'; END IF;
 -- Validate the retained state as well: amendment is not settlement or an expiry escape.
 PERFORM security.prepare_futures_binding(catalog,head.book_id,old_side.definition_revision_id,old_side.curve_code,old_side.contract_id,
  valuation,head.execution_at,head.lots,head.execution_price,old_side.implementation,ordinal);
 SELECT q.catalog_id,q.revision_id,q.currency_code INTO old_currency FROM market_data.curves cv JOIN ref_data.quote_specifications q
 ON(q.catalog_id,q.revision_id,q.code)=(cv.reference_catalog_id,cv.reference_revision_id,cv.quote_code)
 WHERE cv.catalog_id=catalog AND cv.revision_id=definition AND cv.code=old_side.curve_code;
 SELECT q.catalog_id,q.revision_id,q.currency_code INTO new_currency FROM market_data.curves cv JOIN ref_data.quote_specifications q
 ON(q.catalog_id,q.revision_id,q.code)=(cv.reference_catalog_id,cv.reference_revision_id,cv.quote_code)
 WHERE cv.catalog_id=catalog AND cv.revision_id=definition AND cv.code=curve;
 IF old_currency IS DISTINCT FROM new_currency THEN RAISE EXCEPTION 'futures_amendment' USING ERRCODE='P0001'; END IF;
 instrument=security.prepare_futures_binding(catalog,book,definition,curve,contract,valuation,executed,lots,execution,implementation,ordinal);
 IF EXISTS(SELECT 1 FROM trading.futures_contract_references a JOIN trading.futures_contract_references b
  ON(b.catalog_id,b.reference_catalog_id,b.reference_revision_id,b.series_code)=(a.catalog_id,a.reference_catalog_id,a.reference_revision_id,a.series_code)
  WHERE(a.catalog_id,a.instrument_id,b.instrument_id)=(catalog,instrument,head.instrument_id)) THEN instrument=head.instrument_id; END IF;
 IF (book,instrument,lots,execution,executed,trader,trader_revision,memo,booking,definition,curve,contract) IS NOT DISTINCT FROM (head.book_id,head.instrument_id,head.lots,head.execution_price,head.execution_at,head.trader_id,head.trader_revision,head.memo,security.trade_party_payload(head.trade_date,head.legal_entity_id,head.legal_entity_revision,head.counterparty_id,head.counterparty_revision),old_side.definition_revision_id,old_side.curve_code,old_side.contract_id)
 THEN RAISE EXCEPTION 'futures_no_change' USING ERRCODE='P0001'; END IF;
 binding=CASE WHEN instrument=head.instrument_id THEN head.binding_id ELSE gen_random_uuid() END;
 INSERT INTO trading.trade_revisions VALUES(catalog,trade,head.revision+1,head.revision,gen_random_uuid(),'futures_booking_state_v2','amended',book,binding,instrument,lots,execution,executed,effective,
 'unprocessed',operation,c.actor_id,reason,request_value,ordinal,trader,trader_revision,memo,(booking->>'tradeDate')::date,(booking->>'legalEntityId')::uuid,(booking->>'legalEntityRevision')::integer,(booking->>'counterpartyId')::uuid,(booking->>'counterpartyRevision')::integer);
 PERFORM security.retain_futures_market(catalog,trade,head.revision+1,instrument,definition,curve,contract,implementation,ordinal,effective);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'AmendTrade') THEN RAISE EXCEPTION 'Amendment access expired' USING ERRCODE='42501'; END IF;
 RETURN security.futures_operation_status(catalog,operation);
END $$;

DO $$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='security' AND p.proname IN('futures_contract_id','retain_futures_market','prepare_futures_binding') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f.signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.signature);
 END LOOP;
END $$;
COMMIT;
