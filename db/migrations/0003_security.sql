-- Current scoped security and RLS. No sign-in/provider integration or public API.
BEGIN;
CREATE ROLE openetrm_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
CREATE ROLE openetrm_authenticator NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
-- Isolated owner for narrowly granted SECURITY DEFINER routines. Never a runtime
-- login, and never granted to runtime/authenticator roles.
CREATE ROLE openetrm_security_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT BYPASSRLS;
CREATE SCHEMA security;
CREATE TABLE security.tenants (id uuid PRIMARY KEY, code ref_data.code NOT NULL UNIQUE);
CREATE TABLE security.workspaces (
  tenant_id uuid NOT NULL REFERENCES security.tenants(id), id uuid NOT NULL,
  code ref_data.code NOT NULL, PRIMARY KEY (tenant_id,id), UNIQUE (tenant_id,code)
);
CREATE TABLE security.principals (
  id uuid PRIMARY KEY, kind text NOT NULL CHECK (kind IN ('human','service','agent')),
  enabled boolean NOT NULL
);
CREATE TABLE security.identity_bindings (
  issuer text NOT NULL CHECK (btrim(issuer) <> ''), subject text NOT NULL CHECK (btrim(subject) <> ''),
  principal_id uuid NOT NULL REFERENCES security.principals(id),
  login_kind text NOT NULL CHECK (login_kind IN ('human_interactive','service_credential','agent_credential')),
  PRIMARY KEY (issuer,subject)
);
CREATE TABLE security.permissions (code text PRIMARY KEY);
INSERT INTO security.permissions VALUES
 ('ReadMarketData'),('WriteMarketDefinitions'),('SealMarketDefinitions'),('ImportObservations'),
 ('WriteReferenceData'),('SealReferenceData'),('ManageIdentities'),('ManageAccess'),('CreateDelegations'),
 ('BookTrade'),('AmendTrade'),('RunValuation'),('RunScenario'),('ApproveMarketData'),('PublishMarketData');
CREATE TABLE security.roles (id uuid PRIMARY KEY, code ref_data.code NOT NULL UNIQUE);
CREATE TABLE security.role_permissions (
  role_id uuid NOT NULL REFERENCES security.roles(id), permission text NOT NULL REFERENCES security.permissions(code),
  PRIMARY KEY (role_id,permission)
);
CREATE TABLE security.role_grants (
  id uuid PRIMARY KEY, principal_id uuid NOT NULL REFERENCES security.principals(id),
  role_id uuid NOT NULL REFERENCES security.roles(id), tenant_id uuid NOT NULL, workspace_id uuid NOT NULL,
  granted_from ref_data.instant NOT NULL, granted_to timestamptz NOT NULL,
  revoked boolean NOT NULL,
  FOREIGN KEY (tenant_id,workspace_id) REFERENCES security.workspaces(tenant_id,id),
  CHECK (isfinite(granted_to) AND granted_to <= TIMESTAMPTZ '9999-12-31 00:00:00+00' AND granted_from < granted_to)
);
CREATE INDEX role_grants_lookup ON security.role_grants(principal_id,tenant_id,workspace_id) WHERE NOT revoked;
CREATE TABLE security.agent_delegations (
  id uuid PRIMARY KEY, agent_id uuid NOT NULL REFERENCES security.principals(id),
  delegator_id uuid NOT NULL REFERENCES security.principals(id), tenant_id uuid NOT NULL, workspace_id uuid NOT NULL,
  granted_from ref_data.instant NOT NULL, granted_to timestamptz NOT NULL,
  revoked boolean NOT NULL, CHECK (agent_id <> delegator_id),
  FOREIGN KEY (tenant_id,workspace_id) REFERENCES security.workspaces(tenant_id,id),
  CHECK (isfinite(granted_to) AND granted_to <= TIMESTAMPTZ '9999-12-31 00:00:00+00' AND granted_from < granted_to)
);
CREATE TABLE security.delegation_permissions (
  delegation_id uuid NOT NULL REFERENCES security.agent_delegations(id),
  permission text NOT NULL REFERENCES security.permissions(code), PRIMARY KEY (delegation_id,permission)
);
-- Ownership/explicit reference sharing is relational. An unmapped catalog is inaccessible.
CREATE TABLE security.market_catalog_scopes (
  catalog_id uuid PRIMARY KEY REFERENCES market_data.catalogs(id), tenant_id uuid NOT NULL, workspace_id uuid NOT NULL,
  FOREIGN KEY (tenant_id,workspace_id) REFERENCES security.workspaces(tenant_id,id)
);
CREATE TABLE security.reference_catalog_scopes (
  catalog_id uuid NOT NULL REFERENCES ref_data.catalogs(id), tenant_id uuid NOT NULL, workspace_id uuid NOT NULL,
  access_mode text NOT NULL CHECK (access_mode IN ('owner','read_only')),
  PRIMARY KEY (catalog_id,tenant_id,workspace_id),
  FOREIGN KEY (tenant_id,workspace_id) REFERENCES security.workspaces(tenant_id,id)
);
CREATE UNIQUE INDEX reference_catalog_owner ON security.reference_catalog_scopes(catalog_id) WHERE access_mode='owner';
CREATE TABLE security.epoch (id boolean PRIMARY KEY CHECK (id), generation bigint NOT NULL);
INSERT INTO security.epoch VALUES (true,0);
-- Private one-transaction capabilities. Only the trusted authenticator can issue.
CREATE TABLE security.request_contexts (
  id uuid PRIMARY KEY, actor_id uuid NOT NULL REFERENCES security.principals(id),
  tenant_id uuid NOT NULL, workspace_id uuid NOT NULL, delegation_id uuid REFERENCES security.agent_delegations(id),
  runtime_login name NOT NULL, expires_at ref_data.instant NOT NULL,
  backend_pid integer, transaction_id xid8,
  FOREIGN KEY (tenant_id,workspace_id) REFERENCES security.workspaces(tenant_id,id),
  CHECK ((backend_pid IS NULL) = (transaction_id IS NULL)), UNIQUE (backend_pid,transaction_id)
);

-- Templates install no principals, credentials, grants or default administrator.
INSERT INTO security.roles VALUES
 ('a0000000-0000-0000-0000-000000000001','viewer'),
 ('a0000000-0000-0000-0000-000000000002','trader'),
 ('a0000000-0000-0000-0000-000000000003','risk_analyst'),
 ('a0000000-0000-0000-0000-000000000004','market_data_editor'),
 ('a0000000-0000-0000-0000-000000000005','market_data_approver'),
 ('a0000000-0000-0000-0000-000000000006','access_administrator');
INSERT INTO security.role_permissions
SELECT id,'ReadMarketData' FROM security.roles WHERE code <> 'access_administrator';
INSERT INTO security.role_permissions SELECT id,p FROM security.roles CROSS JOIN
  (VALUES ('BookTrade'),('AmendTrade'),('CreateDelegations')) AS x(p) WHERE code='trader';
INSERT INTO security.role_permissions SELECT id,p FROM security.roles CROSS JOIN
  (VALUES ('RunValuation'),('RunScenario'),('CreateDelegations')) AS x(p) WHERE code='risk_analyst';
INSERT INTO security.role_permissions SELECT id,p FROM security.roles CROSS JOIN
  (VALUES ('WriteMarketDefinitions'),('ImportObservations'),('WriteReferenceData'),('CreateDelegations')) AS x(p) WHERE code='market_data_editor';
INSERT INTO security.role_permissions SELECT id,p FROM security.roles CROSS JOIN
  (VALUES ('SealMarketDefinitions'),('SealReferenceData'),('ApproveMarketData'),('PublishMarketData')) AS x(p) WHERE code='market_data_approver';
INSERT INTO security.role_permissions SELECT id,p FROM security.roles CROSS JOIN
  (VALUES ('ManageIdentities'),('ManageAccess'),('CreateDelegations')) AS x(p) WHERE code='access_administrator';

-- Every control-plane mutation conflicts with an active request's epoch lock.
-- Coarse first implementation; no scalability claim. Runtime cannot write these tables.
CREATE FUNCTION security.guard_control_change() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  UPDATE security.epoch SET generation=generation+1 WHERE id=true;
  RETURN NULL;
END;
$$;
CREATE FUNCTION security.validate_binding() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE k text;
BEGIN
  SELECT kind INTO k FROM security.principals WHERE id=NEW.principal_id;
  IF NEW.login_kind IS DISTINCT FROM (CASE k WHEN 'human' THEN 'human_interactive'
      WHEN 'service' THEN 'service_credential' WHEN 'agent' THEN 'agent_credential' END) THEN
    RAISE EXCEPTION 'Identity login kind must match principal kind' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER validate_binding BEFORE INSERT OR UPDATE ON security.identity_bindings
  FOR EACH ROW EXECUTE FUNCTION security.validate_binding();
CREATE FUNCTION security.guard_principal_kind() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF NEW.id <> OLD.id OR NEW.kind <> OLD.kind THEN
    RAISE EXCEPTION 'Principal identity and kind are immutable' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER guard_principal_kind BEFORE UPDATE ON security.principals
  FOR EACH ROW EXECUTE FUNCTION security.guard_principal_kind();
CREATE FUNCTION security.validate_delegation() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM security.principals WHERE id=NEW.agent_id AND kind='agent') OR
     NOT EXISTS (SELECT 1 FROM security.principals WHERE id=NEW.delegator_id AND kind IN ('human','service')) THEN
    RAISE EXCEPTION 'Delegation requires agent and non-agent identities' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER validate_delegation BEFORE INSERT OR UPDATE ON security.agent_delegations
  FOR EACH ROW EXECUTE FUNCTION security.validate_delegation();
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['tenants','workspaces','principals','identity_bindings','permissions','roles',
      'role_permissions','role_grants','agent_delegations','delegation_permissions','market_catalog_scopes','reference_catalog_scopes'] LOOP
    EXECUTE format('CREATE TRIGGER guard_control_change BEFORE INSERT OR UPDATE OR DELETE ON security.%I FOR EACH STATEMENT EXECUTE FUNCTION security.guard_control_change()',t);
  END LOOP;
END;
$$;

CREATE FUNCTION security.issue_context(issuer text, subject text, login_kind text,
  tenant uuid, workspace uuid, delegation uuid, runtime_login name, ttl_seconds integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid; token uuid;
BEGIN
  -- Parameters are VERIFIED identity claims from the isolated authenticator,
  -- never an end-user principal ID or an LLM's asserted identity.
  IF ttl_seconds IS NULL OR ttl_seconds < 1 OR ttl_seconds > 300 OR runtime_login IS NULL OR
      NOT pg_has_role(runtime_login,'openetrm_runtime','MEMBER') THEN
    RAISE EXCEPTION 'Invalid request context lifetime/runtime login' USING ERRCODE='42501';
  END IF;
  SELECT p.id INTO actor FROM security.identity_bindings b JOIN security.principals p ON p.id=b.principal_id
    WHERE b.issuer=issue_context.issuer AND b.subject=issue_context.subject AND b.login_kind=issue_context.login_kind AND p.enabled;
  IF actor IS NULL THEN RAISE EXCEPTION 'Unbound or disabled verified identity' USING ERRCODE='42501'; END IF;
  token=gen_random_uuid();
  INSERT INTO security.request_contexts VALUES
    (token,actor,tenant,workspace,delegation,runtime_login,clock_timestamp()+make_interval(secs=>ttl_seconds),NULL,NULL);
  RETURN token;
END;
$$;
CREATE FUNCTION security.use_context(token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'Runtime requests require read committed isolation' USING ERRCODE='25000';
  END IF;
  PERFORM 1 FROM security.epoch WHERE id=true FOR SHARE;
  SELECT * INTO c FROM security.request_contexts WHERE id=token FOR UPDATE;
  -- Check actual trusted clock AFTER every admission lock wait, not statement
  -- arrival time. A blocked/slow statement must not revive an expired token.
  IF c.id IS NULL OR c.backend_pid IS NOT NULL OR c.runtime_login <> session_user OR c.expires_at <= clock_timestamp() THEN
    RAISE EXCEPTION 'Invalid, expired or already bound request context' USING ERRCODE='42501';
  END IF;
  UPDATE security.request_contexts SET backend_pid=pg_backend_pid(),transaction_id=pg_current_xact_id()
    WHERE id=token;
END;
$$;
CREATE FUNCTION security.principal_has_permission(actor uuid, tenant uuid, workspace uuid, permission text, checked_at timestamptz)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT EXISTS (SELECT 1 FROM security.principals p JOIN security.role_grants g ON g.principal_id=p.id
    JOIN security.role_permissions rp ON rp.role_id=g.role_id
    WHERE p.id=actor AND p.enabled AND g.tenant_id=tenant AND g.workspace_id=workspace
      AND NOT g.revoked AND g.granted_from <= checked_at AND checked_at < g.granted_to
      AND rp.permission=principal_has_permission.permission);
$$;
CREATE FUNCTION security.has_permission(permission text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts; kind text; d security.agent_delegations;
  checked_at timestamptz := clock_timestamp();
BEGIN
  SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid()
    AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user AND expires_at > checked_at;
  IF c.id IS NULL OR NOT security.principal_has_permission(c.actor_id,c.tenant_id,c.workspace_id,permission,checked_at) THEN RETURN false; END IF;
  SELECT p.kind INTO kind FROM security.principals p WHERE p.id=c.actor_id;
  IF kind='agent' THEN
    SELECT * INTO d FROM security.agent_delegations WHERE id=c.delegation_id;
    RETURN d.id IS NOT NULL AND d.agent_id=c.actor_id AND d.tenant_id=c.tenant_id AND d.workspace_id=c.workspace_id
      AND NOT d.revoked AND d.granted_from <= checked_at AND checked_at < d.granted_to
      AND security.principal_has_permission(d.delegator_id,c.tenant_id,c.workspace_id,permission,checked_at)
      AND security.principal_has_permission(d.delegator_id,c.tenant_id,c.workspace_id,'CreateDelegations',checked_at)
      AND EXISTS (SELECT 1 FROM security.delegation_permissions dp WHERE dp.delegation_id=d.id AND dp.permission=has_permission.permission);
  END IF;
  RETURN c.delegation_id IS NULL;
END;
$$;
CREATE FUNCTION security.market_access(catalog uuid, permission text) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.has_permission(permission) AND EXISTS (
   SELECT 1 FROM security.request_contexts c JOIN security.market_catalog_scopes s
     ON (s.tenant_id,s.workspace_id)=(c.tenant_id,c.workspace_id)
   WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned()
     AND c.runtime_login=session_user AND s.catalog_id=catalog);
$$;
CREATE FUNCTION security.reference_access(catalog uuid, permission text) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.has_permission(permission) AND EXISTS (
   SELECT 1 FROM security.request_contexts c JOIN security.reference_catalog_scopes s
     ON (s.tenant_id,s.workspace_id)=(c.tenant_id,c.workspace_id)
   WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned()
     AND c.runtime_login=session_user AND s.catalog_id=catalog
     AND (permission='ReadMarketData' OR s.access_mode='owner'));
$$;

-- Policies apply to every market/reference table, including relationships/history.
DO $$
DECLARE t record; key_column text; permission text; check_sql text;
BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='market_data' LOOP
   key_column=CASE t.tablename WHEN 'catalogs' THEN 'id' ELSE 'catalog_id' END;
   permission=CASE t.tablename WHEN 'observations' THEN 'ImportObservations' ELSE 'WriteMarketDefinitions' END;
   EXECUTE format('ALTER TABLE market_data.%I ENABLE ROW LEVEL SECURITY',t.tablename);
   EXECUTE format('ALTER TABLE market_data.%I FORCE ROW LEVEL SECURITY',t.tablename);
   EXECUTE format('CREATE POLICY scoped_read ON market_data.%I FOR SELECT TO openetrm_runtime USING (security.market_access(%I,''ReadMarketData''))',t.tablename,key_column);
   IF t.tablename <> 'catalogs' THEN
     check_sql=format('security.market_access(%I,%L)',key_column,permission);
     IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='market_data' AND table_name=t.tablename AND column_name='reference_catalog_id') THEN
       check_sql=check_sql || ' AND (reference_catalog_id IS NULL OR security.reference_access(reference_catalog_id,''ReadMarketData''))';
     END IF;
     EXECUTE format('CREATE POLICY scoped_insert ON market_data.%I FOR INSERT TO openetrm_runtime WITH CHECK (%s)',t.tablename,check_sql);
     EXECUTE format('GRANT INSERT ON market_data.%I TO openetrm_runtime',t.tablename);
   END IF;
 END LOOP;
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='ref_data' LOOP
   key_column=CASE t.tablename WHEN 'catalogs' THEN 'id' ELSE 'catalog_id' END;
   EXECUTE format('ALTER TABLE ref_data.%I ENABLE ROW LEVEL SECURITY',t.tablename);
   EXECUTE format('ALTER TABLE ref_data.%I FORCE ROW LEVEL SECURITY',t.tablename);
   EXECUTE format('CREATE POLICY scoped_read ON ref_data.%I FOR SELECT TO openetrm_runtime USING (security.reference_access(%I,''ReadMarketData''))',t.tablename,key_column);
   IF t.tablename NOT IN ('catalogs','revisions') THEN
     EXECUTE format('CREATE POLICY scoped_insert ON ref_data.%I FOR INSERT TO openetrm_runtime WITH CHECK (security.reference_access(%I,''WriteReferenceData''))',t.tablename,key_column);
     EXECUTE format('GRANT INSERT ON ref_data.%I TO openetrm_runtime',t.tablename);
   END IF;
 END LOOP;
END;
$$;
CREATE POLICY definition_generation ON market_data.revisions FOR UPDATE TO openetrm_runtime
 USING (security.market_access(catalog_id,'WriteMarketDefinitions'))
 WITH CHECK (security.market_access(catalog_id,'WriteMarketDefinitions'));
CREATE POLICY definition_lock ON ref_data.revisions FOR UPDATE TO openetrm_runtime
 USING (security.reference_access(catalog_id,'WriteReferenceData'))
 WITH CHECK (security.reference_access(catalog_id,'WriteReferenceData'));
GRANT UPDATE (generation) ON market_data.revisions TO openetrm_runtime;
GRANT UPDATE (created_at) ON ref_data.revisions TO openetrm_runtime;

-- No raw state-column UPDATE privilege; freeze is a permission-checked operation.
CREATE FUNCTION security.seal_market_revision(catalog uuid, revision uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE reference_catalog uuid;
BEGIN
  IF NOT security.market_access(catalog,'SealMarketDefinitions') THEN
    RAISE EXCEPTION 'No current sealing permission' USING ERRCODE='42501';
  END IF;
  SELECT reference_catalog_id INTO reference_catalog FROM market_data.revisions WHERE catalog_id=catalog AND id=revision;
  IF NOT security.reference_access(reference_catalog,'ReadMarketData') THEN
    RAISE EXCEPTION 'Reference scope is not accessible' USING ERRCODE='42501';
  END IF;
  UPDATE market_data.revisions SET state='sealed' WHERE catalog_id=catalog AND id=revision;
  IF NOT FOUND THEN RAISE EXCEPTION 'Revision is absent' USING ERRCODE='55000'; END IF;
END;
$$;

REVOKE ALL ON SCHEMA security FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA security FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA security FROM PUBLIC;
GRANT USAGE ON SCHEMA security,ref_data,market_data TO openetrm_runtime;
GRANT USAGE ON SCHEMA security TO openetrm_authenticator;
GRANT SELECT ON ALL TABLES IN SCHEMA ref_data,market_data TO openetrm_runtime;
GRANT EXECUTE ON FUNCTION security.issue_context(text,text,text,uuid,uuid,uuid,name,integer) TO openetrm_authenticator;
GRANT EXECUTE ON FUNCTION security.use_context(uuid),security.has_permission(text),security.market_access(uuid,text),
 security.reference_access(uuid,text),security.seal_market_revision(uuid,uuid) TO openetrm_runtime;
GRANT USAGE ON SCHEMA security,ref_data,market_data TO openetrm_security_owner;
GRANT SELECT ON ALL TABLES IN SCHEMA ref_data,market_data TO openetrm_security_owner;
GRANT UPDATE (state) ON market_data.revisions TO openetrm_security_owner;
GRANT EXECUTE ON FUNCTION market_data.validate_revision(uuid,uuid) TO openetrm_security_owner;
DO $$
DECLARE t record; f record;
BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='security' LOOP
   EXECUTE format('ALTER TABLE security.%I OWNER TO openetrm_security_owner',t.tablename);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='security' LOOP
   EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f.signature);
 END LOOP;
END;
$$;
COMMENT ON TABLE security.request_contexts IS
 'Private capabilities issued only after trusted authentication; one transaction, exact DB login, max five minutes. Not market knowledge context.';
COMMIT;
