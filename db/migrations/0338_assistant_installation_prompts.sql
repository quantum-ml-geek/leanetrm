-- Installation-owned guidance. No instruction text is seeded or copied from application code.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='15s';
SET LOCAL search_path=pg_catalog;
SELECT pg_advisory_xact_lock(730849102);
DO $assistant_prompt_guard$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($assistant_helpers$
[{"signature":"assistant.is_prompt_page(text)","definition":"7a4188f200ba3cc3ae23ff4b67873997449810dc01b3976de993854cc8021561","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"i","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.agent_tools()","definition":"fb8ab5390896be17b4493d4832fa3d8e6b9ef3a8bd8de03359dfd046e1f710c2","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"i","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.save_page_prompt(uuid,text,integer,text)","definition":"bfe05b2adbd5bfd63ac66b8c302212a2849d6b2ff392b13babefc4c403486d14","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.start_turn(uuid,bytea)","definition":"9bc073a4e028125e14f915a66defe7792e2f6dcc233f785172685c301558ad80","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.open_test(uuid,uuid,text,integer,text,bigint)","definition":"bb2e0c8fae14741d93b2a37c5a545b8192829d81c0c9275e3d2897c8b3a5919c","owner":"openetrm_security_owner","config":["search_path=pg_catalog","TimeZone=UTC"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.actor()","definition":"57932921c06350d28515175f5af6dc561fad562cfcaa564033b94f6af0b538f5","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"assistant.grant_actor(boolean)","definition":"4aaf7c789d860df03d222e891b74008dafb6aae71d01a77b17219c35621a7503","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"v","acl":["openetrm_security_owner=X/openetrm_security_owner"]},{"signature":"market_data.guard_knowledge_receipt()","definition":"a376e86bfb72c2f4fd49e1659c29ae0df0503c2f98c7b096a92fb11cbac5122d","owner":"@migration_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"volatility":"v","acl":["@migration_owner=X/@migration_owner"]}]
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
   actual_acl IS DISTINCT FROM expected_acl THEN RAISE EXCEPTION 'assistant_prompt_upgrade: unexpected helper %',expected->>'signature';END IF;
 END LOOP;
END$assistant_prompt_guard$;


CREATE FUNCTION assistant.is_prompt_scope(scope text) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT assistant.is_prompt_page(scope) OR scope IN('application','provider_test:instructions','provider_test:question')
  OR scope IN(SELECT 'tool:'||code FROM assistant.agent_tools());
$$;
ALTER FUNCTION assistant.is_prompt_scope(text) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION assistant.is_prompt_scope(text) FROM PUBLIC;
ALTER TABLE assistant.page_prompt_versions DROP CONSTRAINT page_prompt_versions_page_check;
ALTER TABLE assistant.page_prompt_versions ADD CONSTRAINT page_prompt_versions_scope_check CHECK(assistant.is_prompt_scope(page));
DO $$DECLARE definition text;before text:='assistant.is_prompt_page(page)';BEGIN
 definition:=pg_get_functiondef('assistant.save_page_prompt(uuid,text,integer,text)'::regprocedure);
 IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'assistant_prompt_upgrade';END IF;
 EXECUTE replace(definition,before,'assistant.is_prompt_scope(page)');
END$$;

-- A NULL version records absence at admission. Later configuration cannot enter an existing turn.
CREATE TABLE assistant.turn_instruction_pins(
 turn_id uuid NOT NULL REFERENCES assistant.turns(id),tenant_id uuid NOT NULL,workspace_id uuid NOT NULL,scope text NOT NULL,
 version integer CHECK(version>0),PRIMARY KEY(turn_id,scope),
 FOREIGN KEY(tenant_id,workspace_id,scope,version) REFERENCES assistant.page_prompt_versions
);
ALTER TABLE assistant.turn_instruction_pins OWNER TO openetrm_security_owner;
ALTER TABLE assistant.turn_instruction_pins ENABLE ROW LEVEL SECURITY;
ALTER TABLE assistant.turn_instruction_pins FORCE ROW LEVEL SECURITY;
CREATE POLICY owner_access ON assistant.turn_instruction_pins TO openetrm_security_owner USING(true) WITH CHECK(true);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON assistant.turn_instruction_pins FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
CREATE FUNCTION assistant.pin_installation_instructions() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 INSERT INTO assistant.turn_instruction_pins
 SELECT NEW.id,NEW.tenant_id,NEW.workspace_id,s.scope,
  (SELECT max(v.version) FROM assistant.page_prompt_versions v WHERE(v.tenant_id,v.workspace_id,v.page)=(NEW.tenant_id,NEW.workspace_id,s.scope))
 FROM(SELECT 'application' scope UNION ALL
  SELECT 'tool:'||unnest(v.tools) FROM assistant.agent_versions v WHERE(v.agent_id,v.version)=(NEW.agent_id,NEW.agent_version)) s;
 RETURN NEW;
END$$;
ALTER FUNCTION assistant.pin_installation_instructions() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION assistant.pin_installation_instructions() FROM PUBLIC;
CREATE TRIGGER installation_instructions AFTER INSERT ON assistant.turns FOR EACH ROW EXECUTE FUNCTION assistant.pin_installation_instructions();

ALTER FUNCTION assistant.start_turn(uuid,bytea) RENAME TO start_turn_with_page_prompt;
REVOKE ALL ON FUNCTION assistant.start_turn_with_page_prompt(uuid,bytea) FROM openetrm_runtime;
CREATE FUNCTION assistant.start_turn(turn uuid,token bytea) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb:=assistant.start_turn_with_page_prompt(turn,token);application text;tools jsonb;
BEGIN
 IF result ? 'started' THEN
  SELECT v.instructions INTO application FROM assistant.turn_instruction_pins p LEFT JOIN assistant.page_prompt_versions v
   ON(v.tenant_id,v.workspace_id,v.page,v.version)=(p.tenant_id,p.workspace_id,p.scope,p.version) WHERE p.turn_id=turn AND p.scope='application';
  SELECT coalesce(jsonb_object_agg(substring(p.scope from 6),coalesce(v.instructions,'')),'{}'::jsonb) INTO tools
   FROM assistant.turn_instruction_pins p LEFT JOIN assistant.page_prompt_versions v
   ON(v.tenant_id,v.workspace_id,v.page,v.version)=(p.tenant_id,p.workspace_id,p.scope,p.version) WHERE p.turn_id=turn AND p.scope LIKE 'tool:%';
  result:=jsonb_set(result,'{started}',(result->'started')||jsonb_build_object('applicationPrompt',coalesce(application,''),'toolPrompts',tools));
 END IF;
 RETURN result;
END$$;
ALTER FUNCTION assistant.start_turn(uuid,bytea) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION assistant.start_turn(uuid,bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assistant.start_turn(uuid,bytea) TO openetrm_runtime;

-- Connectivity tests also use private configuration; their exact versions are retained with the model call.
CREATE TABLE assistant.test_prompt_pins(
 call_id uuid NOT NULL REFERENCES assistant.model_calls(id),tenant_id uuid NOT NULL,workspace_id uuid NOT NULL,scope text NOT NULL,
 version integer CHECK(version>0),PRIMARY KEY(call_id,scope),
 FOREIGN KEY(tenant_id,workspace_id,scope,version) REFERENCES assistant.page_prompt_versions
);
ALTER TABLE assistant.test_prompt_pins OWNER TO openetrm_security_owner;
ALTER TABLE assistant.test_prompt_pins ENABLE ROW LEVEL SECURITY;
ALTER TABLE assistant.test_prompt_pins FORCE ROW LEVEL SECURITY;
CREATE POLICY owner_access ON assistant.test_prompt_pins TO openetrm_security_owner USING(true) WITH CHECK(true);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON assistant.test_prompt_pins FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
ALTER FUNCTION assistant.open_test(uuid,uuid,text,integer,text,bigint) RENAME TO open_test_without_prompt;
REVOKE ALL ON FUNCTION assistant.open_test_without_prompt(uuid,uuid,text,integer,text,bigint) FROM openetrm_runtime;
DO $$DECLARE definition text;before text:='open_test.model';BEGIN
 definition:=pg_get_functiondef('assistant.open_test_without_prompt(uuid,uuid,text,integer,text,bigint)'::regprocedure);
 IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'assistant_prompt_upgrade: test parameter';END IF;
 EXECUTE replace(definition,before,'open_test_without_prompt.model');
END$$;
CREATE FUNCTION assistant.open_test(operation uuid,model uuid,reasoning text,output_limit integer,token_digest text,generation bigint) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb:=assistant.open_test_without_prompt(operation,model,reasoning,output_limit,token_digest,generation);c security.request_contexts;
 instructions text;question text;call uuid;
BEGIN
 IF NOT(result ? 'opened') THEN RETURN result;END IF;
 c:=assistant.actor();call:=(result->'opened'->>'call')::uuid;
 INSERT INTO assistant.test_prompt_pins SELECT call,c.tenant_id,c.workspace_id,s.scope,
  (SELECT max(v.version) FROM assistant.page_prompt_versions v WHERE(v.tenant_id,v.workspace_id,v.page)=(c.tenant_id,c.workspace_id,s.scope))
 FROM(VALUES('provider_test:instructions'),('provider_test:question')) s(scope);
 SELECT v.instructions INTO instructions FROM assistant.test_prompt_pins p LEFT JOIN assistant.page_prompt_versions v
  ON(v.tenant_id,v.workspace_id,v.page,v.version)=(p.tenant_id,p.workspace_id,p.scope,p.version) WHERE p.call_id=call AND p.scope='provider_test:instructions';
 SELECT v.instructions INTO question FROM assistant.test_prompt_pins p LEFT JOIN assistant.page_prompt_versions v
  ON(v.tenant_id,v.workspace_id,v.page,v.version)=(p.tenant_id,p.workspace_id,p.scope,p.version) WHERE p.call_id=call AND p.scope='provider_test:question';
 IF question IS NULL OR btrim(question)='' THEN RAISE EXCEPTION 'page_prompt_required';END IF;
 RETURN jsonb_set(result,'{opened}',(result->'opened')||jsonb_build_object('testInstructions',coalesce(instructions,''),'testQuestion',question));
END$$;
ALTER FUNCTION assistant.open_test(uuid,uuid,text,integer,text,bigint) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION assistant.open_test(uuid,uuid,text,integer,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assistant.open_test(uuid,uuid,text,integer,text,bigint) TO openetrm_runtime;
COMMIT;
