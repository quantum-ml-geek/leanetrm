-- The collection job's existing authority supplies the exact published clock.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);
ALTER TABLE market_data.tou_product_versions ADD CONSTRAINT tou_published_clock_capture
 FOREIGN KEY(clock_catalog_id,clock_revision_id,clock_code)
 REFERENCES ref_data.clock_captures(catalog_id,revision_id,clock_code) NOT VALID;
DO $guard$DECLARE helper pg_proc;BEGIN
 SELECT * INTO STRICT helper FROM pg_proc WHERE oid='power_data.source_config(uuid)'::regprocedure;
 IF encode(sha256(convert_to(helper.prosrc,'UTF8')),'hex')<>'bb8052473f7257a289d04fb52c7fe82841f7caf3ab7167590743d2fe323a6955' OR
  helper.proowner<>'openetrm_security_owner'::regrole OR NOT helper.prosecdef OR helper.provolatile<>'v' OR
  helper.proisstrict OR helper.proleakproof OR helper.proparallel<>'u' OR
  helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR
  (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x) IS DISTINCT FROM
   ARRAY['openetrm_collector=X/openetrm_security_owner','openetrm_security_owner=X/openetrm_security_owner']
 THEN RAISE EXCEPTION 'published_clock_consumer_upgrade: unexpected helper power_data.source_config(uuid)';END IF;
END$guard$;
CREATE OR REPLACE FUNCTION power_data.source_config(job uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE catalog uuid;result jsonb;
BEGIN
 catalog=power_data.worker_catalog();
 SELECT jsonb_agg(to_jsonb(s)||jsonb_build_object('clock',to_jsonb(c),'clockCapture',to_jsonb(capture))) INTO result
 FROM power_data.jobs j JOIN power_data.job_sources m ON m.job_id=j.id JOIN power_data.sources s ON s.id=m.source_id
 JOIN ref_data.clock_rules c ON(c.catalog_id,c.revision_id,c.code)=(s.reference_catalog_id,s.reference_revision_id,s.clock_code)
 JOIN ref_data.clock_captures capture ON(capture.catalog_id,capture.revision_id,capture.clock_code)=(c.catalog_id,c.revision_id,c.code)
 JOIN ref_data.revisions revision ON(revision.catalog_id,revision.id,revision.state)=(c.catalog_id,c.revision_id,'sealed')
 JOIN power_data.collectors actor ON actor.login=session_user
 JOIN security.reference_catalog_scopes scope ON(scope.catalog_id,scope.tenant_id,scope.workspace_id)=(s.reference_catalog_id,actor.tenant_id,actor.workspace_id)
 WHERE j.id=job AND j.catalog_id=catalog AND j.collector_login=session_user AND j.enabled
 AND security.principal_has_permission(actor.principal_id,actor.tenant_id,actor.workspace_id,'ReadMarketData',clock_timestamp());
 IF result IS NULL OR jsonb_array_length(result)<>(SELECT count(*) FROM power_data.job_sources WHERE job_id=job) THEN RAISE EXCEPTION 'collection_reference_scope' USING ERRCODE='42501';END IF;
 RETURN result;
END$$;
COMMIT;
