-- Initial reference-data storage. No booking/activation or historical publication.
-- All examples are installation data; this migration contains no real catalog.
BEGIN;
CREATE SCHEMA ref_data;

CREATE DOMAIN ref_data.code AS text
  CHECK (VALUE ~ '^[a-z][a-z0-9_.-]{0,63}$');
-- Reference capture bound, not the calculation engine's working-precision policy.
-- No numeric(p,s) coercion: excess scale/range is rejected, never rounded here.
CREATE DOMAIN ref_data.exact_number AS numeric
  CHECK (VALUE::text NOT IN ('NaN', 'Infinity', '-Infinity')
    AND scale(VALUE) <= 18 AND abs(VALUE) < 1e24);
CREATE DOMAIN ref_data.instant AS timestamptz
  CHECK (isfinite(VALUE) AND VALUE >= TIMESTAMPTZ '0001-01-01 00:00:00+00'
    AND VALUE < TIMESTAMPTZ '9999-12-31 00:00:00+00');

CREATE TABLE ref_data.catalogs (
  id uuid PRIMARY KEY,
  code ref_data.code NOT NULL UNIQUE,
  description text NOT NULL
);
CREATE TABLE ref_data.revisions (
  catalog_id uuid NOT NULL REFERENCES ref_data.catalogs(id) ON DELETE RESTRICT,
  id uuid NOT NULL,
  revision_key ref_data.code NOT NULL,
  state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft', 'sealed')),
  created_at ref_data.instant NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (catalog_id, id),
  UNIQUE (catalog_id, revision_key)
);
COMMENT ON COLUMN ref_data.revisions.created_at IS
  'Audit creation timestamp only; not known_from or proof of committed availability.';
COMMENT ON COLUMN ref_data.revisions.state IS
  'Storage freeze only. Sealed does not mean approved, entitled, active or published.';

CREATE TABLE ref_data.currencies (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  display_code text NOT NULL CHECK (display_code ~ '^[A-Z]{3}$'),
  name text NOT NULL CHECK (btrim(name) <> ''),
  display_minor_units smallint NOT NULL CHECK (display_minor_units BETWEEN 0 AND 12),
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  UNIQUE (catalog_id, revision_id, display_code)
);

CREATE TABLE ref_data.dimensions (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  mass_power smallint NOT NULL,
  length_power smallint NOT NULL,
  time_power smallint NOT NULL,
  temperature_power smallint NOT NULL,
  amount_power smallint NOT NULL,
  current_power smallint NOT NULL,
  luminous_power smallint NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  UNIQUE (catalog_id, revision_id, mass_power, length_power, time_power,
    temperature_power, amount_power, current_power, luminous_power)
);

CREATE TABLE ref_data.units (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  symbol text NOT NULL CHECK (btrim(symbol) <> ''),
  dimension_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, dimension_code)
    REFERENCES ref_data.dimensions(catalog_id, revision_id, code) ON DELETE RESTRICT,
  UNIQUE (catalog_id, revision_id, code, dimension_code)
);

CREATE TABLE ref_data.unit_conversions (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  from_unit_code ref_data.code NOT NULL,
  to_unit_code ref_data.code NOT NULL,
  dimension_code ref_data.code NOT NULL,
  factor_numerator ref_data.exact_number NOT NULL CHECK (factor_numerator > 0),
  factor_denominator ref_data.exact_number NOT NULL CHECK (factor_denominator > 0),
  PRIMARY KEY (catalog_id, revision_id, from_unit_code, to_unit_code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  CHECK (from_unit_code <> to_unit_code),
  FOREIGN KEY (catalog_id, revision_id, from_unit_code, dimension_code)
    REFERENCES ref_data.units(catalog_id, revision_id, code, dimension_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, to_unit_code, dimension_code)
    REFERENCES ref_data.units(catalog_id, revision_id, code, dimension_code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.commodities (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  quantity_dimension_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, quantity_dimension_code)
    REFERENCES ref_data.dimensions(catalog_id, revision_id, code) ON DELETE RESTRICT,
  UNIQUE (catalog_id, revision_id, code, quantity_dimension_code)
);

CREATE TABLE ref_data.commodity_units (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  commodity_code ref_data.code NOT NULL,
  unit_code ref_data.code NOT NULL,
  dimension_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, commodity_code, unit_code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, commodity_code, dimension_code)
    REFERENCES ref_data.commodities(catalog_id, revision_id, code, quantity_dimension_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, unit_code, dimension_code)
    REFERENCES ref_data.units(catalog_id, revision_id, code, dimension_code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.clock_rules (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  kind text NOT NULL CHECK (kind IN ('fixed_offset', 'iana')),
  fixed_offset_seconds integer,
  iana_zone text,
  tzdb_version text,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  CHECK ((kind = 'fixed_offset' AND fixed_offset_seconds IS NOT NULL
    AND fixed_offset_seconds BETWEEN -64800 AND 64800
    AND iana_zone IS NULL AND tzdb_version IS NULL)
    OR (kind = 'iana' AND fixed_offset_seconds IS NULL
    AND iana_zone IS NOT NULL AND btrim(iana_zone) <> ''
    AND tzdb_version IS NOT NULL AND btrim(tzdb_version) <> ''))
);

CREATE TABLE ref_data.calendars (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  clock_code ref_data.code NOT NULL,
  weekend_mask smallint NOT NULL CHECK (weekend_mask BETWEEN 0 AND 127),
  coverage_from date NOT NULL,
  coverage_to date NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, clock_code)
    REFERENCES ref_data.clock_rules(catalog_id, revision_id, code) ON DELETE RESTRICT,
  CHECK (isfinite(coverage_from) AND isfinite(coverage_to)
    AND coverage_from >= DATE '0001-01-01' AND coverage_to < DATE '9999-12-31'
    AND coverage_from < coverage_to)
);

CREATE TABLE ref_data.calendar_days (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  calendar_code ref_data.code NOT NULL,
  business_date date NOT NULL CHECK (isfinite(business_date)
    AND business_date >= DATE '0001-01-01' AND business_date < DATE '9999-12-31'),
  is_business_day boolean NOT NULL,
  description text NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, calendar_code, business_date),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, calendar_code)
    REFERENCES ref_data.calendars(catalog_id, revision_id, code) ON DELETE RESTRICT
);

COMMENT ON COLUMN ref_data.calendars.coverage_to IS 'Exclusive bound [coverage_from, coverage_to). Weekend mask bit 0 is Monday.';

CREATE TABLE ref_data.location_types (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  description text NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT
);

CREATE TABLE ref_data.locations (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  type_code ref_data.code NOT NULL,
  clock_code ref_data.code,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, type_code)
    REFERENCES ref_data.location_types(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, clock_code)
    REFERENCES ref_data.clock_rules(catalog_id, revision_id, code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.commodity_locations (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  commodity_code ref_data.code NOT NULL,
  location_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, commodity_code, location_code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, commodity_code)
    REFERENCES ref_data.commodities(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, location_code)
    REFERENCES ref_data.locations(catalog_id, revision_id, code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.exchanges (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT
);

CREATE TABLE ref_data.clearing_houses (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT
);

CREATE TABLE ref_data.exchange_clearing_houses (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  exchange_code ref_data.code NOT NULL,
  clearing_house_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, exchange_code, clearing_house_code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, exchange_code)
    REFERENCES ref_data.exchanges(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, clearing_house_code)
    REFERENCES ref_data.clearing_houses(catalog_id, revision_id, code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.day_count_conventions (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  algorithm_id text NOT NULL CHECK (btrim(algorithm_id) <> ''),
  algorithm_version text NOT NULL CHECK (btrim(algorithm_version) <> ''),
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT
);

CREATE TABLE ref_data.compounding_conventions (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  method text NOT NULL CHECK (method IN ('simple', 'periodic', 'continuous')),
  periods_per_year integer,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  CHECK ((method = 'periodic' AND periods_per_year IS NOT NULL AND periods_per_year > 0)
    OR (method <> 'periodic' AND periods_per_year IS NULL))
);

CREATE TABLE ref_data.fx_rate_definitions (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  base_currency_code ref_data.code NOT NULL,
  quote_currency_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, base_currency_code)
    REFERENCES ref_data.currencies(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, quote_currency_code)
    REFERENCES ref_data.currencies(catalog_id, revision_id, code) ON DELETE RESTRICT,
  CHECK (base_currency_code <> quote_currency_code)
);

COMMENT ON TABLE ref_data.fx_rate_definitions IS 'Definition only: quote currency per one base currency; no current quote or observation stored here.';

CREATE TABLE ref_data.interest_rate_definitions (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  currency_code ref_data.code NOT NULL,
  calendar_code ref_data.code NOT NULL,
  day_count_code ref_data.code NOT NULL,
  compounding_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, currency_code)
    REFERENCES ref_data.currencies(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, calendar_code)
    REFERENCES ref_data.calendars(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, day_count_code)
    REFERENCES ref_data.day_count_conventions(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, compounding_code)
    REFERENCES ref_data.compounding_conventions(catalog_id, revision_id, code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.heat_rate_definitions (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  fuel_commodity_code ref_data.code NOT NULL,
  output_commodity_code ref_data.code NOT NULL,
  fuel_unit_code ref_data.code NOT NULL,
  output_unit_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, fuel_commodity_code, fuel_unit_code)
    REFERENCES ref_data.commodity_units(catalog_id, revision_id, commodity_code, unit_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, output_commodity_code, output_unit_code)
    REFERENCES ref_data.commodity_units(catalog_id, revision_id, commodity_code, unit_code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.price_index_definitions (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  commodity_code ref_data.code NOT NULL,
  location_code ref_data.code NOT NULL,
  currency_code ref_data.code NOT NULL,
  quote_unit_code ref_data.code NOT NULL,
  quote_multiplier ref_data.exact_number NOT NULL CHECK (quote_multiplier > 0),
  calendar_code ref_data.code NOT NULL,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, commodity_code, quote_unit_code)
    REFERENCES ref_data.commodity_units(catalog_id, revision_id, commodity_code, unit_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, commodity_code, location_code)
    REFERENCES ref_data.commodity_locations(catalog_id, revision_id, commodity_code, location_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, currency_code)
    REFERENCES ref_data.currencies(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, calendar_code)
    REFERENCES ref_data.calendars(catalog_id, revision_id, code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.sources (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  kind text NOT NULL CHECK (kind IN ('synthetic', 'manual_entry', 'external_document', 'licensed_feed')),
  locator text NOT NULL CHECK (btrim(locator) <> ''),
  retrieved_at ref_data.instant NOT NULL,
  content_sha256 text CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  license_reference text,
  distribution_review text NOT NULL DEFAULT 'not_reviewed'
    CHECK (distribution_review IN ('not_reviewed', 'restricted', 'redistributable')),
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT
);

COMMENT ON COLUMN ref_data.sources.distribution_review IS 'Provenance metadata only, not an authorization or redistribution grant.';

CREATE TABLE ref_data.futures_products (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  name text NOT NULL CHECK (btrim(name) <> ''),
  definition_state text NOT NULL DEFAULT 'placeholder'
    CHECK (definition_state IN ('placeholder', 'candidate', 'synthetic')),
  exchange_code ref_data.code NOT NULL,
  clearing_house_code ref_data.code,
  commodity_code ref_data.code,
  location_code ref_data.code,
  quote_currency_code ref_data.code,
  lot_unit_code ref_data.code,
  quote_unit_code ref_data.code,
  lot_basis text CHECK (lot_basis IN ('fixed_total', 'per_delivery_hour')),
  contract_size ref_data.exact_number CHECK (contract_size > 0),
  quote_multiplier ref_data.exact_number CHECK (quote_multiplier > 0),
  outright_tick_size ref_data.exact_number CHECK (outright_tick_size > 0),
  settlement_method text CHECK (settlement_method IN ('cash', 'physical')),
  market_clock_code ref_data.code,
  trading_calendar_code ref_data.code,
  delivery_calendar_code ref_data.code,
  settlement_calendar_code ref_data.code,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, exchange_code)
    REFERENCES ref_data.exchanges(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, exchange_code, clearing_house_code)
    REFERENCES ref_data.exchange_clearing_houses(catalog_id, revision_id, exchange_code, clearing_house_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, commodity_code)
    REFERENCES ref_data.commodities(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, location_code)
    REFERENCES ref_data.locations(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, commodity_code, location_code)
    REFERENCES ref_data.commodity_locations(catalog_id, revision_id, commodity_code, location_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, quote_currency_code)
    REFERENCES ref_data.currencies(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, lot_unit_code)
    REFERENCES ref_data.units(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, quote_unit_code)
    REFERENCES ref_data.units(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, commodity_code, lot_unit_code)
    REFERENCES ref_data.commodity_units(catalog_id, revision_id, commodity_code, unit_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, commodity_code, quote_unit_code)
    REFERENCES ref_data.commodity_units(catalog_id, revision_id, commodity_code, unit_code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, market_clock_code)
    REFERENCES ref_data.clock_rules(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, trading_calendar_code)
    REFERENCES ref_data.calendars(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, delivery_calendar_code)
    REFERENCES ref_data.calendars(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, settlement_calendar_code)
    REFERENCES ref_data.calendars(catalog_id, revision_id, code) ON DELETE RESTRICT,
  CHECK ((lot_unit_code IS NULL AND quote_unit_code IS NULL AND location_code IS NULL)
    OR commodity_code IS NOT NULL),
  CHECK (definition_state = 'placeholder' OR
    (clearing_house_code IS NOT NULL AND commodity_code IS NOT NULL
    AND quote_currency_code IS NOT NULL AND lot_unit_code IS NOT NULL
    AND quote_unit_code IS NOT NULL AND lot_basis IS NOT NULL
    AND contract_size IS NOT NULL AND quote_multiplier IS NOT NULL
    AND outright_tick_size IS NOT NULL AND settlement_method IS NOT NULL
    AND market_clock_code IS NOT NULL AND trading_calendar_code IS NOT NULL
    AND delivery_calendar_code IS NOT NULL AND settlement_calendar_code IS NOT NULL))
);

CREATE TABLE ref_data.product_evidence (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  product_code ref_data.code NOT NULL,
  source_code ref_data.code NOT NULL,
  fact_group text NOT NULL CHECK (fact_group IN ('units', 'listing', 'dates', 'settlement', 'tick_rules')),
  PRIMARY KEY (catalog_id, revision_id, product_code, source_code, fact_group),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, product_code)
    REFERENCES ref_data.futures_products(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, source_code)
    REFERENCES ref_data.sources(catalog_id, revision_id, code) ON DELETE RESTRICT
);

CREATE TABLE ref_data.futures_series (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  code ref_data.code NOT NULL,
  product_code ref_data.code NOT NULL,
  series_label text NOT NULL CHECK (btrim(series_label) <> ''),
  definition_state text NOT NULL DEFAULT 'placeholder'
    CHECK (definition_state IN ('placeholder', 'candidate', 'synthetic')),
  delivery_from date,
  delivery_to date,
  PRIMARY KEY (catalog_id, revision_id, code),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, product_code)
    REFERENCES ref_data.futures_products(catalog_id, revision_id, code) ON DELETE RESTRICT,
  UNIQUE (catalog_id, revision_id, product_code, series_label),
  CHECK ((delivery_from IS NULL AND delivery_to IS NULL)
    OR (delivery_from IS NOT NULL AND delivery_to IS NOT NULL
    AND isfinite(delivery_from) AND isfinite(delivery_to)
    AND delivery_from >= DATE '0001-01-01' AND delivery_to < DATE '9999-12-31'
    AND delivery_from < delivery_to)),
  CHECK (definition_state = 'placeholder' OR delivery_from IS NOT NULL)
);

COMMENT ON COLUMN ref_data.futures_series.delivery_to IS 'Exclusive local delivery-date bound [delivery_from, delivery_to); not a UTC instant.';

CREATE TABLE ref_data.futures_milestones (
  catalog_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  series_code ref_data.code NOT NULL,
  milestone text NOT NULL CHECK (milestone IN
    ('first_trading', 'last_trading', 'first_notice', 'last_notice', 'final_settlement', 'delivery_start', 'delivery_end')),
  value_state text NOT NULL CHECK (value_state IN ('unknown', 'known', 'not_applicable')),
  business_date date CHECK (isfinite(business_date)
    AND business_date >= DATE '0001-01-01' AND business_date < DATE '9999-12-31'),
  event_at ref_data.instant,
  clock_code ref_data.code,
  source_code ref_data.code,
  PRIMARY KEY (catalog_id, revision_id, series_code, milestone),
  FOREIGN KEY (catalog_id, revision_id)
    REFERENCES ref_data.revisions(catalog_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, series_code)
    REFERENCES ref_data.futures_series(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, clock_code)
    REFERENCES ref_data.clock_rules(catalog_id, revision_id, code) ON DELETE RESTRICT,
  FOREIGN KEY (catalog_id, revision_id, source_code)
    REFERENCES ref_data.sources(catalog_id, revision_id, code) ON DELETE RESTRICT,
  CHECK ((value_state = 'known' AND business_date IS NOT NULL
    AND clock_code IS NOT NULL AND source_code IS NOT NULL)
    OR (value_state <> 'known' AND business_date IS NULL AND event_at IS NULL)),
  CHECK (value_state <> 'not_applicable' OR source_code IS NOT NULL)
);

-- Lock the revision while inserting, so a concurrent seal waits for in-flight
-- inserts and a writer waiting behind the seal sees the sealed state.
CREATE FUNCTION ref_data.guard_definition() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE revision_state text;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Reference rows are immutable; create a new revision'
      USING ERRCODE = '55000';
  END IF;
  SELECT state INTO revision_state FROM ref_data.revisions
    WHERE catalog_id = NEW.catalog_id AND id = NEW.revision_id FOR SHARE;
  IF revision_state IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Reference revision is absent or frozen'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION ref_data.guard_revision() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.state = 'draft' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.state = 'draft' AND NEW.state = 'sealed'
    AND NEW.catalog_id = OLD.catalog_id AND NEW.id = OLD.id
    AND NEW.revision_key = OLD.revision_key AND NEW.created_at = OLD.created_at
  THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Only creation as draft and draft-to-sealed freeze are allowed'
    USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER guard_revision BEFORE INSERT OR UPDATE OR DELETE ON ref_data.revisions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_revision();

CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.currencies
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.dimensions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.units
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.unit_conversions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.commodities
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.commodity_units
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.clock_rules
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.calendars
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.calendar_days
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.location_types
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.locations
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.commodity_locations
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.exchanges
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.clearing_houses
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.exchange_clearing_houses
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.day_count_conventions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.compounding_conventions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.fx_rate_definitions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.interest_rate_definitions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.heat_rate_definitions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.price_index_definitions
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.sources
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.futures_products
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.product_evidence
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.futures_series
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();
CREATE TRIGGER guard_definition BEFORE INSERT OR UPDATE OR DELETE ON ref_data.futures_milestones
  FOR EACH ROW EXECUTE FUNCTION ref_data.guard_definition();

-- Runtime roles must not own the schema or receive TRUNCATE/DDL/trigger-bypass
-- privileges. This prototype grants no application role access.
REVOKE ALL ON SCHEMA ref_data FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA ref_data FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ref_data FROM PUBLIC;
COMMIT;
