-- Dated financial completion is the whole contractual period boundary. Selected
-- peak hours and quantity factors cannot move that boundary implicitly.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"ref_data.clock_boundary(uuid,uuid,text,date)","definition":"2a3764f58d6de30d1fe354896e72b664d78672a82d4498190b04c58e5bc0715e","volatility":"s"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,jsonb,uuid[])","definition":"abe7be789869c4dab13729faac092e736dd73cb3caa3026e8293122be485a49e","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)","definition":"82ad939b9504fdb0c1cc5b662235279c6f2f0c3ba65dc9f70df9e7276e2f8813","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])","definition":"697265708eebc7bba905b21694f4e76537f1dd20c2f2bd4f4727b6e1d2fcf7f6","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamp with time zone,jsonb,uuid[])","definition":"9a2d7d2604807f5252f5cf122fdfa0f06c64d34c256d9c3435fef14b86e06fdb","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.staged_economic_side(uuid,uuid,integer)","definition":"d03028c519f675fa5b8b60df30f6c39c5722e63aa1b3ef1a0babda8ebf26d02c","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.require_side_payment_dates(uuid,uuid,jsonb)","definition":"a7f181ab58fa331c3be780c2b5f4205e37700251b87089bf51f02dac7f65af10","volatility":"v"}]
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



CREATE FUNCTION security.dated_side_completion(definition jsonb,period jsonb) RETURNS timestamptz
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE power jsonb=nullif(definition->'PowerQuantity','null'::jsonb);capture ref_data.clock_captures;key jsonb;completion timestamptz;
BEGIN
 IF definition->>'contract' NOT IN('FixedSide_v5','FloatingSide_v9') OR nullif(definition->'GasDeliveryClock','null'::jsonb) IS NOT NULL
  OR definition#>>'{CalendarPolicy,PaymentTiming}' IS DISTINCT FROM 'utc_payment_day_v1' THEN RAISE EXCEPTION 'delivery_completion';END IF;
 IF power IS NOT NULL THEN
  key=power->'Clock';
  IF key->>0 IS DISTINCT FROM 'reference' OR key#>>'{1,0}' IS DISTINCT FROM 'reference_revision' OR
   key->1 IS DISTINCT FROM(CASE definition->>'contract' WHEN 'FixedSide_v5' THEN definition#>'{DateQuoteKey,1}' ELSE definition#>'{DateQuote,1,1}' END) THEN RAISE EXCEPTION 'clock_reference';END IF;
  SELECT * INTO capture FROM ref_data.clock_captures WHERE(catalog_id,revision_id,clock_code)=((key#>>'{1,1}')::uuid,(key#>>'{1,2}')::uuid,key->>2);
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM ref_data.revisions WHERE(catalog_id,id,state)=(capture.catalog_id,capture.revision_id,'sealed')) OR power->>'ClockRules' IS DISTINCT FROM capture.payload OR
   power->>'ClockFingerprint' IS DISTINCT FROM encode(capture.definition_digest,'hex') THEN RAISE EXCEPTION 'clock_reference';END IF;
  PERFORM ref_data.clock_boundary(capture.catalog_id,capture.revision_id,capture.clock_code,(period->>'DeliveryFrom')::date);
  completion=ref_data.clock_boundary(capture.catalog_id,capture.revision_id,capture.clock_code,(period->>'DeliveryTo')::date);
  IF(period->>'DeliveryCompletionAt')::timestamptz IS DISTINCT FROM completion THEN RAISE EXCEPTION 'delivery_completion';END IF;
 ELSE
  completion=(period->>'DeliveryTo')::date::timestamp AT TIME ZONE 'UTC';
  IF nullif(period->'DeliveryCompletionAt','null'::jsonb) IS NOT NULL THEN RAISE EXCEPTION 'delivery_completion';END IF;
 END IF;
 IF completion IS NULL OR((period->>'PaymentAt')::timestamptz AT TIME ZONE 'UTC')::date<(completion AT TIME ZONE 'UTC')::date THEN RAISE EXCEPTION 'payment_before_completion';END IF;
 RETURN completion;
END$$;
CREATE FUNCTION security.require_scheduled_clock(catalog uuid,operation uuid,slot integer,body jsonb,compiled jsonb,pricing_definition uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE definition jsonb;power jsonb;reference jsonb;period jsonb;rc uuid;rr uuid;market uuid;
BEGIN
 SELECT economic_identity::jsonb,reference_catalog_id,reference_revision_id,definition_revision_id INTO STRICT definition,rc,rr,market FROM trading.sides WHERE(catalog_id,id)=(catalog,security.staged_economic_side(catalog,operation,slot));
 -- Fixed dated cash has no market-price source. It may be reused across
 -- pricing bundles with the same exact reference contract. Floating Sides
 -- retain their own admitted pricing revision.
 IF (definition->>'contract' IS DISTINCT FROM 'FixedSide_v5' AND market IS DISTINCT FROM pricing_definition)
  OR NOT EXISTS(SELECT 1 FROM market_data.revisions r
  WHERE(r.catalog_id,r.id,r.reference_catalog_id,r.reference_revision_id,r.state)=(catalog,pricing_definition,rc,rr,'sealed'))
 THEN RAISE EXCEPTION 'clock_reference';END IF;
 power=nullif(definition->'PowerQuantity','null'::jsonb);
 IF body->>'basis'='selected_interval_power' THEN
  reference=body#>'{power,clock}';
  IF power IS NULL OR power#>'{Clock,1}' IS DISTINCT FROM jsonb_build_array('reference_revision',rc,rr) OR power->'Clock' IS DISTINCT FROM jsonb_build_array('reference',
   jsonb_build_array('reference_revision',reference#>>'{revision,catalogId}',reference#>>'{revision,revisionId}'),reference->>'code') OR
   compiled#>>'{clock,rules}' IS DISTINCT FROM power->>'ClockRules' OR compiled#>>'{clock,fingerprint}' IS DISTINCT FROM power->>'ClockFingerprint'
  THEN RAISE EXCEPTION 'clock_reference';END IF;
 ELSE
  IF power IS NOT NULL OR nullif(compiled->'clock','null'::jsonb) IS NOT NULL THEN RAISE EXCEPTION 'clock_reference';END IF;
 END IF;
 FOR period IN SELECT value FROM jsonb_array_elements(definition->'Periods') LOOP
  PERFORM security.dated_side_completion(definition,period);
 END LOOP;
END$$;
ALTER FUNCTION security.dated_side_completion(jsonb,jsonb) OWNER TO openetrm_security_owner;
ALTER FUNCTION security.require_scheduled_clock(uuid,uuid,integer,jsonb,jsonb,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.dated_side_completion(jsonb,jsonb),security.require_scheduled_clock(uuid,uuid,integer,jsonb,jsonb,uuid) FROM PUBLIC;
DO $$DECLARE source text;marker text;signature regprocedure;BEGIN
 source=pg_get_functiondef('security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamptz,jsonb,uuid[])'::regprocedure);
 marker='kind=(side_body->''periods''->0->>''fixed'') IS NOT NULL;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'contract_clock_upgrade';END IF;
 EXECUTE replace(source,marker,marker||'PERFORM security.require_scheduled_clock(catalog,operation,slot,side_body,shape,definition);');
 -- These private period preparers do not own the whole-Side clock. Completion
 -- is enforced against admitted Side terms before publication in every caller.
 FOREACH signature IN ARRAY ARRAY[
  'security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz)'::regprocedure,
  'security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[])'::regprocedure,
  'security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,jsonb,uuid[])'::regprocedure] LOOP
  source=pg_get_functiondef(signature);
  marker='IF (payment AT TIME ZONE ''UTC'')::date<(body->>''deliveryTo'')::date THEN RAISE EXCEPTION ''payment_before_delivery'';END IF;';
  IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'contract_clock_upgrade';END IF;
  EXECUTE replace(source,marker,'');
 END LOOP;
 source=pg_get_functiondef('trading.require_side_payment_dates(uuid,uuid,jsonb)'::regprocedure);
 source=replace(source,E'AS $function$\nBEGIN',E'AS $function$\nDECLARE definition jsonb;period jsonb;n integer;\nBEGIN');
 IF strpos(source,'DECLARE definition jsonb')=0 THEN RAISE EXCEPTION 'contract_clock_upgrade';END IF;
 marker=' IF EXISTS(';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'contract_clock_upgrade';END IF;
 source=overlay(source placing $patch$
 SELECT s.economic_identity::jsonb INTO STRICT definition FROM trading.side_schedules h JOIN trading.sides s ON(s.catalog_id,s.id)=(h.catalog_id,h.side_id)
  WHERE(h.catalog_id,h.id)=(catalog,schedule);
 IF definition->>'contract' IN('FixedSide_v5','FloatingSide_v9') AND nullif(definition->'IntervalDefinition','null'::jsonb) IS NULL THEN
  IF jsonb_array_length(definition->'Periods') IS DISTINCT FROM jsonb_array_length(expected) THEN RAISE EXCEPTION 'side_schedule_payment_date';END IF;
  FOR period,n IN SELECT value,(ordinality-1)::integer FROM jsonb_array_elements(definition->'Periods') WITH ORDINALITY LOOP
   IF NOT EXISTS(SELECT 1 FROM jsonb_to_recordset(expected) e(ordinal integer,"deliveryFrom" date,"deliveryTo" date,"paymentAt" timestamptz)
    WHERE e.ordinal=n AND(e."deliveryFrom",e."deliveryTo",e."paymentAt")=((period->>'DeliveryFrom')::date,(period->>'DeliveryTo')::date,(period->>'PaymentAt')::timestamptz))
   THEN RAISE EXCEPTION 'side_schedule_payment_date';END IF;
   PERFORM security.dated_side_completion(definition,period);
  END LOOP;
 END IF;
$patch$ from strpos(source,marker) for 0);
 EXECUTE source;
END$$;
CREATE OR REPLACE FUNCTION settlement_data.swap_completion_at(catalog uuid,trade uuid,revision integer,instrument uuid,membership integer,period_from date,period_to date)
 RETURNS timestamptz LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE definition jsonb;period jsonb;
BEGIN
 SELECT s.economic_identity::jsonb INTO STRICT definition FROM trading.swap_instruments i
 JOIN trading.sides s ON(s.catalog_id,s.id)=(i.catalog_id,CASE membership WHEN 0 THEN coalesce(i.scheduled_first_id,i.fixed_side_id,i.first_floating_side_id) WHEN 1 THEN coalesce(i.scheduled_second_id,i.floating_side_id) END)
 WHERE(i.catalog_id,i.instrument_id)=(catalog,instrument);
 SELECT value INTO STRICT period FROM jsonb_array_elements(definition->'Periods') p(value)
  WHERE((value->>'DeliveryFrom')::date,(value->>'DeliveryTo')::date)=(period_from,period_to);
 RETURN security.dated_side_completion(definition,period);
END$$;
CREATE OR REPLACE FUNCTION settlement_data.swap_completion_source(catalog uuid,trade uuid,revision integer,instrument uuid,membership integer) RETURNS text
 LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT CASE WHEN nullif(s.economic_identity::jsonb->'PowerQuantity','null'::jsonb) IS NULL THEN 'date_only_utc_v1' ELSE 'retained_contract_clock_v1' END
 FROM trading.swap_instruments i JOIN trading.sides s ON(s.catalog_id,s.id)=(i.catalog_id,
  CASE membership WHEN 0 THEN coalesce(i.scheduled_first_id,i.fixed_side_id,i.first_floating_side_id) WHEN 1 THEN coalesce(i.scheduled_second_id,i.floating_side_id) END)
 WHERE(i.catalog_id,i.instrument_id)=(catalog,instrument);
$$;
ALTER TABLE settlement_data.swap_occurrences DROP CONSTRAINT swap_occurrences_completion_source_check;
ALTER TABLE settlement_data.swap_occurrences ADD CONSTRAINT swap_occurrences_completion_source_check
 CHECK(completion_source IN('date_only_utc_v1','retained_contract_clock_v1')) NOT VALID;
COMMIT;
