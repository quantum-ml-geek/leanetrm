-- Independent crude cash components retain their exact contractual payment dates.
-- Existing rows are untouched and require explicit migration before execution.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.book_physical_crude(uuid,jsonb,timestamp with time zone)","definition":"a1db471ae1f17bbca4d8ea76a95821ca024cdca8e2e0f2347bc14f161a719c29","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.record_crude_lifecycle(uuid,text,jsonb,timestamp with time zone,uuid)","definition":"ca9bb8428133e907d5e7d76b20713f2dea41d07e03900e1e2fff9e5496db5960","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"trading.require_crude_program_shape(uuid,uuid,integer,timestamp with time zone,timestamp with time zone,timestamp with time zone,numeric,market_data.crude_valuation_assignments)","definition":"9b8eb3ae022a1bb4fc50b6e62dca8dd793d9c80c0879ed6b0f443b3b1d5e6b13","volatility":"v"}]
$calendar_helpers$::jsonb) LOOP
  SELECT * INTO helper FROM pg_proc WHERE oid=to_regprocedure(expected->>'signature');
  SELECT jsonb_agg(x::text ORDER BY x::text) INTO actual_acl FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x;
  SELECT jsonb_agg(value ORDER BY value) INTO expected_acl FROM(
   SELECT replace(value,'@migration_owner',quote_ident(current_user))::aclitem::text value FROM jsonb_array_elements_text(expected->'acl')) a;
  IF helper.oid IS NULL OR encode(sha256(convert_to(pg_get_functiondef(helper.oid),'UTF8')),'hex') IS DISTINCT FROM expected->>'definition' OR
   pg_get_userbyid(helper.proowner) IS DISTINCT FROM(CASE expected->>'owner' WHEN '@migration_owner' THEN current_user ELSE expected->>'owner' END) OR
   helper.prosecdef IS DISTINCT FROM(expected->>'definer')::boolean OR helper.provolatile IS DISTINCT FROM(expected->>'volatility')::"char" OR
   helper.proisstrict IS DISTINCT FROM(expected->>'strict')::boolean OR helper.proleakproof IS DISTINCT FROM(expected->>'leakproof')::boolean OR
   helper.proparallel IS DISTINCT FROM(expected->>'parallel')::"char" OR coalesce(to_jsonb(helper.proconfig),'null'::jsonb) IS DISTINCT FROM expected->'config' OR
   actual_acl IS DISTINCT FROM expected_acl THEN RAISE EXCEPTION 'calendar_contract_upgrade: unexpected helper %',expected->>'signature';END IF;
 END LOOP;
END$calendar_upgrade$;



ALTER TABLE trading.crude_instruments ADD COLUMN handling_fee_payment_at timestamptz;
ALTER TABLE trading.crude_instruments ADD CONSTRAINT crude_fee_payment_date CHECK(
 (handling_fee IS NULL)=(handling_fee_payment_at IS NULL) AND
 (handling_fee_payment_at IS NULL OR isfinite(handling_fee_payment_at) AND
 (handling_fee_payment_at AT TIME ZONE 'UTC')::date>=(delivery_to AT TIME ZONE 'UTC')::date)) NOT VALID;

DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('security.book_physical_crude(uuid,jsonb,timestamptz)'::regprocedure);
 marker='payment timestamptz=(body->>''paymentAt'')::timestamptz;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'crude_calendar_upgrade';END IF;
 source=replace(source,marker,marker||'fee_payment timestamptz=(body->>''handlingFeePaymentAt'')::timestamptz;');
 marker='''direction'',''considerationDirection'',''fixedPrice'',''handlingFee'',''handlingFeeDirection'',''paymentAt'',''discounting''';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'crude_calendar_upgrade';END IF;
 source=replace(source,marker,marker||',''handlingFeePaymentAt'',''deliveryCalendarPolicy'',''considerationCalendarPolicy'',''feeCalendarPolicy''');
 marker=' IF valuation>=start_at OR';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'crude_calendar_upgrade';END IF;
 source=replace(source,marker,$patch$
 IF (fee IS NULL)<>(fee_payment IS NULL) OR fee_payment IS NOT NULL AND(NOT isfinite(fee_payment) OR
  (fee_payment AT TIME ZONE 'UTC')::date<(end_at AT TIME ZONE 'UTC')::date) OR
  fee IS NULL AND nullif(body->'feeCalendarPolicy','null'::jsonb) IS NOT NULL THEN RAISE EXCEPTION 'crude_input';END IF;
 IF valuation>=start_at OR$patch$);
 source=replace(source,'body->>''deliveryTo'',body->>''paymentAt'']','body->>''deliveryTo'',body->>''paymentAt'',body->>''handlingFeePaymentAt'']');
 marker='item.slot,start_at,end_at,payment,CASE';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'crude_calendar_upgrade';END IF;
 source=replace(source,marker,'item.slot,start_at,end_at,CASE WHEN item.slot=2 THEN fee_payment ELSE payment END,CASE');
 marker='consideration_direction,fee_direction,publication,valuation);';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'crude_calendar_upgrade';END IF;
 source=replace(source,marker,'consideration_direction,fee_direction,publication,valuation,fee_payment);');
 EXECUTE source;

 source=pg_get_functiondef('trading.require_crude_program_shape(uuid,uuid,integer,timestamptz,timestamptz,timestamptz,numeric,market_data.crude_valuation_assignments)'::regprocedure);
 marker=' IF slot=0 THEN'||E'\n'||'  IF NOT EXISTS(SELECT 1 FROM trading.side_schedules h JOIN trading.sides d';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'crude_calendar_upgrade';END IF;
 source=replace(source,marker,$patch$
 IF slot=0 AND NOT EXISTS(SELECT 1 FROM trading.side_schedules h
  JOIN trading.side_calendar_bindings b ON(b.catalog_id,b.side_id,b.purpose)=(h.catalog_id,h.side_id,'Delivery')
  JOIN ref_data.calendars c ON(c.catalog_id,c.revision_id,c.code)=(b.reference_catalog_id,b.reference_revision_id,b.calendar_code)
  WHERE(h.catalog_id,h.id)=(catalog,schedule) AND b.applicable AND c.coverage_from<=first_day AND c.coverage_to>=last_day)
 THEN RAISE EXCEPTION 'calendar_coverage';END IF;
 expected_physical=(expected_physical-'contract')||jsonb_build_object('contract','physical_crude_side_v3',
  'QuantityEquivalence',expected_assignment->'QuantityEquivalence',
  'CalendarPolicy',(SELECT d.economic_identity::jsonb->'CalendarPolicy' FROM trading.side_schedules h
   JOIN trading.sides d ON(d.catalog_id,d.id)=(h.catalog_id,h.side_id) WHERE(h.catalog_id,h.id)=(catalog,schedule)));
 IF slot<>0 AND NOT EXISTS(SELECT 1 FROM trading.side_schedules h JOIN trading.sides d ON(d.catalog_id,d.id)=(h.catalog_id,h.side_id)
  WHERE(h.catalog_id,h.id)=(catalog,schedule) AND d.economic_identity::jsonb->>'contract'='FixedSide_v5'
  AND jsonb_array_length(d.economic_identity::jsonb->'Periods')=1
  AND coalesce((d.economic_identity::jsonb#>>'{Periods,0,DeliveryCompletionAt}')::timestamptz,
   (d.economic_identity::jsonb#>>'{Periods,0,DeliveryTo}')::date::timestamp AT TIME ZONE 'UTC')=end_at)
 THEN RAISE EXCEPTION 'crude_schedule_completion';END IF;
 IF slot=0 THEN
  IF NOT EXISTS(SELECT 1 FROM trading.side_schedules h JOIN trading.sides d$patch$);
 EXECUTE source;

 source=pg_get_functiondef('security.record_crude_lifecycle(uuid,text,jsonb,timestamptz,uuid)'::regprocedure);
 marker='''crude_cumulative_receipt_cash_v1'',i.payment_at,dispatch.id';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'crude_calendar_upgrade';END IF;
 EXECUTE replace(source,marker,'''crude_cumulative_receipt_cash_v1'',CASE component_slot WHEN 1 THEN i.payment_at ELSE i.handling_fee_payment_at END,dispatch.id');
END$$;
COMMIT;
