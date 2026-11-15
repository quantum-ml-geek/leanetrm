-- Native swap admission consumes the same Side-owned calendar references as the
-- managed generator. New financial Side IDs name their staged canonical Side;
-- previous rows, identities and committed request outcomes are unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"s","leakproof":false,"signature":"security.ppa_schedule_document(jsonb,jsonb)","definition":"a1e77e9f061a5b4fac78911ab1f2c7ccf34bed9c095bc958a1fd40a79d7ffda4","volatility":"i"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.ppa_side_document(uuid,uuid)","definition":"71bd17195f7e5029ea1acb4f3f01aabca4f11bb3d3b0fbd3b209e33798af5402","volatility":"s"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.ppa_terms_document(uuid,uuid)","definition":"cfab06993640402a652b3fc101d9cb9ab0c7ed81501f419b230d0212ca5db26c","volatility":"s"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,jsonb,uuid[])","definition":"55802b0b81af883f07a74635513cd1d608eaa05ebf533f075b9d049dfe9132c4","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)","definition":"4c15b8eb91aab08ad270e3c809a45f22111a950c8c30b317df4bed182f681022","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])","definition":"a5cbc0aeb406b075ec212a255a3f6a16eba856354b5cce8f1f356a4c961a1cbc","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.read_side_calendar(uuid,uuid,text)","definition":"7e96eb0f7eb70d7c0e42e082a181cd0a847114131350e7056462a3d88d3c7a84","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)","definition":"bbd2f7fd8153115583fd761453693919f035f6f8a82897d877d2100370e8651c","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])","definition":"7ffbcb2521b9d8fc6906315b5ed7a4a4c4372b7bf9d0c733a76899f46ce671e6","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.retain_ppa_terms(uuid,jsonb,integer,timestamp with time zone)","definition":"a7d6d33550b108b43230e957048be692a55ea6babc28fe80b51f21087271d6f6","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.retain_swap_observation_schedule(uuid,uuid,uuid,uuid,text,text,ref_data.quote_specifications,date,date,text,jsonb,jsonb,integer,timestamp with time zone)","definition":"4275ad6f16ebd8be393bbf06bf0232e708e462a3d1a3294ec1dd8aa98d9e97c7","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.retain_swap_payment_rule(uuid,uuid,uuid,jsonb,integer,timestamp with time zone)","definition":"65e0edd9088a11d5ff4a4e8a3fe5da96ba10ce384c85dae6d73d4ecb5451b2c4","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamp with time zone,timestamp with time zone,text,text,text,jsonb,uuid[])","definition":"275b907de73db56d7e447e7e404ae896449561238c9132530821544795ea3cfb","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_ppa_booking(uuid,uuid,jsonb)","definition":"296bd0630efb9445a5070f899ece80cde1d0ed16ed878415def0f8c1b18016cc","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamp with time zone,jsonb,uuid[])","definition":"b175916954422743c0dd739661beb1b4430048bbb9bd620708bfd81092375069","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_schedule_request_authority(uuid,uuid)","definition":"e4700244f2b0b99268195fd2832900a8be269ce8ed7d09ad6b3f036a36ed1033","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.swap_observation_rows(uuid,uuid,uuid,uuid,text,text,date,date,text,jsonb)","definition":"82ebaca7c363c73cbb69c63b577491ee097e8930bb50ce40a9448ff97cd3d1d1","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.swap_payment_date(uuid,uuid,date,date,jsonb)","definition":"d2f5a79c979acd5354fc5940fbc66717986744cbcdc36ac5737b135ad2092546","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.indexed_whole_term_swap_period_input(uuid,uuid,integer)","definition":"84c930510497c38b811324492c5b86a2f07f9a3d6627d82822eb88bc8ee07b9e","volatility":"s"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off","join_collapse_limit=1"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.read_swap_revisions(uuid,uuid,boolean,uuid[])","definition":"1875a3a5ac8503fa2631eaaf5fe56baeeda8580e47f0011a00fd16734c399569","volatility":"s"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off","join_collapse_limit=1"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.read_swap_revisions(uuid,uuid,boolean,uuid[],uuid[])","definition":"1e92823e9a21085745f3d46ecb510b56f25b55f173987c88e8740d8b706dba39","volatility":"s"}
,{"acl":["openetrm_risk_worker=X/@migration_owner","openetrm_runtime=X/@migration_owner","openetrm_security_owner=X/@migration_owner","@migration_owner=X/@migration_owner"],"owner":"@migration_owner","config":["search_path=pg_catalog","join_collapse_limit=8"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.scheduled_swap_terms(uuid,uuid,integer,uuid)","definition":"37a70e6c3465cc2bbcd73e8b61751e6ecbf5a2c2b76d494e2eb28d823769d736","volatility":"s"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.stamp_whole_term_swap_identity()","definition":"46521631d13fbde275d12d1a6d19bd9afc934938ef273438196b6d5e1252267c","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.swap_observation_terms(uuid,uuid[])","definition":"bf409661c9635a7e821f584e178610112f4630aae66a0ffb3cb2729b28d56277","volatility":"s"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.swap_revision_terms(uuid,uuid,integer)","definition":"60641aec50f5d08aec64f5bd2936a7ad62ef9b0d2cbb971ecdeecc688a9a540a","volatility":"s"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.whole_term_swap_period_input(uuid,uuid,integer)","definition":"5504acd202eb28b9ac9c02cd066d33172186f2ad2c6d51a0778c5c061e784a62","volatility":"s"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.require_swap_metadata_references(uuid,uuid)","definition":"c6634cfbd6e2017f9898076c6bd7d6f110e621149f29bd1277de5c6054942d5f","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_calendar_proofs_visible(uuid,uuid,uuid)","definition":"1ac5d76ef39132f98b83fc496a7b4c59dad4d73efd29479b41803becc635edbc","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.require_retained_swap_period(jsonb,boolean)","definition":"ab7c6088ec114a9cb7aaca0aff7cc7fc450fd27838ea09eec16bb8cad26f399e","volatility":"i"}]
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

-- The retained hydration readers now consume invoker views. Their exact
-- definitions and authority boundaries are part of this upgrade contract.
DO $calendar_views$DECLARE expected jsonb;view_row pg_class;actual_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($view_contracts$
[{"acl":["openetrm_risk_worker=r/openetrm_security_owner","openetrm_runtime=r/openetrm_security_owner","openetrm_security_owner=arwdDxt/openetrm_security_owner"],"kind":"v","name":"trading.scheduled_swap_term_projection","owner":"openetrm_security_owner","options":["security_invoker=true"],"definition":"9dadde7dde28a2aeffadb0970de6af0710f2b7e2c744517093078a8372834705"},{"acl":["openetrm_risk_worker=r/openetrm_security_owner","openetrm_runtime=r/openetrm_security_owner","openetrm_security_owner=arwdDxt/openetrm_security_owner"],"kind":"v","name":"trading.swap_period_input_projection","owner":"openetrm_security_owner","options":["security_invoker=true"],"definition":"e21cfc5d5f96de9a5aa17de61435e6cbe855927ecbc24e06c3db7c4a509d9d3e"}]
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





CREATE FUNCTION security.side_policy_calendar(policy jsonb,purpose text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE binding jsonb;reference jsonb;
BEGIN
 IF jsonb_typeof(policy) IS DISTINCT FROM 'object' OR policy->>'implementation' IS DISTINCT FROM 'side_calendar_policy_v1'
  OR NOT policy ?& ARRAY['implementation','delivery','observation','payment'] OR(SELECT count(*) FROM jsonb_object_keys(policy))<>4
  OR purpose NOT IN('delivery','observation','payment') THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
 binding=policy->purpose;reference=binding->'calendar';
 IF jsonb_typeof(binding) IS DISTINCT FROM 'object' OR binding->'applicable' IS DISTINCT FROM 'true'::jsonb
  OR(SELECT count(*) FROM jsonb_object_keys(binding))<>2 OR jsonb_typeof(reference) IS DISTINCT FROM 'object'
  OR NOT reference ?& ARRAY['revision','code'] OR(SELECT count(*) FROM jsonb_object_keys(reference))<>2
  OR jsonb_typeof(reference->'revision') IS DISTINCT FROM 'object'
  OR NOT(reference->'revision') ?& ARRAY['catalogId','revisionId'] OR(SELECT count(*) FROM jsonb_object_keys(reference->'revision'))<>2
 THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
 PERFORM security.read_side_calendar((reference#>>'{revision,catalogId}')::uuid,(reference#>>'{revision,revisionId}')::uuid,reference->>'code');
 RETURN reference;
END$$;
CREATE FUNCTION security.side_payment_rule(policy jsonb,terms jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE reference jsonb=security.side_policy_calendar(policy,'payment');
BEGIN
 IF jsonb_typeof(terms) IS DISTINCT FROM 'object' OR terms->'calendar' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'side_calendar_conflict';END IF;
 RETURN terms||jsonb_build_object('calendar',CASE WHEN terms->>'dayBasis'='business_days' OR terms->>'adjustment'<>'unadjusted' THEN reference->>'code' END);
END$$;
CREATE FUNCTION security.side_payment_date(policy jsonb,from_day date,to_day date,terms jsonb) RETURNS date
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE reference jsonb=security.side_policy_calendar(policy,'payment');rule jsonb;anchor date;result date;calendar ref_data.calendars;unadjusted jsonb;
BEGIN
 rule=security.side_payment_rule(policy,terms);
 SELECT * INTO STRICT calendar FROM ref_data.calendars WHERE(catalog_id,revision_id,code)=
  ((reference#>>'{revision,catalogId}')::uuid,(reference#>>'{revision,revisionId}')::uuid,reference->>'code');
 result=security.swap_payment_date(calendar.catalog_id,calendar.revision_id,from_day,to_day,rule);
 unadjusted=terms||jsonb_build_object('adjustment','unadjusted','calendar',CASE WHEN terms->>'dayBasis'='business_days' THEN calendar.code END);
 anchor=security.swap_payment_date(calendar.catalog_id,calendar.revision_id,from_day,to_day,unadjusted);
 IF anchor<calendar.coverage_from OR anchor>=calendar.coverage_to OR result<calendar.coverage_from OR result>=calendar.coverage_to THEN RAISE EXCEPTION 'calendar_coverage';END IF;
 RETURN result;
END$$;
CREATE FUNCTION security.retain_side_payment_rule(catalog uuid,policy jsonb,terms jsonb,publication integer,from_at timestamptz) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE reference jsonb=security.side_policy_calendar(policy,'payment');
BEGIN
 RETURN security.retain_swap_payment_rule(catalog,(reference#>>'{revision,catalogId}')::uuid,(reference#>>'{revision,revisionId}')::uuid,
  security.side_payment_rule(policy,terms),publication,from_at);
END$$;

CREATE FUNCTION security.staged_economic_side(catalog uuid,operation uuid,slot_number integer) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE selected uuid;
BEGIN
 PERFORM security.side_schedule_request_authority(catalog,operation);
 SELECT h.side_id INTO selected FROM trading.side_schedule_request_items i
 JOIN trading.side_schedules h ON(h.catalog_id,h.id)=(i.catalog_id,i.schedule_id)
 JOIN trading.side_schedule_seals sealed ON(sealed.catalog_id,sealed.schedule_id)=(h.catalog_id,h.id)
 WHERE(i.catalog_id,i.request_id,i.slot)=(catalog,operation,slot_number)
  AND h.generator_version='whole_term_side_blocks_v3';
 IF selected IS NULL THEN RAISE EXCEPTION 'side_schedule_missing';END IF;
 RETURN selected;
END$$;
DO $$DECLARE signature regprocedure;BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'security.side_policy_calendar(jsonb,text)'::regprocedure,'security.side_payment_rule(jsonb,jsonb)'::regprocedure,
  'security.side_payment_date(jsonb,date,date,jsonb)'::regprocedure,'security.retain_side_payment_rule(uuid,jsonb,jsonb,integer,timestamptz)'::regprocedure,
  'security.staged_economic_side(uuid,uuid,integer)'::regprocedure] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',signature);
 END LOOP;
END$$;

-- Independent validation helpers use native dates, while the managed generator
-- remains the authoring and execution owner.
DO $$DECLARE signature regprocedure;source text;BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz)'::regprocedure,
  'security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[])'::regprocedure] LOOP
  source=pg_get_functiondef(signature);
  IF strpos(source,'security.swap_payment_date(ref_catalog,ref_revision,')=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
  source=replace(source,$match$'paymentAt','paymentSchedule'$match$,$replace$'paymentAt','paymentSchedule','calendarPolicy'$replace$);
  source=replace(source,$match$'observationSchedule','settlement'$match$,$replace$'observationSchedule','settlement','calendarPolicy'$replace$);
  source=replace(source,'security.swap_payment_date(ref_catalog,ref_revision,','security.side_payment_date(body->''calendarPolicy'',');
  source=replace(source,'security.retain_swap_payment_rule(catalog,ref_catalog,ref_revision,body->''paymentSchedule'',publication_number,from_at)',
   'security.retain_side_payment_rule(catalog,body->''calendarPolicy'',body->''paymentSchedule'',publication_number,from_at)');
  source=replace(source,'valuation>=payment','(valuation AT TIME ZONE ''UTC'')::date>(payment AT TIME ZONE ''UTC'')::date');
  EXECUTE source;
 END LOOP;
END$$;

DO $$DECLARE item record;table_name text;definition text;BEGIN
 FOREACH table_name IN ARRAY ARRAY['swap_fixed_sides','swap_floating_sides','swap_whole_term_sides','ppa_sides'] LOOP
  FOR item IN SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint
   WHERE conrelid=to_regclass('trading.'||table_name) AND contype='c' AND pg_get_constraintdef(oid) LIKE '%definition_version%' LOOP
   definition=replace(replace(replace(replace(replace(item.definition,'FixedSide_v4','FixedSide_v5'),
    'FloatingSide_v8','FloatingSide_v9'),'power_physical_side_v2','power_physical_side_v3'),
    'ppa_certificate_delivery_v2','ppa_certificate_delivery_v3'),'ppa_capacity_delivery_v2','ppa_capacity_delivery_v3');
   EXECUTE format('ALTER TABLE trading.%I DROP CONSTRAINT %I',table_name,item.conname);
   EXECUTE format('ALTER TABLE trading.%I ADD CONSTRAINT %I %s NOT VALID',table_name,item.conname,definition);
  END LOOP;
  IF table_name='ppa_sides' THEN
   ALTER TABLE trading.ppa_sides ADD COLUMN canonical_side_id uuid,
    ADD CONSTRAINT canonical_side FOREIGN KEY(catalog_id,canonical_side_id) REFERENCES trading.sides(catalog_id,id),
    ADD CONSTRAINT canonical_side_required CHECK(canonical_side_id IS NOT NULL) NOT VALID;
  ELSE
   EXECUTE format('ALTER TABLE trading.%I ADD CONSTRAINT canonical_side FOREIGN KEY(catalog_id,id) REFERENCES trading.sides(catalog_id,id) NOT VALID',table_name);
  END IF;
 END LOOP;
 ALTER TABLE trading.swap_fixed_sides ALTER COLUMN definition_version SET DEFAULT 'FixedSide_v5';
 ALTER TABLE trading.swap_floating_sides ALTER COLUMN definition_version SET DEFAULT 'FloatingSide_v9';
 -- The canonical identity includes calendars, provenance, all periods and pricing
 -- bindings. The previous partial economic key cannot distinguish those terms.
 FOR item IN SELECT conname FROM pg_constraint WHERE conrelid='trading.swap_fixed_sides'::regclass AND contype='u'
  AND pg_get_constraintdef(oid) NOT LIKE '%identity_hash%' LOOP
  EXECUTE format('ALTER TABLE trading.swap_fixed_sides DROP CONSTRAINT %I',item.conname);
 END LOOP;
END$$;
CREATE OR REPLACE FUNCTION trading.stamp_whole_term_swap_identity() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE canonical trading.sides;
BEGIN
 SELECT * INTO canonical FROM trading.sides WHERE(catalog_id,id)=(NEW.catalog_id,NEW.id);
 IF NOT FOUND OR canonical.family<>(CASE TG_TABLE_NAME WHEN 'swap_fixed_sides' THEN 'fixed' ELSE 'floating' END)
  OR canonical.economic_identity::jsonb->>'contract' IS DISTINCT FROM NEW.definition_version
 THEN RAISE EXCEPTION 'side_schedule_identity';END IF;
 NEW.identity_hash=canonical.identity_hash;RETURN NEW;
END$$;

DO $$DECLARE signature regprocedure;source text;BEGIN
 signature='security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz)'::regprocedure;
 source=pg_get_functiondef(signature);
 source=replace(source,'from_at timestamp with time zone)','from_at timestamp with time zone,canonical_side uuid DEFAULT NULL)');
 source=replace(source,'BEGIN',E'BEGIN\n IF canonical_side IS NULL THEN RAISE EXCEPTION ''side_schedule_missing'';END IF;');
 source=replace(source,$match$'paymentAt','paymentSchedule'$match$,$replace$'paymentAt','paymentSchedule','calendarPolicy'$replace$);
 source=replace(source,'security.swap_payment_date(ref_catalog,ref_revision,','security.side_payment_date(body->''calendarPolicy'',');
 source=replace(source,'security.retain_swap_payment_rule(catalog,ref_catalog,ref_revision,body->''paymentSchedule'',publication_number,from_at)',
  'security.retain_side_payment_rule(catalog,body->''calendarPolicy'',body->''paymentSchedule'',publication_number,from_at)');
 source=replace(source,'valuation>=payment','(valuation AT TIME ZONE ''UTC'')::date>(payment AT TIME ZONE ''UTC'')::date');
 source=replace(source,'WHERE s.catalog_id=catalog AND','WHERE s.id=canonical_side AND s.catalog_id=catalog AND');
 source=replace(source,'side=gen_random_uuid();','side=canonical_side;');
 EXECUTE source;
 signature='security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[])'::regprocedure;
 source=pg_get_functiondef(signature);
 source=replace(source,'input_pins uuid[])','input_pins uuid[],canonical_side uuid DEFAULT NULL)');
 source=replace(source,'BEGIN',E'BEGIN\n IF canonical_side IS NULL THEN RAISE EXCEPTION ''side_schedule_missing'';END IF;');
 source=replace(source,'WHERE s.catalog_id=catalog AND','WHERE s.id=canonical_side AND s.catalog_id=catalog AND');
 source=replace(source,'side=gen_random_uuid();','side=canonical_side;');
 EXECUTE source;
 signature='security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamptz,timestamptz,text,text,text,jsonb,uuid[])'::regprocedure;
 source=pg_get_functiondef(signature);
 IF strpos(source,'fixed_body,valuation,publication_number,from_at)')=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 source=replace(source,'fixed_body,valuation,publication_number,from_at)','fixed_body,valuation,publication_number,from_at,security.staged_economic_side(catalog,operation,0))');
 source=replace(source,'first_body,valuation,publication_number,from_at,input_pins)','first_body,valuation,publication_number,from_at,input_pins,security.staged_economic_side(catalog,operation,0))');
 source=replace(source,'float_body,valuation,publication_number,from_at,input_pins)','float_body,valuation,publication_number,from_at,input_pins,security.staged_economic_side(catalog,operation,1))');
 EXECUTE source;
END$$;
DROP FUNCTION security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz);
DROP FUNCTION security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[]);
ALTER FUNCTION security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid) OWNER TO openetrm_security_owner;
ALTER FUNCTION security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[],uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid),
 security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[],uuid) FROM PUBLIC;

DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamptz,jsonb,uuid[])'::regprocedure);
 marker='period_body=side_body->''periods''->n;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 source=replace(source,marker,marker||$patch$
   IF nullif(period_body#>'{fixed,calendarPolicy}','null'::jsonb) IS NOT NULL
    OR nullif(period_body#>'{floating,calendarPolicy}','null'::jsonb) IS NOT NULL THEN RAISE EXCEPTION 'side_calendar_conflict';END IF;
   IF kind THEN period_body=jsonb_set(period_body,'{fixed,calendarPolicy}',side_body->'calendarPolicy');
   ELSE period_body=jsonb_set(period_body,'{floating,calendarPolicy}',side_body->'calendarPolicy');END IF;
 $patch$);
 source=replace(replace(source,'FixedSide_v4','FixedSide_v5'),'FloatingSide_v8','FloatingSide_v9');
 marker='SELECT id INTO side_id FROM trading.swap_whole_term_sides s WHERE s.catalog_id=catalog AND s.identity_hash=digest_value;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 source=replace(source,marker,$patch$
  SELECT s.identity_hash INTO STRICT digest_value FROM trading.sides s
   WHERE(s.catalog_id,s.id)=(catalog,security.staged_economic_side(catalog,operation,slot));
  SELECT id INTO side_id FROM trading.swap_whole_term_sides s WHERE s.catalog_id=catalog AND s.identity_hash=digest_value;
 $patch$);
 source=replace(source,'side_id=gen_random_uuid();','side_id=security.staged_economic_side(catalog,operation,slot);');
 EXECUTE source;
END$$;
-- Public terms expose the three owned bindings; nested rules carry no calendar.
CREATE FUNCTION security.side_calendar_policy_document(catalog uuid,side uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('implementation','side_calendar_policy_v1')||jsonb_object_agg(lower(b.purpose),
  jsonb_build_object('applicable',b.applicable,'calendar',CASE WHEN b.applicable THEN
   jsonb_build_object('revision',jsonb_build_object('catalogId',b.reference_catalog_id,'revisionId',b.reference_revision_id),'code',b.calendar_code) END))
 FROM trading.side_calendar_bindings b WHERE(b.catalog_id,b.side_id)=(catalog,side) HAVING count(*)=3
$$;
ALTER FUNCTION security.side_calendar_policy_document(uuid,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.side_calendar_policy_document(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.side_calendar_policy_document(uuid,uuid) TO openetrm_runtime,openetrm_risk_worker;

DO $$DECLARE item record;source text;BEGIN
 -- The typed Side relationship owns the calendar. Old scalar calendar columns
 -- remain readable on existing rows and must be empty on newly admitted rows.
 FOR item IN SELECT c.conrelid::regclass AS relation,c.conname,pg_get_constraintdef(c.oid) AS definition
  FROM pg_constraint c WHERE c.conrelid IN('trading.ppa_sides'::regclass,'trading.ppa_side_schedules'::regclass)
  AND c.contype='c' AND pg_get_constraintdef(c.oid) LIKE '%holiday_calendar_code%' LOOP
  source=CASE WHEN item.relation='trading.ppa_sides'::regclass THEN 'CHECK(holiday_calendar_code IS NULL)'
   ELSE replace(item.definition,'holiday_calendar_code IS NOT NULL','holiday_calendar_code IS NULL') END;
  EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',item.relation,item.conname);
  EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s NOT VALID',item.relation,item.conname,source);
 END LOOP;
 source=pg_get_functiondef('security.ppa_side_document(uuid,uuid)'::regprocedure);
 source=replace(source,'''kind'',s.kind,','''calendarPolicy'',security.side_calendar_policy_document(catalog,s.canonical_side_id),''kind'',s.kind,');
 source=replace(source,'''calendar'',s.holiday_calendar_code','''calendar'',NULL');
 source=replace(source,'''calendar'',r.calendar_code','''calendar'',NULL');
 EXECUTE source;
 source=pg_get_functiondef('security.ppa_schedule_document(jsonb,jsonb)'::regprocedure);
 source=replace(source,'h->>''calendar'' IS NULL','h->''calendar'' IS DISTINCT FROM ''null''::jsonb');
 EXECUTE source;
END$$;

DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('security.retain_ppa_terms(uuid,jsonb,integer,timestamptz)'::regprocedure);
 source=replace(source,'from_at timestamp with time zone)','from_at timestamp with time zone,operation uuid DEFAULT NULL)');
 source=replace(source,'candidate uuid;instrument uuid;','candidate uuid;canonical_side uuid;calendar_reference jsonb;instrument uuid;');
 source=replace(source,E'BEGIN\n spec=',E'BEGIN\n IF operation IS NULL THEN RAISE EXCEPTION ''side_schedule_missing'';END IF;\n spec=');
 source=replace(source,'IF security.ppa_terms_document(catalog,candidate)=spec THEN RETURN candidate;END IF;',
  $patch$IF security.ppa_terms_document(catalog,candidate)=spec AND NOT EXISTS(
   SELECT 1 FROM trading.ppa_memberships m JOIN trading.ppa_sides s ON(s.catalog_id,s.id)=(m.catalog_id,m.side_id)
   WHERE(m.catalog_id,m.instrument_id)=(catalog,candidate) AND s.canonical_side_id<>security.staged_economic_side(catalog,operation,m.position)) THEN RETURN candidate;END IF;$patch$);
 source=replace(source,$match$ARRAY['kind','quantity','paymentRule','location','fixedPrice','indexPrice','attribute']$match$,
  $replace$ARRAY['kind','quantity','paymentRule','location','fixedPrice','indexPrice','attribute','calendarPolicy']$replace$);
 marker='q=side->''quantity'';h=q->''hours'';';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 source=replace(source,marker,'canonical_side=security.staged_economic_side(catalog,operation,position);'||marker);
 source=replace(source,'h->>''calendar'' IS NULL','h->''calendar'' IS DISTINCT FROM ''null''::jsonb');
 marker='AND t.state=''published'' AND(t.clock_catalog_id,t.clock_revision_id,t.clock_code)=(rc,rr,delivery->>''clock''))';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 source=replace(source,marker,marker||$patch$
      AND (t.calendar_catalog_id,t.calendar_revision_id,t.calendar_code)=
       ((calendar_reference#>>'{revision,catalogId}')::uuid,(calendar_reference#>>'{revision,revisionId}')::uuid,calendar_reference->>'code')
      AND t.holiday_treatment='weekly_mask_explicit_closures_v1'$patch$);
 -- Move the added predicates inside the TOU EXISTS.
 source=replace(source,'delivery->>''clock''))'||E'\n      AND','delivery->>''clock'')'||E'\n      AND');
 source=replace(source,'AND t.holiday_treatment=''weekly_mask_explicit_closures_v1'')','AND t.holiday_treatment=''weekly_mask_explicit_closures_v1''))');
 source=replace(source,'IF q->>''kind''=''profile'' THEN',E'IF q->>''kind''=''profile'' THEN\n   calendar_reference=security.side_policy_calendar(side->''calendarPolicy'',''delivery'');');
 source=replace(source,'security.swap_payment_date(rc,rr,payment_month,','security.side_payment_date(side->''calendarPolicy'',payment_month,');
 source=replace(source,'FROM trading.ppa_sides WHERE catalog_id=catalog AND economic_hash=key',
  'FROM trading.ppa_sides WHERE canonical_side_id=canonical_side AND catalog_id=catalog AND economic_hash=key');
 source=replace(source,'security.retain_swap_payment_rule(catalog,rc,rr,side->''paymentRule'',publication,from_at);side_id=gen_random_uuid();',
  'security.retain_side_payment_rule(catalog,side->''calendarPolicy'',side->''paymentRule'',publication,from_at);side_id=gen_random_uuid();');
 source=replace(source,'normalization_choice,settlement_mode,settlement_target,settlement_index,settlement_policy);',
  'normalization_choice,settlement_mode,settlement_target,settlement_index,settlement_policy,canonical_side);');
 source=replace(replace(replace(replace(replace(source,'FixedSide_v4','FixedSide_v5'),'FloatingSide_v8','FloatingSide_v9'),
  'power_physical_side_v2','power_physical_side_v3'),'ppa_certificate_delivery_v2','ppa_certificate_delivery_v3'),'ppa_capacity_delivery_v2','ppa_capacity_delivery_v3');
 EXECUTE source;
 source=pg_get_functiondef('security.save_ppa_booking(uuid,uuid,jsonb)'::regprocedure);
 marker='security.retain_ppa_terms(catalog,terms,publication,executed)';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 EXECUTE replace(source,marker,'security.retain_ppa_terms(catalog,terms,publication,executed,operation)');
END$$;
DROP FUNCTION security.retain_ppa_terms(uuid,jsonb,integer,timestamptz);
ALTER FUNCTION security.retain_ppa_terms(uuid,jsonb,integer,timestamptz,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.retain_ppa_terms(uuid,jsonb,integer,timestamptz,uuid) FROM PUBLIC;

ALTER TABLE trading.swap_observation_schedules
 ADD COLUMN calendar_catalog_id uuid,ADD COLUMN calendar_revision_id uuid,
 ADD CONSTRAINT observation_calendar_reference FOREIGN KEY(calendar_catalog_id,calendar_revision_id,calendar_code)
  REFERENCES ref_data.calendars(catalog_id,revision_id,code),
 ADD CONSTRAINT observation_calendar_complete CHECK((calendar_code IS NULL AND calendar_catalog_id IS NULL AND calendar_revision_id IS NULL)
  OR(calendar_code IS NOT NULL AND calendar_catalog_id IS NOT NULL AND calendar_revision_id IS NOT NULL)) NOT VALID;
DO $$DECLARE item record;source text;marker text;BEGIN
 FOR item IN SELECT conname FROM pg_constraint WHERE conrelid='trading.swap_observation_schedules'::regclass AND contype='f'
  AND confrelid='ref_data.calendars'::regclass AND conname<>'observation_calendar_reference' LOOP
  EXECUTE format('ALTER TABLE trading.swap_observation_schedules DROP CONSTRAINT %I',item.conname);
 END LOOP;
 source=pg_get_functiondef('security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[])'::regprocedure);
 marker='observation_schedule=NULLIF(body->''observationSchedule'',''null''::jsonb);';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 source=replace(source,marker,marker||$patch$
 IF observation_schedule IS NOT NULL THEN
  IF observation_schedule->'calendar' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'side_calendar_conflict';END IF;
  IF sampling<>'quantity_weighted' THEN
   observation_schedule=jsonb_set(observation_schedule,'{calendar}',security.side_policy_calendar(body->'calendarPolicy','observation'));
  END IF;
 END IF;
 $patch$);
 EXECUTE source;
 source=pg_get_functiondef('security.swap_observation_rows(uuid,uuid,uuid,uuid,text,text,date,date,text,jsonb)'::regprocedure);
 source=replace(source,'OR schedule->''calendar''->''revision'' IS DISTINCT FROM jsonb_build_object(''catalogId'',ref_catalog,''revisionId'',ref_revision)',
  'OR jsonb_typeof(schedule#>''{calendar,revision}'') IS DISTINCT FROM ''object''');
 marker='SELECT * INTO calendar FROM ref_data.calendars c WHERE(c.catalog_id,c.revision_id,c.code)=(ref_catalog,ref_revision,schedule->''calendar''->>''code'');';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 source=replace(source,marker,$patch$
  PERFORM security.read_side_calendar((schedule#>>'{calendar,revision,catalogId}')::uuid,(schedule#>>'{calendar,revision,revisionId}')::uuid,schedule#>>'{calendar,code}');
  SELECT * INTO calendar FROM ref_data.calendars c WHERE(c.catalog_id,c.revision_id,c.code)=
   ((schedule#>>'{calendar,revision,catalogId}')::uuid,(schedule#>>'{calendar,revision,revisionId}')::uuid,schedule#>>'{calendar,code}');
 $patch$);
 source=replace(source,'(ref_catalog,ref_revision,calendar.code,d.date)','(calendar.catalog_id,calendar.revision_id,calendar.code,d.date)');
 source=replace(source,$match$THEN RAISE EXCEPTION 'swap_averaging';END IF;
  FOR entry$match$,$replace$THEN RAISE EXCEPTION 'calendar_coverage';END IF;
  FOR entry$replace$);
 source=replace(source,$match$IF averaging='observation_arithmetic' THEN CONTINUE;END IF;
    RAISE EXCEPTION 'swap_averaging';$match$,$replace$IF averaging='observation_arithmetic' THEN CONTINUE;END IF;
    RAISE EXCEPTION 'calendar_coverage';$replace$);
 EXECUTE source;
 source=pg_get_functiondef('security.retain_swap_observation_schedule(uuid,uuid,uuid,uuid,text,text,ref_data.quote_specifications,date,date,text,jsonb,jsonb,integer,timestamptz)'::regprocedure);
 source=replace(source,'calendar_name,''side_observation_schedule_v1'',selected','schedule->''calendar'',''side_observation_schedule_v1'',selected');
 source=replace(source,'calendar_name,key,''side_observation_schedule_v1'',publication,effective);',
  'calendar_name,key,''side_observation_schedule_v1'',publication,effective,(schedule#>>''{calendar,revision,catalogId}'')::uuid,(schedule#>>''{calendar,revision,revisionId}'')::uuid);');
 EXECUTE source;
 source=pg_get_functiondef('trading.swap_observation_terms(uuid,uuid[])'::regprocedure);
 marker='CASE WHEN o.calendar_code IS NULL THEN NULL ELSE jsonb_build_object(''revision'',jsonb_build_object(''catalogId'',o.reference_catalog_id,''revisionId'',o.reference_revision_id),''code'',o.calendar_code) END';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_writer_upgrade';END IF;
 EXECUTE replace(source,marker,'NULL');
END$$;

-- The contract observation author uses the same owned payment calendar and UTC
-- payment-day boundary as every other floating Side.
DO $$DECLARE source text;BEGIN
 source=pg_get_functiondef('security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,jsonb,uuid[])'::regprocedure);
 source=replace(source,$match$'settlement','contractObservations'$match$,$replace$'settlement','contractObservations','calendarPolicy'$replace$);
 source=replace(source,'security.swap_payment_date(ref_catalog,ref_revision,','security.side_payment_date(body->''calendarPolicy'',');
 source=replace(source,'security.retain_swap_payment_rule(catalog,ref_catalog,ref_revision,body->''paymentSchedule'',publication_number,from_at)',
  'security.retain_side_payment_rule(catalog,body->''calendarPolicy'',body->''paymentSchedule'',publication_number,from_at)');
 source=replace(source,'valuation>=payment','(valuation AT TIME ZONE ''UTC'')::date>(payment AT TIME ZONE ''UTC'')::date');
 source=replace(source,'anchor>=payment','(anchor AT TIME ZONE ''UTC'')::date>(payment AT TIME ZONE ''UTC'')::date');
 EXECUTE source;
END$$;

CREATE FUNCTION trading.swap_authoring_terms(catalog uuid,document jsonb) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT document||jsonb_build_object(
  'fixed_calendar_policy',security.side_calendar_policy_document(catalog,(document->>'fixed_side_id')::uuid),
  'floating_calendar_policy',security.side_calendar_policy_document(catalog,(document->>'floating_side_id')::uuid),
  'fixed_payment_rule',CASE WHEN document->>'fixed_payment_rule' IS NOT NULL THEN jsonb_set(document->'fixed_payment_rule','{calendar}','null') END,
  'floating_payment_rule',CASE WHEN document->>'floating_payment_rule' IS NOT NULL THEN jsonb_set(document->'floating_payment_rule','{calendar}','null') END,
  'first_floating',CASE WHEN document->>'first_floating' IS NOT NULL THEN jsonb_set(document->'first_floating','{paymentSchedule,calendar}','null')||
   jsonb_build_object('calendarPolicy',security.side_calendar_policy_document(catalog,(document->>'first_floating_side_id')::uuid)) END)
$$;
ALTER FUNCTION trading.swap_authoring_terms(uuid,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION trading.swap_authoring_terms(uuid,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trading.swap_authoring_terms(uuid,jsonb) TO openetrm_runtime,openetrm_risk_worker;
DO $$DECLARE signature regprocedure;source text;BEGIN
 FOREACH signature IN ARRAY ARRAY['trading.swap_revision_terms(uuid,uuid,integer)'::regprocedure,
  'trading.read_swap_revisions(uuid,uuid,boolean,uuid[],uuid[])'::regprocedure] LOOP
  source=pg_get_functiondef(signature);
  IF strpos(source,'to_jsonb(v)')=0 THEN RAISE EXCEPTION 'side_calendar_read_predecessor';END IF;
  EXECUTE replace(source,'to_jsonb(v)','trading.swap_authoring_terms(catalog,to_jsonb(v))');
 END LOOP;
END$$;

DO $$DECLARE source text;marker text;item record;BEGIN
 source=pg_get_viewdef('trading.scheduled_swap_term_projection'::regclass);
 marker='jsonb_build_object(''basis'', a.basis';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_read_predecessor';END IF;
 source=replace(source,marker,'jsonb_build_object(''calendarPolicy'', security.side_calendar_policy_document(selected.catalog_id,selected.side_id),''basis'', a.basis');
 marker=$match$CASE
                        WHEN (a.calendar_code IS NULL) THEN NULL::jsonb
                        ELSE jsonb_build_object('revision', jsonb_build_object('catalogId', a.reference_catalog_id, 'revisionId', a.reference_revision_id), 'code', a.calendar_code)
                    END$match$;
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_read_predecessor';END IF;
 EXECUTE 'CREATE OR REPLACE VIEW trading.scheduled_swap_term_projection WITH(security_invoker=true) AS '||replace(source,marker,'NULL::jsonb');
 source=pg_get_viewdef('trading.swap_period_input_projection'::regclass);
 IF strpos(source,'''calendar'', r.calendar_code')=0 THEN RAISE EXCEPTION 'side_calendar_read_predecessor';END IF;
 source=replace(source,'''calendar'', r.calendar_code','''calendar'', NULL::text');
 -- Both indexed and generic period inputs project the same owned observation
 -- policy. Only those exact scalar expressions change; protected joins remain.
 source=regexp_replace(source,
  $match$CASE\s+WHEN \(o.calendar_code IS NULL\) THEN NULL::jsonb\s+ELSE jsonb_build_object\('revision', jsonb_build_object\('catalogId', o.reference_catalog_id, 'revisionId', o.reference_revision_id\), 'code', o.calendar_code\)\s+END$match$,
  'NULL::jsonb','g');
 IF strpos(source,'''code'', o.calendar_code')<>0 THEN RAISE EXCEPTION 'side_calendar_read_predecessor';END IF;
 EXECUTE 'CREATE OR REPLACE VIEW trading.swap_period_input_projection WITH(security_invoker=true) AS '||source;
 FOR item IN SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint
  WHERE conrelid='trading.swap_quantity_authoring'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%calendar_code IS NOT NULL%' LOOP
  EXECUTE format('ALTER TABLE trading.swap_quantity_authoring DROP CONSTRAINT %I',item.conname);
  EXECUTE format('ALTER TABLE trading.swap_quantity_authoring ADD CONSTRAINT %I %s NOT VALID',item.conname,replace(item.definition,'calendar_code IS NOT NULL','calendar_code IS NULL'));
 END LOOP;
END$$;

-- Lifecycle determination, payment, netting and committed retry all use this
-- private metadata gate. Recheck retained calendar proofs without reselecting
-- publications or broadening reference-catalog visibility.
DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('security.require_swap_metadata_references(uuid,uuid)'::regprocedure);
 marker=E'END LOOP;\nEND';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_calendar_read_predecessor';END IF;
 EXECUTE replace(source,marker,$patch$END LOOP;
 IF EXISTS(SELECT 1 FROM trading.instrument_side_schedules m
  WHERE(m.catalog_id,m.instrument_id)=(catalog,instrument)
   AND security.side_calendar_proofs_visible(catalog,m.schedule_id,NULL) IS NOT TRUE)
 THEN RAISE EXCEPTION 'side_calendar_denied' USING ERRCODE='42501';END IF;
END$patch$);
END$$;

COMMIT;
