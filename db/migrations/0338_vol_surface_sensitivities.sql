-- A fitted volatility surface states the option sensitivity selection its series' analytics were computed under, and that
-- selection is part of what a refit is compared against: the same inputs under another selection are a new revision, never a
-- nondeterministic refit. Surfaces fitted before analytics state none, so they are removed here and refitted; their fit
-- jobs stay as operational history. The Options page is a page whose guidance can be configured.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

ALTER TABLE trading.vol_surface_commands DISABLE TRIGGER immutable_record;
ALTER TABLE trading.vol_surface_inputs DISABLE TRIGGER immutable_record;
ALTER TABLE trading.vol_surface_revisions DISABLE TRIGGER immutable_record;
DELETE FROM trading.vol_surface_commands;
DELETE FROM trading.vol_surface_inputs;
DELETE FROM trading.vol_surface_revisions;
ALTER TABLE trading.vol_surface_revisions ENABLE TRIGGER immutable_record;
ALTER TABLE trading.vol_surface_inputs ENABLE TRIGGER immutable_record;
ALTER TABLE trading.vol_surface_commands ENABLE TRIGGER immutable_record;
ALTER TABLE trading.vol_surface_revisions ADD CONSTRAINT vol_surface_states_sensitivities CHECK(jsonb_typeof(content->'sensitivities')='object');

-- Each patch replaces the one occurrence of the text it expects, or stops: a function that no longer reads as expected is
-- not patched.
DO $upgrade$DECLARE body text;before text;BEGIN
 body=pg_get_functiondef('trading.record_vol_surface_revision(uuid,uuid,uuid,jsonb,date,text,text,uuid,uuid,timestamptz,uuid[],jsonb,text)'::regprocedure);
 before='OR jsonb_typeof(surface) IS DISTINCT FROM ''object'' OR pg_column_size(surface)>8000000';
 IF(length(body)-length(replace(body,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'vol_surface_sensitivities_drift: record input';END IF;
 body=replace(body,before,before||' OR jsonb_typeof(surface->''sensitivities'') IS DISTINCT FROM ''object''');
 before='AND r.close_id IS NOT DISTINCT FROM close AND r.valuation_at=record_vol_surface_revision.valuation_at AND r.definition_revision_id=definition';
 IF(length(body)-length(replace(body,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'vol_surface_sensitivities_drift: record identity';END IF;
 EXECUTE replace(body,before,before||' AND r.content->''sensitivities''=surface->''sensitivities''');

 body=pg_get_functiondef('risk.submit_vol_surface_fit(uuid,uuid,uuid,uuid,timestamptz,jsonb,jsonb)'::regprocedure);
 before='IS DISTINCT FROM ARRAY[''businessDate'',''convention'',''engineVersion'',''futuresConvention'',''model'',''product'',''solverPolicy'']';
 IF(length(body)-length(replace(body,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'vol_surface_sensitivities_drift: submit request';END IF;
 EXECUTE replace(body,before,'IS DISTINCT FROM ARRAY[''businessDate'',''convention'',''engineVersion'',''futuresConvention'',''model'',''product'',''sensitivities'',''solverPolicy'']'
  ||' OR jsonb_typeof(request->''sensitivities'') IS DISTINCT FROM ''object''');

 body=pg_get_functiondef('assistant.is_prompt_page(text)'::regprocedure);
 before='''vol_surfaces''';
 IF(length(body)-length(replace(body,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'vol_surface_sensitivities_drift: prompt pages';END IF;
 EXECUTE replace(body,before,before||',''options''');
END $upgrade$;
COMMIT;
