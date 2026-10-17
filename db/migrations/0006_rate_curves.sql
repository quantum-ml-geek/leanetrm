-- A non-commodity curve needs dated rate pillars, not fictional delivery contracts.
BEGIN;
CREATE TABLE market_data.rate_curves (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, code ref_data.code NOT NULL,
  reference_catalog_id uuid NOT NULL, reference_revision_id uuid NOT NULL,
  interest_rate_code ref_data.code NOT NULL, source_code ref_data.code NOT NULL,
  date_basis text NOT NULL CHECK (date_basis='valuation_utc_date'),
  PRIMARY KEY (catalog_id,revision_id,code),
  FOREIGN KEY (catalog_id,revision_id,reference_catalog_id,reference_revision_id)
    REFERENCES market_data.revisions(catalog_id,id,reference_catalog_id,reference_revision_id),
  FOREIGN KEY (reference_catalog_id,reference_revision_id,interest_rate_code)
    REFERENCES ref_data.interest_rate_definitions(catalog_id,revision_id,code),
  FOREIGN KEY (reference_catalog_id,reference_revision_id,source_code)
    REFERENCES ref_data.sources(catalog_id,revision_id,code)
);
CREATE TABLE market_data.rate_curve_points (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, curve_code ref_data.code NOT NULL,
  maturity date NOT NULL, series_id uuid NOT NULL, ordinal integer NOT NULL CHECK (ordinal>=0),
  PRIMARY KEY (catalog_id,revision_id,curve_code,maturity),
  UNIQUE (catalog_id,revision_id,curve_code,series_id),
  UNIQUE (catalog_id,revision_id,curve_code,ordinal),
  FOREIGN KEY (catalog_id,revision_id,curve_code) REFERENCES market_data.rate_curves(catalog_id,revision_id,code),
  FOREIGN KEY (catalog_id,revision_id,series_id) REFERENCES market_data.series(catalog_id,revision_id,id),
  CHECK (isfinite(maturity) AND maturity>=DATE '1901-01-01' AND maturity<=DATE '2199-12-31')
);
COMMENT ON TABLE market_data.rate_curve_points IS
  'Exact dated zero-rate samples, annual decimal rates. No maturity interpolation, extrapolation, bootstrapping or holiday rolling.';
CREATE FUNCTION market_data.validate_rate_revision(cat uuid, rev uuid) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM market_data.rate_curve_points p JOIN market_data.rate_curve_points q
    ON (p.catalog_id,p.revision_id,p.series_id)=(q.catalog_id,q.revision_id,q.series_id)
    WHERE p.catalog_id=cat AND p.revision_id=rev AND p.maturity<>q.maturity) THEN
    RAISE EXCEPTION 'A rate series cannot represent different maturities' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.rate_curves r JOIN market_data.curves c
    ON (r.catalog_id,r.revision_id,r.code)=(c.catalog_id,c.revision_id,c.code) WHERE r.catalog_id=cat AND r.revision_id=rev) THEN
    RAISE EXCEPTION 'Curve names must be distinct across supported curve kinds' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.rate_curves r WHERE r.catalog_id=cat AND r.revision_id=rev AND
    NOT EXISTS (SELECT 1 FROM market_data.rate_curve_points p WHERE (p.catalog_id,p.revision_id,p.curve_code)=(r.catalog_id,r.revision_id,r.code))) THEN
    RAISE EXCEPTION 'Rate curves require explicit dated samples' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.rate_curve_points p JOIN market_data.series s
    ON (p.catalog_id,p.revision_id,p.series_id)=(s.catalog_id,s.revision_id,s.id)
    LEFT JOIN ref_data.value_specifications v ON (s.reference_catalog_id,s.reference_revision_id,s.value_specification_code)=(v.catalog_id,v.revision_id,v.code)
    WHERE p.catalog_id=cat AND p.revision_id=rev AND (s.contract_id IS NOT NULL OR s.quote_code IS NOT NULL OR v.kind IS DISTINCT FROM 'dimensionless')) THEN
    RAISE EXCEPTION 'Rate samples require typed non-contract decimal rates' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM (SELECT maturity,lag(maturity) OVER(PARTITION BY curve_code ORDER BY ordinal) AS previous
    FROM market_data.rate_curve_points WHERE catalog_id=cat AND revision_id=rev) p WHERE maturity<=previous) THEN
    RAISE EXCEPTION 'Rate maturity order must increase' USING ERRCODE='23514';
  END IF;
END;
$$;
CREATE FUNCTION market_data.guard_rate_revision() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF NEW.state='sealed' AND OLD.state='draft' THEN PERFORM market_data.validate_rate_revision(NEW.catalog_id,NEW.id); END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER guard_rate_revision BEFORE UPDATE ON market_data.revisions FOR EACH ROW EXECUTE FUNCTION market_data.guard_rate_revision();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.rate_curves FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.rate_curve_points FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
ALTER TABLE market_data.rate_curves ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_data.rate_curves FORCE ROW LEVEL SECURITY;
ALTER TABLE market_data.rate_curve_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_data.rate_curve_points FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON market_data.rate_curves FOR SELECT TO openetrm_runtime USING (security.market_access(catalog_id,'ReadMarketData'));
CREATE POLICY scoped_read ON market_data.rate_curve_points FOR SELECT TO openetrm_runtime USING (security.market_access(catalog_id,'ReadMarketData'));
CREATE POLICY scoped_insert ON market_data.rate_curves FOR INSERT TO openetrm_runtime WITH CHECK (security.market_access(catalog_id,'WriteMarketDefinitions') AND security.reference_access(reference_catalog_id,'ReadMarketData'));
CREATE POLICY scoped_insert ON market_data.rate_curve_points FOR INSERT TO openetrm_runtime WITH CHECK (security.market_access(catalog_id,'WriteMarketDefinitions'));
REVOKE ALL ON market_data.rate_curves,market_data.rate_curve_points FROM PUBLIC;
REVOKE ALL ON FUNCTION market_data.validate_rate_revision(uuid,uuid),market_data.guard_rate_revision() FROM PUBLIC;
GRANT SELECT,INSERT ON market_data.rate_curves,market_data.rate_curve_points TO openetrm_runtime;
GRANT SELECT ON market_data.rate_curves,market_data.rate_curve_points TO openetrm_security_owner;
GRANT EXECUTE ON FUNCTION market_data.validate_rate_revision(uuid,uuid) TO openetrm_security_owner;
COMMIT;
