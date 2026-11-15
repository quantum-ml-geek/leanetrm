-- Published clock captures are the common source for native admission and managed
-- generation. Reference preparation is private and identical retries are no-ops.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_runtime=X/@migration_owner","openetrm_security_owner=X/@migration_owner","@migration_owner=X/@migration_owner"],"owner":"@migration_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"market_data.ppa_day_boundary(timestamp with time zone,uuid,uuid,ref_data.code)","definition":"1a8e517f8236b98ecbc0f7e6093e23fb4a4301173ee46bfe6017421113221868","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"ref_data.captured_clock_boundary(jsonb,date)","definition":"071fde309bb7bffaa06dc88f3c91bea4c8834c1ab61ebde1169339ef1428f83d","volatility":"i"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"ref_data.clock_boundary(uuid,uuid,text,date)","definition":"2a3764f58d6de30d1fe354896e72b664d78672a82d4498190b04c58e5bc0715e","volatility":"s"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.ppa_boundary(uuid,uuid,text,integer,timestamp with time zone,boolean)","definition":"3c6a72454cb83411630c031414cc826cc1740301826e5fdc8352f04ad24ab4ac","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.ppa_day_start(uuid,uuid,text,date)","definition":"f4a8ed13a7839dd68d3c8f41f3623f0de6897f3ca0f86dae53683aaf3c94b048","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.require_side_payment_dates(uuid,uuid,jsonb)","definition":"c9e2ae1788a0207a338a1e65160f59c3a3d27e3b5d875fca8ac87006c533a1b4","volatility":"v"}]
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



CREATE FUNCTION ref_data.publish_clock_capture(catalog uuid,revision uuid,clock_name text,starts date,ends date,rules text,digest bytea,release text)
 RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE prior ref_data.clock_captures;
BEGIN
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT * INTO prior FROM ref_data.clock_captures WHERE(catalog_id,revision_id,clock_code)=(catalog,revision,clock_name);
 IF FOUND THEN
  IF(prior.coverage_from,prior.coverage_to,prior.payload,prior.definition_digest,prior.tzdb_version) IS DISTINCT FROM(starts,ends,rules,digest,release)
   THEN RAISE EXCEPTION 'clock_capture_conflict';END IF;
  RETURN;
 END IF;
 INSERT INTO ref_data.clock_captures VALUES(catalog,revision,clock_name,starts,ends,rules,digest,release);
END$$;
ALTER FUNCTION ref_data.publish_clock_capture(uuid,uuid,text,date,date,text,bytea,text) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION ref_data.publish_clock_capture(uuid,uuid,text,date,date,text,bytea,text) FROM PUBLIC;

CREATE FUNCTION ref_data.clock_local(catalog uuid,revision uuid,clock_name text,at timestamptz)
 RETURNS timestamp LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE capture ref_data.clock_captures;document jsonb;offset_minutes integer;
BEGIN
 SELECT * INTO capture FROM ref_data.clock_captures WHERE(catalog_id,revision_id,clock_code)=(catalog,revision,clock_name);
 IF NOT FOUND THEN RAISE EXCEPTION 'clock_reference';END IF;
 document=capture.payload::jsonb;
 IF at IS NULL OR NOT isfinite(at) OR at<(document->>'From')::timestamptz OR at>(document->>'To')::timestamptz
  THEN RAISE EXCEPTION 'clock_coverage';END IF;
 SELECT(r->>'Minutes')::integer INTO STRICT offset_minutes FROM jsonb_array_elements(document->'Runs') r
  WHERE(r->>'From')::timestamptz<=at ORDER BY(r->>'From')::timestamptz DESC LIMIT 1;
 RETURN(at AT TIME ZONE 'UTC')+make_interval(mins=>offset_minutes);
END$$;
ALTER FUNCTION ref_data.clock_local(uuid,uuid,text,timestamptz) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION ref_data.clock_local(uuid,uuid,text,timestamptz) FROM PUBLIC;
-- Invoker reads retain the clock table's forced historical/current-authority RLS.
GRANT EXECUTE ON FUNCTION ref_data.clock_local(uuid,uuid,text,timestamptz),ref_data.clock_boundary(uuid,uuid,text,date),ref_data.captured_clock_boundary(jsonb,date)
 TO openetrm_runtime,openetrm_risk_worker;
CREATE OR REPLACE FUNCTION market_data.ppa_day_boundary(at timestamptz,reference_catalog uuid,reference_revision uuid,clock_code ref_data.code)
 RETURNS boolean LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE local_at timestamp;
BEGIN
 IF at IS NULL OR NOT isfinite(at) THEN RETURN false;END IF;
 local_at=ref_data.clock_local(reference_catalog,reference_revision,clock_code,at);
 RETURN local_at=date_trunc('day',local_at) AND
  at=ref_data.clock_boundary(reference_catalog,reference_revision,clock_code,local_at::date);
END$$;
CREATE OR REPLACE FUNCTION security.ppa_day_start(rc uuid,rr uuid,clock_name text,day date)
 RETURNS timestamptz LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RETURN ref_data.clock_boundary(rc,rr,clock_name,day);END$$;
CREATE OR REPLACE FUNCTION security.ppa_boundary(rc uuid,rr uuid,clock_name text,minutes integer,at timestamptz,whole_month boolean)
 RETURNS boolean LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE local_at timestamp;
BEGIN
 IF at IS NULL OR NOT isfinite(at) OR minutes IS NULL OR minutes NOT IN(15,60) OR whole_month IS NULL THEN RETURN false;END IF;
 local_at=ref_data.clock_local(rc,rr,clock_name,at);
 RETURN extract(second FROM local_at)=0 AND mod(extract(minute FROM local_at)::integer,minutes)=0 AND
  (NOT whole_month OR(local_at=date_trunc('month',local_at) AND market_data.ppa_day_boundary(at,rc,rr,clock_name::ref_data.code)));
END$$;

CREATE FUNCTION security.require_interval_clock(schedule jsonb) RETURNS void
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE key jsonb=schedule#>'{Delivery,Clock}';capture ref_data.clock_captures;
BEGIN
 IF schedule->>'contract' IS DISTINCT FROM 'interval_side_schedule_parameters_v2' OR
  key->>0 IS DISTINCT FROM 'reference' OR key#>>'{1,0}' IS DISTINCT FROM 'reference_revision' THEN RAISE EXCEPTION 'clock_reference';END IF;
 SELECT * INTO capture FROM ref_data.clock_captures WHERE(catalog_id,revision_id,clock_code)=((key#>>'{1,1}')::uuid,(key#>>'{1,2}')::uuid,key->>2);
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM ref_data.revisions WHERE(catalog_id,id,state)=(capture.catalog_id,capture.revision_id,'sealed')) OR schedule->>'ClockRules' IS DISTINCT FROM capture.payload OR
  schedule->>'ClockFingerprint' IS DISTINCT FROM encode(capture.definition_digest,'hex') THEN RAISE EXCEPTION 'clock_reference';END IF;
 IF schedule#>>'{Delivery,From}' IS NULL OR schedule#>>'{Delivery,To}' IS NULL THEN RAISE EXCEPTION 'clock_reference';END IF;
 PERFORM ref_data.clock_boundary(capture.catalog_id,capture.revision_id,capture.clock_code,(schedule#>>'{Delivery,From}')::date);
 PERFORM ref_data.clock_boundary(capture.catalog_id,capture.revision_id,capture.clock_code,(schedule#>>'{Delivery,To}')::date);
END$$;
CREATE FUNCTION security.require_ppa_clock(catalog uuid,schedule uuid,definition jsonb,expected jsonb) RETURNS void
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE terms jsonb=coalesce(nullif(definition->'IntervalDefinition','null'::jsonb),definition->'Terms');
 delivery jsonb=terms->'Delivery';key jsonb=delivery->'Clock';port jsonb;native trading.ppa_sides;found_native boolean=false;payment record;owner record;port_number integer;
BEGIN
 IF terms->>'contract' IS DISTINCT FROM 'ppa_side_terms_v3' OR terms#>'{Schedule,Delivery}' IS DISTINCT FROM delivery OR
  definition#>>'{CalendarPolicy,PaymentTiming}' IS DISTINCT FROM 'utc_payment_day_v1' THEN RAISE EXCEPTION 'clock_reference';END IF;
 PERFORM security.require_interval_clock(terms->'Schedule');
 IF jsonb_typeof(terms->'InputPorts') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'clock_reference';END IF;
 FOR port IN SELECT value FROM jsonb_array_elements(terms->'InputPorts') LOOP
  IF port->'Schedule' IS DISTINCT FROM terms->'Schedule' THEN RAISE EXCEPTION 'ppa_schedule_source';END IF;
  PERFORM security.require_interval_clock(port->'Schedule');
 END LOOP;
 FOR native IN SELECT s.* FROM trading.ppa_sides s JOIN trading.side_schedules h ON(h.catalog_id,h.side_id)=(s.catalog_id,s.canonical_side_id)
  WHERE(h.catalog_id,h.id)=(catalog,schedule) LOOP
  found_native=true;
  IF jsonb_array_length(terms->'InputPorts')<>(SELECT count(*) FROM trading.ppa_side_slots WHERE(catalog_id,side_id)=(catalog,native.id)) THEN RAISE EXCEPTION 'ppa_schedule_source';END IF;
  IF native.quantity_kind='slots' THEN
   IF terms#>>'{Quantity,contract}' IS DISTINCT FROM 'ppa_slot_quantity_v1' OR
    terms#>'{Quantity,Slots}' IS DISTINCT FROM(SELECT jsonb_agg(p->'Slot' ORDER BY n) FROM jsonb_array_elements(terms->'InputPorts') WITH ORDINALITY x(p,n))
   THEN RAISE EXCEPTION 'ppa_schedule_source';END IF;
  ELSIF jsonb_array_length(terms->'InputPorts')<>0 THEN RAISE EXCEPTION 'ppa_schedule_source';END IF;
  FOR port,port_number IN SELECT value,(ordinality-1)::integer FROM jsonb_array_elements(terms->'InputPorts') WITH ORDINALITY LOOP
   IF NOT EXISTS(SELECT 1 FROM trading.ppa_side_slots l WHERE(l.catalog_id,l.side_id,l.position)=(catalog,native.id,port_number)
    AND port->'Slot'=jsonb_build_object('contract','ppa_slot_v1','Ordinal',l.ordinal,'Role',CASE l.role WHEN 'energy_delivery' THEN 1 WHEN 'certificate_delivery' THEN 2 WHEN 'capacity_delivery' THEN 3 END))
   THEN RAISE EXCEPTION 'ppa_schedule_source';END IF;
   FOR owner IN SELECT instrument_id FROM trading.ppa_memberships WHERE(catalog_id,side_id)=(catalog,native.id) LOOP
    IF NOT EXISTS(SELECT 1 FROM trading.ppa_side_slots l JOIN trading.ppa_memberships m ON(m.catalog_id,m.instrument_id,m.role,m.ordinal)=(l.catalog_id,owner.instrument_id,l.role,l.ordinal)
     JOIN trading.ppa_sides target ON(target.catalog_id,target.id)=(m.catalog_id,m.side_id)
     JOIN trading.sides canonical ON(canonical.catalog_id,canonical.id)=(target.catalog_id,target.canonical_side_id)
     WHERE(l.catalog_id,l.side_id,l.position)=(catalog,native.id,port_number) AND target.kind IN('energy','certificate','capacity')
      AND canonical.economic_identity::jsonb#>'{Terms,Schedule}'=port->'Schedule'
      AND canonical.economic_identity::jsonb#>'{Terms,ScheduleQuantity}'=port->'Quantity') THEN RAISE EXCEPTION 'ppa_schedule_source';END IF;
   END LOOP;
  END LOOP;
  IF key IS DISTINCT FROM jsonb_build_array('reference',jsonb_build_array('reference_revision',native.reference_catalog_id,native.reference_revision_id),native.clock_code) OR
   ((delivery->>'From')::date,(delivery->>'To')::date,(delivery->>'IntervalMinutes')::integer) IS DISTINCT FROM(native.delivery_from,native.delivery_to,native.interval_minutes)
   THEN RAISE EXCEPTION 'clock_reference';END IF;
 END LOOP;
 IF NOT found_native THEN RAISE EXCEPTION 'clock_reference';END IF;
 IF jsonb_array_length(expected) IS DISTINCT FROM((extract(year FROM(delivery->>'To')::date)-extract(year FROM(delivery->>'From')::date))*12+
  extract(month FROM(delivery->>'To')::date)-extract(month FROM(delivery->>'From')::date))::integer THEN RAISE EXCEPTION 'side_schedule_payment_date';END IF;
 FOR payment IN SELECT * FROM jsonb_to_recordset(expected) e(ordinal integer,"deliveryFrom" date,"deliveryTo" date,"paymentAt" timestamptz) LOOP
  IF payment."deliveryFrom" IS DISTINCT FROM((delivery->>'From')::date+make_interval(months=>payment.ordinal))::date OR
   payment."deliveryTo" IS DISTINCT FROM(payment."deliveryFrom"+INTERVAL '1 month')::date THEN RAISE EXCEPTION 'side_schedule_payment_date';END IF;
  IF payment."paymentAt" IS NULL OR(payment."paymentAt" AT TIME ZONE 'UTC')::date<
   (ref_data.clock_boundary((key#>>'{1,1}')::uuid,(key#>>'{1,2}')::uuid,key->>2,payment."deliveryTo") AT TIME ZONE 'UTC')::date
   THEN RAISE EXCEPTION 'payment_before_completion';END IF;
 END LOOP;
END$$;
ALTER FUNCTION security.require_interval_clock(jsonb) OWNER TO openetrm_security_owner;
ALTER FUNCTION security.require_ppa_clock(uuid,uuid,jsonb,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.require_interval_clock(jsonb),security.require_ppa_clock(uuid,uuid,jsonb,jsonb) FROM PUBLIC;
DO $$DECLARE source text;marker text=' IF definition->>''contract'' IN(''FixedSide_v5'',''FloatingSide_v9'')';BEGIN
 source=pg_get_functiondef('trading.require_side_payment_dates(uuid,uuid,jsonb)'::regprocedure);
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'ppa_clock_upgrade';END IF;
 EXECUTE overlay(source placing $patch$
 IF nullif(definition->'IntervalDefinition','null'::jsonb) IS NOT NULL OR definition ? 'Terms' THEN
  PERFORM security.require_ppa_clock(catalog,schedule,definition,expected);
 END IF;
$patch$ from strpos(source,marker) for 0);
END$$;
ALTER TABLE trading.swap_quantity_authoring ADD CONSTRAINT swap_quantity_published_clock
 FOREIGN KEY(reference_catalog_id,reference_revision_id,clock_code) REFERENCES ref_data.clock_captures(catalog_id,revision_id,clock_code) NOT VALID;
ALTER TABLE trading.ppa_side_schedules ADD CONSTRAINT ppa_schedule_published_clock
 FOREIGN KEY(reference_catalog_id,reference_revision_id,clock_code) REFERENCES ref_data.clock_captures(catalog_id,revision_id,clock_code) NOT VALID;
COMMIT;
