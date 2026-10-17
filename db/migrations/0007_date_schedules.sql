-- Independent schedules: editable drafts, immutable published versions.
BEGIN;
CREATE TABLE market_data.date_schedules (
 catalog_id uuid NOT NULL REFERENCES market_data.catalogs(id), id uuid NOT NULL,
 symbol text NOT NULL CHECK(symbol ~ '^oe\.[a-z][a-z0-9_]{0,31}$'),
 PRIMARY KEY(catalog_id,id), UNIQUE(catalog_id,symbol)
);
CREATE FUNCTION market_data.guard_date_schedule_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'Schedule reference identity is immutable' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER guard_date_schedule_identity BEFORE UPDATE OR DELETE ON market_data.date_schedules
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_date_schedule_identity();
REVOKE ALL ON FUNCTION market_data.guard_date_schedule_identity() FROM PUBLIC;
CREATE TABLE market_data.date_schedule_versions (
 catalog_id uuid NOT NULL, schedule_id uuid NOT NULL, version integer NOT NULL CHECK(version BETWEEN 1 AND 64),
 generation integer NOT NULL CHECK(generation>0), state text NOT NULL CHECK(state IN ('draft','published')),
 definition jsonb NOT NULL CHECK(jsonb_typeof(definition)='object' AND octet_length(definition::text)<=32768),
 selection text NOT NULL CHECK(selection IN ('absolute_index','context_month')),
 effective_from date NOT NULL CHECK(isfinite(effective_from) AND effective_from >= DATE '0001-01-01' AND effective_from < DATE '9999-12-31'),
 effective_to date NOT NULL CHECK(isfinite(effective_to) AND effective_to <= DATE '9999-12-31' AND effective_to>effective_from),
 engine_version text NOT NULL CHECK(engine_version='date_schedule_v1'),
 publication_order integer CHECK(publication_order>0), published_at timestamptz,
 PRIMARY KEY(catalog_id,schedule_id,version), UNIQUE(catalog_id,publication_order),
 FOREIGN KEY(catalog_id,schedule_id) REFERENCES market_data.date_schedules(catalog_id,id),
 CHECK((state='published')=(publication_order IS NOT NULL AND published_at IS NOT NULL)),
 CHECK((state='draft')=(publication_order IS NULL AND published_at IS NULL))
);
CREATE UNIQUE INDEX one_schedule_draft ON market_data.date_schedule_versions(catalog_id,schedule_id) WHERE state='draft';
CREATE FUNCTION market_data.guard_date_schedule() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE symbol text;
BEGIN
 IF TG_OP='DELETE' OR (TG_OP='UPDATE' AND OLD.state='published') THEN
   RAISE EXCEPTION 'Published schedule versions cannot change or be removed' USING ERRCODE='55000';
 END IF;
 SELECT s.symbol INTO symbol FROM market_data.date_schedules s WHERE s.catalog_id=NEW.catalog_id AND s.id=NEW.schedule_id;
 IF NEW.definition->>'symbol' IS DISTINCT FROM symbol THEN
   RAISE EXCEPTION 'Schedule reference identity cannot change' USING ERRCODE='23514';
 END IF;
 IF TG_OP='UPDATE' AND NEW.state='draft' AND NEW.generation<>OLD.generation+1 THEN
   RAISE EXCEPTION 'Draft changes must advance generation' USING ERRCODE='40001';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER guard_date_schedule BEFORE INSERT OR UPDATE OR DELETE ON market_data.date_schedule_versions
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_date_schedule();
ALTER TABLE market_data.date_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_data.date_schedules FORCE ROW LEVEL SECURITY;
ALTER TABLE market_data.date_schedule_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_data.date_schedule_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON market_data.date_schedules FOR SELECT TO openetrm_runtime USING(security.market_access(catalog_id,'ReadMarketData'));
CREATE POLICY scoped_insert ON market_data.date_schedules FOR INSERT TO openetrm_runtime WITH CHECK(security.market_access(catalog_id,'WriteMarketDefinitions'));
CREATE POLICY scoped_read ON market_data.date_schedule_versions FOR SELECT TO openetrm_runtime USING(security.market_access(catalog_id,'ReadMarketData'));
CREATE POLICY scoped_insert ON market_data.date_schedule_versions FOR INSERT TO openetrm_runtime
 WITH CHECK(state='draft' AND publication_order IS NULL AND security.market_access(catalog_id,'WriteMarketDefinitions'));
CREATE POLICY scoped_update ON market_data.date_schedule_versions FOR UPDATE TO openetrm_runtime
 USING(state='draft' AND security.market_access(catalog_id,'WriteMarketDefinitions'))
 WITH CHECK(state='draft' AND security.market_access(catalog_id,'WriteMarketDefinitions'));
GRANT SELECT,INSERT ON market_data.date_schedules,market_data.date_schedule_versions TO openetrm_runtime;
GRANT UPDATE(definition,selection,effective_from,effective_to,generation) ON market_data.date_schedule_versions TO openetrm_runtime;
GRANT SELECT ON market_data.date_schedules TO openetrm_security_owner;
GRANT SELECT,UPDATE ON market_data.date_schedule_versions TO openetrm_security_owner;

-- Publication and capture share this transaction-scoped fence. The order is a
-- committed prefix after capture, not a claim about wall-clock commit timestamps.
CREATE FUNCTION security.publish_date_schedule(catalog uuid, schedule uuid, requested_version integer, expected_generation integer)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE row market_data.date_schedule_versions; next_order integer;
BEGIN
 IF NOT security.market_access(catalog,'SealMarketDefinitions') THEN RAISE EXCEPTION 'No current publishing permission' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT * INTO row FROM market_data.date_schedule_versions
  WHERE catalog_id=catalog AND schedule_id=schedule AND version=requested_version FOR UPDATE;
 IF row.schedule_id IS NULL OR row.generation IS DISTINCT FROM expected_generation THEN RAISE EXCEPTION 'Stale schedule version' USING ERRCODE='40001'; END IF;
 IF NOT security.market_access(catalog,'SealMarketDefinitions') THEN RAISE EXCEPTION 'Publishing authority expired during admission' USING ERRCODE='42501'; END IF;
 IF row.state='published' THEN RETURN row.publication_order; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO next_order FROM market_data.date_schedule_versions WHERE catalog_id=catalog;
 UPDATE market_data.date_schedule_versions SET state='published',publication_order=next_order,published_at=clock_timestamp()
  WHERE catalog_id=catalog AND schedule_id=schedule AND version=requested_version;
 RETURN next_order;
END; $$;
ALTER FUNCTION security.publish_date_schedule(uuid,uuid,integer,integer) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.publish_date_schedule(uuid,uuid,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.publish_date_schedule(uuid,uuid,integer,integer) TO openetrm_runtime;
REVOKE ALL ON FUNCTION market_data.guard_date_schedule() FROM PUBLIC;
COMMENT ON TABLE market_data.date_schedule_versions IS
 'Independent date definitions. Published rows immutable. Known-through is a captured publication prefix; published_at is audit metadata, not certified wall-clock commit time.';
COMMIT;
