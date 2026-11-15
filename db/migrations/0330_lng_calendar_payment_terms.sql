-- LNG admission verifies the one canonical Side contract and retains UTC payment
-- dates independently of discharge/event instants. Existing bookings are untouched.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.book_physical_lng(uuid,jsonb,timestamp with time zone)","definition":"d6075998ebdf474b05acd6841da3d5d5b8778d66bc314296721510ab03808517","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"trading.require_lng_program_shape(uuid,uuid,integer,jsonb,market_data.lng_valuation_assignments)","definition":"a9ac7f70b19914bff7525fbf4188f55c94ed8fdcb04fa0a1cbc52e1319f787dd","volatility":"v"}]
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



DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('security.book_physical_lng(uuid,jsonb,timestamptz)'::regprocedure);
 marker='''discounting'',''legalEntityId'',''legalEntityRevision'',''counterpartyId'',''counterpartyRevision'']';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'lng_calendar_upgrade';END IF;
 source=replace(source,marker,'''discounting'',''legalEntityId'',''legalEntityRevision'',''counterpartyId'',''counterpartyRevision'',''deliveryCalendarPolicy'',''considerationCalendarPolicy'']');
 IF strpos(source,'(payment AT TIME ZONE ''UTC'')::date<(discharge_end AT TIME ZONE ''UTC'')::date')=0 THEN RAISE EXCEPTION 'lng_calendar_upgrade';END IF;
 EXECUTE source;
 source=pg_get_functiondef('trading.require_lng_program_shape(uuid,uuid,integer,jsonb,market_data.lng_valuation_assignments)'::regprocedure);
 marker=' IF NOT EXISTS(SELECT 1 FROM trading.side_schedules h JOIN trading.sides s ON(s.catalog_id,s.id)=(h.catalog_id,h.side_id)'||E'\n'||' WHERE(h.catalog_id,h.id)=(catalog,schedule) AND s.economic_identity::jsonb=CASE';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'lng_calendar_upgrade';END IF;
 source=overlay(source placing $patch$
 expected_physical=(expected_physical-'contract')||jsonb_build_object('contract','physical_lng_cargo_side_v2',
  'CalendarPolicy',(SELECT s.economic_identity::jsonb->'CalendarPolicy' FROM trading.side_schedules h
   JOIN trading.sides s ON(s.catalog_id,s.id)=(h.catalog_id,h.side_id) WHERE(h.catalog_id,h.id)=(catalog,schedule)));
 expected_cash=(expected_cash-'contract')||jsonb_build_object('contract','FixedSide_v5','PowerQuantity',NULL,'GasDeliveryClock',NULL,
  'CalendarPolicy',expected_physical->'CalendarPolicy');
 expected_cash=jsonb_set(expected_cash,'{Periods,0}',(expected_cash#>'{Periods,0}')||jsonb_build_object('contract','fixed_side_period_v2',
  'DeliveryCompletionAt',to_char(discharge_end AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00'));
 IF slot=0 AND NOT EXISTS(SELECT 1 FROM trading.side_schedules h
  JOIN trading.side_calendar_bindings b ON(b.catalog_id,b.side_id,b.purpose)=(h.catalog_id,h.side_id,'Delivery')
  JOIN ref_data.calendars c ON(c.catalog_id,c.revision_id,c.code)=(b.reference_catalog_id,b.reference_revision_id,b.calendar_code)
  WHERE(h.catalog_id,h.id)=(catalog,schedule) AND b.applicable AND c.coverage_from<=first_day AND c.coverage_to>=last_day)
 THEN RAISE EXCEPTION 'calendar_coverage';END IF;
 IF(payment AT TIME ZONE 'UTC')::date<(discharge_end AT TIME ZONE 'UTC')::date THEN RAISE EXCEPTION 'payment_before_completion';END IF;
$patch$ from strpos(source,marker) for 0);
 EXECUTE source;
END$$;
COMMIT;
