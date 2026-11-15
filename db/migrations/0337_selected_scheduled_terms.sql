-- Scope scheduled terms to the exact trade revision before aggregating Sides.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_risk_worker=X/@migration_owner","openetrm_runtime=X/@migration_owner","openetrm_security_owner=X/@migration_owner","@migration_owner=X/@migration_owner"],"owner":"@migration_owner","config":["search_path=pg_catalog","join_collapse_limit=8"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.scheduled_swap_terms(uuid,uuid,integer,uuid)","definition":"37a70e6c3465cc2bbcd73e8b61751e6ecbf5a2c2b76d494e2eb28d823769d736","volatility":"s"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.side_calendar_policy_document(uuid,uuid)","definition":"468af4999ed99cbedec32957bcf2e029dda5f6a09698778a6be666049e02f993","volatility":"s"}]
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

DO $calendar_views$DECLARE expected jsonb;view_row pg_class;actual_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($view_contracts$
[{"acl":["openetrm_risk_worker=r/openetrm_security_owner","openetrm_runtime=r/openetrm_security_owner","openetrm_security_owner=arwdDxt/openetrm_security_owner"],"kind":"v","name":"trading.swap_period_input_projection","owner":"openetrm_security_owner","options":["security_invoker=true"],"definition":"f0b839088f160bd9089b2fa01d5946111e58a54f7b1beacb63cbf3be6588bee5"},{"acl":["openetrm_risk_worker=r/openetrm_security_owner","openetrm_runtime=r/openetrm_security_owner","openetrm_security_owner=arwdDxt/openetrm_security_owner"],"kind":"v","name":"trading.scheduled_swap_term_projection","owner":"openetrm_security_owner","options":["security_invoker=true"],"definition":"31401d37e38471681cccc0de021cb2232dcdb3f764429801b11f40577dc307c8"}]
$view_contracts$::jsonb) LOOP
  SELECT * INTO view_row FROM pg_class WHERE oid=to_regclass(expected->>'name');
  SELECT jsonb_agg(x::text ORDER BY x::text) INTO actual_acl FROM unnest(coalesce(view_row.relacl,acldefault('r',view_row.relowner))) x;
  IF view_row.oid IS NULL OR view_row.relkind<>'v' OR view_row.relpersistence<>'p' OR view_row.relhastriggers
   OR pg_get_userbyid(view_row.relowner) IS DISTINCT FROM expected->>'owner'
   OR to_jsonb(view_row.reloptions) IS DISTINCT FROM expected->'options' OR actual_acl IS DISTINCT FROM expected->'acl'
   OR encode(sha256(convert_to(pg_get_viewdef(view_row.oid),'UTF8')),'hex') IS DISTINCT FROM expected->>'definition'
   OR EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=view_row.oid AND a.attacl IS NOT NULL)
   OR(SELECT count(*) FROM pg_rewrite r WHERE r.ev_class=view_row.oid)<>1
   OR NOT EXISTS(SELECT 1 FROM pg_rewrite r WHERE r.ev_class=view_row.oid AND r.rulename='_RETURN' AND r.ev_type='1' AND r.is_instead AND r.ev_enabled='O')
  THEN RAISE EXCEPTION 'calendar_contract_upgrade: unexpected helper %',expected->>'name';END IF;
 END LOOP;
END$calendar_views$;

-- The invoker view remains the query contract. Compile its exact selected form
-- with the key inside slots: row-security expressions prevent the planner from
-- consistently pushing an outer filter through its grouped CTEs.
DO $$DECLARE source text;projection text;marker text='WHERE (i.scheduled_first_id IS NOT NULL)';original text;
BEGIN
 projection=pg_get_viewdef('trading.scheduled_swap_term_projection'::regclass);
 IF(length(projection)-length(replace(projection,marker,'')))/length(marker)<>1
 THEN RAISE EXCEPTION 'calendar_contract_upgrade: scheduled selection marker';END IF;
 projection=replace(projection,marker,marker||' AND (r.catalog_id,r.trade_id,r.revision,r.instrument_id)=($1,$2,$3,$4)');
 source=pg_get_functiondef('trading.scheduled_swap_terms(uuid,uuid,integer,uuid)'::regprocedure);
 original=$before$
 SELECT p.scheduled_data FROM trading.scheduled_swap_term_projection p
 WHERE(p.catalog_id,p.trade_id,p.revision,p.instrument_id)=(catalog,trade,revision_number,instrument)
$before$;
 IF strpos(source,original)=0 THEN RAISE EXCEPTION 'calendar_contract_upgrade: scheduled reader body';END IF;
 -- Preserve the view's current table/column SELECT authority without rendering
 -- unrelated rows. The final statement retains all invoker base/child policies.
 EXECUTE replace(source,original,E'
 SELECT p.catalog_id,p.trade_id,p.revision,p.instrument_id,p.scheduled_data FROM trading.scheduled_swap_term_projection p LIMIT 0;
 SELECT exact.scheduled_data FROM ('||rtrim(projection,E';\n ')||E') exact;
');
END$$;
COMMIT;
