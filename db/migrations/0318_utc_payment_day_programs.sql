-- The managed compiler and retained-program reader use one UTC payment-day
-- contract. Existing bytes remain immutable; incompatible programs require
-- explicit review and replacement, never reinterpretation on read.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)","definition":"1c30a9b5805d6e4f2f2e4bde6a34d9e63828810f9b1456322a781eaaecc6c1d3","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.read_instrument_side_programs(uuid,uuid,uuid,timestamp with time zone)","definition":"a1cd6c7fa8911d4d29611c5ef96e8716088aae1e204401bc5e73f13919f2c760","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.seal_side_schedule_program(uuid,uuid,uuid,bytea)","definition":"16e24c9e1601bfe31af1ca4e40c794fad8b3dfc3ae6ca74c61f24a818bf21ee7","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.require_side_program_content(uuid,uuid,bytea)","definition":"50ec417e194704964227b8b076a2fc372df67b51458f91ca6e3c7edb1aec07de","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","enable_nestloop=off","jit=off"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"trading.side_program_document(uuid,uuid)","definition":"99fda8f00cd4e05c0de6b7d79f837947f901a73afd9ff0e99523c05d640cc4ae","volatility":"s"}]
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






DO $$
DECLARE signature regprocedure;body text;old_literal text;new_literal text;
BEGIN
 FOR signature,old_literal,new_literal IN SELECT * FROM (VALUES
  ('security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)'::regprocedure,'whole_term_side_blocks_v2','whole_term_side_blocks_v3'),
  ('trading.side_program_document(uuid,uuid)'::regprocedure,'booked_side_program_v1','booked_side_program_v2'),
  ('trading.require_side_program_content(uuid,uuid,bytea)'::regprocedure,'booked_side_program_v1','booked_side_program_v2'),
  ('security.seal_side_schedule_program(uuid,uuid,uuid,bytea)'::regprocedure,'booked_side_program_v1','booked_side_program_v2'),
  ('security.read_instrument_side_programs(uuid,uuid,uuid,timestamptz)'::regprocedure,'booked_side_program_v1','booked_side_program_v2')
 ) changes LOOP
  body=pg_get_functiondef(signature);
  IF position(quote_literal(old_literal) in body)=0 OR position(quote_literal(new_literal) in body)>0
  THEN RAISE EXCEPTION 'payment_day_program_predecessor';END IF;
  EXECUTE replace(body,quote_literal(old_literal),quote_literal(new_literal));
 END LOOP;
END$$;
ALTER TABLE trading.side_schedule_programs DROP CONSTRAINT side_schedule_programs_version_check;
-- NOT VALID preserves old rows without admitting another old-format write.
ALTER TABLE trading.side_schedule_programs ADD CONSTRAINT side_schedule_programs_version_check
 CHECK(version='booked_side_program_v2') NOT VALID;
COMMIT;
