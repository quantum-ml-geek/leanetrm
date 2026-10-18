-- Side-owned payment conventions; generated dates are retained with exact rule references.
-- Stop runtime admission and drain calls before this additive upgrade.
BEGIN;
SELECT pg_advisory_xact_lock(730849102);
CREATE TABLE trading.swap_payment_rules (
 catalog_id uuid NOT NULL,id uuid NOT NULL,reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,
 frequency text NOT NULL CHECK(frequency='monthly'),rule text NOT NULL,days integer,day_of_month integer,day_basis text,short_month text,
 adjustment text NOT NULL CHECK(adjustment IN('unadjusted','following','preceding','modified_following')),calendar_code ref_data.code,
 implementation text NOT NULL CHECK(implementation='monthly_payment_date_rules_v1'),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),
 UNIQUE NULLS NOT DISTINCT(catalog_id,reference_catalog_id,reference_revision_id,frequency,rule,days,day_of_month,day_basis,short_month,adjustment,calendar_code,implementation),
 CHECK((rule='days_after_period_end' AND days IS NOT NULL AND days BETWEEN 0 AND 366 AND day_of_month IS NULL AND day_basis IS NOT NULL AND day_basis IN('calendar_days','business_days') AND short_month IS NULL)
  OR(rule='day_of_following_month' AND days IS NULL AND day_of_month IS NOT NULL AND day_of_month BETWEEN 1 AND 31 AND day_basis IS NULL AND short_month IS NOT NULL AND short_month IN('reject','clamp'))),
 CHECK((day_basis IS NOT DISTINCT FROM 'business_days' OR adjustment<>'unadjusted')=(calendar_code IS NOT NULL)),
 FOREIGN KEY(reference_catalog_id,reference_revision_id) REFERENCES ref_data.revisions(catalog_id,id),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,calendar_code) REFERENCES ref_data.calendars(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
ALTER TABLE trading.swap_payment_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading.swap_payment_rules FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON trading.swap_payment_rules FOR SELECT TO openetrm_runtime USING(security.trading_visible(catalog_id,publication_order,effective_at));
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.swap_payment_rules FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
GRANT SELECT,INSERT ON trading.swap_payment_rules TO openetrm_security_owner;
GRANT SELECT ON trading.swap_payment_rules TO openetrm_runtime;
GRANT SELECT ON ref_data.calendars,ref_data.calendar_days TO openetrm_security_owner;
ALTER TABLE trading.swap_fixed_sides ADD COLUMN payment_rule_id uuid;
ALTER TABLE trading.swap_floating_sides ADD COLUMN payment_rule_id uuid;
ALTER TABLE trading.swap_fixed_sides ADD FOREIGN KEY(catalog_id,payment_rule_id) REFERENCES trading.swap_payment_rules(catalog_id,id);
ALTER TABLE trading.swap_floating_sides ADD FOREIGN KEY(catalog_id,payment_rule_id) REFERENCES trading.swap_payment_rules(catalog_id,id);
DO $$ DECLARE c record;BEGIN
 FOR c IN SELECT conrelid::regclass AS t,conname FROM pg_constraint WHERE conrelid IN('trading.swap_fixed_sides'::regclass,'trading.swap_floating_sides'::regclass) AND contype='u' LOOP
 EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',c.t,c.conname);END LOOP;
END $$;
ALTER TABLE trading.swap_fixed_sides ADD UNIQUE NULLS NOT DISTINCT(catalog_id,reference_catalog_id,reference_revision_id,quote_code,delivery_from,delivery_to,payment_at,fixed_price,implementation,payment_rule_id);
ALTER TABLE trading.swap_floating_sides ADD UNIQUE NULLS NOT DISTINCT(catalog_id,definition_revision_id,curve_code,contract_id,index_code,delivery_from,delivery_to,first_fixing_at,payment_at,averaging,implementation,payment_rule_id);
-- Legacy checks keep their original meaning. New dates are validated from the selected rule.
DO $$ DECLARE c record;BEGIN
 FOR c IN SELECT conrelid::regclass AS t,conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid IN('trading.swap_fixed_sides'::regclass,'trading.swap_floating_sides'::regclass) AND contype='c' LOOP
 IF c.definition LIKE '%payment_at%' THEN EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',c.t,c.conname); END IF;
 END LOOP;
END $$;
ALTER TABLE trading.swap_fixed_sides ADD CHECK(delivery_to>delivery_from AND delivery_to-delivery_from<=366 AND(payment_rule_id IS NOT NULL OR(payment_at AT TIME ZONE 'UTC')::date>=delivery_to));
ALTER TABLE trading.swap_floating_sides ADD CHECK(delivery_to=(delivery_from+INTERVAL '1 month')::date AND extract(day FROM delivery_from)=1 AND(averaging='monthly_index_price')=(contract_id IS NOT NULL) AND first_fixing_at<payment_at AND(payment_rule_id IS NOT NULL OR(payment_at AT TIME ZONE 'UTC')::date>=delivery_to));
CREATE FUNCTION security.swap_business_day(rc uuid,rr uuid,code text,day date) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c ref_data.calendars;result boolean;
BEGIN
 SELECT * INTO c FROM ref_data.calendars WHERE(catalog_id,revision_id,calendars.code)=(rc,rr,swap_business_day.code);
 IF NOT FOUND OR c.coverage_to-c.coverage_from>36600 OR day<c.coverage_from OR day>=c.coverage_to THEN RAISE EXCEPTION 'payment_calendar' USING ERRCODE='P0001';END IF;
 SELECT is_business_day INTO result FROM ref_data.calendar_days WHERE(catalog_id,revision_id,calendar_code,business_date)=(rc,rr,code,day);
 RETURN coalesce(result,(c.weekend_mask & (1 << (extract(isodow FROM day)::integer-1)))=0);
END $$;
CREATE FUNCTION security.swap_payment_date(rc uuid,rr uuid,from_day date,to_day date,spec jsonb) RETURNS date
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE rule text;days integer;dom integer;basis text;short text;roll text;cal text;result date;base date;candidate date;remaining integer;steps integer=0;
BEGIN
 IF spec IS NULL OR jsonb_typeof(spec)<>'object' OR spec->>'frequency' IS DISTINCT FROM 'monthly' OR spec->>'implementation' IS DISTINCT FROM 'monthly_payment_date_rules_v1'
 OR from_day IS NULL OR from_day<DATE '1901-01-01' OR from_day>=DATE '2199-01-01' OR extract(day FROM from_day)<>1 OR to_day IS DISTINCT FROM(from_day+INTERVAL '1 month')::date
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(spec) k WHERE k NOT IN('frequency','rule','days','dayOfMonth','dayBasis','shortMonth','adjustment','calendar','implementation'))
 THEN RAISE EXCEPTION 'payment_rule' USING ERRCODE='P0001';END IF;
 rule=spec->>'rule';days=(spec->>'days')::integer;dom=(spec->>'dayOfMonth')::integer;basis=spec->>'dayBasis';short=spec->>'shortMonth';roll=spec->>'adjustment';cal=spec->>'calendar';
 IF rule IS NULL OR rule NOT IN('days_after_period_end','day_of_following_month') OR roll IS NULL OR roll NOT IN('unadjusted','following','preceding','modified_following')
 OR (rule='days_after_period_end' AND(days IS NULL OR days<0 OR days>366 OR dom IS NOT NULL OR basis IS NULL OR basis NOT IN('calendar_days','business_days') OR short IS NOT NULL))
 OR (rule='day_of_following_month' AND(days IS NOT NULL OR basis IS NOT NULL OR dom IS NULL OR dom<1 OR dom>31 OR short IS NULL OR short NOT IN('reject','clamp')))
 OR((basis IS NOT DISTINCT FROM 'business_days' OR roll<>'unadjusted')<>(cal IS NOT NULL))
 THEN RAISE EXCEPTION 'payment_rule' USING ERRCODE='P0001';END IF;
 IF rule='days_after_period_end' THEN
  result=to_day-1;
  IF basis='calendar_days' THEN result=result+days;
  ELSE
   PERFORM security.swap_business_day(rc,rr,cal,result);remaining=days;
   WHILE remaining>0 LOOP steps=steps+1;IF steps>36600 THEN RAISE EXCEPTION 'payment_calendar' USING ERRCODE='P0001';END IF;result=result+1;IF security.swap_business_day(rc,rr,cal,result) THEN remaining=remaining-1;END IF;END LOOP;
  END IF;
 ELSE
  base=date_trunc('month',to_day)::date;
  remaining=extract(day FROM(base+INTERVAL '1 month'-INTERVAL '1 day'))::integer;
  IF dom>remaining AND short='reject' THEN RAISE EXCEPTION 'short_month' USING ERRCODE='P0001';END IF;
  result=base+least(dom,remaining)-1;
 END IF;
 IF cal IS NOT NULL AND NOT security.swap_business_day(rc,rr,cal,result) AND roll<>'unadjusted' THEN
  base=result;
  IF roll='preceding' THEN
   LOOP steps=steps+1;IF steps>36600 THEN RAISE EXCEPTION 'payment_calendar' USING ERRCODE='P0001';END IF;result=result-1;EXIT WHEN security.swap_business_day(rc,rr,cal,result);END LOOP;
  ELSE
   LOOP steps=steps+1;IF steps>36600 THEN RAISE EXCEPTION 'payment_calendar' USING ERRCODE='P0001';END IF;result=result+1;EXIT WHEN security.swap_business_day(rc,rr,cal,result);END LOOP;
   IF roll='modified_following' AND date_trunc('month',result)<>date_trunc('month',base) THEN
    result=base;LOOP steps=steps+1;IF steps>36600 THEN RAISE EXCEPTION 'payment_calendar' USING ERRCODE='P0001';END IF;result=result-1;EXIT WHEN security.swap_business_day(rc,rr,cal,result);END LOOP;
   END IF;
  END IF;
 END IF;
 IF result<DATE '1901-01-01' OR result>=DATE '2200-01-01' THEN RAISE EXCEPTION 'payment_period' USING ERRCODE='P0001';END IF;
 RETURN result;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR datetime_field_overflow THEN RAISE EXCEPTION 'payment_rule' USING ERRCODE='P0001';
END $$;
CREATE FUNCTION security.retain_swap_payment_rule(catalog uuid,rc uuid,rr uuid,spec jsonb,publication integer,from_at timestamptz) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result uuid;
BEGIN
 SELECT id INTO result FROM trading.swap_payment_rules WHERE catalog_id=catalog AND(reference_catalog_id,reference_revision_id,frequency,rule,days,day_of_month,day_basis,short_month,adjustment,calendar_code,implementation)
 IS NOT DISTINCT FROM(rc,rr,spec->>'frequency',spec->>'rule',(spec->>'days')::integer,(spec->>'dayOfMonth')::integer,spec->>'dayBasis',spec->>'shortMonth',spec->>'adjustment',spec->>'calendar',spec->>'implementation');
 IF result IS NULL THEN
  result=gen_random_uuid();INSERT INTO trading.swap_payment_rules VALUES(catalog,result,rc,rr,spec->>'frequency',spec->>'rule',(spec->>'days')::integer,(spec->>'dayOfMonth')::integer,spec->>'dayBasis',spec->>'shortMonth',spec->>'adjustment',spec->>'calendar',spec->>'implementation',publication,from_at);
 END IF;
 RETURN result;
END $$;
CREATE FUNCTION security.save_scheduled_swap(catalog uuid,operation uuid,trade uuid,expected integer,book uuid,definition uuid,ref_catalog uuid,ref_revision uuid,
 curve text,index_name text,fixed_currency text,float_currency text,fixed_from date,fixed_to date,fixed_payment timestamptz,float_from date,float_to date,
 fixing timestamptz,float_payment timestamptz,averaging text,price numeric,quantity numeric,coefficient numeric,discounting boolean,
 valuation timestamptz,executed timestamptz,effective timestamptz,reason text,implementation text,fixed_schedule jsonb,float_schedule jsonb,commodity text) RETURNS jsonb
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
 SELECT * INTO prior FROM trading.swap_trade_revisions r WHERE r.catalog_id=catalog AND r.operation_id=operation;
 IF FOUND THEN
  IF prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'swap_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.swap_operation_status(catalog,operation);
 END IF;
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
    AND (valuation>=s.first_fixing_at OR valuation>=s.payment_at OR valuation>=f.payment_at OR s.definition_revision_id<>definition OR f.reference_catalog_id<>ref_catalog OR f.reference_revision_id<>ref_revision OR f.quote_code<>q.code))
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
 SELECT id INTO floating_side FROM trading.swap_floating_sides WHERE catalog_id=catalog AND definition_revision_id=definition AND curve_code=curve AND contract_id IS NOT DISTINCT FROM k.id AND delivery_from=float_from AND delivery_to=float_to AND index_code=index_name AND first_fixing_at=fixing AND payment_at=float_payment AND swap_floating_sides.averaging=save_scheduled_swap.averaging AND payment_rule_id=float_rule;
 IF floating_side IS NULL THEN
  floating_side=gen_random_uuid();INSERT INTO trading.swap_floating_sides VALUES(catalog,floating_side,definition,curve,k.id,ref_catalog,ref_revision,index_name,q.code,float_from,float_to,fixing,float_payment,averaging,'prefixing_index_projection_v1',publication_number,from_at,float_rule);
  INSERT INTO trading.swap_reset_projections
   SELECT catalog,floating_side,(row_number() OVER(ORDER BY k1.delivery_from,k1.id)-1)::integer,definition,curve,k1.id,1,publication_number,from_at
   FROM market_data.contracts k1 JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.contract_id)=(k1.catalog_id,k1.revision_id,k1.id)
   WHERE m.catalog_id=catalog AND m.revision_id=definition AND m.curve_code=curve AND
    (averaging='monthly_index_price' AND k1.id=k.id OR averaging='calendar_day_arithmetic' AND k1.kind='forward' AND k1.delivery_to=k1.delivery_from+1 AND float_from<=k1.delivery_from AND k1.delivery_from<float_to);
 END IF;
 SELECT instrument_id INTO instrument FROM trading.swap_instruments WHERE catalog_id=catalog AND fixed_side_id=fixed_side AND floating_side_id=floating_side AND fixed_coefficient=coefficient AND swap_instruments.discounting=save_scheduled_swap.discounting;
 IF instrument IS NULL THEN
  instrument=gen_random_uuid();INSERT INTO trading.instruments VALUES(catalog,instrument,publication_number,from_at);
  INSERT INTO trading.swap_instruments VALUES(catalog,instrument,fixed_side,floating_side,coefficient,discounting,implementation,publication_number,from_at);
 END IF;
 IF trade IS NULL THEN
  trade=gen_random_uuid();binding=gen_random_uuid();
  INSERT INTO trading.trades VALUES(catalog,trade,book,operation,c.actor_id,request_value,publication_number,executed);
 ELSE
  IF(book,instrument,quantity,executed) IS NOT DISTINCT FROM(head.book_id,head.instrument_id,head.quantity,head.execution_at) THEN RAISE EXCEPTION 'swap_no_change' USING ERRCODE='P0001'; END IF;
  binding=CASE WHEN instrument=head.instrument_id THEN head.binding_id ELSE gen_random_uuid() END;
 END IF;
 INSERT INTO trading.swap_trade_revisions VALUES(catalog,trade,coalesce(head.revision,0)+1,head.revision,gen_random_uuid(),'monthly_financial_swap_booking_v1',CASE WHEN head.revision IS NULL THEN 'booked' ELSE 'amended' END,
  book,binding,instrument,quantity,executed,effective,operation,c.actor_id,CASE WHEN head.revision IS NULL THEN 'Initial booking' ELSE btrim(reason) END,request_value,publication_number);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,permission) THEN RAISE EXCEPTION 'Trade write access expired' USING ERRCODE='42501'; END IF;
 RETURN security.swap_operation_status(catalog,operation);
END $$;
DROP FUNCTION security.save_monthly_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,text,text,text,date,date,timestamptz,date,date,timestamptz,timestamptz,text,numeric,numeric,numeric,boolean,timestamptz,timestamptz,timestamptz,text,text);
DO $$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure signature,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='security' AND p.proname IN('swap_business_day','swap_payment_date','retain_swap_payment_rule','save_scheduled_swap') LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f.signature);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.signature);
 IF f.proname='save_scheduled_swap' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO openetrm_runtime',f.signature);END IF;
 END LOOP;
END $$;
COMMIT;
