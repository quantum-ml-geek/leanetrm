-- Gas authoring retains the same explicit Side policy as its executable program.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.write_gas_composition(uuid,jsonb,timestamp with time zone,boolean)","definition":"fb1b463fde8805a475a8598915f0f79dcb27a132b6200a7857d99cf8d6785ded","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":true,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.gas_identity_reference(uuid,uuid,text)","definition":"4667610cba8f35cc96cd2b8d9c08f14bf37adaf90515b48c15d182b0b19e8b3b","volatility":"i"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"trading.require_gas_index_cash_shape(uuid,uuid,trading.gas_component_terms,market_data.gas_valuation_assignments,jsonb)","definition":"1a84f310d99676ab7a7aa4cdc807ffc1edcff9795fd4608f9632ddeeff24490a","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"trading.require_gas_program_shape(uuid,uuid,integer,date,date,timestamp with time zone,numeric,numeric,market_data.gas_valuation_assignments,ref_data.gas_delivery_conventions,timestamp with time zone)","definition":"489c229a2b55899843b0fdccaf16a4c80816ac6720c18e72f45098ba50ba33c2","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"trading.require_gas_program_shape(uuid,uuid,integer,date,date,timestamp with time zone,numeric,numeric,market_data.gas_valuation_assignments,ref_data.gas_delivery_conventions,timestamp with time zone,jsonb)","definition":"4274bcac9033ce34003616f095aedc8d2935267f33d101366bf1dfc9a1f59c76","volatility":"v"}]
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
 source=pg_get_functiondef('security.write_gas_composition(uuid,jsonb,timestamptz,boolean)'::regprocedure);
 FOREACH marker IN ARRAY ARRAY['''quantity'',''link'',''forecastCurve''','''paymentAt'',''indexed'''] LOOP
  IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'gas_calendar_upgrade';END IF;
  source=replace(source,marker,marker||',''calendarPolicy''');
 END LOOP;
 EXECUTE source;
END$$;
-- Fixed-offset gas is independently verifiable from its sealed reference. The
-- cash clock is the linked source contract, independent of calendar ownership.
CREATE FUNCTION trading.require_gas_completion(catalog uuid,schedule uuid,physical boolean,first_day date,last_day date,
 assignment market_data.gas_valuation_assignments,delivery ref_data.gas_delivery_conventions) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE definition jsonb;clock ref_data.clock_rules;expected_clock jsonb;p jsonb;n integer;completion timestamptz;starts date;ends date;count_periods integer;
BEGIN
 SELECT s.economic_identity::jsonb INTO STRICT definition FROM trading.side_schedules h
  JOIN trading.sides s ON(s.catalog_id,s.id)=(h.catalog_id,h.side_id) WHERE(h.catalog_id,h.id)=(catalog,schedule);
 SELECT * INTO STRICT clock FROM ref_data.clock_rules WHERE(catalog_id,revision_id,code)=(assignment.reference_catalog_id,assignment.reference_revision_id,delivery.clock_code);
 IF clock.kind<>'fixed_offset' OR clock.fixed_offset_seconds%60<>0 OR abs(clock.fixed_offset_seconds)>50400 THEN RAISE EXCEPTION 'gas_schedule_completion';END IF;
 expected_clock=jsonb_build_object('contract','gas_day_clock_v1','Key',trading.gas_identity_reference(clock.catalog_id,clock.revision_id,clock.code),
  'StartMinute',delivery.day_start_minute,'Rules',clock.code||';'||(clock.fixed_offset_seconds/60)::text||';'||clock.code||';'||clock.code||';'||clock.code||';;');
 IF physical THEN
  IF definition->>'contract' IS DISTINCT FROM 'physical_gas_side_v2' OR definition#>'{Quantities,Clock}' IS DISTINCT FROM expected_clock OR
   (definition#>>'{Quantities,From}')::date IS DISTINCT FROM first_day OR(definition#>>'{Quantities,To}')::date IS DISTINCT FROM last_day
  THEN RAISE EXCEPTION 'gas_schedule_completion';END IF;
  RETURN;
 END IF;
 IF definition->>'contract' NOT IN('FixedSide_v5','FloatingSide_v9') OR definition->'GasDeliveryClock' IS DISTINCT FROM expected_clock OR
  nullif(definition->'PowerQuantity','null'::jsonb) IS NOT NULL OR jsonb_typeof(definition->'Periods') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'gas_schedule_completion';END IF;
 count_periods=jsonb_array_length(definition->'Periods');
 IF count_periods<>(CASE definition->>'contract' WHEN 'FixedSide_v5' THEN 1 ELSE last_day-first_day END) THEN RAISE EXCEPTION 'gas_schedule_completion';END IF;
 FOR p,n IN SELECT value,(ordinality-1)::integer FROM jsonb_array_elements(definition->'Periods') WITH ORDINALITY LOOP
  starts=CASE WHEN count_periods=1 THEN first_day ELSE first_day+n END;
  ends=CASE WHEN count_periods=1 THEN last_day ELSE starts+1 END;
  completion=ends::timestamp AT TIME ZONE 'UTC'+make_interval(mins=>delivery.day_start_minute)-make_interval(secs=>clock.fixed_offset_seconds);
  IF(p->>'DeliveryFrom')::date IS DISTINCT FROM starts OR(p->>'DeliveryTo')::date IS DISTINCT FROM ends OR
   (p->>'DeliveryCompletionAt')::timestamptz IS DISTINCT FROM completion OR
   ((p->>'PaymentAt')::timestamptz AT TIME ZONE 'UTC')::date<(completion AT TIME ZONE 'UTC')::date OR
   NOT EXISTS(SELECT 1 FROM trading.side_schedule_rows r WHERE(r.catalog_id,r.schedule_id,r.operation,r.payment_ordinal)=(catalog,schedule,'output_guard',n)
    AND(r.delivery_from,r.delivery_to,r.value_at)=(starts,ends,(p->>'PaymentAt')::timestamptz))
  THEN RAISE EXCEPTION 'gas_schedule_completion';END IF;
 END LOOP;
END$$;
ALTER FUNCTION trading.require_gas_completion(uuid,uuid,boolean,date,date,market_data.gas_valuation_assignments,ref_data.gas_delivery_conventions) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION trading.require_gas_completion(uuid,uuid,boolean,date,date,market_data.gas_valuation_assignments,ref_data.gas_delivery_conventions) FROM PUBLIC;

DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('trading.require_gas_program_shape(uuid,uuid,integer,date,date,timestamptz,numeric,numeric,market_data.gas_valuation_assignments,ref_data.gas_delivery_conventions,timestamptz,jsonb)'::regprocedure);
 marker=' IF days<1 OR days>1200 THEN RAISE EXCEPTION ''gas_schedule_geometry'';END IF;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'gas_calendar_upgrade';END IF;
 EXECUTE replace(source,marker,marker||'PERFORM trading.require_gas_completion(catalog,schedule,slot=0,first_day,last_day,assignment,delivery);');
 source=pg_get_functiondef('trading.require_gas_index_cash_shape(uuid,uuid,trading.gas_component_terms,market_data.gas_valuation_assignments,jsonb)'::regprocedure);
 marker=' IF clock.kind<>''fixed_offset'' THEN RAISE EXCEPTION ''gas_index_terms'';END IF;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'gas_calendar_upgrade';END IF;
 EXECUTE replace(source,marker,marker||'PERFORM trading.require_gas_completion(catalog,schedule,false,source.delivery_from,source.delivery_to,a,delivery);');
END$$;

COMMIT;
