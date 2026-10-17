-- Market storage foundation. No activation, knowledge publication or service.
BEGIN;

CREATE TABLE ref_data.measurement_bases (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL,
  code ref_data.code NOT NULL, commodity_code ref_data.code NOT NULL,
  dimension_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  UNIQUE (catalog_id, revision_id, code, commodity_code, dimension_code),
  FOREIGN KEY (catalog_id, revision_id, commodity_code)
    REFERENCES ref_data.commodities(catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id, dimension_code)
    REFERENCES ref_data.dimensions(catalog_id, revision_id, code)
);
CREATE TABLE ref_data.quantity_specifications (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL,
  code ref_data.code NOT NULL, commodity_code ref_data.code NOT NULL,
  basis_code ref_data.code NOT NULL, unit_code ref_data.code NOT NULL,
  dimension_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  UNIQUE (catalog_id, revision_id, code, commodity_code),
  FOREIGN KEY (catalog_id, revision_id, basis_code, commodity_code, dimension_code)
    REFERENCES ref_data.measurement_bases(catalog_id, revision_id, code, commodity_code, dimension_code),
  FOREIGN KEY (catalog_id, revision_id, unit_code, dimension_code)
    REFERENCES ref_data.units(catalog_id, revision_id, code, dimension_code)
);
COMMENT ON TABLE ref_data.quantity_specifications IS
  'Explicit commodity/measurement basis/unit. Does not imply volume-energy interchangeability.';
CREATE TABLE ref_data.quote_specifications (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL,
  code ref_data.code NOT NULL, commodity_code ref_data.code NOT NULL,
  kind text NOT NULL CHECK (kind IN ('outright', 'basis')),
  quantity_code ref_data.code NOT NULL, currency_code ref_data.code NOT NULL,
  multiplier ref_data.exact_number NOT NULL CHECK (multiplier > 0),
  trading_tick ref_data.exact_number NOT NULL CHECK (trading_tick > 0),
  clearing_increment ref_data.exact_number NOT NULL CHECK (clearing_increment > 0),
  minimum ref_data.exact_number NOT NULL, maximum ref_data.exact_number NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  UNIQUE (catalog_id, revision_id, code, commodity_code),
  CHECK (minimum <= maximum),
  FOREIGN KEY (catalog_id, revision_id, quantity_code, commodity_code)
    REFERENCES ref_data.quantity_specifications(catalog_id, revision_id, code, commodity_code),
  FOREIGN KEY (catalog_id, revision_id, currency_code)
    REFERENCES ref_data.currencies(catalog_id, revision_id, code)
);
CREATE TABLE ref_data.value_specifications (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, code ref_data.code NOT NULL,
  kind text NOT NULL CHECK (kind IN ('quantity_ratio','dimensionless')),
  numerator_quantity_code ref_data.code, denominator_quantity_code ref_data.code,
  minimum ref_data.exact_number NOT NULL, maximum ref_data.exact_number NOT NULL,
  PRIMARY KEY (catalog_id,revision_id,code), CHECK (minimum <= maximum),
  FOREIGN KEY (catalog_id,revision_id) REFERENCES ref_data.revisions(catalog_id,id),
  FOREIGN KEY (catalog_id,revision_id,numerator_quantity_code)
    REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code),
  FOREIGN KEY (catalog_id,revision_id,denominator_quantity_code)
    REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code),
  CHECK ((kind='quantity_ratio' AND numerator_quantity_code IS NOT NULL AND denominator_quantity_code IS NOT NULL)
    OR (kind='dimensionless' AND numerator_quantity_code IS NULL AND denominator_quantity_code IS NULL))
);
CREATE TABLE ref_data.delivery_profiles (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, code ref_data.code NOT NULL,
  kind text NOT NULL CHECK (kind = 'uniform'),
  clock_code ref_data.code NOT NULL, calendar_code ref_data.code NOT NULL,
  quantity_basis text NOT NULL CHECK (quantity_basis IN ('fixed_total', 'per_delivery_day', 'per_delivery_hour')),
  interval_minutes integer NOT NULL CHECK (interval_minutes > 0 AND interval_minutes <= 1440),
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id, clock_code)
    REFERENCES ref_data.clock_rules(catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id, calendar_code)
    REFERENCES ref_data.calendars(catalog_id, revision_id, code)
);
COMMENT ON TABLE ref_data.delivery_profiles IS
  'Uniform specification only. No TOU/DST schedule generator is implemented by this table.';
CREATE TABLE ref_data.settlement_targets (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, code ref_data.code NOT NULL,
  kind text NOT NULL CHECK (kind IN ('future_series', 'index', 'index_difference')),
  index_a_code ref_data.code, index_b_code ref_data.code,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id) REFERENCES ref_data.revisions(catalog_id, id),
  FOREIGN KEY (catalog_id, revision_id, index_a_code)
    REFERENCES ref_data.price_index_definitions(catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id, index_b_code)
    REFERENCES ref_data.price_index_definitions(catalog_id, revision_id, code),
  CHECK ((kind = 'future_series' AND index_a_code IS NULL AND index_b_code IS NULL)
    OR (kind = 'index' AND index_a_code IS NOT NULL AND index_b_code IS NULL)
    OR (kind = 'index_difference' AND index_a_code IS NOT NULL AND index_b_code IS NOT NULL
      AND index_a_code <> index_b_code))
);
COMMENT ON TABLE ref_data.settlement_targets IS
  'Target identity only. Fixing aggregation, finality, payment and cash lifecycle are not implemented.';
CREATE TABLE ref_data.cash_rounding_conventions (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, code ref_data.code NOT NULL,
  currency_code ref_data.code NOT NULL,
  increment ref_data.exact_number NOT NULL CHECK (increment > 0),
  tie_rule text NOT NULL CHECK (tie_rule IN ('to_even', 'away_from_zero')),
  stage text NOT NULL CHECK (stage IN ('cashflow', 'payment_total')),
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id, currency_code)
    REFERENCES ref_data.currencies(catalog_id, revision_id, code)
);

CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.value_specifications
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.measurement_bases
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.quantity_specifications
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.quote_specifications
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.delivery_profiles
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.settlement_targets
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.cash_rounding_conventions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();

ALTER TABLE ref_data.futures_products DROP CONSTRAINT futures_products_lot_basis_check;
ALTER TABLE ref_data.futures_products ADD CHECK (lot_basis IN ('fixed_total', 'per_delivery_day', 'per_delivery_hour'));

CREATE SCHEMA market_data;
CREATE TABLE market_data.catalogs (
  id uuid PRIMARY KEY, code ref_data.code NOT NULL UNIQUE
);
CREATE TABLE market_data.revisions (
  catalog_id uuid NOT NULL REFERENCES market_data.catalogs(id), id uuid NOT NULL,
  reference_catalog_id uuid NOT NULL, reference_revision_id uuid NOT NULL,
  state text NOT NULL CHECK (state IN ('draft', 'sealed')),
  generation bigint NOT NULL CHECK (generation >= 0),
  PRIMARY KEY (catalog_id, id),
  UNIQUE (catalog_id, id, reference_catalog_id, reference_revision_id),
  FOREIGN KEY (reference_catalog_id, reference_revision_id) REFERENCES ref_data.revisions(catalog_id, id)
);
COMMENT ON TABLE market_data.revisions IS
  'Immutable definition bundle. Sealing is validation/freeze, not activation or known_from publication.';
CREATE TABLE market_data.contracts (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, id uuid NOT NULL,
  reference_catalog_id uuid NOT NULL, reference_revision_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('future', 'forward')),
  delivery_from date NOT NULL, delivery_to date NOT NULL, expiry_at ref_data.instant NOT NULL,
  futures_series_code ref_data.code,
  PRIMARY KEY (catalog_id, revision_id, id),
  UNIQUE (catalog_id, revision_id, futures_series_code),
  CHECK (isfinite(delivery_from) AND isfinite(delivery_to)
    AND delivery_from >= DATE '0001-01-01' AND delivery_to < DATE '9999-12-31'
    AND delivery_from < delivery_to),
  CHECK ((kind = 'future') = (futures_series_code IS NOT NULL)),
  FOREIGN KEY (catalog_id, revision_id, reference_catalog_id, reference_revision_id)
    REFERENCES market_data.revisions(catalog_id, id, reference_catalog_id, reference_revision_id),
  FOREIGN KEY (reference_catalog_id, reference_revision_id, futures_series_code)
    REFERENCES ref_data.futures_series(catalog_id, revision_id, code)
);
CREATE TABLE market_data.curves (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, code ref_data.code NOT NULL,
  reference_catalog_id uuid NOT NULL, reference_revision_id uuid NOT NULL,
  commodity_code ref_data.code NOT NULL, location_code ref_data.code NOT NULL,
  quote_code ref_data.code NOT NULL, profile_code ref_data.code NOT NULL,
  settlement_target_code ref_data.code NOT NULL,
  rule text NOT NULL CHECK (rule IN ('direct', 'add', 'scale_add')),
  direct_source_code ref_data.code,
  direct_role text CHECK (direct_role IN ('trader_mark', 'daily_settlement')),
  PRIMARY KEY (catalog_id, revision_id, code),
  CHECK ((rule = 'direct' AND direct_source_code IS NOT NULL AND direct_role IS NOT NULL)
    OR (rule <> 'direct' AND direct_source_code IS NULL AND direct_role IS NULL)),
  FOREIGN KEY (catalog_id, revision_id, reference_catalog_id, reference_revision_id)
    REFERENCES market_data.revisions(catalog_id, id, reference_catalog_id, reference_revision_id),
  FOREIGN KEY (reference_catalog_id, reference_revision_id, commodity_code, location_code)
    REFERENCES ref_data.commodity_locations(catalog_id, revision_id, commodity_code, location_code),
  FOREIGN KEY (reference_catalog_id, reference_revision_id, quote_code, commodity_code)
    REFERENCES ref_data.quote_specifications(catalog_id, revision_id, code, commodity_code),
  FOREIGN KEY (reference_catalog_id, reference_revision_id, profile_code)
    REFERENCES ref_data.delivery_profiles(catalog_id, revision_id, code),
  FOREIGN KEY (reference_catalog_id, reference_revision_id, settlement_target_code)
    REFERENCES ref_data.settlement_targets(catalog_id, revision_id, code),
  FOREIGN KEY (reference_catalog_id, reference_revision_id, direct_source_code)
    REFERENCES ref_data.sources(catalog_id, revision_id, code)
);
CREATE TABLE market_data.series (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, id uuid NOT NULL,
  code ref_data.code NOT NULL, reference_catalog_id uuid NOT NULL, reference_revision_id uuid NOT NULL,
  contract_id uuid, quote_code ref_data.code, value_specification_code ref_data.code,
  PRIMARY KEY (catalog_id,revision_id,id), UNIQUE (catalog_id,revision_id,code),
  UNIQUE (catalog_id,revision_id,contract_id,quote_code),
  FOREIGN KEY (catalog_id,revision_id,reference_catalog_id,reference_revision_id)
    REFERENCES market_data.revisions(catalog_id,id,reference_catalog_id,reference_revision_id),
  FOREIGN KEY (catalog_id,revision_id,contract_id) REFERENCES market_data.contracts(catalog_id,revision_id,id),
  FOREIGN KEY (reference_catalog_id,reference_revision_id,quote_code)
    REFERENCES ref_data.quote_specifications(catalog_id,revision_id,code),
  FOREIGN KEY (reference_catalog_id,reference_revision_id,value_specification_code)
    REFERENCES ref_data.value_specifications(catalog_id,revision_id,code),
  CHECK ((contract_id IS NOT NULL AND quote_code IS NOT NULL AND value_specification_code IS NULL)
    OR (contract_id IS NULL AND quote_code IS NULL AND value_specification_code IS NOT NULL))
);
COMMENT ON TABLE market_data.series IS 'Typed price or numeric history identity. Numeric series require no fictional contract.';
CREATE TABLE market_data.curve_members (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, curve_code ref_data.code NOT NULL,
  contract_id uuid NOT NULL, ordinal integer NOT NULL CHECK (ordinal >= 0),
  PRIMARY KEY (catalog_id, revision_id, curve_code, contract_id),
  UNIQUE (catalog_id, revision_id, curve_code, ordinal),
  FOREIGN KEY (catalog_id, revision_id, curve_code) REFERENCES market_data.curves(catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id, contract_id) REFERENCES market_data.contracts(catalog_id, revision_id, id)
);
CREATE TABLE market_data.curve_inputs (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, curve_code ref_data.code NOT NULL,
  slot text NOT NULL CHECK (slot IN ('base','spread','multiplier')), source_curve_code ref_data.code,
  expiry_rule text CHECK (expiry_rule IN ('require_live','freeze_final_future')),
  source_series_id uuid, constant_value ref_data.exact_number, value_specification_code ref_data.code,
  reference_catalog_id uuid, reference_revision_id uuid, numeric_source_code ref_data.code,
  numeric_role text CHECK (numeric_role='parameter'),
  PRIMARY KEY (catalog_id,revision_id,curve_code,slot),
  UNIQUE (catalog_id,revision_id,curve_code,slot,source_curve_code),
  CHECK (curve_code <> source_curve_code),
  CHECK ((slot IN ('base','spread') AND source_curve_code IS NOT NULL AND expiry_rule IS NOT NULL
      AND source_series_id IS NULL AND constant_value IS NULL AND value_specification_code IS NULL
      AND reference_catalog_id IS NULL AND reference_revision_id IS NULL AND numeric_source_code IS NULL AND numeric_role IS NULL)
    OR (slot='multiplier' AND source_curve_code IS NULL AND expiry_rule IS NULL
      AND reference_catalog_id IS NOT NULL AND reference_revision_id IS NOT NULL AND (
        (source_series_id IS NOT NULL AND constant_value IS NULL AND value_specification_code IS NULL
          AND numeric_source_code IS NOT NULL AND numeric_role IS NOT NULL AND numeric_role='parameter') OR
        (source_series_id IS NULL AND constant_value IS NOT NULL AND value_specification_code IS NOT NULL
          AND numeric_source_code IS NULL AND numeric_role IS NULL)))),
  FOREIGN KEY (catalog_id,revision_id,curve_code) REFERENCES market_data.curves(catalog_id,revision_id,code),
  FOREIGN KEY (catalog_id,revision_id,source_curve_code) REFERENCES market_data.curves(catalog_id,revision_id,code),
  FOREIGN KEY (catalog_id,revision_id,source_series_id) REFERENCES market_data.series(catalog_id,revision_id,id),
  FOREIGN KEY (catalog_id,revision_id,reference_catalog_id,reference_revision_id)
    REFERENCES market_data.revisions(catalog_id,id,reference_catalog_id,reference_revision_id),
  FOREIGN KEY (reference_catalog_id,reference_revision_id,value_specification_code)
    REFERENCES ref_data.value_specifications(catalog_id,revision_id,code),
  FOREIGN KEY (reference_catalog_id,reference_revision_id,numeric_source_code)
    REFERENCES ref_data.sources(catalog_id,revision_id,code)
);
CREATE TABLE market_data.constituent_mappings (
  catalog_id uuid NOT NULL, revision_id uuid NOT NULL, curve_code ref_data.code NOT NULL,
  slot text NOT NULL, target_contract_id uuid NOT NULL,
  source_curve_code ref_data.code NOT NULL, source_contract_id uuid NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, curve_code, slot, target_contract_id),
  FOREIGN KEY (catalog_id, revision_id, curve_code, slot, source_curve_code)
    REFERENCES market_data.curve_inputs(catalog_id, revision_id, curve_code, slot, source_curve_code),
  FOREIGN KEY (catalog_id, revision_id, curve_code, target_contract_id)
    REFERENCES market_data.curve_members(catalog_id, revision_id, curve_code, contract_id),
  FOREIGN KEY (catalog_id, revision_id, source_curve_code, source_contract_id)
    REFERENCES market_data.curve_members(catalog_id, revision_id, curve_code, contract_id)
);
COMMENT ON TABLE market_data.constituent_mappings IS
  'First supported mapping: explicitly paired equal delivery periods/profiles. No implicit matching or weights.';
CREATE FUNCTION market_data.guard_definition() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE s text;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Market definitions are immutable; create another revision' USING ERRCODE = '55000';
  END IF;
  SELECT state INTO s FROM market_data.revisions
    WHERE catalog_id = NEW.catalog_id AND id = NEW.revision_id FOR UPDATE;
  IF s IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Market revision is absent or frozen' USING ERRCODE = '55000';
  END IF;
  -- Change the locked revision row for every definition write. A stale
  -- repeatable-read/serializable sealer must then retry, never validate against
  -- a snapshot that misses a writer whose definitions entered the bundle.
  UPDATE market_data.revisions SET generation=generation+1
    WHERE catalog_id=NEW.catalog_id AND id=NEW.revision_id;
  RETURN NEW;
END;
$$;

-- Validate complete bundles at sealing, after insertion-order-independent FKs.
CREATE FUNCTION market_data.validate_revision(cat uuid, rev uuid) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM market_data.revisions m JOIN ref_data.revisions r
      ON (r.catalog_id,r.id) = (m.reference_catalog_id,m.reference_revision_id)
      WHERE m.catalog_id=cat AND m.id=rev AND r.state='sealed') THEN
    RAISE EXCEPTION 'Exact reference revision must be sealed' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.curves c
      WHERE c.catalog_id=cat AND c.revision_id=rev AND (
        NOT EXISTS (SELECT 1 FROM market_data.curve_members m WHERE
          (m.catalog_id,m.revision_id,m.curve_code)=(c.catalog_id,c.revision_id,c.code)) OR
        (SELECT count(*) FROM market_data.curve_inputs i WHERE
          (i.catalog_id,i.revision_id,i.curve_code)=(c.catalog_id,c.revision_id,c.code))
          <> CASE c.rule WHEN 'direct' THEN 0 WHEN 'add' THEN 2 ELSE 3 END OR
        (c.rule='scale_add') <> EXISTS (SELECT 1 FROM market_data.curve_inputs h WHERE
          (h.catalog_id,h.revision_id,h.curve_code)=(c.catalog_id,c.revision_id,c.code) AND h.slot='multiplier'))) THEN
    RAISE EXCEPTION 'Curve members, slots or multiplier configuration are incomplete' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.curve_inputs i
      JOIN market_data.curves c ON (c.catalog_id,c.revision_id,c.code)=(i.catalog_id,i.revision_id,i.curve_code)
      JOIN market_data.curves s ON (s.catalog_id,s.revision_id,s.code)=(i.catalog_id,i.revision_id,i.source_curve_code)
      JOIN ref_data.quote_specifications q ON (q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code)
      JOIN ref_data.quote_specifications sq ON (sq.catalog_id,sq.revision_id,sq.code)=(s.reference_catalog_id,s.reference_revision_id,s.quote_code)
      WHERE i.catalog_id=cat AND i.revision_id=rev AND (
        q.kind <> 'outright' OR c.profile_code <> s.profile_code OR
        (i.slot='spread' AND (sq.kind <> 'basis' OR
          (q.quantity_code,q.currency_code,q.multiplier) <> (sq.quantity_code,sq.currency_code,sq.multiplier))) OR
        (i.slot='base' AND (sq.kind <> 'outright' OR (c.rule='add' AND
          (q.quantity_code,q.currency_code,q.multiplier) <> (sq.quantity_code,sq.currency_code,sq.multiplier)))) OR
        (SELECT count(*) FROM market_data.constituent_mappings m WHERE
          (m.catalog_id,m.revision_id,m.curve_code,m.slot)=(i.catalog_id,i.revision_id,i.curve_code,i.slot)) <>
        (SELECT count(*) FROM market_data.curve_members m WHERE
          (m.catalog_id,m.revision_id,m.curve_code)=(i.catalog_id,i.revision_id,i.curve_code)))) THEN
    RAISE EXCEPTION 'Incompatible quote/profile types or incomplete mappings' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.curve_members a
      JOIN market_data.curve_members b ON (b.catalog_id,b.revision_id,b.contract_id)=(a.catalog_id,a.revision_id,a.contract_id)
        AND a.curve_code < b.curve_code
      JOIN market_data.curves c ON (c.catalog_id,c.revision_id,c.code)=(a.catalog_id,a.revision_id,a.curve_code)
      JOIN market_data.curves d ON (d.catalog_id,d.revision_id,d.code)=(b.catalog_id,b.revision_id,b.curve_code)
      JOIN ref_data.quote_specifications q ON (q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code)
      JOIN ref_data.quote_specifications z ON (z.catalog_id,z.revision_id,z.code)=(d.reference_catalog_id,d.reference_revision_id,d.quote_code)
      WHERE a.catalog_id=cat AND a.revision_id=rev AND
        (c.commodity_code,c.location_code,c.profile_code,q.quantity_code,q.currency_code,q.multiplier)
        <> (d.commodity_code,d.location_code,d.profile_code,z.quantity_code,z.currency_code,z.multiplier)) THEN
    RAISE EXCEPTION 'Contract membership cannot change common economic specifications' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.constituent_mappings m
      JOIN market_data.contracts t ON (t.catalog_id,t.revision_id,t.id)=(m.catalog_id,m.revision_id,m.target_contract_id)
      JOIN market_data.contracts s ON (s.catalog_id,s.revision_id,s.id)=(m.catalog_id,m.revision_id,m.source_contract_id)
      JOIN market_data.curve_inputs i ON (i.catalog_id,i.revision_id,i.curve_code,i.slot)=(m.catalog_id,m.revision_id,m.curve_code,m.slot)
      JOIN market_data.curves sc ON (sc.catalog_id,sc.revision_id,sc.code)=(m.catalog_id,m.revision_id,m.source_curve_code)
      WHERE m.catalog_id=cat AND m.revision_id=rev AND (
        (t.delivery_from,t.delivery_to) <> (s.delivery_from,s.delivery_to) OR
        (i.expiry_rule='freeze_final_future' AND (s.kind <> 'future' OR sc.rule <> 'direct')))) THEN
    RAISE EXCEPTION 'Unsupported delivery mapping or frozen-final source' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (WITH RECURSIVE walk AS (
      SELECT curve_code AS root, source_curve_code AS node, ARRAY[curve_code] AS visited,
        source_curve_code=curve_code AS cycle FROM market_data.curve_inputs
        WHERE catalog_id=cat AND revision_id=rev
      UNION ALL
      SELECT w.root,i.source_curve_code,w.visited || w.node,i.source_curve_code=ANY(w.visited || w.node)
        FROM walk w JOIN market_data.curve_inputs i ON i.curve_code=w.node
        WHERE i.catalog_id=cat AND i.revision_id=rev AND NOT w.cycle)
      SELECT 1 FROM walk WHERE cycle) THEN
    RAISE EXCEPTION 'Curve dependency cycle' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.curve_inputs m
      JOIN market_data.curves c ON (c.catalog_id,c.revision_id,c.code)=(m.catalog_id,m.revision_id,m.curve_code)
      JOIN market_data.curve_inputs b ON (b.catalog_id,b.revision_id,b.curve_code)=(m.catalog_id,m.revision_id,m.curve_code) AND b.slot='base'
      JOIN market_data.curves source ON (source.catalog_id,source.revision_id,source.code)=(b.catalog_id,b.revision_id,b.source_curve_code)
      JOIN ref_data.quote_specifications q ON (q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code)
      JOIN ref_data.quote_specifications sq ON (sq.catalog_id,sq.revision_id,sq.code)=(source.reference_catalog_id,source.reference_revision_id,source.quote_code)
      LEFT JOIN market_data.series series ON (series.catalog_id,series.revision_id,series.id)=(m.catalog_id,m.revision_id,m.source_series_id)
      LEFT JOIN ref_data.value_specifications v ON (v.catalog_id,v.revision_id,v.code)=
        (c.reference_catalog_id,c.reference_revision_id,COALESCE(m.value_specification_code,series.value_specification_code))
      WHERE m.catalog_id=cat AND m.revision_id=rev AND m.slot='multiplier' AND (
        v.code IS NULL OR (q.currency_code,q.multiplier) <> (sq.currency_code,sq.multiplier) OR
        (v.kind='quantity_ratio' AND (sq.quantity_code,q.quantity_code) <> (v.numerator_quantity_code,v.denominator_quantity_code)) OR
        (v.kind='dimensionless' AND sq.quantity_code <> q.quantity_code) OR
        (m.constant_value IS NOT NULL AND (m.constant_value < v.minimum OR m.constant_value > v.maximum)))) THEN
    RAISE EXCEPTION 'Multiplier value/type is incompatible with curve inputs/output' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.curve_members member
      JOIN market_data.curves c ON (c.catalog_id,c.revision_id,c.code)=(member.catalog_id,member.revision_id,member.curve_code)
      WHERE c.catalog_id=cat AND c.revision_id=rev AND c.rule='direct' AND NOT EXISTS (
        SELECT 1 FROM market_data.series s WHERE (s.catalog_id,s.revision_id,s.contract_id,s.quote_code)=
          (c.catalog_id,c.revision_id,member.contract_id,c.quote_code))) THEN
    RAISE EXCEPTION 'Direct constituents require exact price series' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.contracts k
      JOIN ref_data.futures_series s ON (s.catalog_id,s.revision_id,s.code)=(k.reference_catalog_id,k.reference_revision_id,k.futures_series_code)
      WHERE k.catalog_id=cat AND k.revision_id=rev AND (s.definition_state='placeholder' OR
        (s.delivery_from,s.delivery_to) IS DISTINCT FROM (k.delivery_from,k.delivery_to) OR
        NOT EXISTS (SELECT 1 FROM ref_data.futures_milestones x WHERE
          (x.catalog_id,x.revision_id,x.series_code)=(s.catalog_id,s.revision_id,s.code)
          AND x.milestone='last_trading' AND x.value_state='known' AND x.event_at=k.expiry_at))) THEN
    RAISE EXCEPTION 'Futures constituent must match a specified dated series' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.curve_members m
      JOIN market_data.contracts k ON (k.catalog_id,k.revision_id,k.id)=(m.catalog_id,m.revision_id,m.contract_id)
      JOIN market_data.curves c ON (c.catalog_id,c.revision_id,c.code)=(m.catalog_id,m.revision_id,m.curve_code)
      JOIN ref_data.settlement_targets t ON (t.catalog_id,t.revision_id,t.code)=(c.reference_catalog_id,c.reference_revision_id,c.settlement_target_code)
      JOIN ref_data.quote_specifications q ON (q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code)
      JOIN ref_data.quantity_specifications z ON (z.catalog_id,z.revision_id,z.code)=(q.catalog_id,q.revision_id,q.quantity_code)
      JOIN ref_data.delivery_profiles dp ON (dp.catalog_id,dp.revision_id,dp.code)=(c.reference_catalog_id,c.reference_revision_id,c.profile_code)
      LEFT JOIN ref_data.futures_series s ON (s.catalog_id,s.revision_id,s.code)=(k.reference_catalog_id,k.reference_revision_id,k.futures_series_code)
      LEFT JOIN ref_data.futures_products p ON (p.catalog_id,p.revision_id,p.code)=(s.catalog_id,s.revision_id,s.product_code)
      WHERE m.catalog_id=cat AND m.revision_id=rev AND (
        (t.kind='future_series' AND k.kind <> 'future') OR
        (k.kind='future' AND (p.definition_state='placeholder' OR t.kind <> 'future_series' OR q.kind <> 'outright' OR
          c.rule <> 'direct' OR c.direct_role IS DISTINCT FROM 'daily_settlement' OR
          (p.location_code IS NOT NULL AND p.location_code <> c.location_code) OR
          p.market_clock_code <> dp.clock_code OR p.delivery_calendar_code <> dp.calendar_code OR
          (p.commodity_code,p.quote_currency_code,p.quote_unit_code,p.quote_multiplier,p.outright_tick_size)
          IS DISTINCT FROM (c.commodity_code,q.currency_code,z.unit_code,q.multiplier,q.trading_tick))))) THEN
    RAISE EXCEPTION 'Constituent conflicts with common curve/futures specifications' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM market_data.curves c
      JOIN ref_data.settlement_targets t ON (t.catalog_id,t.revision_id,t.code)=(c.reference_catalog_id,c.reference_revision_id,c.settlement_target_code)
      JOIN ref_data.quote_specifications q ON (q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code)
      JOIN ref_data.quantity_specifications z ON (z.catalog_id,z.revision_id,z.code)=(q.catalog_id,q.revision_id,q.quantity_code)
      JOIN ref_data.price_index_definitions x ON (x.catalog_id,x.revision_id)=(t.catalog_id,t.revision_id)
        AND x.code IN (t.index_a_code,t.index_b_code)
      WHERE c.catalog_id=cat AND c.revision_id=rev AND
        (x.commodity_code,x.currency_code,x.quote_unit_code,x.quote_multiplier)
        <> (c.commodity_code,q.currency_code,z.unit_code,q.multiplier)) THEN
    RAISE EXCEPTION 'Settlement index target has incompatible commodity/quote units' USING ERRCODE = '23514';
  END IF;
END;
$$;
CREATE FUNCTION market_data.guard_revision() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF TG_OP='INSERT' AND NEW.state='draft' AND NEW.generation=0 THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND OLD.state='draft' AND NEW.state='draft'
    AND NEW.generation=OLD.generation+1
    AND (NEW.catalog_id,NEW.id,NEW.reference_catalog_id,NEW.reference_revision_id)
      = (OLD.catalog_id,OLD.id,OLD.reference_catalog_id,OLD.reference_revision_id) THEN
    RETURN NEW;
  END IF;
  IF TG_OP='UPDATE' AND OLD.state='draft' AND NEW.state='sealed'
    AND NEW.generation=OLD.generation
    AND (NEW.catalog_id,NEW.id,NEW.reference_catalog_id,NEW.reference_revision_id)
      = (OLD.catalog_id,OLD.id,OLD.reference_catalog_id,OLD.reference_revision_id) THEN
    PERFORM market_data.validate_revision(NEW.catalog_id,NEW.id);
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Only draft creation and validated sealing are allowed' USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER guard_revision BEFORE INSERT OR UPDATE OR DELETE ON market_data.revisions
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_revision();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.contracts
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.curves
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.curve_members
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.curve_inputs
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.constituent_mappings
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON market_data.series
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_definition();

CREATE TABLE market_data.observations (
  catalog_id uuid NOT NULL, id uuid NOT NULL, definition_revision_id uuid NOT NULL,
  series_id uuid NOT NULL, reference_catalog_id uuid NOT NULL, reference_revision_id uuid NOT NULL,
  source_code ref_data.code NOT NULL,
  source_event_id text NOT NULL CHECK (btrim(source_event_id) <> ''),
  source_revision_id text NOT NULL CHECK (btrim(source_revision_id) <> ''),
  role text NOT NULL CHECK (role IN ('trader_mark','daily_settlement','final_contract_settlement','parameter')),
  publication_state text NOT NULL CHECK (publication_state IN ('preliminary','final')),
  observed_at ref_data.instant NOT NULL, received_at ref_data.instant NOT NULL,
  value ref_data.exact_number NOT NULL, corrects_id uuid,
  PRIMARY KEY (catalog_id, id),
  UNIQUE (catalog_id, source_code, source_event_id, source_revision_id),
  UNIQUE (catalog_id, corrects_id),
  FOREIGN KEY (catalog_id, definition_revision_id, series_id) REFERENCES market_data.series(catalog_id, revision_id, id),
  FOREIGN KEY (catalog_id, definition_revision_id, reference_catalog_id, reference_revision_id)
    REFERENCES market_data.revisions(catalog_id, id, reference_catalog_id, reference_revision_id),
  FOREIGN KEY (reference_catalog_id, reference_revision_id, source_code)
    REFERENCES ref_data.sources(catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, corrects_id) REFERENCES market_data.observations(catalog_id, id),
  CHECK (corrects_id IS NULL OR corrects_id <> id),
  CHECK (observed_at <= received_at)
);
COMMENT ON COLUMN market_data.observations.received_at IS
  'Receipt audit metadata only; neither known_from nor proof of committed publication.';
CREATE INDEX observations_history ON market_data.observations
  (catalog_id, series_id, role, observed_at);
CREATE FUNCTION market_data.guard_observation() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE previous market_data.observations; q ref_data.quote_specifications;
  series market_data.series; v ref_data.value_specifications;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Observations are immutable; append a correction' USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM market_data.revisions WHERE catalog_id=NEW.catalog_id
      AND id=NEW.definition_revision_id AND state='sealed') THEN
    RAISE EXCEPTION 'Observations require sealed definitions' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO series FROM market_data.series WHERE (catalog_id,revision_id,id)=(NEW.catalog_id,NEW.definition_revision_id,NEW.series_id);
  IF series.id IS NOT NULL AND series.quote_code IS NOT NULL THEN
    SELECT * INTO q FROM ref_data.quote_specifications WHERE
      (catalog_id,revision_id,code)=(series.reference_catalog_id,series.reference_revision_id,series.quote_code);
    IF NEW.role='parameter' OR NEW.value < q.minimum OR NEW.value > q.maximum THEN
      RAISE EXCEPTION 'Price observation role/domain mismatch' USING ERRCODE = '23514';
    END IF;
    IF NEW.role IN ('daily_settlement','final_contract_settlement') AND mod(NEW.value,q.clearing_increment) <> 0 THEN
      RAISE EXCEPTION 'Settlement observation violates explicit clearing increment' USING ERRCODE = '23514';
    END IF;
  ELSIF series.id IS NOT NULL THEN
    SELECT * INTO v FROM ref_data.value_specifications WHERE
      (catalog_id,revision_id,code)=(series.reference_catalog_id,series.reference_revision_id,series.value_specification_code);
    IF NEW.role <> 'parameter' OR NEW.value < v.minimum OR NEW.value > v.maximum THEN
      RAISE EXCEPTION 'Numeric observation role/domain mismatch' USING ERRCODE = '23514';
    END IF;
  END IF;
  IF NEW.corrects_id IS NOT NULL THEN
    SELECT * INTO previous FROM market_data.observations WHERE catalog_id=NEW.catalog_id AND id=NEW.corrects_id;
    IF previous.id IS NULL THEN
      RAISE EXCEPTION 'Correction predecessor must already exist' USING ERRCODE = '23503';
    END IF;
    IF (
      (NEW.definition_revision_id,NEW.series_id,NEW.source_code,NEW.source_event_id,NEW.role,NEW.observed_at)
      IS DISTINCT FROM
      (previous.definition_revision_id,previous.series_id,previous.source_code,previous.source_event_id,previous.role,previous.observed_at)
      OR NEW.received_at < previous.received_at) THEN
      RAISE EXCEPTION 'Correction must preserve source fact identity and receipt ordering' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER guard_observation BEFORE INSERT OR UPDATE OR DELETE ON market_data.observations
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_observation();

-- No application/runtime roles or grants. Owners are trusted migration operators.
REVOKE ALL ON ALL TABLES IN SCHEMA ref_data FROM PUBLIC;
REVOKE ALL ON SCHEMA market_data FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA market_data FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA market_data FROM PUBLIC;
COMMIT;
