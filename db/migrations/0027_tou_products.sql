-- Authored time-of-use products: editable drafts and immutable published versions,
-- each bound to an exact sealed reference clock rule. Peak hours are hour-beginning
-- [start, end) on Monday–Friday (and Saturday when peak_saturday) in that clock;
-- off-peak is the exact complement. Holidays come from the settlement index
-- calendar, never from a product. Products are current-workspace definitions: they
-- are invisible under a historical market context, which the power preview rejects.
BEGIN;
CREATE TABLE market_data.tou_products (
 catalog_id uuid NOT NULL REFERENCES market_data.catalogs(id), id uuid NOT NULL,
 code ref_data.code NOT NULL,
 PRIMARY KEY (catalog_id, id), UNIQUE (catalog_id, code)
);
CREATE FUNCTION market_data.guard_tou_product_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'TOU product identity is immutable' USING ERRCODE='55000'; END; $$;
CREATE TRIGGER guard_tou_product_identity BEFORE UPDATE OR DELETE ON market_data.tou_products
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_tou_product_identity();
REVOKE ALL ON FUNCTION market_data.guard_tou_product_identity() FROM PUBLIC;

CREATE TABLE market_data.tou_product_versions (
 catalog_id uuid NOT NULL, product_id uuid NOT NULL,
 version integer NOT NULL CHECK (version BETWEEN 1 AND 64),
 generation integer NOT NULL CHECK (generation > 0),
 state text NOT NULL CHECK (state IN ('draft','published')),
 name text NOT NULL CHECK (name = btrim(name) AND name <> '' AND length(name) <= 80),
 clock_catalog_id uuid NOT NULL, clock_revision_id uuid NOT NULL, clock_code ref_data.code NOT NULL,
 peak_start_hour smallint NOT NULL CHECK (peak_start_hour BETWEEN 0 AND 23),
 peak_end_hour smallint NOT NULL CHECK (peak_end_hour BETWEEN 1 AND 24),
 peak_saturday boolean NOT NULL,
 publication_order integer CHECK (publication_order > 0), published_at timestamptz,
 PRIMARY KEY (catalog_id, product_id, version), UNIQUE (catalog_id, publication_order),
 FOREIGN KEY (catalog_id, product_id) REFERENCES market_data.tou_products(catalog_id, id),
 FOREIGN KEY (clock_catalog_id, clock_revision_id, clock_code)
   REFERENCES ref_data.clock_rules(catalog_id, revision_id, code) ON DELETE RESTRICT,
 CHECK (peak_start_hour < peak_end_hour),
 CHECK ((state = 'published') = (publication_order IS NOT NULL AND published_at IS NOT NULL)),
 CHECK ((state = 'draft') = (publication_order IS NULL AND published_at IS NULL))
);
CREATE UNIQUE INDEX one_tou_product_draft ON market_data.tou_product_versions(catalog_id, product_id) WHERE state = 'draft';
COMMENT ON TABLE market_data.tou_product_versions IS
 'TOU product definitions. Published rows are immutable; editing one creates the next draft version. Clock rules must come from a sealed reference revision.';

-- Published versions never change; drafts advance generation; clocks come from a
-- sealed (immutable) reference revision. Run as the security owner so sealing is
-- judged independently of the writer's visibility; policies judge catalog scope.
CREATE FUNCTION market_data.guard_tou_product_version() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.state = 'published') THEN
   RAISE EXCEPTION 'Published TOU product versions cannot change or be removed' USING ERRCODE='55000';
 END IF;
 IF TG_OP = 'UPDATE' AND NEW.state = 'draft' AND NEW.generation <> OLD.generation + 1 THEN
   RAISE EXCEPTION 'Draft changes must advance generation' USING ERRCODE='40001';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM ref_data.revisions r WHERE r.catalog_id = NEW.clock_catalog_id
     AND r.id = NEW.clock_revision_id AND r.state = 'sealed') THEN
   RAISE EXCEPTION 'TOU product clocks must come from a sealed reference revision' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
ALTER FUNCTION market_data.guard_tou_product_version() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION market_data.guard_tou_product_version() FROM PUBLIC;
CREATE TRIGGER guard_tou_product_version BEFORE INSERT OR UPDATE OR DELETE ON market_data.tou_product_versions
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_tou_product_version();

ALTER TABLE market_data.tou_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_data.tou_products FORCE ROW LEVEL SECURITY;
ALTER TABLE market_data.tou_product_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_data.tou_product_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON market_data.tou_products FOR SELECT TO openetrm_runtime
 USING (security.market_access(catalog_id,'ReadMarketData'));
CREATE POLICY scoped_insert ON market_data.tou_products FOR INSERT TO openetrm_runtime
 WITH CHECK (security.market_access(catalog_id,'WriteMarketDefinitions'));
-- Drafts are working material: readers see published versions only; authors see drafts too.
CREATE POLICY scoped_read ON market_data.tou_product_versions FOR SELECT TO openetrm_runtime
 USING (security.market_access(catalog_id,'ReadMarketData') AND (state='published'
   OR security.market_access(catalog_id,'WriteMarketDefinitions') OR security.market_access(catalog_id,'SealMarketDefinitions')));
CREATE POLICY scoped_insert ON market_data.tou_product_versions FOR INSERT TO openetrm_runtime
 WITH CHECK (state='draft' AND publication_order IS NULL AND security.market_access(catalog_id,'WriteMarketDefinitions')
   AND security.reference_access(clock_catalog_id,'ReadMarketData'));
CREATE POLICY scoped_update ON market_data.tou_product_versions FOR UPDATE TO openetrm_runtime
 USING (state='draft' AND security.market_access(catalog_id,'WriteMarketDefinitions'))
 WITH CHECK (state='draft' AND security.market_access(catalog_id,'WriteMarketDefinitions')
   AND security.reference_access(clock_catalog_id,'ReadMarketData'));
-- Current definitions only: no rows under a historical market context, and writes
-- use the same restrictive current-write gate as every other market table.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['tou_products','tou_product_versions'] LOOP
  EXECUTE format('CREATE POLICY current_read ON market_data.%I AS RESTRICTIVE FOR SELECT TO openetrm_runtime USING(security.current_write_context())',t);
  EXECUTE format('CREATE POLICY current_insert ON market_data.%I AS RESTRICTIVE FOR INSERT TO openetrm_runtime WITH CHECK(security.current_write_context())',t);
  EXECUTE format('CREATE POLICY current_update ON market_data.%I AS RESTRICTIVE FOR UPDATE TO openetrm_runtime USING(security.current_write_context()) WITH CHECK(security.current_write_context())',t);
 END LOOP;
END $$;
REVOKE ALL ON market_data.tou_products, market_data.tou_product_versions FROM PUBLIC;
GRANT SELECT, INSERT ON market_data.tou_products, market_data.tou_product_versions TO openetrm_runtime;
GRANT UPDATE (generation, name, clock_catalog_id, clock_revision_id, clock_code, peak_start_hour, peak_end_hour, peak_saturday)
 ON market_data.tou_product_versions TO openetrm_runtime;
GRANT SELECT ON market_data.tou_products TO openetrm_security_owner;
GRANT SELECT, UPDATE ON market_data.tou_product_versions TO openetrm_security_owner;

CREATE FUNCTION security.publish_tou_product(catalog uuid, product uuid, requested_version integer, expected_generation integer)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE row market_data.tou_product_versions; next_order integer;
BEGIN
 IF NOT security.market_access(catalog,'SealMarketDefinitions') THEN RAISE EXCEPTION 'No current publishing permission' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(730849104);
 SELECT * INTO row FROM market_data.tou_product_versions WHERE catalog_id=catalog AND product_id=product AND version=requested_version FOR UPDATE;
 IF row.product_id IS NULL OR row.generation IS DISTINCT FROM expected_generation THEN RAISE EXCEPTION 'Stale TOU product version' USING ERRCODE='40001'; END IF;
 IF NOT security.market_access(catalog,'SealMarketDefinitions') THEN RAISE EXCEPTION 'Publishing authority expired during admission' USING ERRCODE='42501'; END IF;
 IF row.state='published' THEN RETURN row.publication_order; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO next_order FROM market_data.tou_product_versions WHERE catalog_id=catalog;
 UPDATE market_data.tou_product_versions SET state='published',publication_order=next_order,published_at=clock_timestamp()
  WHERE catalog_id=catalog AND product_id=product AND version=requested_version;
 RETURN next_order;
END $$;
ALTER FUNCTION security.publish_tou_product(uuid,uuid,integer,integer) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.publish_tou_product(uuid,uuid,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.publish_tou_product(uuid,uuid,integer,integer) TO openetrm_runtime;
COMMIT;
