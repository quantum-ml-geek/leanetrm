-- Native publication and period preparation share the Side-owned observation binding.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])","definition":"6986e06f9912f1ee325cee5e7a8f916d404ba67fe9f71d6fb729a118194f5857","volatility":"v"},{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamp with time zone,timestamp with time zone,text,text,text,jsonb,uuid[])","definition":"a445448948e0e2a75fb83bc04ce847741b2b23947113a4556f1be468e67ba9e0","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_policy_calendar(jsonb,text)","definition":"e3cfd85b8166be071c631573997564b804df8dd62615f651efb8bf78f7522da7","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.swap_observation_sampling(text,text)","definition":"fa9d08014e189e204d090792ed65715caa8008d32b0432097ceb16fa4c4470df","volatility":"i"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.market_access(uuid,text)","definition":"804fc62e6057b1b2d528e3493d761aa52d613a766a9087c90fcd6313b5832383","volatility":"v"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.reference_access(uuid,text)","definition":"697d1e75ddba8a9a7fbdfa948951d3c6760e445f6f681ba307c1c937568c0828","volatility":"v"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","plan_cache_mode=force_generic_plan"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.market_fact_visible(uuid,uuid,uuid)","definition":"2681ef478a2a067b6859826f2cc1a93a3faea813d0180a7b4a12e6f6471e96ae","volatility":"v"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","plan_cache_mode=force_generic_plan"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.reference_version_visible(uuid,uuid)","definition":"1618ae8b3f399f0489e6cee8b496228ab327e17333526c6bea9ba61c3f0486bc","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_calendar_proofs_visible(uuid,uuid,uuid)","definition":"1ac5d76ef39132f98b83fc496a7b4c59dad4d73efd29479b41803becc635edbc","volatility":"v"}]
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

CREATE FUNCTION security.side_observation_rule(body jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE schedule jsonb=nullif(body->'observationSchedule','null'::jsonb);
BEGIN
 IF schedule IS NULL THEN RETURN NULL;END IF;
 IF schedule->'calendar' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'side_calendar_conflict';END IF;
 IF security.swap_observation_sampling(body->>'resetFrequency',body->>'averagingMethod')<>'quantity_weighted'
 THEN schedule=jsonb_set(schedule,'{calendar}',security.side_policy_calendar(body->'calendarPolicy','observation'));END IF;
 RETURN schedule;
END$$;
ALTER FUNCTION security.side_observation_rule(jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.side_observation_rule(jsonb) FROM PUBLIC;

-- A committed outcome is read under current authority. It does not regenerate
-- schedules or impose new authoring requirements on its immutable request.
CREATE FUNCTION security.require_swap_receipt_authority(catalog uuid,instrument uuid,definition uuid,ref_catalog uuid,ref_revision uuid) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NOT security.market_access(catalog,'ReadMarketData') OR NOT security.reference_access(ref_catalog,'ReadMarketData')
  OR NOT security.market_fact_visible(catalog,definition,NULL) OR NOT security.reference_version_visible(ref_catalog,ref_revision)
 THEN RAISE EXCEPTION 'No current swap receipt reference access' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM trading.instrument_side_schedules m
  WHERE(m.catalog_id,m.instrument_id)=(catalog,instrument) AND NOT security.side_calendar_proofs_visible(catalog,m.schedule_id,NULL))
 THEN RAISE EXCEPTION 'No current swap receipt calendar access' USING ERRCODE='42501';END IF;
END$$;
ALTER FUNCTION security.require_swap_receipt_authority(uuid,uuid,uuid,uuid,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.require_swap_receipt_authority(uuid,uuid,uuid,uuid,uuid) FROM PUBLIC;

DO $$DECLARE source text;marker text;side text;receipt text;BEGIN
 source=pg_get_functiondef('security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[])'::regprocedure);
 marker=$old$observation_schedule=NULLIF(body->'observationSchedule','null'::jsonb);
 IF observation_schedule IS NOT NULL THEN
  IF observation_schedule->'calendar' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'side_calendar_conflict';END IF;
  IF sampling<>'quantity_weighted' THEN
   observation_schedule=jsonb_set(observation_schedule,'{calendar}',security.side_policy_calendar(body->'calendarPolicy','observation'));
  END IF;
 END IF;
 $old$;
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_observation_rule_upgrade';END IF;
 EXECUTE replace(source,marker,'observation_schedule=security.side_observation_rule(body);');
 source=pg_get_functiondef('security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamptz,timestamptz,text,text,text,jsonb,uuid[])'::regprocedure);
 -- Remove only the committed branch's observation regeneration. Current
 -- reference and retained calendar-source permissions remain mandatory.
 receipt=substring(source FROM strpos(source,' IF FOUND THEN') FOR strpos(source,'  RETURN security.swap_operation_status(catalog,operation);')-strpos(source,' IF FOUND THEN'));
 FOREACH side IN ARRAY ARRAY['first_body','float_body'] LOOP
  marker=' IF NULLIF('||side||'->''observationSchedule'',''null''::jsonb) IS NOT NULL THEN'||E'\n'||
   '  PERFORM security.swap_observation_rows(catalog,definition,ref_catalog,ref_revision,'||side||'->>''curve'','||side||'->>''index'','||E'\n'||
   '   ('||side||'->>''deliveryFrom'')::date,('||side||'->>''deliveryTo'')::date,security.swap_observation_sampling('||side||'->>''resetFrequency'','||side||'->>''averagingMethod''),'||side||'->''observationSchedule'');'||E'\n END IF;';
  IF strpos(receipt,marker)=0 THEN RAISE EXCEPTION 'side_observation_receipt_upgrade';END IF;
  source=overlay(source PLACING replace(receipt,marker,'') FROM strpos(source,receipt) FOR length(receipt));
  receipt=replace(receipt,marker,'');
 END LOOP;
 marker='  RETURN security.swap_operation_status(catalog,operation);';
 source=replace(source,marker,'  PERFORM security.require_swap_receipt_authority(catalog,prior.instrument_id,definition,ref_catalog,ref_revision);'||E'\n'||marker);
 -- New admission resolves the Side-owned observation calendar.
 FOREACH side IN ARRAY ARRAY['first_body','float_body'] LOOP
  marker=side||'->''observationSchedule'');';
  IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_observation_rule_upgrade';END IF;
  source=replace(source,marker,'security.side_observation_rule('||side||'));');
 END LOOP;
 EXECUTE source;
END$$;
COMMIT;
