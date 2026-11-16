-- Turns retain selection identity at admission; only requested financial tools acquire a context.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='15s';
SET LOCAL search_path=pg_catalog;
SELECT pg_advisory_xact_lock(730849102);
DO $assistant_context_guard$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($assistant_helpers$
[{"signature":"assistant.ask_turn(uuid,text,uuid,uuid,integer,text,jsonb,uuid,text,uuid,uuid,text,text,timestamptz,text,bigint,text,integer,integer,integer)","definition":"afd1edc87b3b896cec52e1b02bdead8efe0fd341ad6a8576bc039255d514a704","owner":"openetrm_security_owner","config":["search_path=pg_catalog","TimeZone=UTC"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.record_tool_step(uuid,bytea,text,text,jsonb,text,timestamptz,jsonb,jsonb,jsonb)","definition":"a999fe1ba4e8f567e243d831ecb0cd0e75229bc9c65815fe488a230d0c2b59bd","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.start_turn_without_page_prompt(uuid,bytea)","definition":"9f5d96327e376581a489c9a4baa734adb3db76208033785d498639462961bb46","owner":"openetrm_security_owner","config":["search_path=pg_catalog","TimeZone=UTC"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.pin_market_turn(uuid,bytea,date,jsonb,integer)","definition":"dbc4cf7a6a6dd6b98d1b5717da3e5cd80433d133e85d150c3f8ef063a963a6da","owner":"openetrm_security_owner","config":["search_path=pg_catalog","TimeZone=UTC"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.pin_turn(uuid,bytea,date,jsonb,integer)","definition":"25957bdbbc5e489aa358a346e118a22a0078b0b0cc8c3be7bf1816832798f16f","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.turn_state(assistant.turns)","definition":"c72f829f3c6541582b6a5d428d7a7a3dcbb002096807e7e4161d4b683c2b174e","owner":"openetrm_security_owner","config":["search_path=pg_catalog","TimeZone=UTC"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"s","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.is_navigation_target(assistant.turns,jsonb)","definition":"81374153e4e080a7d106f3937ecd31fccdd7163a2487917f96363d3ec1d3859f","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"s","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.is_walkthrough(assistant.turns,jsonb)","definition":"c219da3c158768a29e378a565d8c49314735412c7c88d45d05de8d8a3fa26b20","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"s","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.fenced_turn(uuid,bytea)","definition":"11646406f0f2eedc699b5bdf3cfa6f4fcb7dbe04b35c9a6ef17f320094b0f968","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.turn_authorized(assistant.turns)","definition":"d42e6b9389fad6033cfc6526e2c68d17f70a09b4a07c3e940d6842bcd2e311a9","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"s","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"security.market_access(uuid,text)","definition":"804fc62e6057b1b2d528e3493d761aa52d613a766a9087c90fcd6313b5832383","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"security.capture_date_context(uuid,date,timestamptz)","definition":"28efa5f53cfd95ccf25845df80c33cd68c60d13166cd0bdab44cf00c45a20274","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"security.use_market_context(uuid,uuid)","definition":"5b1d2a216dab1eb4b34ab68199245fdf513d0cc7fcac417020194e5cebc6e772","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"security.read_market_close_parts(uuid,uuid[],uuid)","definition":"690930b45105acd708708006cbd9d7f1cfcecf97bb9f25ffc5ea9e1f060e4853","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.turn_operating_limits(uuid)","definition":"50ccccdc32d687bdc033fb2e230aa4524253bf14af76e0edffa76f361f33a9a4","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_security_owner=X/openetrm_security_owner"]}]
$assistant_helpers$::jsonb) LOOP
  SELECT * INTO helper FROM pg_proc WHERE oid=to_regprocedure(expected->>'signature');
  SELECT jsonb_agg(x::text ORDER BY x::text) INTO actual_acl FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x;
  SELECT jsonb_agg(value ORDER BY value) INTO expected_acl FROM(
   SELECT replace(value,'@migration_owner',quote_ident(current_user))::aclitem::text value FROM jsonb_array_elements_text(expected->'acl')) a;
  IF helper.oid IS NULL OR encode(sha256(convert_to(pg_get_functiondef(helper.oid),'UTF8')),'hex') IS DISTINCT FROM expected->>'definition' OR
   pg_get_userbyid(helper.proowner) IS DISTINCT FROM(CASE expected->>'owner' WHEN '@migration_owner' THEN current_user ELSE expected->>'owner' END) OR
   helper.prosecdef IS DISTINCT FROM(expected->>'definer')::boolean OR helper.provolatile IS DISTINCT FROM(expected->>'volatility')::"char" OR
   helper.proisstrict IS DISTINCT FROM(expected->>'strict')::boolean OR helper.proleakproof IS DISTINCT FROM(expected->>'leakproof')::boolean OR
   helper.proparallel IS DISTINCT FROM(expected->>'parallel')::"char" OR coalesce(to_jsonb(helper.proconfig),'null'::jsonb) IS DISTINCT FROM expected->'config' OR
   actual_acl IS DISTINCT FROM expected_acl THEN RAISE EXCEPTION 'assistant_context_upgrade: unexpected helper %',expected->>'signature';END IF;
 END LOOP;
END$assistant_context_guard$;

DO $upgrade$
DECLARE signature text;definition text;before text;c record;found boolean:=false;
BEGIN
 FOR c IN SELECT conname,pg_get_constraintdef(oid) definition FROM pg_constraint WHERE conrelid='assistant.turns'::regclass AND contype='c' LOOP
  IF c.definition LIKE '%context_id IS NOT NULL%' AND c.definition LIKE '%started_at IS NOT NULL%' THEN
   definition:=replace(c.definition,'context_id IS NOT NULL','(context_id IS NOT NULL OR runtime_set=''turns_v22'')');
   EXECUTE format('ALTER TABLE assistant.turns DROP CONSTRAINT %I,ADD CONSTRAINT %I %s',c.conname,c.conname,definition);found:=true;
  END IF;
 END LOOP;
 IF NOT found THEN RAISE EXCEPTION 'assistant_context_upgrade: start constraint';END IF;
 FOREACH signature IN ARRAY ARRAY[
  'assistant.ask_turn(uuid,text,uuid,uuid,integer,text,jsonb,uuid,text,uuid,uuid,text,text,timestamptz,text,bigint,text,integer,integer,integer)',
  'assistant.record_tool_step(uuid,bytea,text,text,jsonb,text,timestamptz,jsonb,jsonb,jsonb)'
 ] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);before:='runtime_set<>''turns_v21''';
  IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'assistant_context_upgrade: runtime';END IF;
  definition:=replace(definition,before,'runtime_set<>''turns_v22''');
  IF signature LIKE 'assistant.ask_turn%' THEN
   before:='x.recorded_at IS NULL AND x.asked_at';
   IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'assistant_context_upgrade: admission';END IF;
   definition:=replace(definition,before,'x.recorded_at IS NULL AND x.started_at IS NULL AND x.asked_at');
   before:='IF stale.recorded_at IS NOT NULL THEN';
   IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'assistant_context_upgrade: expiry';END IF;
   definition:=replace(definition,before,'IF stale.recorded_at IS NOT NULL OR stale.started_at IS NOT NULL THEN');
  END IF;
  EXECUTE definition;
 END LOOP;
 signature:='assistant.start_turn_without_page_prompt(uuid,bytea)';definition:=pg_get_functiondef(signature::regprocedure);
 before:='IF t.recorded_at IS NULL OR';
 IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'assistant_context_upgrade: start';END IF;
 EXECUTE replace(definition,before,'IF t.recorded_at IS NULL AND t.runtime_set<>''turns_v22'' OR');
 -- The existing exact full-frame validator remains the working-frame reader.
 signature:='assistant.pin_market_turn(uuid,bytea,date,jsonb,integer)';definition:=pg_get_functiondef(signature::regprocedure);
 before:='t.state NOT IN(''queued'',''cancel_requested'')';
 IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'assistant_context_upgrade: pin';END IF;
 EXECUTE replace(definition,before,'(t.state NOT IN(''queued'',''cancel_requested'') AND NOT(t.state=''running'' AND t.runtime_set=''turns_v22''))');
 -- Presentation retains an unresolved selected historical context without acquiring market inputs.
 FOREACH signature IN ARRAY ARRAY['assistant.turn_state(assistant.turns)','assistant.is_navigation_target(assistant.turns,jsonb)','assistant.is_walkthrough(assistant.turns,jsonb)'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);before:='t.context_id';
  IF position(before in definition)=0 THEN RAISE EXCEPTION 'assistant_context_upgrade: presentation %',signature;END IF;
  EXECUTE replace(definition,before,'coalesce(t.context_id,t.requested_context)');
 END LOOP;
END $upgrade$;

CREATE TABLE assistant.turn_close_pins(
 turn_id uuid PRIMARY KEY REFERENCES assistant.turns(id),catalog_id uuid NOT NULL,close_id uuid NOT NULL,
 FOREIGN KEY(catalog_id,close_id) REFERENCES market_data.market_closes(catalog_id,id)
);
ALTER TABLE assistant.turn_close_pins OWNER TO openetrm_security_owner;
ALTER TABLE assistant.turn_close_pins ENABLE ROW LEVEL SECURITY;
ALTER TABLE assistant.turn_close_pins FORCE ROW LEVEL SECURITY;
CREATE POLICY owner_access ON assistant.turn_close_pins TO openetrm_security_owner USING(true) WITH CHECK(true);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON assistant.turn_close_pins FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();

CREATE FUNCTION assistant.resolve_turn_context(turn uuid,token bytea,effective_date date,pins jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE t assistant.turns;c security.request_contexts;x market_data.temporal_contexts;context uuid;close uuid;result jsonb;reserve integer;
BEGIN
 PERFORM 1 FROM security.epoch WHERE id=true FOR SHARE;
 t:=assistant.fenced_turn(turn,token);c:=assistant.grant_actor(true);
 IF(t.owner_id,t.tenant_id,t.workspace_id)<>(c.actor_id,c.tenant_id,c.workspace_id) OR NOT assistant.turn_authorized(t)
  OR NOT security.market_access(t.catalog_id,'ReadMarketData') THEN RAISE EXCEPTION 'No turn read authority' USING ERRCODE='42501';END IF;
 IF t.runtime_set<>'turns_v22' OR t.state<>'running' OR t.knowledge_mode='operational' OR t.session_ends_at<=clock_timestamp()
  OR t.asked_at+make_interval(secs=>(SELECT max_elapsed_seconds FROM assistant.agent_versions WHERE(agent_id,version)=(t.agent_id,t.agent_version)))<=clock_timestamp()
  THEN RAISE EXCEPTION 'turn_state_conflict';END IF;
 IF t.recorded_at IS NOT NULL THEN
  SELECT * INTO x FROM market_data.temporal_contexts WHERE(catalog_id,id)=(t.catalog_id,t.context_id);
  IF t.pins IS DISTINCT FROM pins OR t.knowledge_mode='current' AND effective_date IS DISTINCT FROM x.effective_on THEN RAISE EXCEPTION 'turn_conflict';END IF;
  RETURN jsonb_build_object('turn',assistant.turn_state(t));
 END IF;
 IF pins ? 'closeId' THEN
  IF jsonb_typeof(pins)<>'object' OR(SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(pins) key)<>ARRAY['closeId','frameId']
   OR pins->>'frameId' IS DISTINCT FROM t.frame_id::text OR NOT assistant.is_uuid_array(jsonb_build_array(pins->'closeId')) THEN RAISE EXCEPTION 'turn_input';END IF;
  close:=(pins->>'closeId')::uuid;
  IF t.knowledge_mode='current' THEN
   IF effective_date IS NULL THEN RAISE EXCEPTION 'context_required';END IF;
   PERFORM pg_advisory_xact_lock(730849102);
   reserve:=(assistant.turn_operating_limits(t.id)->>'retainedContextReserve')::integer;
   IF(SELECT count(*) FROM market_data.temporal_contexts WHERE catalog_id=t.catalog_id)>=4096-reserve THEN RAISE EXCEPTION 'knowledge_budget_reserved';END IF;
   context:=security.capture_date_context(t.catalog_id,effective_date,NULL);
  ELSE context:=t.requested_context;END IF;
  SELECT * INTO x FROM market_data.temporal_contexts WHERE(catalog_id,id)=(t.catalog_id,context);
  IF x.id IS NULL OR NOT EXISTS(SELECT 1 FROM market_data.market_closes m WHERE(m.catalog_id,m.id,m.business_date)=(t.catalog_id,close,x.effective_on)) THEN RAISE EXCEPTION 'temporal_context';END IF;
  -- Exact close reader checks source visibility at this context; no current-close substitution.
  PERFORM security.use_market_context(t.catalog_id,context);
  PERFORM security.read_market_close_parts(t.catalog_id,ARRAY[close],context);
  INSERT INTO assistant.turn_close_pins VALUES(t.id,t.catalog_id,close);
  UPDATE assistant.turns y SET context_id=x.id,cutoff=x.known_at,pins=resolve_turn_context.pins,recorded_at=clock_timestamp() WHERE y.id=t.id RETURNING y.* INTO t;
  result:=jsonb_build_object('turn',assistant.turn_state(t));
 ELSE
  IF t.knowledge_mode='current' AND effective_date IS NULL THEN RAISE EXCEPTION 'context_required';END IF;
  PERFORM assistant.pin_turn(turn,token,effective_date,pins,NULL);
  SELECT y.* INTO t FROM assistant.turns y WHERE y.id=turn;
  result:=jsonb_build_object('turn',assistant.turn_state(t));
 END IF;
 c:=assistant.grant_actor(true);
 IF NOT assistant.turn_authorized(t) OR NOT security.market_access(t.catalog_id,'ReadMarketData') OR t.session_ends_at<=clock_timestamp()
  OR t.asked_at+make_interval(secs=>(SELECT max_elapsed_seconds FROM assistant.agent_versions WHERE(agent_id,version)=(t.agent_id,t.agent_version)))<=clock_timestamp()
  THEN RAISE EXCEPTION 'Turn read authority expired' USING ERRCODE='42501';END IF;
 RETURN result;
END$$;
ALTER FUNCTION assistant.resolve_turn_context(uuid,bytea,date,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION assistant.resolve_turn_context(uuid,bytea,date,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assistant.resolve_turn_context(uuid,bytea,date,jsonb) TO openetrm_runtime;
COMMIT;
