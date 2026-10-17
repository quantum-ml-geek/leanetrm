-- Workspace access administration. Authentication/credential issuance is separate.
BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM security.role_grants) THEN RAISE EXCEPTION 'Existing grants require a verified workspace membership migration'; END IF;
END $$;
CREATE TABLE security.workspace_memberships (
 tenant_id uuid NOT NULL,workspace_id uuid NOT NULL,principal_id uuid NOT NULL REFERENCES security.principals(id),
 login_handle text NOT NULL CHECK(login_handle~'^[a-z][a-z0-9_]{0,47}$'),display_name text NOT NULL CHECK(btrim(display_name)<>'' AND length(display_name)<=80),
 enabled boolean NOT NULL,version integer NOT NULL CHECK(version>0),
 PRIMARY KEY(tenant_id,workspace_id,principal_id),UNIQUE(tenant_id,workspace_id,login_handle),
 FOREIGN KEY(tenant_id,workspace_id) REFERENCES security.workspaces(tenant_id,id)
);
-- Deliberately no inferred migration of existing grants/names. Operators must
-- supply verified memberships before enabling the replaced permission function.
CREATE TRIGGER guard_control_change BEFORE INSERT OR UPDATE OR DELETE ON security.workspace_memberships FOR EACH STATEMENT EXECUTE FUNCTION security.guard_control_change();
CREATE TABLE security.administration_audit (
 tenant_id uuid NOT NULL,workspace_id uuid NOT NULL,operation_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),
 target_id uuid NOT NULL REFERENCES security.principals(id),recorded_at ref_data.instant NOT NULL,request jsonb NOT NULL,before_state jsonb,after_state jsonb NOT NULL,
 PRIMARY KEY(tenant_id,workspace_id,operation_id),FOREIGN KEY(tenant_id,workspace_id) REFERENCES security.workspaces(tenant_id,id)
);
CREATE TRIGGER immutable_audit BEFORE UPDATE OR DELETE ON security.administration_audit FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
ALTER TABLE security.request_contexts ADD COLUMN administration boolean NOT NULL DEFAULT false;
CREATE OR REPLACE FUNCTION security.principal_has_permission(actor uuid,tenant uuid,workspace uuid,permission text,checked_at timestamptz)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM security.principals p JOIN security.workspace_memberships m ON m.principal_id=p.id
 JOIN security.role_grants g ON(g.principal_id,g.tenant_id,g.workspace_id)=(m.principal_id,m.tenant_id,m.workspace_id)
 JOIN security.role_permissions rp ON rp.role_id=g.role_id
 WHERE p.id=actor AND p.enabled AND m.enabled AND m.tenant_id=tenant AND m.workspace_id=workspace
 AND NOT g.revoked AND g.granted_from<=checked_at AND checked_at<g.granted_to AND rp.permission=principal_has_permission.permission);
$$;
CREATE FUNCTION security.use_administration_context(token uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 -- Take exclusive admission BEFORE the ordinary shared request lock. Mutations
 -- cannot deadlock by upgrading two previously admitted shared epoch locks.
 IF EXISTS(SELECT 1 FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user) THEN
  RAISE EXCEPTION 'Administration must be the first transaction admission' USING ERRCODE='42501';
 END IF;
 PERFORM 1 FROM security.epoch WHERE id=true FOR UPDATE;
 PERFORM security.use_context(token);
 IF NOT security.has_permission('ManageIdentities') OR NOT security.has_permission('ManageAccess') THEN RAISE EXCEPTION 'No current workspace administration permission' USING ERRCODE='42501'; END IF;
 UPDATE security.request_contexts SET administration=true WHERE id=token;
END $$;
CREATE FUNCTION security.member_description(tenant uuid,workspace uuid,principal uuid) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('id',m.principal_id,'login',m.login_handle,'name',m.display_name,'kind',p.kind,'enabled',m.enabled,'version',m.version,
 'roles',coalesce((SELECT jsonb_agg(r.code ORDER BY r.code) FROM security.role_grants g JOIN security.roles r ON r.id=g.role_id
 WHERE(g.tenant_id,g.workspace_id,g.principal_id)=(m.tenant_id,m.workspace_id,m.principal_id) AND NOT g.revoked AND g.granted_from<=clock_timestamp() AND clock_timestamp()<g.granted_to),'[]'::jsonb))
 FROM security.workspace_memberships m JOIN security.principals p ON p.id=m.principal_id
 WHERE(m.tenant_id,m.workspace_id,m.principal_id)=($1,$2,$3);
$$;
CREATE FUNCTION security.administration_directory() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts; result jsonb;
BEGIN
 IF NOT security.has_permission('ManageIdentities') OR NOT security.has_permission('ManageAccess') THEN RAISE EXCEPTION 'No administration access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 SELECT jsonb_build_object('members',coalesce((SELECT jsonb_agg(security.member_description(c.tenant_id,c.workspace_id,m.principal_id) ORDER BY m.display_name,m.principal_id)
 FROM security.workspace_memberships m WHERE(m.tenant_id,m.workspace_id)=(c.tenant_id,c.workspace_id)),'[]'::jsonb),
 'roles',(SELECT jsonb_agg(jsonb_build_object('code',r.code,'permissions',(SELECT jsonb_agg(rp.permission ORDER BY rp.permission) FROM security.role_permissions rp WHERE rp.role_id=r.id)) ORDER BY r.code) FROM security.roles r),
 'audit',coalesce((SELECT jsonb_agg(jsonb_build_object('operationId',a.operation_id,'at',a.recorded_at,'actor',a.actor_name,'action',a.request->>'action','before',a.before_state,'after',a.after_state) ORDER BY a.recorded_at DESC,a.operation_id)
 FROM(SELECT a.*,m.display_name actor_name FROM security.administration_audit a JOIN security.workspace_memberships m ON(m.tenant_id,m.workspace_id,m.principal_id)=(a.tenant_id,a.workspace_id,a.actor_id)
 WHERE(a.tenant_id,a.workspace_id)=(c.tenant_id,c.workspace_id) ORDER BY a.recorded_at DESC,a.operation_id LIMIT 100)a),'[]'::jsonb)) INTO result;
 IF NOT security.has_permission('ManageIdentities') OR NOT security.has_permission('ManageAccess') THEN RAISE EXCEPTION 'Administration access expired' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;
CREATE FUNCTION security.apply_administration(request jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts; previous security.administration_audit; member security.workspace_memberships;
 operation uuid; target uuid; action text; kind text; login text; name text; before_value jsonb; after_value jsonb; requested_roles text[]; desired_enabled boolean;
BEGIN
 IF NOT security.has_permission('ManageIdentities') OR NOT security.has_permission('ManageAccess') THEN RAISE EXCEPTION 'No administration access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user AND administration;
 IF NOT FOUND OR c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'Exclusive current administration context required' USING ERRCODE='42501'; END IF;
 operation=(request->>'operationId')::uuid;action=request->>'action';name=request->>'name';
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid THEN RAISE EXCEPTION 'admin_input' USING ERRCODE='P0001'; END IF;
 SELECT * INTO previous FROM security.administration_audit WHERE(tenant_id,workspace_id,operation_id)=(c.tenant_id,c.workspace_id,operation);
 IF FOUND THEN
  IF previous.actor_id<>c.actor_id OR previous.request<>request THEN RAISE EXCEPTION 'admin_conflict' USING ERRCODE='P0001'; END IF;
  RETURN previous.after_state;
 END IF;
 IF name IS NULL OR btrim(name)='' OR length(name)>80 OR jsonb_typeof(request->'roles') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'admin_input' USING ERRCODE='P0001'; END IF;
 SELECT array_agg(value ORDER BY value) INTO requested_roles FROM jsonb_array_elements_text(request->'roles');
 IF coalesce(array_length(requested_roles,1),0)>6 OR EXISTS(SELECT 1 FROM unnest(requested_roles) role WHERE NOT EXISTS(SELECT 1 FROM security.roles WHERE code=role)) OR (SELECT count(*) FROM unnest(requested_roles))<>(SELECT count(DISTINCT x) FROM unnest(requested_roles)x) THEN RAISE EXCEPTION 'admin_input' USING ERRCODE='P0001'; END IF;
 IF action='create' THEN
  login=request->>'login';kind=request->>'kind';
  IF login IS NULL OR login!~'^[a-z][a-z0-9_]{0,47}$' OR kind IS NULL OR kind NOT IN('human','service','agent') OR coalesce(array_length(requested_roles,1),0)=0 THEN RAISE EXCEPTION 'admin_input' USING ERRCODE='P0001'; END IF;
  IF(SELECT count(*) FROM security.workspace_memberships WHERE(tenant_id,workspace_id)=(c.tenant_id,c.workspace_id))>=256 THEN RAISE EXCEPTION 'admin_limit' USING ERRCODE='P0001'; END IF;
  target=gen_random_uuid();desired_enabled=true;
  INSERT INTO security.principals VALUES(target,kind,true);
  -- Registration only: this preview issuer never validates a real credential.
  INSERT INTO security.identity_bindings VALUES('https://preview.invalid',login,target,CASE kind WHEN 'human' THEN 'human_interactive' WHEN 'service' THEN 'service_credential' ELSE 'agent_credential' END);
  INSERT INTO security.workspace_memberships VALUES(c.tenant_id,c.workspace_id,target,login,name,true,1);
 ELSIF action='update' THEN
  target=(request->>'id')::uuid;desired_enabled=(request->>'enabled')::boolean;
  SELECT * INTO member FROM security.workspace_memberships WHERE(tenant_id,workspace_id,principal_id)=(c.tenant_id,c.workspace_id,target) FOR UPDATE;
  IF NOT FOUND OR member.version IS DISTINCT FROM (request->>'expectedVersion')::integer THEN RAISE EXCEPTION 'admin_conflict' USING ERRCODE='P0001'; END IF;
  IF desired_enabled IS NULL THEN RAISE EXCEPTION 'admin_input' USING ERRCODE='P0001'; END IF;
  before_value=security.member_description(c.tenant_id,c.workspace_id,target);
  IF NOT(desired_enabled AND 'access_administrator'=ANY(coalesce(requested_roles,ARRAY[]::text[]))) AND security.principal_has_permission(target,c.tenant_id,c.workspace_id,'ManageAccess',clock_timestamp())
   AND NOT EXISTS(SELECT 1 FROM security.workspace_memberships m JOIN security.principals p ON p.id=m.principal_id WHERE(m.tenant_id,m.workspace_id)=(c.tenant_id,c.workspace_id) AND m.principal_id<>target AND p.kind IN('human','service') AND security.principal_has_permission(m.principal_id,c.tenant_id,c.workspace_id,'ManageAccess',clock_timestamp()) AND security.principal_has_permission(m.principal_id,c.tenant_id,c.workspace_id,'ManageIdentities',clock_timestamp())) THEN
   RAISE EXCEPTION 'last_administrator' USING ERRCODE='P0001';
  END IF;
  IF target=c.actor_id AND NOT(desired_enabled AND 'access_administrator'=ANY(coalesce(requested_roles,ARRAY[]::text[]))) THEN RAISE EXCEPTION 'self_access_change' USING ERRCODE='P0001'; END IF;
  UPDATE security.workspace_memberships SET display_name=name,enabled=desired_enabled,version=version+1 WHERE(tenant_id,workspace_id,principal_id)=(c.tenant_id,c.workspace_id,target);
  UPDATE security.role_grants SET revoked=true WHERE(tenant_id,workspace_id,principal_id)=(c.tenant_id,c.workspace_id,target) AND NOT revoked;
 ELSE RAISE EXCEPTION 'admin_input' USING ERRCODE='P0001';END IF;
 INSERT INTO security.role_grants(id,principal_id,role_id,tenant_id,workspace_id,granted_from,granted_to,revoked)
 SELECT gen_random_uuid(),target,id,c.tenant_id,c.workspace_id,clock_timestamp(),TIMESTAMPTZ '9999-12-31 00:00:00+00',false FROM security.roles WHERE code=ANY(requested_roles);
 after_value=security.member_description(c.tenant_id,c.workspace_id,target);
 INSERT INTO security.administration_audit VALUES(c.tenant_id,c.workspace_id,operation,c.actor_id,target,clock_timestamp(),request,before_value,after_value);
 IF NOT security.has_permission('ManageIdentities') OR NOT security.has_permission('ManageAccess') THEN RAISE EXCEPTION 'Administration access expired during change' USING ERRCODE='42501'; END IF;
 RETURN after_value;
END $$;
ALTER TABLE security.workspace_memberships OWNER TO openetrm_security_owner;
ALTER TABLE security.administration_audit OWNER TO openetrm_security_owner;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='security' AND p.proname IN('use_administration_context','member_description','administration_directory','apply_administration') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f.signature);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.signature);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION security.use_administration_context(uuid),security.administration_directory(),security.apply_administration(jsonb) TO openetrm_runtime;
ALTER TABLE security.workspace_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.workspace_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE security.administration_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE security.administration_audit FORCE ROW LEVEL SECURITY;
CREATE FUNCTION security.current_permissions() RETURNS text[] LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT ARRAY(SELECT code FROM security.permissions WHERE security.has_permission(code) ORDER BY code);
$$;
ALTER FUNCTION security.current_permissions() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.current_permissions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.current_permissions() TO openetrm_runtime;
COMMIT;
