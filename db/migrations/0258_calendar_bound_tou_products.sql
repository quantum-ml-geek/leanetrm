-- New authored TOU versions own their calendar. Existing published versions stay
-- immutable and inspectable; no calendar is guessed for an existing version.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849104);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"market_data.guard_tou_product_version()","definition":"768e84a2ca013568470dd1e58e81f9e7b72ccd83db277e86e780523e37e4e3b2","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.publish_tou_product(uuid,uuid,integer,integer)","definition":"a25c59a62b55f1580b7f12e0b0235708d6f5eb5f57d18c7df30c9458deb593e7","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.read_side_calendar(uuid,uuid,text)","definition":"7e96eb0f7eb70d7c0e42e082a181cd0a847114131350e7056462a3d88d3c7a84","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.reference_access(uuid,text)","definition":"697d1e75ddba8a9a7fbdfa948951d3c6760e445f6f681ba307c1c937568c0828","volatility":"v"}]
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



ALTER TABLE market_data.tou_product_versions
 ADD COLUMN calendar_catalog_id uuid,
 ADD COLUMN calendar_revision_id uuid,
 ADD COLUMN calendar_code ref_data.code,
 ADD COLUMN holiday_treatment text,
 ADD CONSTRAINT tou_calendar_reference FOREIGN KEY(calendar_catalog_id,calendar_revision_id,calendar_code)
  REFERENCES ref_data.calendars(catalog_id,revision_id,code) MATCH FULL,
 ADD CONSTRAINT tou_calendar_contract CHECK(calendar_catalog_id IS NOT NULL AND calendar_revision_id IS NOT NULL
  AND calendar_code IS NOT NULL AND holiday_treatment IS NOT DISTINCT FROM 'weekly_mask_explicit_closures_v1') NOT VALID;
GRANT UPDATE(calendar_catalog_id,calendar_revision_id,calendar_code,holiday_treatment)
 ON market_data.tou_product_versions TO openetrm_runtime;

DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('market_data.guard_tou_product_version()'::regprocedure);
 marker=' RETURN NEW;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'tou_calendar_upgrade';END IF;
 source=replace(source,marker,$patch$
 IF NEW.calendar_catalog_id IS NULL OR NEW.calendar_revision_id IS NULL OR NEW.calendar_code IS NULL
  OR NEW.holiday_treatment IS DISTINCT FROM 'weekly_mask_explicit_closures_v1'
  OR NOT EXISTS(SELECT 1 FROM ref_data.revisions r WHERE(r.catalog_id,r.id,r.state)=
   (NEW.calendar_catalog_id,NEW.calendar_revision_id,'sealed'))
 THEN RAISE EXCEPTION 'tou_calendar_contract' USING ERRCODE='23514';END IF;
 RETURN NEW;$patch$);
 EXECUTE source;
 source=pg_get_functiondef('security.publish_tou_product(uuid,uuid,integer,integer)'::regprocedure);
 marker='IF row.state=''published'' THEN RETURN row.publication_order; END IF;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'tou_calendar_upgrade';END IF;
 -- Committed publication retries return their original result before new
 -- authoring requirements, under the function's existing current authority.
 source=replace(source,marker,marker||$patch$
 IF row.holiday_treatment IS DISTINCT FROM 'weekly_mask_explicit_closures_v1' THEN RAISE EXCEPTION 'tou_calendar_contract';END IF;
 PERFORM security.read_side_calendar(row.calendar_catalog_id,row.calendar_revision_id,row.calendar_code);
 $patch$);
 EXECUTE source;
END$$;
CREATE POLICY calendar_insert ON market_data.tou_product_versions AS RESTRICTIVE FOR INSERT TO openetrm_runtime
 WITH CHECK(security.reference_access(calendar_catalog_id,'ReadMarketData'));
CREATE POLICY calendar_update ON market_data.tou_product_versions AS RESTRICTIVE FOR UPDATE TO openetrm_runtime
 USING(security.reference_access(calendar_catalog_id,'ReadMarketData'))
 WITH CHECK(security.reference_access(calendar_catalog_id,'ReadMarketData'));
COMMIT;
