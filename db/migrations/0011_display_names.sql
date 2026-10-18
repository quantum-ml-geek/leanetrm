-- Stored display names for curves and roles. Names are presentation labels;
-- identity remains the code. Existing curve rows have no defined name, so the
-- NOT NULL step deliberately fails on a database that already holds curves.
BEGIN;
ALTER TABLE market_data.curves ADD COLUMN name text
  CHECK (name = btrim(name) AND name <> '' AND length(name) <= 80);
ALTER TABLE market_data.curves ALTER COLUMN name SET NOT NULL;
ALTER TABLE market_data.curves ADD UNIQUE (catalog_id, revision_id, name);
ALTER TABLE market_data.rate_curves ADD COLUMN name text
  CHECK (name = btrim(name) AND name <> '' AND length(name) <= 80);
ALTER TABLE market_data.rate_curves ALTER COLUMN name SET NOT NULL;
ALTER TABLE market_data.rate_curves ADD UNIQUE (catalog_id, revision_id, name);

ALTER TABLE security.roles ADD COLUMN name text
  CHECK (name = btrim(name) AND name <> '' AND length(name) <= 80) UNIQUE;
UPDATE security.roles SET name = CASE code
  WHEN 'viewer' THEN 'Viewer'
  WHEN 'trader' THEN 'Trader'
  WHEN 'risk_analyst' THEN 'Risk analyst'
  WHEN 'market_data_editor' THEN 'Market data editor'
  WHEN 'market_data_approver' THEN 'Market data approver'
  WHEN 'access_administrator' THEN 'Access administrator' END;
ALTER TABLE security.roles ALTER COLUMN name SET NOT NULL;

-- Same authority checks as 0010; the role list now carries its stored name.
CREATE OR REPLACE FUNCTION security.administration_directory() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts; result jsonb;
BEGIN
 IF NOT security.has_permission('ManageIdentities') OR NOT security.has_permission('ManageAccess') THEN RAISE EXCEPTION 'No administration access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 SELECT jsonb_build_object('members',coalesce((SELECT jsonb_agg(security.member_description(c.tenant_id,c.workspace_id,m.principal_id) ORDER BY m.display_name,m.principal_id)
 FROM security.workspace_memberships m WHERE(m.tenant_id,m.workspace_id)=(c.tenant_id,c.workspace_id)),'[]'::jsonb),
 'roles',(SELECT jsonb_agg(jsonb_build_object('code',r.code,'name',r.name,'permissions',(SELECT jsonb_agg(rp.permission ORDER BY rp.permission) FROM security.role_permissions rp WHERE rp.role_id=r.id)) ORDER BY r.name) FROM security.roles r),
 'audit',coalesce((SELECT jsonb_agg(jsonb_build_object('operationId',a.operation_id,'at',a.recorded_at,'actor',a.actor_name,'action',a.request->>'action','before',a.before_state,'after',a.after_state) ORDER BY a.recorded_at DESC,a.operation_id)
 FROM(SELECT a.*,m.display_name actor_name FROM security.administration_audit a JOIN security.workspace_memberships m ON(m.tenant_id,m.workspace_id,m.principal_id)=(a.tenant_id,a.workspace_id,a.actor_id)
 WHERE(a.tenant_id,a.workspace_id)=(c.tenant_id,c.workspace_id) ORDER BY a.recorded_at DESC,a.operation_id LIMIT 100)a),'[]'::jsonb)) INTO result;
 IF NOT security.has_permission('ManageIdentities') OR NOT security.has_permission('ManageAccess') THEN RAISE EXCEPTION 'Administration access expired' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;
COMMIT;
