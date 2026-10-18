-- Retain the authenticated provider namespace for workspace account creation.
BEGIN;
ALTER TABLE security.request_contexts ADD COLUMN identity_issuer text;
ALTER TABLE security.request_contexts ADD COLUMN identity_subject text;
ALTER TABLE security.request_contexts ADD FOREIGN KEY(identity_issuer,identity_subject) REFERENCES security.identity_bindings(issuer,subject);
CREATE OR REPLACE FUNCTION security.issue_context(issuer text,subject text,login_kind text,tenant uuid,workspace uuid,delegation uuid,runtime_login name,ttl_seconds integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;token uuid;
BEGIN
 IF ttl_seconds IS NULL OR ttl_seconds<1 OR ttl_seconds>300 OR runtime_login IS NULL OR NOT pg_has_role(runtime_login,'openetrm_runtime','MEMBER') THEN RAISE EXCEPTION 'Invalid request context' USING ERRCODE='42501'; END IF;
 SELECT p.id INTO actor FROM security.identity_bindings b JOIN security.principals p ON p.id=b.principal_id WHERE b.issuer=issue_context.issuer AND b.subject=issue_context.subject AND b.login_kind=issue_context.login_kind AND p.enabled;
 IF actor IS NULL THEN RAISE EXCEPTION 'Unbound or disabled identity' USING ERRCODE='42501'; END IF;
 token=gen_random_uuid();
 INSERT INTO security.request_contexts(id,actor_id,tenant_id,workspace_id,delegation_id,runtime_login,expires_at,identity_issuer,identity_subject) VALUES(token,actor,tenant,workspace,delegation,runtime_login,clock_timestamp()+make_interval(secs=>ttl_seconds),issuer,subject);
 RETURN token;
END $$;
CREATE OR REPLACE FUNCTION security.apply_administration(request jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
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
  INSERT INTO security.identity_bindings VALUES(c.identity_issuer,login,target,CASE kind WHEN 'human' THEN 'human_interactive' WHEN 'service' THEN 'service_credential' ELSE 'agent_credential' END);
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
COMMIT;
