-- Verify each exact retained calendar publication once per visibility check.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.market_access(uuid,text)","definition":"804fc62e6057b1b2d528e3493d761aa52d613a766a9087c90fcd6313b5832383","volatility":"v"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.reference_access(uuid,text)","definition":"697d1e75ddba8a9a7fbdfa948951d3c6760e445f6f681ba307c1c937568c0828","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_calendar_cutoff(uuid,uuid)","definition":"c367ed8cd6dc681f90f37899648188b3d77a273855d10d5df0a4d3b425885bee","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_calendar_proofs_visible(uuid,uuid,uuid)","definition":"1ac5d76ef39132f98b83fc496a7b4c59dad4d73efd29479b41803becc635edbc","volatility":"v"}]
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

CREATE OR REPLACE FUNCTION security.side_calendar_proofs_visible(catalog uuid,schedule uuid,context uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE proof record;cutoff timestamptz;cutoff_resolved boolean=false;
BEGIN
 FOR proof IN SELECT DISTINCT b.source_catalog_id,b.source_event_order,b.reference_catalog_id,b.reference_revision_id
  FROM trading.side_schedules h JOIN trading.side_calendar_bindings b ON(b.catalog_id,b.side_id)=(h.catalog_id,h.side_id)
  WHERE(h.catalog_id,h.id)=(catalog,schedule) AND b.applicable
 LOOP
  IF NOT cutoff_resolved THEN
   cutoff=security.side_calendar_cutoff(catalog,context);cutoff_resolved=true;
  END IF;
  -- Read the immutable proof before checking live authority: a relation lock
  -- must not carry an earlier authorization decision past its expiry.
  IF NOT EXISTS(SELECT 1 FROM market_data.knowledge_events e
   JOIN market_data.market_knowledge_receipts k ON(k.catalog_id,k.event_order,k.publication_xid)=(e.catalog_id,e.event_order,e.publication_xid)
   JOIN market_data.revisions r ON(r.catalog_id,r.id)=(e.catalog_id,e.revision_id)
   JOIN ref_data.revisions rr ON(rr.catalog_id,rr.id)=(r.reference_catalog_id,r.reference_revision_id)
   WHERE(e.catalog_id,e.event_order)=(proof.source_catalog_id,proof.source_event_order) AND e.observation_id IS NULL
    AND(r.reference_catalog_id,r.reference_revision_id,r.state,rr.state)=(proof.reference_catalog_id,proof.reference_revision_id,'sealed','sealed')
    AND k.known_from<=cutoff) THEN RETURN false;END IF;
  IF security.reference_access(proof.reference_catalog_id,'ReadMarketData') IS NOT TRUE
   OR security.market_access(proof.source_catalog_id,'ReadMarketData') IS NOT TRUE THEN RETURN false;END IF;
 END LOOP;
 RETURN true;
END$$;
COMMIT;
