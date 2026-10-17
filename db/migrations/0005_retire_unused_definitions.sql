-- Retire speculative reference catalogs. Retain only the explicitly supported
-- interest convention identifiers on the interest-rate definition itself.
-- Never discard an installation's retained rows or dependent extension tables.
BEGIN;
SET LOCAL row_security=off;
DO $$
DECLARE table_name text; populated boolean;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'Reference retirement requires READ COMMITTED' USING ERRCODE='25000';
  END IF;
  FOREACH table_name IN ARRAY ARRAY['day_count_conventions','compounding_conventions',
      'interest_rate_definitions','fx_rate_definitions','heat_rate_definitions'] LOOP
    EXECUTE format('LOCK TABLE ref_data.%I IN ACCESS EXCLUSIVE MODE',table_name);
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM ref_data.%I)',table_name) INTO populated;
    IF populated THEN
      RAISE EXCEPTION 'Reference retirement requires explicit reconciliation: % contains retained rows',table_name
        USING ERRCODE='55000';
    END IF;
  END LOOP;
END;
$$;
ALTER TABLE ref_data.interest_rate_definitions
  DROP COLUMN day_count_code,
  DROP COLUMN compounding_code,
  ADD COLUMN day_count text NOT NULL CHECK (day_count='actual_365_fixed'),
  ADD COLUMN compounding text NOT NULL CHECK (compounding='simple'),
  ADD COLUMN implementation text NOT NULL CHECK (implementation='openetrm_rates_v1');
DROP TABLE ref_data.fx_rate_definitions;
DROP TABLE ref_data.heat_rate_definitions;
DROP TABLE ref_data.day_count_conventions;
DROP TABLE ref_data.compounding_conventions;
COMMENT ON TABLE ref_data.interest_rate_definitions IS
  'Interest-rate identity with explicit supported convention and implementation IDs. No default conventions or broad imported catalogs. Current consumer: dated simple zero rates to discount factors.';
COMMIT;
