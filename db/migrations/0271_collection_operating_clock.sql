-- Collection coverage is the exact published contractual clock, including DST.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849110);
SELECT pg_advisory_xact_lock(730849102);
DO $guard$DECLARE helper pg_proc;BEGIN
 SELECT * INTO STRICT helper FROM pg_proc WHERE oid='power_data.begin_attempt(uuid,date,date)'::regprocedure;
 IF encode(sha256(convert_to(helper.prosrc,'UTF8')),'hex')<>'8afb17ff884a9e86a4c4d26ec23ce7b00bb7a7b6eeb4644770a219636f54e6e9' OR
  helper.proowner<>'openetrm_security_owner'::regrole OR NOT helper.prosecdef OR helper.provolatile<>'v' OR
  helper.proisstrict OR helper.proleakproof OR helper.proparallel<>'u' OR
  helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR
  (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x) IS DISTINCT FROM
   ARRAY['openetrm_collector=X/openetrm_security_owner','openetrm_security_owner=X/openetrm_security_owner']
 THEN RAISE EXCEPTION 'operating_clock_upgrade: unexpected helper power_data.begin_attempt(uuid,date,date)';END IF;
 SELECT * INTO STRICT helper FROM pg_proc WHERE oid='power_data.finish_attempt(uuid,jsonb,text)'::regprocedure;
 IF encode(sha256(convert_to(helper.prosrc,'UTF8')),'hex')<>'866de2a346ee1c36d8d58ce884623521a7c830f2dcca75b10631eb4c62860253' OR
  helper.proowner<>'openetrm_security_owner'::regrole OR NOT helper.prosecdef OR helper.provolatile<>'v' OR
  helper.proisstrict OR helper.proleakproof OR helper.proparallel<>'u' OR
  helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR
  (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x) IS DISTINCT FROM
   ARRAY['openetrm_collector=X/openetrm_security_owner','openetrm_security_owner=X/openetrm_security_owner']
 THEN RAISE EXCEPTION 'operating_clock_upgrade: unexpected helper power_data.finish_attempt(uuid,jsonb,text)';END IF;
END$guard$;
ALTER TABLE power_data.operating_days ADD CONSTRAINT operating_day_clock_capture
 FOREIGN KEY(reference_catalog_id,reference_revision_id,clock_code)
 REFERENCES ref_data.clock_captures(catalog_id,revision_id,clock_code) NOT VALID;
CREATE FUNCTION power_data.require_operating_day(day power_data.operating_days) RETURNS void
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE capture ref_data.clock_captures;
BEGIN
 SELECT c.* INTO capture FROM ref_data.clock_captures c JOIN ref_data.revisions r
  ON(r.catalog_id,r.id,r.state)=(c.catalog_id,c.revision_id,'sealed')
  WHERE(c.catalog_id,c.revision_id,c.clock_code)=(day.reference_catalog_id,day.reference_revision_id,day.clock_code);
 IF NOT FOUND OR day.operating_date<capture.coverage_from OR day.operating_date>=capture.coverage_to OR
  day.clock_fingerprint IS DISTINCT FROM encode(capture.definition_digest,'hex') THEN RAISE EXCEPTION 'collection_clock';END IF;
 IF day.starts_at IS DISTINCT FROM ref_data.captured_clock_boundary(capture.payload::jsonb,day.operating_date) OR
  day.ends_at IS DISTINCT FROM ref_data.captured_clock_boundary(capture.payload::jsonb,day.operating_date+1)
 THEN RAISE EXCEPTION 'collection_clock';END IF;
END$$;
CREATE FUNCTION power_data.guard_operating_day() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN PERFORM power_data.require_operating_day(NEW);RETURN NEW;END$$;
CREATE TRIGGER validate_clock BEFORE INSERT ON power_data.operating_days FOR EACH ROW EXECUTE FUNCTION power_data.guard_operating_day();
CREATE FUNCTION power_data.require_operating_days(job uuid,first_day date,last_day date) RETURNS void
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE day power_data.operating_days;actual integer=0;expected integer;
BEGIN
 SELECT count(*)*(last_day-first_day+1) INTO expected FROM power_data.job_sources WHERE job_id=job;
 FOR day IN SELECT d.* FROM power_data.job_sources m JOIN power_data.sources s ON s.id=m.source_id
  JOIN power_data.operating_days d ON(d.reference_catalog_id,d.reference_revision_id,d.clock_code)=(s.reference_catalog_id,s.reference_revision_id,s.clock_code)
  WHERE m.job_id=job AND d.operating_date BETWEEN first_day AND last_day LOOP
  PERFORM power_data.require_operating_day(day);actual=actual+1;
 END LOOP;
 IF expected IS NULL OR expected<=0 OR actual<>expected THEN RAISE EXCEPTION 'collection_calendar';END IF;
END$$;
-- Operator-only preparation. Repeat publication returns the original day and
-- refuses incompatible existing rows; it never rewrites retained intervals.
CREATE FUNCTION power_data.publish_operating_day(catalog uuid,revision uuid,clock_name text,day date) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE expected power_data.operating_days;existing power_data.operating_days;
BEGIN
 expected.reference_catalog_id=catalog;expected.reference_revision_id=revision;expected.clock_code=clock_name;expected.operating_date=day;
 expected.starts_at=ref_data.clock_boundary(catalog,revision,clock_name,day);
 expected.ends_at=ref_data.clock_boundary(catalog,revision,clock_name,day+1);
 SELECT encode(definition_digest,'hex') INTO expected.clock_fingerprint FROM ref_data.clock_captures
  WHERE(catalog_id,revision_id,clock_code)=(catalog,revision,clock_name);
 PERFORM power_data.require_operating_day(expected);
 INSERT INTO power_data.operating_days SELECT expected.* ON CONFLICT DO NOTHING;
 SELECT * INTO STRICT existing FROM power_data.operating_days
  WHERE(reference_catalog_id,reference_revision_id,clock_code,operating_date)=(catalog,revision,clock_name,day);
 IF existing IS DISTINCT FROM expected THEN RAISE EXCEPTION 'collection_clock';END IF;
END$$;
ALTER FUNCTION power_data.require_operating_day(power_data.operating_days) OWNER TO openetrm_security_owner;
ALTER FUNCTION power_data.guard_operating_day() OWNER TO openetrm_security_owner;
ALTER FUNCTION power_data.require_operating_days(uuid,date,date) OWNER TO openetrm_security_owner;
ALTER FUNCTION power_data.publish_operating_day(uuid,uuid,text,date) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION power_data.require_operating_day(power_data.operating_days),power_data.guard_operating_day(),
 power_data.require_operating_days(uuid,date,date),power_data.publish_operating_day(uuid,uuid,text,date) FROM PUBLIC;
DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('power_data.begin_attempt(uuid,date,date)'::regprocedure);
 marker=' UPDATE power_data.attempts SET state=';
 EXECUTE replace(source,marker,' PERFORM power_data.require_operating_days(job,first_day,last_day);'||marker);
 source=pg_get_functiondef('power_data.finish_attempt(uuid,jsonb,text)'::regprocedure);
 marker=' IF payload IS NULL';
 EXECUTE replace(source,marker,' PERFORM power_data.require_operating_days(job.id,attempt.from_date,attempt.through_date);'||marker);
END$$;
COMMIT;
