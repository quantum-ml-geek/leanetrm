-- Optional revisioned business attribution, independent of recording authority.
BEGIN;
CREATE TABLE trading.traders (
 catalog_id uuid NOT NULL REFERENCES market_data.catalogs(id),id uuid NOT NULL,revision integer NOT NULL CHECK(revision>0),
 code text NOT NULL CHECK(code ~ '^[a-z][a-z0-9_]{0,47}$'),name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 80),
 publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id,revision),UNIQUE(catalog_id,code,revision),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
ALTER TABLE trading.traders ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading.traders FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON trading.traders FOR SELECT TO openetrm_runtime USING(security.trading_visible(catalog_id,publication_order,effective_at));
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.traders FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
GRANT SELECT ON trading.traders TO openetrm_runtime,openetrm_security_owner;
ALTER TABLE trading.trade_revisions ADD COLUMN trader_id uuid,ADD COLUMN trader_revision integer,ADD COLUMN memo text CHECK(length(memo)<=4000),
 ADD FOREIGN KEY(catalog_id,trader_id,trader_revision) REFERENCES trading.traders(catalog_id,id,revision),
 ADD CHECK((trader_id IS NULL)=(trader_revision IS NULL));
ALTER TABLE trading.swap_trade_revisions ADD COLUMN trader_id uuid,ADD COLUMN trader_revision integer,ADD COLUMN memo text CHECK(length(memo)<=4000),
 ADD FOREIGN KEY(catalog_id,trader_id,trader_revision) REFERENCES trading.traders(catalog_id,id,revision),
 ADD CHECK((trader_id IS NULL)=(trader_revision IS NULL));
CREATE FUNCTION security.require_trade_annotation(catalog uuid,trader uuid,trader_revision integer,memo text,executed timestamptz) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF(trader IS NULL)<>(trader_revision IS NULL) OR length(memo)>4000 OR
 (trader IS NOT NULL AND NOT EXISTS(SELECT 1 FROM trading.traders t WHERE t.catalog_id=catalog AND t.id=trader AND t.revision=trader_revision AND t.effective_at<=executed AND security.trading_access(catalog,'ReadTrades') AND(EXISTS(SELECT 1 FROM security.request_contexts c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user AND c.market_context_id IS NULL) OR security.trading_visible(catalog,t.publication_order,t.effective_at))))
 THEN RAISE EXCEPTION 'trade_annotation' USING ERRCODE='P0001';END IF;
END $$;
CREATE FUNCTION security.book_futures_annotated(catalog uuid,operation uuid,book uuid,revision uuid,curve text,contract uuid,
 valuation timestamptz,executed timestamptz,lots numeric,execution numeric,implementation text,trader uuid,trader_revision integer,memo text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts; prior trading.trades; request_value jsonb; ordinal integer; instrument uuid; trade uuid; binding uuid;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'No booking access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'Booking access expired' USING ERRCODE='42501'; END IF;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR executed IS NULL OR NOT isfinite(executed) OR valuation IS NULL OR NOT isfinite(valuation) OR implementation IS DISTINCT FROM 'fixed_total_cash_execution_pnl_v1' THEN RAISE EXCEPTION 'futures_input' USING ERRCODE='P0001'; END IF;
 request_value=jsonb_build_object('book',book,'revision',revision,'curve',curve,'contract',contract,'valuation',valuation AT TIME ZONE 'UTC','executed',executed AT TIME ZONE 'UTC','lots',lots,'execution',execution,'implementation',implementation);
 IF trader IS NOT NULL OR trader_revision IS NOT NULL OR memo IS NOT NULL THEN request_value=request_value||jsonb_build_object('trader',trader,'traderRevision',trader_revision,'memo',memo);END IF;
 SELECT * INTO prior FROM trading.trades WHERE catalog_id=catalog AND operation_id=operation;
 IF FOUND THEN
  IF prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.futures_booking_status(catalog,operation);
 END IF;
 IF EXISTS(SELECT 1 FROM trading.trade_revisions WHERE catalog_id=catalog AND operation_id=operation) THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
 PERFORM security.require_trade_annotation(catalog,trader,trader_revision,memo,executed);
 IF(SELECT count(*) FROM trading.trades WHERE catalog_id=catalog)>=256 THEN RAISE EXCEPTION 'futures_limit' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO ordinal FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,ordinal,pg_current_xact_id());
 instrument=security.prepare_futures_binding(catalog,book,revision,curve,contract,valuation,executed,lots,execution,implementation,ordinal);
 trade=gen_random_uuid();binding=gen_random_uuid();
 INSERT INTO trading.trades VALUES(catalog,trade,book,operation,c.actor_id,request_value,ordinal,executed);
 INSERT INTO trading.trade_instruments VALUES(catalog,trade,binding,instrument,lots,execution,'unprocessed',ordinal,executed);
 INSERT INTO trading.trade_revisions VALUES(catalog,trade,1,NULL,gen_random_uuid(),'futures_booking_state_v1','booked',book,binding,instrument,lots,execution,executed,executed,'unprocessed',operation,c.actor_id,'Initial booking',request_value,ordinal,trader,trader_revision,memo);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'Booking access expired' USING ERRCODE='42501'; END IF;
 RETURN security.futures_booking_status(catalog,operation);
END $$;

CREATE FUNCTION security.amend_futures_annotated(catalog uuid,operation uuid,trade uuid,expected integer,book uuid,definition uuid,curve text,contract uuid,
 valuation timestamptz,effective timestamptz,executed timestamptz,lots numeric,execution numeric,reason text,implementation text,convention text,trader uuid,trader_revision integer,memo text)
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
 IF trader IS NOT NULL OR trader_revision IS NOT NULL OR memo IS NOT NULL THEN request_value=request_value||jsonb_build_object('trader',trader,'traderRevision',trader_revision,'memo',memo);END IF;
 SELECT * INTO prior FROM trading.trade_revisions r WHERE r.catalog_id=catalog AND r.operation_id=operation;
 IF FOUND THEN
  IF prior.event_kind<>'amended' OR prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.futures_operation_status(catalog,operation);
 END IF;
 PERFORM security.require_trade_annotation(catalog,trader,trader_revision,memo,executed);
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
 IF (book,instrument,lots,execution,executed,trader,trader_revision,memo) IS NOT DISTINCT FROM (head.book_id,head.instrument_id,head.lots,head.execution_price,head.execution_at,head.trader_id,head.trader_revision,head.memo)
 THEN RAISE EXCEPTION 'futures_no_change' USING ERRCODE='P0001'; END IF;
 binding=CASE WHEN instrument=head.instrument_id THEN head.binding_id ELSE gen_random_uuid() END;
 INSERT INTO trading.trade_revisions VALUES(catalog,trade,head.revision+1,head.revision,gen_random_uuid(),'futures_booking_state_v1','amended',book,binding,instrument,lots,execution,executed,effective,
 'unprocessed',operation,c.actor_id,reason,request_value,ordinal,trader,trader_revision,memo);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'AmendTrade') THEN RAISE EXCEPTION 'Amendment access expired' USING ERRCODE='42501'; END IF;
 RETURN security.futures_operation_status(catalog,operation);
END $$;

CREATE FUNCTION security.save_annotated_swap(catalog uuid,operation uuid,trade uuid,expected integer,book uuid,definition uuid,ref_catalog uuid,ref_revision uuid,
 curve text,index_name text,fixed_currency text,float_currency text,fixed_from date,fixed_to date,fixed_payment timestamptz,float_from date,float_to date,
 fixing timestamptz,float_payment timestamptz,averaging text,price numeric,quantity numeric,coefficient numeric,discounting boolean,
 valuation timestamptz,executed timestamptz,effective timestamptz,reason text,implementation text,fixed_schedule jsonb,float_schedule jsonb,commodity text,trader uuid,trader_revision integer,memo text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE fixed_rule uuid;float_rule uuid;c security.request_contexts;prior trading.swap_trade_revisions;head trading.swap_trade_revisions;request_value jsonb;permission text;publication_number integer;
 cv market_data.curves;q ref_data.quote_specifications;k market_data.contracts;target ref_data.settlement_targets;fixed_side uuid;floating_side uuid;instrument uuid;binding uuid;from_at timestamptz;
BEGIN
 permission=CASE WHEN trade IS NULL THEN 'BookTrade' ELSE 'AmendTrade' END;
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,permission) THEN RAISE EXCEPTION 'No trade write access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF NOT security.trading_access(catalog,permission) THEN RAISE EXCEPTION 'Trade write access expired' USING ERRCODE='42501'; END IF;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR implementation IS DISTINCT FROM 'independent_side_financial_swap_v2' OR
  discounting IS NULL OR coefficient IS NULL OR coefficient NOT IN(-1,1) OR quantity IS NULL OR quantity<=0 OR abs(quantity)>=1e24 OR scale(quantity)>18 OR
  valuation IS NULL OR executed IS NULL OR effective IS NULL OR NOT isfinite(valuation) OR NOT isfinite(executed) OR NOT isfinite(effective) OR executed>effective OR effective>valuation OR
  fixed_from IS NULL OR fixed_to IS NULL OR fixed_to<=fixed_from OR fixed_to-fixed_from>366 OR
  fixed_payment IS NULL OR float_payment IS NULL OR fixing IS NULL OR NOT isfinite(fixed_payment) OR NOT isfinite(float_payment) OR NOT isfinite(fixing) OR
  valuation>=fixing OR valuation>=fixed_payment OR valuation>=float_payment OR fixing>=float_payment OR(fixed_schedule IS NULL AND(fixed_payment AT TIME ZONE 'UTC')::date<fixed_to) OR(float_schedule IS NULL AND(float_payment AT TIME ZONE 'UTC')::date<float_to) OR
  averaging IS NULL OR averaging NOT IN('monthly_index_price','calendar_day_arithmetic') OR price IS NULL OR abs(price)>=1e24 OR scale(price)>18
 THEN RAISE EXCEPTION 'swap_input' USING ERRCODE='P0001'; END IF;
 request_value=jsonb_build_object('trade',trade,'expected',expected,'book',book,'definition',definition,'referenceCatalog',ref_catalog,'referenceRevision',ref_revision,
  'curve',curve,'index',index_name,'fixedCurrency',fixed_currency,'floatingCurrency',float_currency,'fixedFrom',fixed_from,'fixedTo',fixed_to,'fixedPayment',fixed_payment AT TIME ZONE 'UTC',
  'floatingFrom',float_from,'floatingTo',float_to,'firstFixing',fixing AT TIME ZONE 'UTC','floatingPayment',float_payment AT TIME ZONE 'UTC','averaging',averaging,
  'price',price,'quantity',quantity,'coefficient',coefficient,'discounting',discounting,'valuation',valuation AT TIME ZONE 'UTC','executed',executed AT TIME ZONE 'UTC','effective',effective AT TIME ZONE 'UTC','reason',reason,'implementation',implementation);
 IF fixed_schedule IS NOT NULL OR float_schedule IS NOT NULL OR commodity IS NOT NULL THEN request_value=request_value||jsonb_build_object('fixedSchedule',fixed_schedule,'floatingSchedule',float_schedule,'commodity',commodity);END IF;
 IF trader IS NOT NULL OR trader_revision IS NOT NULL OR memo IS NOT NULL THEN request_value=request_value||jsonb_build_object('trader',trader,'traderRevision',trader_revision,'memo',memo);END IF;
 SELECT * INTO prior FROM trading.swap_trade_revisions r WHERE r.catalog_id=catalog AND r.operation_id=operation;
 IF FOUND THEN
  IF prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'swap_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.swap_operation_status(catalog,operation);
 END IF;
 PERFORM security.require_trade_annotation(catalog,trader,trader_revision,memo,executed);
 IF EXISTS(SELECT 1 FROM trading.trades WHERE catalog_id=catalog AND operation_id=operation) OR EXISTS(SELECT 1 FROM trading.trade_revisions WHERE catalog_id=catalog AND operation_id=operation)
 THEN RAISE EXCEPTION 'swap_conflict' USING ERRCODE='P0001'; END IF;
 IF fixed_schedule IS NULL OR float_schedule IS NULL OR commodity IS NULL THEN RAISE EXCEPTION 'payment_rule' USING ERRCODE='P0001';END IF;
 IF fixed_payment IS DISTINCT FROM(security.swap_payment_date(ref_catalog,ref_revision,fixed_from,fixed_to,fixed_schedule)::timestamp AT TIME ZONE 'UTC') OR float_payment IS DISTINCT FROM(security.swap_payment_date(ref_catalog,ref_revision,float_from,float_to,float_schedule)::timestamp AT TIME ZONE 'UTC') THEN RAISE EXCEPTION 'payment_date_mismatch' USING ERRCODE='P0001';END IF;
 IF NOT EXISTS(SELECT 1 FROM trading.books b JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id) WHERE b.catalog_id=catalog AND b.id=book AND b.effective_at<=executed AND p.effective_at<=executed)
 THEN RAISE EXCEPTION 'swap_book' USING ERRCODE='P0001'; END IF;
 SELECT * INTO cv FROM market_data.curves WHERE catalog_id=catalog AND revision_id=definition AND code=curve AND reference_catalog_id=ref_catalog AND reference_revision_id=ref_revision;
 SELECT * INTO q FROM ref_data.quote_specifications WHERE(catalog_id,revision_id,code)=(ref_catalog,ref_revision,cv.quote_code);
 SELECT * INTO target FROM ref_data.settlement_targets WHERE(catalog_id,revision_id,code)=(ref_catalog,ref_revision,cv.settlement_target_code);
 IF cv.commodity_code IS DISTINCT FROM commodity OR q.kind IS DISTINCT FROM 'outright' OR target.kind IS DISTINCT FROM 'index' OR target.index_a_code IS DISTINCT FROM index_name OR
  q.currency_code IS DISTINCT FROM fixed_currency OR q.currency_code IS DISTINCT FROM float_currency OR
  NOT EXISTS(SELECT 1 FROM ref_data.price_index_definitions i JOIN ref_data.quantity_specifications u ON(u.catalog_id,u.revision_id,u.code)=(q.catalog_id,q.revision_id,q.quantity_code)
   WHERE(i.catalog_id,i.revision_id,i.code)=(ref_catalog,ref_revision,index_name) AND(i.currency_code,i.commodity_code,i.location_code,i.quote_unit_code,i.quote_multiplier)=(q.currency_code,cv.commodity_code,cv.location_code,u.unit_code,q.multiplier))
 THEN RAISE EXCEPTION 'swap_definition' USING ERRCODE='P0001'; END IF;
 IF float_from IS NULL OR float_to IS NULL OR extract(day FROM float_from)<>1 OR float_to IS DISTINCT FROM(float_from+INTERVAL '1 month')::date THEN RAISE EXCEPTION 'swap_projection' USING ERRCODE='P0001'; END IF;
 IF averaging='monthly_index_price' THEN
  IF(SELECT count(*) FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
   WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND k1.kind='forward' AND k1.delivery_from=float_from AND k1.delivery_to=float_to)<>1 THEN RAISE EXCEPTION 'swap_projection' USING ERRCODE='P0001'; END IF;
  SELECT k1.* INTO k FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
   WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND k1.kind='forward' AND k1.delivery_from=float_from AND k1.delivery_to=float_to;
  IF valuation>=k.expiry_at THEN RAISE EXCEPTION 'swap_projection' USING ERRCODE='P0001'; END IF;
 ELSE
  IF(SELECT count(*) FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
    WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND k1.kind='forward' AND k1.delivery_to=k1.delivery_from+1 AND float_from<=k1.delivery_from AND k1.delivery_from<float_to)<>float_to-float_from OR
    (SELECT count(DISTINCT k1.delivery_from) FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
    WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND k1.kind='forward' AND k1.delivery_to=k1.delivery_from+1 AND float_from<=k1.delivery_from AND k1.delivery_from<float_to)<>float_to-float_from OR
    EXISTS(SELECT 1 FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
     WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND k1.kind='forward' AND k1.delivery_to=k1.delivery_from+1 AND float_from<=k1.delivery_from AND k1.delivery_from<float_to AND valuation>=k1.expiry_at)
  THEN RAISE EXCEPTION 'swap_projection' USING ERRCODE='P0001'; END IF;
 END IF;
 SELECT effective_from::timestamp AT TIME ZONE 'UTC' INTO from_at FROM market_data.revision_periods WHERE catalog_id=catalog AND revision_id=definition AND effective_from<=(executed AT TIME ZONE 'UTC')::date AND(executed AT TIME ZONE 'UTC')::date<effective_to;
 IF from_at IS NULL OR NOT EXISTS(SELECT 1 FROM market_data.revisions WHERE catalog_id=catalog AND id=definition AND state='sealed') THEN RAISE EXCEPTION 'swap_definition' USING ERRCODE='P0001'; END IF;
 IF trade IS NOT NULL THEN
  SELECT * INTO head FROM trading.swap_trade_revisions r WHERE r.catalog_id=catalog AND r.trade_id=trade ORDER BY r.revision DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'swap_trade' USING ERRCODE='P0001'; END IF;
  IF head.revision IS DISTINCT FROM expected THEN RAISE EXCEPTION 'swap_revision_conflict' USING ERRCODE='P0001'; END IF;
  IF head.revision>=256 OR effective IS DISTINCT FROM valuation OR effective<head.effective_at OR reason IS NULL OR length(btrim(reason)) NOT BETWEEN 1 AND 500 OR reason ~ '^[[:space:]]*$'
   OR EXISTS(SELECT 1 FROM trading.swap_instruments i JOIN trading.swap_floating_sides s ON(s.catalog_id,s.id)=(i.catalog_id,i.floating_side_id)
    JOIN trading.swap_fixed_sides f ON(f.catalog_id,f.id)=(i.catalog_id,i.fixed_side_id) WHERE i.catalog_id=catalog AND i.instrument_id=head.instrument_id
    AND (valuation>=s.first_fixing_at OR valuation>=s.payment_at OR valuation>=f.payment_at OR f.reference_catalog_id<>ref_catalog OR f.reference_revision_id<>ref_revision OR f.quote_code<>q.code))
  THEN RAISE EXCEPTION 'swap_amendment' USING ERRCODE='P0001'; END IF;
 ELSE
  IF effective IS DISTINCT FROM executed OR expected IS NOT NULL OR (SELECT count(*) FROM trading.trades WHERE catalog_id=catalog)>=256 THEN RAISE EXCEPTION 'swap_limit' USING ERRCODE='P0001'; END IF;
 END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO publication_number FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,publication_number,pg_current_xact_id());
 fixed_rule=security.retain_swap_payment_rule(catalog,ref_catalog,ref_revision,fixed_schedule,publication_number,from_at);
 float_rule=security.retain_swap_payment_rule(catalog,ref_catalog,ref_revision,float_schedule,publication_number,from_at);
 SELECT id INTO fixed_side FROM trading.swap_fixed_sides WHERE catalog_id=catalog AND reference_catalog_id=ref_catalog AND reference_revision_id=ref_revision AND quote_code=q.code AND delivery_from=fixed_from AND delivery_to=fixed_to AND payment_at=fixed_payment AND fixed_price=price AND payment_rule_id=fixed_rule;
 IF fixed_side IS NULL THEN
  fixed_side=gen_random_uuid();INSERT INTO trading.swap_fixed_sides VALUES(catalog,fixed_side,ref_catalog,ref_revision,q.code,fixed_from,fixed_to,fixed_payment,price,'fixed_total_payment_v1',publication_number,from_at,fixed_rule);
 END IF;
 SELECT id INTO floating_side FROM trading.swap_floating_sides WHERE catalog_id=catalog AND definition_revision_id=definition AND curve_code=curve AND contract_id IS NOT DISTINCT FROM k.id AND delivery_from=float_from AND delivery_to=float_to AND index_code=index_name AND first_fixing_at=fixing AND payment_at=float_payment AND swap_floating_sides.averaging=save_annotated_swap.averaging AND payment_rule_id=float_rule;
 IF floating_side IS NULL THEN
  floating_side=gen_random_uuid();INSERT INTO trading.swap_floating_sides VALUES(catalog,floating_side,definition,curve,k.id,ref_catalog,ref_revision,index_name,q.code,float_from,float_to,fixing,float_payment,averaging,'prefixing_index_projection_v1',publication_number,from_at,float_rule);
  INSERT INTO trading.swap_reset_projections
   SELECT catalog,floating_side,(row_number() OVER(ORDER BY k1.delivery_from,k1.id)-1)::integer,definition,curve,k1.id,1,publication_number,from_at
   FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
   WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND
    (averaging='monthly_index_price' AND k1.id=k.id OR averaging='calendar_day_arithmetic' AND k1.kind='forward' AND k1.delivery_to=k1.delivery_from+1 AND float_from<=k1.delivery_from AND k1.delivery_from<float_to);
 END IF;
 SELECT instrument_id INTO instrument FROM trading.swap_instruments WHERE catalog_id=catalog AND fixed_side_id=fixed_side AND floating_side_id=floating_side AND fixed_coefficient=coefficient AND swap_instruments.discounting=save_annotated_swap.discounting;
 IF instrument IS NULL THEN
  instrument=gen_random_uuid();INSERT INTO trading.instruments VALUES(catalog,instrument,publication_number,from_at);
  INSERT INTO trading.swap_instruments VALUES(catalog,instrument,fixed_side,floating_side,coefficient,discounting,implementation,publication_number,from_at);
 END IF;
 IF trade IS NULL THEN
  trade=gen_random_uuid();binding=gen_random_uuid();
  INSERT INTO trading.trades VALUES(catalog,trade,book,operation,c.actor_id,request_value,publication_number,executed);
 ELSE
  IF(book,instrument,quantity,executed,trader,trader_revision,memo) IS NOT DISTINCT FROM(head.book_id,head.instrument_id,head.quantity,head.execution_at,head.trader_id,head.trader_revision,head.memo) THEN RAISE EXCEPTION 'swap_no_change' USING ERRCODE='P0001'; END IF;
  binding=CASE WHEN instrument=head.instrument_id THEN head.binding_id ELSE gen_random_uuid() END;
 END IF;
 INSERT INTO trading.swap_trade_revisions VALUES(catalog,trade,coalesce(head.revision,0)+1,head.revision,gen_random_uuid(),'monthly_financial_swap_booking_v1',CASE WHEN head.revision IS NULL THEN 'booked' ELSE 'amended' END,
  book,binding,instrument,quantity,executed,effective,operation,c.actor_id,CASE WHEN head.revision IS NULL THEN 'Initial booking' ELSE btrim(reason) END,request_value,publication_number,trader,trader_revision,memo);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,permission) THEN RAISE EXCEPTION 'Trade write access expired' USING ERRCODE='42501'; END IF;
 RETURN security.swap_operation_status(catalog,operation);
END $$;
DO $$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure signature,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='security' AND p.proname IN('require_trade_annotation','book_futures_annotated','amend_futures_annotated','save_annotated_swap') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f.signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.signature);
  IF f.proname<>'require_trade_annotation' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO openetrm_runtime',f.signature);END IF;
 END LOOP;
END $$;
COMMIT;
