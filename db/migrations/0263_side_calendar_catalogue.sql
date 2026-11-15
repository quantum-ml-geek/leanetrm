-- Side authoring discovers exact published calendar versions under the same
-- narrow authority and knowledge policy used to capture a selected binding.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.market_access(uuid,text)","definition":"804fc62e6057b1b2d528e3493d761aa52d613a766a9087c90fcd6313b5832383","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.read_side_calendar(uuid,uuid,text)","definition":"7e96eb0f7eb70d7c0e42e082a181cd0a847114131350e7056462a3d88d3c7a84","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.reference_access(uuid,text)","definition":"697d1e75ddba8a9a7fbdfa948951d3c6760e445f6f681ba307c1c937568c0828","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_calendar_cutoff(uuid,uuid)","definition":"c367ed8cd6dc681f90f37899648188b3d77a273855d10d5df0a4d3b425885bee","volatility":"v"}]
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



CREATE FUNCTION security.list_side_calendars() RETURNS SETOF jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE selected record;cutoff timestamptz=security.side_calendar_cutoff(NULL,NULL);
BEGIN
 IF pg_has_role(session_user,'openetrm_risk_worker','MEMBER') AND NOT risk.worker_read()
 THEN RAISE EXCEPTION 'calendar_reference';END IF;
 FOR selected IN SELECT c.catalog_id,c.revision_id,c.code FROM ref_data.calendars c
  JOIN ref_data.revisions r ON(r.catalog_id,r.id)=(c.catalog_id,c.revision_id)
  WHERE r.state='sealed' ORDER BY c.catalog_id,c.revision_id,c.code LOOP
  IF security.reference_access(selected.catalog_id,'ReadMarketData') AND EXISTS(
   SELECT 1 FROM market_data.revisions r
   JOIN market_data.knowledge_events e ON(e.catalog_id,e.revision_id)=(r.catalog_id,r.id) AND e.observation_id IS NULL
   JOIN market_data.market_knowledge_receipts k ON(k.catalog_id,k.event_order,k.publication_xid)=(e.catalog_id,e.event_order,e.publication_xid)
   WHERE(r.reference_catalog_id,r.reference_revision_id,r.state)=(selected.catalog_id,selected.revision_id,'sealed')
    AND k.known_from<=cutoff AND security.market_access(r.catalog_id,'ReadMarketData'))
  THEN RETURN NEXT security.read_side_calendar(selected.catalog_id,selected.revision_id,selected.code);END IF;
 END LOOP;
END$$;
ALTER FUNCTION security.list_side_calendars() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.list_side_calendars() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.list_side_calendars() TO openetrm_runtime;
COMMIT;
