-- Publication certification has no financial effective date. Exact calendar
-- authoring and ordinary context capture share the same commit proof.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);
DO $guard$DECLARE helper pg_proc;BEGIN
 SELECT * INTO STRICT helper FROM pg_proc WHERE oid='security.capture_market_and_schedule_context(uuid,date,timestamptz)'::regprocedure;
 IF encode(sha256(convert_to(helper.prosrc,'UTF8')),'hex')<>'8313b637237d690c196e71f8b47f732e36a5a30f19a720ed29846778d735d56f' OR
  helper.proowner<>'openetrm_security_owner'::regrole OR NOT helper.prosecdef OR helper.provolatile<>'v' OR
  helper.proisstrict OR helper.proleakproof OR helper.proparallel<>'u' OR
  helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR
  (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x) IS DISTINCT FROM
   ARRAY['openetrm_security_owner=X/openetrm_security_owner']
 THEN RAISE EXCEPTION 'calendar_certification_upgrade: unexpected helper security.capture_market_and_schedule_context(uuid,date,timestamptz)';END IF;
 SELECT * INTO STRICT helper FROM pg_proc WHERE oid='security.resolve_side_calendar(uuid,uuid,text,jsonb)'::regprocedure;
 IF encode(sha256(convert_to(helper.prosrc,'UTF8')),'hex')<>'4bc485cee68989072042e6284eee36c65feba5bcc6cdda82fd456addb1446a78' OR
  helper.proowner<>'openetrm_security_owner'::regrole OR NOT helper.prosecdef OR helper.provolatile<>'v' OR
  helper.proisstrict OR helper.proleakproof OR helper.proparallel<>'u' OR
  helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR
  (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x) IS DISTINCT FROM ARRAY['openetrm_security_owner=X/openetrm_security_owner']
 THEN RAISE EXCEPTION 'calendar_certification_upgrade: unexpected helper security.resolve_side_calendar(uuid,uuid,text,jsonb)';END IF;
 SELECT * INTO STRICT helper FROM pg_proc WHERE oid='security.list_side_calendars()'::regprocedure;
 IF encode(sha256(convert_to(helper.prosrc,'UTF8')),'hex')<>'72870d3ed968e65bfd97eabb171a0198439ac7f53bcfb4211b841142e74a159a' OR
  helper.proowner<>'openetrm_security_owner'::regrole OR NOT helper.prosecdef OR helper.provolatile<>'v' OR
  helper.proisstrict OR helper.proleakproof OR helper.proparallel<>'u' OR
  helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR
  (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x) IS DISTINCT FROM ARRAY['openetrm_runtime=X/openetrm_security_owner','openetrm_security_owner=X/openetrm_security_owner']
 THEN RAISE EXCEPTION 'calendar_certification_upgrade: unexpected helper security.list_side_calendars()';END IF;
END$guard$;

CREATE FUNCTION security.certify_market_publications(catalog uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE clock market_data.knowledge_clocks;event record;commit_at timestamptz;last_commit timestamptz;captured_at timestamptz;
BEGIN
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'No current temporal read permission' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT * INTO clock FROM market_data.knowledge_clocks WHERE catalog_id=catalog FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'knowledge_coverage';END IF;
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'Temporal authority expired during admission' USING ERRCODE='42501';END IF;
 IF current_setting('track_commit_timestamp')<>'on' THEN RAISE EXCEPTION 'knowledge_tracking';END IF;
 IF pg_is_in_recovery() OR clock.system_identifier IS DISTINCT FROM(pg_control_system()).system_identifier::text OR
  clock.timeline_id IS DISTINCT FROM(pg_control_checkpoint()).timeline_id THEN RAISE EXCEPTION 'knowledge_timeline';END IF;
 -- Validate retention without initializing only one half of the shared clock.
 IF clock.coverage_from IS NULL THEN clock.coverage_from=security.checked_commit_time(clock.origin_xid);END IF;
 SELECT known_from INTO last_commit FROM market_data.market_knowledge_receipts WHERE catalog_id=catalog ORDER BY event_order DESC LIMIT 1;
 last_commit=coalesce(last_commit,clock.coverage_from);
 FOR event IN SELECT * FROM market_data.knowledge_events WHERE catalog_id=catalog AND event_order>clock.market_certified_head ORDER BY event_order LOOP
  IF event.event_order<>clock.market_certified_head+1 THEN RAISE EXCEPTION 'knowledge_coverage';END IF;
  commit_at=security.checked_commit_time(event.publication_xid);
  IF commit_at<last_commit OR(clock.certified_through IS NOT NULL AND commit_at<=clock.certified_through) THEN RAISE EXCEPTION 'knowledge_clock';END IF;
  INSERT INTO market_data.market_knowledge_receipts VALUES(catalog,event.event_order,event.publication_xid,commit_at);
  clock.market_certified_head=event.event_order;last_commit=commit_at;
 END LOOP;
 captured_at=clock_timestamp();
 IF captured_at<last_commit OR(clock.certified_through IS NOT NULL AND captured_at<clock.certified_through) THEN RAISE EXCEPTION 'knowledge_clock';END IF;
 IF NOT isfinite(captured_at) OR captured_at>=TIMESTAMPTZ '9999-12-31 00:00:00+00' THEN RAISE EXCEPTION 'knowledge_coverage';END IF;
 UPDATE market_data.knowledge_clocks SET market_certified_head=clock.market_certified_head WHERE catalog_id=catalog;
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'Temporal authority expired during certification' USING ERRCODE='42501';END IF;
END$$;
CREATE OR REPLACE FUNCTION security.capture_market_and_schedule_context(catalog uuid,effective_date date,requested_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE token uuid;cutoff timestamptz;head integer;last_commit timestamptz;
BEGIN
 PERFORM security.certify_market_publications(catalog);
 token=security.capture_schedule_context(catalog,effective_date,requested_at);
 SELECT known_at INTO cutoff FROM market_data.temporal_contexts WHERE catalog_id=catalog AND id=token;
 SELECT known_from INTO last_commit FROM market_data.market_knowledge_receipts WHERE catalog_id=catalog ORDER BY event_order DESC LIMIT 1;
 IF last_commit>(SELECT certified_through FROM market_data.knowledge_clocks WHERE catalog_id=catalog) THEN RAISE EXCEPTION 'knowledge_clock';END IF;
 SELECT coalesce(max(event_order),0) INTO head FROM market_data.market_knowledge_receipts WHERE catalog_id=catalog AND known_from<=cutoff;
 INSERT INTO market_data.market_contexts VALUES(catalog,token,head) ON CONFLICT DO NOTHING;
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'Temporal authority expired during certification' USING ERRCODE='42501';END IF;
 RETURN token;
END$$;
CREATE FUNCTION security.certify_calendar_sources(reference_catalog uuid,reference_revision uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE source uuid;
BEGIN
 -- Certification records committed publication facts without changing the
 -- caller's resolved knowledge cutoff. This includes cold independent catalogs.
 IF(reference_catalog IS NULL)<>(reference_revision IS NULL) THEN RAISE EXCEPTION 'calendar_reference';END IF;
 FOR source IN SELECT DISTINCT r.catalog_id FROM market_data.revisions r
  WHERE r.state='sealed' AND(reference_catalog IS NULL OR(r.reference_catalog_id,r.reference_revision_id)=(reference_catalog,reference_revision))
   AND NOT EXISTS(SELECT 1 FROM market_data.knowledge_events e JOIN market_data.market_knowledge_receipts k
    ON(k.catalog_id,k.event_order,k.publication_xid)=(e.catalog_id,e.event_order,e.publication_xid)
    WHERE(e.catalog_id,e.revision_id)=(r.catalog_id,r.id) AND e.observation_id IS NULL)
   AND security.reference_access(r.reference_catalog_id,'ReadMarketData') AND security.market_access(r.catalog_id,'ReadMarketData')
  ORDER BY r.catalog_id LOOP
  PERFORM security.certify_market_publications(source);
 END LOOP;
END$$;
ALTER FUNCTION security.certify_market_publications(uuid) OWNER TO openetrm_security_owner;
ALTER FUNCTION security.certify_calendar_sources(uuid,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.certify_market_publications(uuid),security.certify_calendar_sources(uuid,uuid) FROM PUBLIC;
DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('security.resolve_side_calendar(uuid,uuid,text,jsonb)'::regprocedure);
 marker=' SELECT e.catalog_id,e.event_order,k.known_from INTO source';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'calendar_certification_upgrade';END IF;
 EXECUTE replace(source,marker,' IF pinned IS NULL THEN PERFORM security.certify_calendar_sources(catalog,revision);END IF;'||marker);
 source=pg_get_functiondef('security.list_side_calendars()'::regprocedure);
 marker=' FOR selected IN SELECT';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'calendar_certification_upgrade';END IF;
 EXECUTE replace(source,marker,' PERFORM security.certify_calendar_sources(NULL,NULL);'||marker);
END$$;
COMMIT;
