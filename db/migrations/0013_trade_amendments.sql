-- Upgrade requires stopped runtime write admission and drained legacy calls.
-- The publication fence alone cannot replace an already-running function body.
-- Retained trade revisions and latest-head booking amendments.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT pg_advisory_xact_lock(730849102);
LOCK TABLE trading.trades,trading.trade_instruments IN SHARE ROW EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM trading.trades t LEFT JOIN trading.trade_instruments p ON(p.catalog_id,p.trade_id)=(t.catalog_id,t.id)
  GROUP BY t.catalog_id,t.id HAVING count(p.binding_id)<>1)
 THEN RAISE EXCEPTION 'Trade revision migration requires one supported futures binding per trade'; END IF;
END $$;
CREATE TABLE trading.trade_revisions (
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,revision integer NOT NULL CHECK(revision BETWEEN 1 AND 256),previous_revision integer,
 event_id uuid NOT NULL,event_schema text NOT NULL CHECK(event_schema='futures_booking_state_v1'),event_kind text NOT NULL CHECK(event_kind IN('booked','amended')),
 book_id uuid NOT NULL,binding_id uuid NOT NULL,instrument_id uuid NOT NULL,
 lots ref_data.exact_number NOT NULL CHECK(lots<>0 AND lots=trunc(lots) AND abs(lots)<=100000),execution_price ref_data.exact_number NOT NULL,
 execution_at ref_data.instant NOT NULL,effective_at ref_data.instant NOT NULL,settlement_state text NOT NULL CHECK(settlement_state='unprocessed'),
 operation_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 500 AND reason !~ '^[[:space:]]*$'),
 request jsonb NOT NULL,publication_order integer NOT NULL,
 PRIMARY KEY(catalog_id,trade_id,revision),UNIQUE(catalog_id,event_id),UNIQUE(catalog_id,operation_id),
 FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.trades(catalog_id,id),
 FOREIGN KEY(catalog_id,trade_id,previous_revision) REFERENCES trading.trade_revisions(catalog_id,trade_id,revision),
 FOREIGN KEY(catalog_id,book_id) REFERENCES trading.books(catalog_id,id),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.instruments(catalog_id,id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order),
 CHECK(execution_at<=effective_at),
 CHECK((revision=1 AND previous_revision IS NULL AND event_kind='booked') OR (revision>1 AND previous_revision=revision-1 AND event_kind='amended'))
);
-- Original bookings retain the same publication/effective coordinates on upgrade.
INSERT INTO trading.trade_revisions
 SELECT t.catalog_id,t.id,1,NULL,gen_random_uuid(),'futures_booking_state_v1','booked',t.book_id,p.binding_id,p.instrument_id,p.lots,p.execution_price,p.effective_at,p.effective_at,p.settlement_state,
 t.operation_id,t.actor_id,'Initial booking',t.request,p.publication_order
 FROM trading.trades t JOIN trading.trade_instruments p ON(p.catalog_id,p.trade_id)=(t.catalog_id,t.id);
ALTER TABLE trading.trade_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading.trade_revisions FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON trading.trade_revisions FOR SELECT TO openetrm_runtime
 USING(security.trading_visible(catalog_id,publication_order,effective_at));
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.trade_revisions FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
GRANT SELECT,INSERT ON trading.trade_revisions TO openetrm_security_owner;
GRANT SELECT ON trading.trade_revisions TO openetrm_runtime;

CREATE FUNCTION security.prepare_futures_binding(catalog uuid,book uuid,revision uuid,curve text,contract uuid,
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
 SELECT id INTO side FROM trading.futures_sides WHERE catalog_id=catalog AND definition_revision_id=revision AND curve_code=curve AND contract_id=contract AND futures_sides.implementation=prepare_futures_binding.implementation;
 IF side IS NULL THEN
  side=gen_random_uuid();instrument=gen_random_uuid();
  INSERT INTO trading.futures_sides VALUES(catalog,side,revision,curve,contract,implementation,ordinal,definition_from);
  INSERT INTO trading.instruments VALUES(catalog,instrument,ordinal,definition_from);
  INSERT INTO trading.instrument_sides VALUES(catalog,instrument,side,1,ordinal,definition_from);
 ELSE SELECT instrument_id INTO instrument FROM trading.instrument_sides WHERE catalog_id=catalog AND side_id=side; END IF;
 RETURN instrument;
END $$;

CREATE OR REPLACE FUNCTION security.book_futures(catalog uuid,operation uuid,book uuid,revision uuid,curve text,contract uuid,
 valuation timestamptz,executed timestamptz,lots numeric,execution numeric,implementation text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts; prior trading.trades; request_value jsonb; ordinal integer; instrument uuid; trade uuid; binding uuid;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'No booking access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'Booking access expired' USING ERRCODE='42501'; END IF;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR executed IS NULL OR NOT isfinite(executed) OR valuation IS NULL OR NOT isfinite(valuation) OR implementation IS DISTINCT FROM 'fixed_total_cash_execution_pnl_v1' THEN RAISE EXCEPTION 'futures_input' USING ERRCODE='P0001'; END IF;
 request_value=jsonb_build_object('book',book,'revision',revision,'curve',curve,'contract',contract,'valuation',valuation AT TIME ZONE 'UTC','executed',executed AT TIME ZONE 'UTC','lots',lots,'execution',execution,'implementation',implementation);
 SELECT * INTO prior FROM trading.trades WHERE catalog_id=catalog AND operation_id=operation;
 IF FOUND THEN
  IF prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.futures_booking_status(catalog,operation);
 END IF;
 IF EXISTS(SELECT 1 FROM trading.trade_revisions WHERE catalog_id=catalog AND operation_id=operation) THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
 IF(SELECT count(*) FROM trading.trades WHERE catalog_id=catalog)>=256 THEN RAISE EXCEPTION 'futures_limit' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO ordinal FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,ordinal,pg_current_xact_id());
 instrument=security.prepare_futures_binding(catalog,book,revision,curve,contract,valuation,executed,lots,execution,implementation,ordinal);
 trade=gen_random_uuid();binding=gen_random_uuid();
 INSERT INTO trading.trades VALUES(catalog,trade,book,operation,c.actor_id,request_value,ordinal,executed);
 INSERT INTO trading.trade_instruments VALUES(catalog,trade,binding,instrument,lots,execution,'unprocessed',ordinal,executed);
 INSERT INTO trading.trade_revisions VALUES(catalog,trade,1,NULL,gen_random_uuid(),'futures_booking_state_v1','booked',book,binding,instrument,lots,execution,executed,executed,'unprocessed',operation,c.actor_id,'Initial booking',request_value,ordinal);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'Booking access expired' USING ERRCODE='42501'; END IF;
 RETURN security.futures_booking_status(catalog,operation);
END $$;
CREATE FUNCTION security.futures_current_head(catalog uuid,trade uuid) RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result integer;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'No trading access' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned()
  AND runtime_login=session_user AND market_context_id IS NOT NULL) THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT max(r.revision) INTO result FROM trading.trade_revisions r WHERE r.catalog_id=catalog AND r.trade_id=trade;
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'Trading access expired' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;
CREATE FUNCTION security.futures_operation_status(catalog uuid,operation uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;actor uuid;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'No trading access' USING ERRCODE='42501'; END IF;
 SELECT actor_id INTO actor FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 SELECT jsonb_build_object('operationId',r.operation_id,'tradeId',r.trade_id,'bookId',r.book_id,'instrumentId',r.instrument_id,'bindingId',r.binding_id,
 'controlState','current','revision',r.revision,'eventId',r.event_id,'eventSchema',r.event_schema,'kind',r.event_kind,'settlement',r.settlement_state,'effectiveAt',r.effective_at)
 INTO result FROM trading.trade_revisions r WHERE r.catalog_id=catalog AND r.operation_id=operation AND r.actor_id=actor AND r.event_kind='amended';
 IF result IS NULL THEN result=security.futures_booking_status(catalog,operation); END IF;
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'Trading access expired' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;
CREATE FUNCTION security.amend_futures(catalog uuid,operation uuid,trade uuid,expected integer,book uuid,definition uuid,curve text,contract uuid,
 valuation timestamptz,effective timestamptz,executed timestamptz,lots numeric,execution numeric,reason text,implementation text,convention text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts;head trading.trade_revisions;prior trading.trade_revisions;request_value jsonb;ordinal integer;instrument uuid;binding uuid;old_side trading.futures_sides;old_currency record;new_currency record;
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
 SELECT * INTO prior FROM trading.trade_revisions r WHERE r.catalog_id=catalog AND r.operation_id=operation;
 IF FOUND THEN
  IF prior.event_kind<>'amended' OR prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.futures_operation_status(catalog,operation);
 END IF;
 SELECT * INTO head FROM trading.trade_revisions r WHERE r.catalog_id=catalog AND r.trade_id=trade ORDER BY r.revision DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'futures_trade' USING ERRCODE='P0001'; END IF;
 IF head.revision<>expected THEN RAISE EXCEPTION 'futures_revision_conflict' USING ERRCODE='P0001'; END IF;
 IF head.revision>=256 THEN RAISE EXCEPTION 'futures_limit' USING ERRCODE='P0001'; END IF;
 IF effective<head.effective_at OR head.settlement_state<>'unprocessed' THEN RAISE EXCEPTION 'futures_amendment' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO ordinal FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,ordinal,pg_current_xact_id());
 SELECT s.* INTO old_side FROM trading.instrument_sides m JOIN trading.futures_sides s ON(s.catalog_id,s.id)=(m.catalog_id,m.side_id)
 WHERE m.catalog_id=catalog AND m.instrument_id=head.instrument_id;
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
 IF (book,instrument,lots,execution,executed) IS NOT DISTINCT FROM (head.book_id,head.instrument_id,head.lots,head.execution_price,head.execution_at)
 THEN RAISE EXCEPTION 'futures_no_change' USING ERRCODE='P0001'; END IF;
 binding=CASE WHEN instrument=head.instrument_id THEN head.binding_id ELSE gen_random_uuid() END;
 INSERT INTO trading.trade_revisions VALUES(catalog,trade,head.revision+1,head.revision,gen_random_uuid(),'futures_booking_state_v1','amended',book,binding,instrument,lots,execution,executed,effective,
 'unprocessed',operation,c.actor_id,reason,request_value,ordinal);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'AmendTrade') THEN RAISE EXCEPTION 'Amendment access expired' USING ERRCODE='42501'; END IF;
 RETURN security.futures_operation_status(catalog,operation);
END $$;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure signature,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='security' AND p.proname IN('prepare_futures_binding','book_futures','futures_current_head','futures_operation_status','amend_futures') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f.signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.signature);
  IF f.proname<>'prepare_futures_binding' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO openetrm_runtime',f.signature); END IF;
 END LOOP;
END $$;
COMMIT;
