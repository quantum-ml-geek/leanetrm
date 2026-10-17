-- Commit-certified market inputs and exact immutable definition/reference bundles.
-- Install before sealing market bundles/importing observations. No inferred backfill.
BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM market_data.revisions WHERE state='sealed') OR EXISTS(SELECT 1 FROM market_data.observations) THEN
  RAISE EXCEPTION 'Existing market data requires verified migration evidence';
 END IF;
END $$;
CREATE TABLE market_data.revision_periods (
 catalog_id uuid NOT NULL,revision_id uuid NOT NULL,effective_from date NOT NULL,effective_to date NOT NULL,
 PRIMARY KEY(catalog_id,revision_id),FOREIGN KEY(catalog_id,revision_id) REFERENCES market_data.revisions(catalog_id,id),
 CHECK(isfinite(effective_from) AND isfinite(effective_to) AND DATE '0001-01-01'<=effective_from AND effective_from<effective_to AND effective_to<=DATE '9999-12-31')
);
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.revision_periods FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
ALTER TABLE market_data.observations ADD UNIQUE(catalog_id,id,definition_revision_id);
CREATE TABLE market_data.knowledge_events (
 catalog_id uuid NOT NULL,event_order integer NOT NULL,revision_id uuid NOT NULL,observation_id uuid,publication_xid xid8 NOT NULL,
 PRIMARY KEY(catalog_id,event_order),UNIQUE(catalog_id,event_order,publication_xid),UNIQUE(catalog_id,observation_id),
 FOREIGN KEY(catalog_id,revision_id) REFERENCES market_data.revisions(catalog_id,id),
 FOREIGN KEY(catalog_id,observation_id,revision_id) REFERENCES market_data.observations(catalog_id,id,definition_revision_id)
);
CREATE UNIQUE INDEX one_bundle_publication ON market_data.knowledge_events(catalog_id,revision_id) WHERE observation_id IS NULL;
CREATE TABLE market_data.market_knowledge_receipts (
 catalog_id uuid NOT NULL,event_order integer NOT NULL,publication_xid xid8 NOT NULL,known_from timestamptz NOT NULL,
 PRIMARY KEY(catalog_id,event_order),FOREIGN KEY(catalog_id,event_order,publication_xid) REFERENCES market_data.knowledge_events(catalog_id,event_order,publication_xid),
 CHECK(isfinite(known_from) AND known_from<TIMESTAMPTZ '9999-12-31 00:00:00+00')
);
CREATE TABLE market_data.market_contexts (
 catalog_id uuid NOT NULL,context_id uuid NOT NULL,known_through integer NOT NULL CHECK(known_through>=0),
 PRIMARY KEY(catalog_id,context_id),FOREIGN KEY(catalog_id,context_id) REFERENCES market_data.temporal_contexts(catalog_id,id)
);
ALTER TABLE market_data.knowledge_clocks ADD COLUMN market_certified_head integer NOT NULL DEFAULT 0 CHECK(market_certified_head>=0);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['revision_periods','knowledge_events','market_knowledge_receipts','market_contexts'] LOOP
  EXECUTE format('ALTER TABLE market_data.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE market_data.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY scoped_read ON market_data.%I FOR SELECT TO openetrm_runtime USING(security.market_access(catalog_id,''ReadMarketData''))',t);
  EXECUTE format('GRANT SELECT ON market_data.%I TO openetrm_runtime',t);
  IF t<>'revision_periods' THEN
   EXECUTE format('CREATE TRIGGER immutable_receipt BEFORE UPDATE OR DELETE ON market_data.%I FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt()',t);
  END IF;
 END LOOP;
END $$;
CREATE POLICY scoped_insert ON market_data.revision_periods FOR INSERT TO openetrm_runtime WITH CHECK(security.market_access(catalog_id,'WriteMarketDefinitions'));
GRANT INSERT ON market_data.revision_periods TO openetrm_runtime;
GRANT SELECT ON market_data.revision_periods TO openetrm_security_owner;
GRANT SELECT,INSERT ON market_data.knowledge_events,market_data.market_knowledge_receipts,market_data.market_contexts TO openetrm_security_owner;
CREATE FUNCTION security.record_market_event() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE rev uuid; observation uuid; ordinal integer;
BEGIN
 IF TG_TABLE_NAME='revisions' THEN
  IF NEW.state<>'sealed' THEN RETURN NEW; END IF;
  rev=NEW.id;
  IF NOT EXISTS(SELECT 1 FROM market_data.revision_periods WHERE catalog_id=NEW.catalog_id AND revision_id=rev) THEN
   RAISE EXCEPTION 'Explicit definition applicability is required before sealing' USING ERRCODE='23514';
  END IF;
 ELSE rev=NEW.definition_revision_id;observation=NEW.id; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname=session_user) AND NOT security.market_access(NEW.catalog_id,CASE TG_TABLE_NAME WHEN 'revisions' THEN 'SealMarketDefinitions' ELSE 'ImportObservations' END) THEN
  RAISE EXCEPTION 'Market publication authority expired during admission' USING ERRCODE='42501';
 END IF;
 IF current_setting('track_commit_timestamp')<>'on' THEN RAISE EXCEPTION 'knowledge_tracking' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(max(event_order),0)+1 INTO ordinal FROM market_data.knowledge_events WHERE catalog_id=NEW.catalog_id;
 INSERT INTO market_data.knowledge_events VALUES(NEW.catalog_id,ordinal,rev,observation,pg_current_xact_id());
 RETURN NEW;
END $$;
ALTER FUNCTION security.record_market_event() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.record_market_event() FROM PUBLIC;
CREATE TRIGGER record_market_revision AFTER UPDATE OF state ON market_data.revisions FOR EACH ROW WHEN(NEW.state='sealed') EXECUTE FUNCTION security.record_market_event();
CREATE TRIGGER record_market_observation AFTER INSERT ON market_data.observations FOR EACH ROW EXECUTE FUNCTION security.record_market_event();

-- The schedule and market streams share one commit gate and exact cutoff. Each
-- stream has its own certified prefix; neither prefix stands in for the other.
ALTER FUNCTION security.capture_date_context(uuid,date,timestamptz) RENAME TO capture_schedule_context;
REVOKE ALL ON FUNCTION security.capture_schedule_context(uuid,date,timestamptz) FROM openetrm_runtime;
CREATE FUNCTION security.capture_date_context(catalog uuid,effective_date date,requested_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE clock market_data.knowledge_clocks; row record; commit_at timestamptz; last_commit timestamptz; token uuid; cutoff timestamptz; head integer;
BEGIN
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'No current temporal read permission' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT * INTO clock FROM market_data.knowledge_clocks WHERE catalog_id=catalog FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
 SELECT known_from INTO last_commit FROM market_data.market_knowledge_receipts WHERE catalog_id=catalog ORDER BY event_order DESC LIMIT 1;
 FOR row IN SELECT * FROM market_data.knowledge_events WHERE catalog_id=catalog AND event_order>clock.market_certified_head ORDER BY event_order LOOP
  IF row.event_order<>clock.market_certified_head+1 THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
  commit_at=security.checked_commit_time(row.publication_xid);
  IF commit_at<last_commit OR (clock.certified_through IS NOT NULL AND commit_at<=clock.certified_through) THEN RAISE EXCEPTION 'knowledge_clock' USING ERRCODE='P0001'; END IF;
  INSERT INTO market_data.market_knowledge_receipts VALUES(catalog,row.event_order,row.publication_xid,commit_at);
  clock.market_certified_head=row.event_order;last_commit=commit_at;
 END LOOP;
 token=security.capture_schedule_context(catalog,effective_date,requested_at);
 SELECT known_at INTO cutoff FROM market_data.temporal_contexts WHERE catalog_id=catalog AND id=token;
 IF last_commit>(SELECT certified_through FROM market_data.knowledge_clocks WHERE catalog_id=catalog) THEN RAISE EXCEPTION 'knowledge_clock' USING ERRCODE='P0001'; END IF;
 UPDATE market_data.knowledge_clocks SET market_certified_head=clock.market_certified_head WHERE catalog_id=catalog;
 SELECT coalesce(max(event_order),0) INTO head FROM market_data.market_knowledge_receipts WHERE catalog_id=catalog AND known_from<=cutoff;
 INSERT INTO market_data.market_contexts VALUES(catalog,token,head) ON CONFLICT DO NOTHING;
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'Temporal authority expired during certification' USING ERRCODE='42501'; END IF;
 RETURN token;
END $$;
ALTER FUNCTION security.capture_date_context(uuid,date,timestamptz) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.capture_date_context(uuid,date,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.capture_date_context(uuid,date,timestamptz) TO openetrm_runtime;

ALTER TABLE security.request_contexts ADD COLUMN market_catalog_id uuid;
ALTER TABLE security.request_contexts ADD COLUMN market_context_id uuid;
ALTER TABLE security.request_contexts ADD CHECK((market_catalog_id IS NULL)=(market_context_id IS NULL));
ALTER TABLE security.request_contexts ADD FOREIGN KEY(market_catalog_id,market_context_id) REFERENCES market_data.market_contexts(catalog_id,context_id);
-- Existing issue_context intentionally names its columns after adding fields.
CREATE OR REPLACE FUNCTION security.issue_context(issuer text,subject text,login_kind text,tenant uuid,workspace uuid,delegation uuid,runtime_login name,ttl_seconds integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;token uuid;
BEGIN
 IF ttl_seconds IS NULL OR ttl_seconds<1 OR ttl_seconds>300 OR runtime_login IS NULL OR NOT pg_has_role(runtime_login,'openetrm_runtime','MEMBER') THEN RAISE EXCEPTION 'Invalid request context' USING ERRCODE='42501'; END IF;
 SELECT p.id INTO actor FROM security.identity_bindings b JOIN security.principals p ON p.id=b.principal_id WHERE b.issuer=issue_context.issuer AND b.subject=issue_context.subject AND b.login_kind=issue_context.login_kind AND p.enabled;
 IF actor IS NULL THEN RAISE EXCEPTION 'Unbound or disabled identity' USING ERRCODE='42501'; END IF;
 token=gen_random_uuid();
 INSERT INTO security.request_contexts(id,actor_id,tenant_id,workspace_id,delegation_id,runtime_login,expires_at) VALUES(token,actor,tenant,workspace,delegation,runtime_login,clock_timestamp()+make_interval(secs=>ttl_seconds));
 RETURN token;
END $$;
CREATE FUNCTION security.use_market_context(catalog uuid,context uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NOT security.market_access(catalog,'ReadMarketData') OR NOT EXISTS(SELECT 1 FROM market_data.market_contexts WHERE catalog_id=catalog AND context_id=context) THEN RAISE EXCEPTION 'Unavailable market context' USING ERRCODE='42501'; END IF;
 UPDATE security.request_contexts SET market_catalog_id=catalog,market_context_id=context WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user AND market_context_id IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Market context must bind exactly once per request' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION security.market_fact_visible(catalog uuid,revision uuid,observation uuid) RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.market_access(catalog,'ReadMarketData') AND (NOT EXISTS(SELECT 1 FROM security.request_contexts c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user AND c.market_context_id IS NOT NULL)
 OR EXISTS(
  SELECT 1 FROM security.request_contexts c JOIN market_data.temporal_contexts t ON(t.catalog_id,t.id)=(c.market_catalog_id,c.market_context_id)
  JOIN market_data.market_contexts m ON(m.catalog_id,m.context_id)=(t.catalog_id,t.id)
  JOIN market_data.knowledge_events e ON e.catalog_id=t.catalog_id AND e.revision_id=revision AND e.observation_id IS NOT DISTINCT FROM observation
  JOIN market_data.market_knowledge_receipts k ON(k.catalog_id,k.event_order,k.publication_xid)=(e.catalog_id,e.event_order,e.publication_xid)
  JOIN market_data.revision_periods p ON(p.catalog_id,p.revision_id)=(e.catalog_id,e.revision_id)
  WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user AND t.catalog_id=catalog
   AND e.event_order<=m.known_through AND k.known_from<=t.known_at AND p.effective_from<=t.effective_on AND t.effective_on<p.effective_to
   AND(observation IS NULL OR EXISTS(SELECT 1 FROM market_data.observations o WHERE o.catalog_id=catalog AND o.id=observation AND o.observed_at<((t.effective_on+1)::timestamp AT TIME ZONE 'UTC')))
 ));
$$;
CREATE FUNCTION security.reference_version_visible(catalog uuid,revision uuid) RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.reference_access(catalog,'ReadMarketData') AND (NOT EXISTS(SELECT 1 FROM security.request_contexts c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user AND c.market_context_id IS NOT NULL)
 OR EXISTS(SELECT 1 FROM market_data.revisions r WHERE r.reference_catalog_id=catalog AND r.reference_revision_id=revision AND security.market_fact_visible(r.catalog_id,r.id,NULL)));
$$;
DO $$ DECLARE t record; rev text; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='market_data' AND tablename IN('revisions','contracts','curves','series','curve_members','curve_inputs','constituent_mappings','rate_curves','rate_curve_points','observations','revision_periods') LOOP
  rev=CASE t.tablename WHEN 'revisions' THEN 'id' WHEN 'observations' THEN 'definition_revision_id' ELSE 'revision_id' END;
  EXECUTE format('CREATE POLICY temporal_read ON market_data.%I AS RESTRICTIVE FOR SELECT TO openetrm_runtime USING(security.market_fact_visible(catalog_id,%I,%s))',t.tablename,rev,CASE t.tablename WHEN 'observations' THEN 'id' ELSE 'NULL' END);
 END LOOP;
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='ref_data' AND tablename<>'catalogs' LOOP
  rev=CASE t.tablename WHEN 'revisions' THEN 'id' ELSE 'revision_id' END;
  EXECUTE format('CREATE POLICY temporal_read ON ref_data.%I AS RESTRICTIVE FOR SELECT TO openetrm_runtime USING(security.reference_version_visible(catalog_id,%I))',t.tablename,rev);
 END LOOP;
END $$;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='security' AND p.proname IN('use_market_context','market_fact_visible','reference_version_visible') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f.signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO openetrm_runtime',f.signature);
 END LOOP;
END $$;
CREATE FUNCTION security.current_write_context() RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT NOT EXISTS(SELECT 1 FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user AND market_context_id IS NOT NULL);
$$;
ALTER FUNCTION security.current_write_context() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.current_write_context() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.current_write_context() TO openetrm_runtime;
DO $$ DECLARE t record; BEGIN
 FOR t IN SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN('market_data','ref_data') LOOP
  EXECUTE format('CREATE POLICY current_insert ON %I.%I AS RESTRICTIVE FOR INSERT TO openetrm_runtime WITH CHECK(security.current_write_context())',t.schemaname,t.tablename);
  EXECUTE format('CREATE POLICY current_update ON %I.%I AS RESTRICTIVE FOR UPDATE TO openetrm_runtime USING(security.current_write_context()) WITH CHECK(security.current_write_context())',t.schemaname,t.tablename);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION security.market_access(catalog uuid,permission text) RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.has_permission(permission) AND (permission='ReadMarketData' OR security.current_write_context()) AND EXISTS(
 SELECT 1 FROM security.request_contexts c JOIN security.market_catalog_scopes s ON(s.tenant_id,s.workspace_id)=(c.tenant_id,c.workspace_id)
 WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user AND s.catalog_id=catalog);
$$;
CREATE OR REPLACE FUNCTION security.reference_access(catalog uuid,permission text) RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.has_permission(permission) AND (permission='ReadMarketData' OR security.current_write_context()) AND EXISTS(
 SELECT 1 FROM security.request_contexts c JOIN security.reference_catalog_scopes s ON(s.tenant_id,s.workspace_id)=(c.tenant_id,c.workspace_id)
 WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user AND s.catalog_id=catalog AND(permission='ReadMarketData' OR s.access_mode='owner'));
$$;
COMMIT;
