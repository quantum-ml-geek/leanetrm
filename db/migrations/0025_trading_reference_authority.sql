-- Existing functions retain their owners and ACLs. Drain runtime calls before applying.
-- Replays return retained control IDs; new economics require current reference scope.
BEGIN;
SELECT pg_advisory_xact_lock(730849102);
CREATE OR REPLACE FUNCTION security.prepare_futures_binding(catalog uuid,book uuid,revision uuid,curve text,contract uuid,
 valuation timestamptz,executed timestamptz,lots numeric,execution numeric,implementation text,ordinal integer)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE q ref_data.quote_specifications;product ref_data.futures_products;series_row ref_data.futures_series;
 contract_row market_data.contracts;curve_row market_data.curves;definition_from timestamptz;starts timestamptz;ends timestamptz;side uuid;instrument uuid;
BEGIN
 IF executed IS NULL OR NOT isfinite(executed) OR valuation IS NULL OR NOT isfinite(valuation) OR (implementation IS NULL OR implementation NOT IN('fixed_total_cash_execution_pnl_v1','contract_lot_execution_pnl_v2'))
 THEN RAISE EXCEPTION 'futures_input' USING ERRCODE='P0001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM trading.books b JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id) WHERE b.catalog_id=catalog AND b.id=book AND b.effective_at<=executed AND p.effective_at<=executed) THEN RAISE EXCEPTION 'futures_book' USING ERRCODE='P0001'; END IF;
 IF lots IS NULL OR lots<>trunc(lots) OR lots=0 OR abs(lots)>100000 THEN RAISE EXCEPTION 'futures_lots' USING ERRCODE='P0001'; END IF;
 SELECT * INTO contract_row FROM market_data.contracts WHERE catalog_id=catalog AND revision_id=revision AND id=contract;
 SELECT * INTO curve_row FROM market_data.curves WHERE catalog_id=catalog AND revision_id=revision AND code=curve;
 IF contract_row.kind IS DISTINCT FROM 'future' OR curve_row.rule IS DISTINCT FROM 'direct' OR curve_row.direct_role IS DISTINCT FROM 'daily_settlement' OR
  NOT EXISTS(SELECT 1 FROM market_data.curve_members WHERE catalog_id=catalog AND revision_id=revision AND curve_code=curve AND contract_id=contract) THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 IF NOT security.reference_access(contract_row.reference_catalog_id,'ReadMarketData') THEN RAISE EXCEPTION 'No current reference access' USING ERRCODE='42501'; END IF;
 SELECT p.* INTO product FROM ref_data.futures_series s JOIN ref_data.futures_products p ON(p.catalog_id,p.revision_id,p.code)=(s.catalog_id,s.revision_id,s.product_code)
 WHERE(s.catalog_id,s.revision_id,s.code)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code) AND s.definition_state='synthetic';
 IF product.definition_state IS DISTINCT FROM 'synthetic' OR product.settlement_method NOT IN('cash','physical') OR
   (implementation='fixed_total_cash_execution_pnl_v1' AND(product.settlement_method<>'cash' OR product.lot_basis<>'fixed_total')) OR
   (product.lot_basis='fixed_total' AND product.lot_unit_code IS DISTINCT FROM product.quote_unit_code)
 THEN RAISE EXCEPTION 'futures_convention' USING ERRCODE='P0001'; END IF;
 SELECT * INTO series_row FROM ref_data.futures_series WHERE(catalog_id,revision_id,code)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code);
 IF series_row.delivery_from IS DISTINCT FROM contract_row.delivery_from OR series_row.delivery_to IS DISTINCT FROM contract_row.delivery_to OR
  curve_row.commodity_code IS DISTINCT FROM product.commodity_code OR curve_row.location_code IS DISTINCT FROM product.location_code OR
  NOT EXISTS(SELECT 1 FROM ref_data.futures_product_terms t WHERE(t.catalog_id,t.revision_id,t.product_code,t.profile_code)=(product.catalog_id,product.revision_id,product.code,curve_row.profile_code))
 THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 SELECT * INTO q FROM ref_data.quote_specifications WHERE(catalog_id,revision_id,code)=(curve_row.reference_catalog_id,curve_row.reference_revision_id,curve_row.quote_code);
 IF EXISTS(SELECT 1 FROM ref_data.futures_basis_settlements b
   JOIN ref_data.futures_series benchmark ON(benchmark.catalog_id,benchmark.revision_id,benchmark.code)=(b.catalog_id,b.revision_id,b.benchmark_series_code)
   JOIN ref_data.futures_products bp ON(bp.catalog_id,bp.revision_id,bp.code)=(benchmark.catalog_id,benchmark.revision_id,benchmark.product_code)
   JOIN ref_data.price_index_definitions i ON(i.catalog_id,i.revision_id,i.code)=(b.catalog_id,b.revision_id,b.index_code)
   WHERE(b.catalog_id,b.revision_id,b.series_code)=(series_row.catalog_id,series_row.revision_id,series_row.code) AND
   (product.settlement_method<>'cash' OR EXISTS(SELECT 1 FROM ref_data.futures_product_terms t WHERE(t.catalog_id,t.revision_id,t.product_code)=(product.catalog_id,product.revision_id,product.code) AND t.index_code IS NOT NULL) OR (benchmark.delivery_from,benchmark.delivery_to) IS DISTINCT FROM(series_row.delivery_from,series_row.delivery_to) OR
    (bp.commodity_code,bp.quote_currency_code,bp.quote_unit_code,bp.quote_multiplier) IS DISTINCT FROM(product.commodity_code,product.quote_currency_code,product.quote_unit_code,product.quote_multiplier) OR
    (i.commodity_code,i.location_code,i.currency_code,i.quote_unit_code,i.quote_multiplier) IS DISTINCT FROM(product.commodity_code,product.location_code,product.quote_currency_code,product.quote_unit_code,product.quote_multiplier) OR
    EXISTS(SELECT 1 FROM ref_data.futures_basis_settlements bb WHERE(bb.catalog_id,bb.revision_id,bb.series_code)=(benchmark.catalog_id,benchmark.revision_id,benchmark.code))))
 THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 IF q.kind IS DISTINCT FROM (CASE WHEN EXISTS(SELECT 1 FROM ref_data.futures_basis_settlements b WHERE(b.catalog_id,b.revision_id,b.series_code)=(series_row.catalog_id,series_row.revision_id,series_row.code)) THEN 'basis' ELSE 'outright' END) OR
  (implementation='fixed_total_cash_execution_pnl_v1' AND q.kind<>'outright') OR q.currency_code IS DISTINCT FROM product.quote_currency_code OR q.multiplier IS DISTINCT FROM product.quote_multiplier OR q.trading_tick IS DISTINCT FROM product.outright_tick_size OR
  (SELECT count(*) FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,commodity_code,unit_code)=(q.catalog_id,q.revision_id,product.commodity_code,product.quote_unit_code))<>1 OR
  NOT EXISTS(SELECT 1 FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code,commodity_code,unit_code)=(q.catalog_id,q.revision_id,q.quantity_code,product.commodity_code,product.quote_unit_code))
 THEN RAISE EXCEPTION 'futures_convention' USING ERRCODE='P0001'; END IF;
 IF product.lot_basis='fixed_total' THEN
  IF EXISTS(SELECT 1 FROM ref_data.futures_lot_resolutions WHERE(catalog_id,revision_id,series_code)=(series_row.catalog_id,series_row.revision_id,series_row.code)) THEN RAISE EXCEPTION 'futures_lot' USING ERRCODE='P0001'; END IF;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM ref_data.futures_lot_resolutions r WHERE(r.catalog_id,r.revision_id,r.series_code,r.quantity_code)=(series_row.catalog_id,series_row.revision_id,series_row.code,q.quantity_code)
    AND r.amount=product.contract_size*r.factor AND
    (r.implementation='published_contract_size_v1' OR(r.implementation='calendar_delivery_days_v1' AND product.lot_basis='per_delivery_day' AND r.factor=series_row.delivery_to-series_row.delivery_from)))
  THEN RAISE EXCEPTION 'futures_lot' USING ERRCODE='P0001'; END IF;
 END IF;
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
CREATE OR REPLACE FUNCTION security.save_swap_with_parties(catalog uuid,operation uuid,trade uuid,expected integer,book uuid,definition uuid,ref_catalog uuid,ref_revision uuid,
 curve text,index_name text,fixed_currency text,float_currency text,fixed_from date,fixed_to date,fixed_payment timestamptz,float_from date,float_to date,
 fixing timestamptz,float_payment timestamptz,averaging text,price numeric,quantity numeric,coefficient numeric,discounting boolean,
 valuation timestamptz,executed timestamptz,effective timestamptz,reason text,implementation text,fixed_schedule jsonb,float_schedule jsonb,commodity text,trader uuid,trader_revision integer,memo text,booking jsonb) RETURNS jsonb
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
 request_value=request_value||jsonb_build_object('booking',booking);
 IF trader IS NOT NULL OR trader_revision IS NOT NULL OR memo IS NOT NULL THEN request_value=request_value||jsonb_build_object('trader',trader,'traderRevision',trader_revision,'memo',memo);END IF;
 SELECT * INTO prior FROM trading.swap_trade_revisions r WHERE r.catalog_id=catalog AND r.operation_id=operation;
 IF FOUND THEN
  IF prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'swap_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.swap_operation_status(catalog,operation);
 END IF;
 PERFORM security.require_trade_annotation(catalog,trader,trader_revision,memo,executed);
 PERFORM security.require_trade_parties(catalog,booking,executed);
 IF EXISTS(SELECT 1 FROM trading.trades WHERE catalog_id=catalog AND operation_id=operation) OR EXISTS(SELECT 1 FROM trading.trade_revisions WHERE catalog_id=catalog AND operation_id=operation)
 THEN RAISE EXCEPTION 'swap_conflict' USING ERRCODE='P0001'; END IF;
 IF NOT security.reference_access(ref_catalog,'ReadMarketData') THEN RAISE EXCEPTION 'No current reference access' USING ERRCODE='42501'; END IF;
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
 SELECT id INTO floating_side FROM trading.swap_floating_sides WHERE catalog_id=catalog AND definition_revision_id=definition AND curve_code=curve AND reference_catalog_id=ref_catalog AND reference_revision_id=ref_revision AND quote_code=q.code AND delivery_from=float_from AND delivery_to=float_to AND index_code=index_name AND first_fixing_at=fixing AND payment_at=float_payment AND swap_floating_sides.averaging=save_swap_with_parties.averaging AND payment_rule_id=float_rule;
 IF floating_side IS NOT NULL AND EXISTS(
  SELECT 1 FROM (
   SELECT p.ordinal,p.definition_revision_id,p.curve_code,p.contract_id,p.weight FROM trading.swap_reset_projections p
   WHERE(p.catalog_id,p.side_id)=(catalog,floating_side)
  ) retained FULL JOIN (
   SELECT (row_number() OVER(ORDER BY k1.delivery_from,k1.id)-1)::integer AS ordinal,definition AS definition_revision_id,
    curve AS curve_code,k1.id AS contract_id,1::numeric AS weight
   FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
   WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND
    (averaging='monthly_index_price' AND k1.id=k.id OR averaging='calendar_day_arithmetic' AND k1.kind='forward' AND k1.delivery_to=k1.delivery_from+1 AND float_from<=k1.delivery_from AND k1.delivery_from<float_to)
  ) expected USING(ordinal)
  WHERE retained.ordinal IS NULL OR expected.ordinal IS NULL OR
   (retained.definition_revision_id,retained.curve_code,retained.contract_id,retained.weight)
    IS DISTINCT FROM(expected.definition_revision_id,expected.curve_code,expected.contract_id,expected.weight)
 ) THEN RAISE EXCEPTION 'swap_projection' USING ERRCODE='P0001'; END IF;
 IF floating_side IS NULL THEN
  floating_side=gen_random_uuid();INSERT INTO trading.swap_floating_sides VALUES(catalog,floating_side,definition,curve,k.id,ref_catalog,ref_revision,index_name,q.code,float_from,float_to,fixing,float_payment,averaging,'prefixing_index_projection_v1',publication_number,from_at,float_rule);
  INSERT INTO trading.swap_reset_projections
   SELECT catalog,floating_side,(row_number() OVER(ORDER BY k1.delivery_from,k1.id)-1)::integer,definition,curve,k1.id,1,publication_number,from_at
   FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
   WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND
    (averaging='monthly_index_price' AND k1.id=k.id OR averaging='calendar_day_arithmetic' AND k1.kind='forward' AND k1.delivery_to=k1.delivery_from+1 AND float_from<=k1.delivery_from AND k1.delivery_from<float_to);
 END IF;
 SELECT instrument_id INTO instrument FROM trading.swap_instruments WHERE catalog_id=catalog AND fixed_side_id=fixed_side AND floating_side_id=floating_side AND fixed_coefficient=coefficient AND swap_instruments.discounting=save_swap_with_parties.discounting;
 IF instrument IS NULL THEN
  instrument=gen_random_uuid();INSERT INTO trading.instruments VALUES(catalog,instrument,publication_number,from_at);
  INSERT INTO trading.swap_instruments VALUES(catalog,instrument,fixed_side,floating_side,coefficient,discounting,implementation,publication_number,from_at);
 END IF;
 IF trade IS NULL THEN
  trade=gen_random_uuid();binding=gen_random_uuid();
  INSERT INTO trading.trades VALUES(catalog,trade,book,operation,c.actor_id,request_value,publication_number,executed);
 ELSE
  IF(book,instrument,quantity,executed,trader,trader_revision,memo,booking) IS NOT DISTINCT FROM(head.book_id,head.instrument_id,head.quantity,head.execution_at,head.trader_id,head.trader_revision,head.memo,security.trade_party_payload(head.trade_date,head.legal_entity_id,head.legal_entity_revision,head.counterparty_id,head.counterparty_revision)) THEN RAISE EXCEPTION 'swap_no_change' USING ERRCODE='P0001'; END IF;
  binding=CASE WHEN instrument=head.instrument_id THEN head.binding_id ELSE gen_random_uuid() END;
 END IF;
 INSERT INTO trading.swap_trade_revisions VALUES(catalog,trade,coalesce(head.revision,0)+1,head.revision,gen_random_uuid(),'monthly_financial_swap_booking_v2',CASE WHEN head.revision IS NULL THEN 'booked' ELSE 'amended' END,
  book,binding,instrument,quantity,executed,effective,operation,c.actor_id,CASE WHEN head.revision IS NULL THEN 'Initial booking' ELSE btrim(reason) END,request_value,publication_number,trader,trader_revision,memo,(booking->>'tradeDate')::date,(booking->>'legalEntityId')::uuid,(booking->>'legalEntityRevision')::integer,(booking->>'counterpartyId')::uuid,(booking->>'counterpartyRevision')::integer);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,permission) THEN RAISE EXCEPTION 'Trade write access expired' USING ERRCODE='42501'; END IF;
 RETURN security.swap_operation_status(catalog,operation);
END $$;
CREATE OR REPLACE FUNCTION security.swap_discount_default(catalog uuid,ref_catalog uuid,ref_revision uuid,currency text,definition uuid,valuation timestamptz) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts;result jsonb;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'No trading access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL AND c.trading_as_of IS DISTINCT FROM valuation THEN RAISE EXCEPTION 'swap_context' USING ERRCODE='P0001'; END IF;
 IF NOT security.reference_access(ref_catalog,'ReadMarketData') OR NOT security.reference_version_visible(ref_catalog,ref_revision) OR NOT security.market_fact_visible(catalog,definition,NULL) THEN RAISE EXCEPTION 'No visible reference or market definition' USING ERRCODE='42501'; END IF;
 SELECT to_jsonb(d) INTO result FROM trading.currency_discount_defaults d
 WHERE d.catalog_id=catalog AND d.reference_catalog_id=ref_catalog AND d.reference_revision_id=ref_revision AND d.currency_code=currency AND d.definition_revision_id=definition AND d.effective_at<=valuation
 AND(c.market_context_id IS NULL OR security.trading_visible(d.catalog_id,d.publication_order,d.effective_at))
 ORDER BY d.effective_at DESC,d.publication_order DESC LIMIT 1;
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'Trading access expired' USING ERRCODE='42501'; END IF;
 IF NOT security.reference_access(ref_catalog,'ReadMarketData') OR NOT security.reference_version_visible(ref_catalog,ref_revision) OR NOT security.market_fact_visible(catalog,definition,NULL) THEN RAISE EXCEPTION 'No visible reference or market definition' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;
COMMIT;
