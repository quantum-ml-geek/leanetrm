-- A booked clock capture is an exact published reference contract. Neither its
-- payload nor its release can be supplied independently by the booking runtime.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["@migration_owner=X/@migration_owner"],"owner":"@migration_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"ref_data.guard_definition()","definition":"f239850eb71b229d4bc335f5781de0e0488e0933b715d97de1e2488bb8f2e072","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.reference_display_tables()","definition":"5a738889cd4c9e3fa6138288d01c8ffd069141159dd7618285ba09303e9597df","volatility":"i"}]
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



CREATE TABLE ref_data.clock_captures (
 catalog_id uuid NOT NULL,revision_id uuid NOT NULL,clock_code ref_data.code NOT NULL,
 coverage_from date NOT NULL,coverage_to date NOT NULL,payload text NOT NULL,definition_digest bytea NOT NULL,tzdb_version text,
 PRIMARY KEY(catalog_id,revision_id,clock_code),
 FOREIGN KEY(catalog_id,revision_id,clock_code) REFERENCES ref_data.clock_rules(catalog_id,revision_id,code),
 CHECK(coverage_from>=DATE '2000-01-01' AND coverage_to<=DATE '2100-01-01' AND coverage_from<coverage_to),
 CHECK(length(payload) BETWEEN 1 AND 65536 AND definition_digest=sha256(convert_to(payload,'UTF8')))
);
CREATE FUNCTION ref_data.captured_clock_boundary(document jsonb,day date) RETURNS timestamptz
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE candidates integer;instant timestamptz;
BEGIN
 SELECT count(*),min(candidate) INTO candidates,instant FROM(
  SELECT (day::timestamp AT TIME ZONE 'UTC')-make_interval(mins=>(r->>'Minutes')::integer) candidate,
   (r->>'From')::timestamptz starts,lead((r->>'From')::timestamptz) OVER(ORDER BY n) ends
  FROM jsonb_array_elements(document->'Runs') WITH ORDINALITY x(r,n)
 ) offsets WHERE candidate>=starts AND(candidate<ends OR ends IS NULL AND candidate<=(document->>'To')::timestamptz)
  AND candidate>=(document->>'From')::timestamptz;
 IF candidates<>1 THEN RAISE EXCEPTION 'clock_boundary';END IF;
 RETURN instant;
END$$;
CREATE FUNCTION ref_data.clock_boundary(catalog uuid,revision uuid,clock_name text,day date) RETURNS timestamptz
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE capture ref_data.clock_captures;
BEGIN
 SELECT * INTO capture FROM ref_data.clock_captures WHERE(catalog_id,revision_id,clock_code)=(catalog,revision,clock_name);
 IF NOT FOUND THEN RAISE EXCEPTION 'clock_reference';END IF;
 IF day<capture.coverage_from OR day>capture.coverage_to THEN RAISE EXCEPTION 'clock_coverage';END IF;
 RETURN ref_data.captured_clock_boundary(capture.payload::jsonb,day);
END$$;
CREATE FUNCTION ref_data.guard_clock_capture() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE clock ref_data.clock_rules;raw json=NEW.payload::json;document jsonb=NEW.payload::jsonb;first_at timestamptz;last_at timestamptz;
 stamp_pattern constant text='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:00([.]0{1,7})?(Z|\+00:00)$';
BEGIN
 SELECT * INTO STRICT clock FROM ref_data.clock_rules WHERE(catalog_id,revision_id,code)=(NEW.catalog_id,NEW.revision_id,NEW.clock_code);
 IF document->>'Implementation' IS DISTINCT FROM 'captured_power_grid_clock_v1' OR
  document->>'Id' IS DISTINCT FROM(CASE clock.kind WHEN 'iana' THEN clock.iana_zone ELSE clock.code END) OR
  NEW.tzdb_version IS DISTINCT FROM clock.tzdb_version OR jsonb_typeof(document->'Runs') IS DISTINCT FROM 'array' OR
  document-ARRAY['Implementation','Id','From','To','Runs']<>'{}'::jsonb OR
  jsonb_array_length(document->'Runs') NOT BETWEEN 1 AND 4096 OR
  (document->>'From')!~'(Z|\+00:00)$' OR(document->>'To')!~'(Z|\+00:00)$'
 THEN RAISE EXCEPTION 'clock_capture';END IF;
 -- jsonb normalizes number spellings; validate the authorized wire bytes before
 -- interpreting them. Both readers accept whole-minute ISO UTC coordinates.
 IF EXISTS(SELECT 1 FROM json_each(raw) GROUP BY key HAVING count(*)>1) OR
  EXISTS(SELECT 1 FROM json_array_elements(raw->'Runs') r CROSS JOIN LATERAL json_each(r) p GROUP BY r::text,p.key HAVING count(*)>1) OR
  (raw->>'From')!~stamp_pattern OR(raw->>'To')!~stamp_pattern OR EXISTS(
  SELECT 1 FROM json_array_elements(raw->'Runs') r WHERE
   (r->>'From')!~stamp_pattern OR(r->>'Minutes')!~'^-?(0|[1-9][0-9]*)$')
 THEN RAISE EXCEPTION 'clock_capture';END IF;
 first_at=(document->>'From')::timestamptz;last_at=(document->>'To')::timestamptz;
 IF first_at IS NULL OR last_at IS NULL OR NOT isfinite(first_at) OR NOT isfinite(last_at) OR first_at>=last_at OR
  last_at-first_at>INTERVAL '36600 days' OR extract(epoch FROM(last_at-first_at))%300<>0 OR
  (document#>>'{Runs,0,From}')::timestamptz IS DISTINCT FROM first_at
 THEN RAISE EXCEPTION 'clock_capture';END IF;
 IF EXISTS(SELECT 1 FROM(
  SELECT r,n,lag((r->>'From')::timestamptz) OVER(ORDER BY n) previous_at,lag((r->>'Minutes')::integer) OVER(ORDER BY n) previous_offset
  FROM jsonb_array_elements(document->'Runs') WITH ORDINALITY x(r,n)) x
  WHERE jsonb_typeof(r) IS DISTINCT FROM 'object' OR jsonb_typeof(r->'Minutes') IS DISTINCT FROM 'number' OR jsonb_typeof(r->'From') IS DISTINCT FROM 'string' OR NOT(r ?& ARRAY['From','Minutes']) OR r-ARRAY['From','Minutes']<>'{}'::jsonb OR
   (r->>'From')!~'(Z|\+00:00)$' OR(r->>'Minutes')!~'^-?[0-9]+$' OR(r->>'Minutes')::integer NOT BETWEEN -840 AND 840 OR
   (r->>'From')::timestamptz<first_at OR(r->>'From')::timestamptz>last_at OR
   extract(epoch FROM((r->>'From')::timestamptz-first_at))%300<>0 OR
   n>1 AND((r->>'From')::timestamptz<=previous_at OR(r->>'Minutes')::integer=previous_offset) OR
   clock.kind='fixed_offset' AND(clock.fixed_offset_seconds%60<>0 OR(r->>'Minutes')::integer*60<>clock.fixed_offset_seconds))
 THEN RAISE EXCEPTION 'clock_capture';END IF;
 IF ref_data.captured_clock_boundary(document,NEW.coverage_from)<>first_at OR
  ref_data.captured_clock_boundary(document,NEW.coverage_to)<>last_at THEN RAISE EXCEPTION 'clock_capture';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.clock_captures FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER validate_capture BEFORE INSERT ON ref_data.clock_captures FOR EACH ROW EXECUTE FUNCTION ref_data.guard_clock_capture();
ALTER TABLE ref_data.clock_captures ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref_data.clock_captures FORCE ROW LEVEL SECURITY;
GRANT SELECT ON ref_data.clock_captures TO openetrm_runtime,openetrm_risk_worker,openetrm_security_owner;
GRANT INSERT ON ref_data.clock_captures TO openetrm_security_owner;
-- Reuse the exact installed clock-reference read fences, including historical
-- visibility, current authority and worker admission. No general visibility change.
DO $$DECLARE policy record;roles text;source text;BEGIN
 FOR policy IN SELECT * FROM pg_policy WHERE polrelid='ref_data.clock_rules'::regclass AND polcmd IN('r','*') LOOP
  SELECT string_agg(CASE WHEN id=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(id)) END,',') INTO roles FROM unnest(policy.polroles) id;
  EXECUTE format('CREATE POLICY %I ON ref_data.clock_captures AS %s FOR SELECT TO %s USING(%s)',policy.polname,
   CASE WHEN policy.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END,roles,pg_get_expr(policy.polqual,policy.polrelid));
 END LOOP;
 CREATE POLICY internal_insert ON ref_data.clock_captures FOR INSERT TO openetrm_security_owner WITH CHECK(true);
 source=pg_get_functiondef('security.reference_display_tables()'::regprocedure);
 IF strpos(source,'''clock_rules''')=0 THEN RAISE EXCEPTION 'clock_capture_upgrade';END IF;
 EXECUTE replace(source,'''clock_rules''','''clock_rules'',''clock_captures''');
END$$;
ALTER FUNCTION ref_data.captured_clock_boundary(jsonb,date) OWNER TO openetrm_security_owner;
ALTER FUNCTION ref_data.clock_boundary(uuid,uuid,text,date) OWNER TO openetrm_security_owner;
ALTER FUNCTION ref_data.guard_clock_capture() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION ref_data.captured_clock_boundary(jsonb,date),ref_data.clock_boundary(uuid,uuid,text,date),ref_data.guard_clock_capture() FROM PUBLIC;
COMMIT;
