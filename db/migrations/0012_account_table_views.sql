-- Presentation layouts belong to the current account and workspace.
BEGIN;
CREATE SCHEMA presentation;
CREATE TABLE presentation.table_views (
 tenant_id uuid NOT NULL, workspace_id uuid NOT NULL, principal_id uuid NOT NULL REFERENCES security.principals(id),
 table_key text NOT NULL CHECK(table_key='blotter'), name text NOT NULL CHECK(length(name) BETWEEN 1 AND 60 AND btrim(name)=name),
 version uuid NOT NULL, layout jsonb NOT NULL CHECK(jsonb_typeof(layout)='object' AND octet_length(layout::text)<=24000),
 PRIMARY KEY(tenant_id,workspace_id,principal_id,table_key,name),
 FOREIGN KEY(tenant_id,workspace_id) REFERENCES security.workspaces(tenant_id,id)
);
CREATE FUNCTION security.table_view_identity() RETURNS TABLE(tenant_id uuid,workspace_id uuid,principal_id uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT c.tenant_id,c.workspace_id,c.actor_id FROM security.request_contexts c
 JOIN security.principals p ON p.id=c.actor_id AND p.kind='human'
 WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned()
 AND c.runtime_login=session_user AND security.has_permission('ReadTrades');
$$;
ALTER FUNCTION security.table_view_identity() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.table_view_identity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.table_view_identity() TO openetrm_runtime;
ALTER TABLE presentation.table_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE presentation.table_views FORCE ROW LEVEL SECURITY;
CREATE POLICY own_layout ON presentation.table_views TO openetrm_runtime
 USING (EXISTS(SELECT 1 FROM security.table_view_identity() i WHERE(i.tenant_id,i.workspace_id,i.principal_id)=(table_views.tenant_id,table_views.workspace_id,table_views.principal_id)))
 WITH CHECK (EXISTS(SELECT 1 FROM security.table_view_identity() i WHERE(i.tenant_id,i.workspace_id,i.principal_id)=(table_views.tenant_id,table_views.workspace_id,table_views.principal_id)));
GRANT USAGE ON SCHEMA presentation TO openetrm_runtime;
GRANT SELECT,INSERT,UPDATE,DELETE ON presentation.table_views TO openetrm_runtime;
COMMIT;
