-- Schedules bind an exact reference calendar version (engine date_schedule_v2).
-- Existing date_schedule_v1 rows keep their retained inline calendar unchanged.
BEGIN;
COMMENT ON COLUMN ref_data.calendars.weekend_mask IS
  'Closed weekdays: bit 0 Monday, bit 1 Tuesday … bit 6 Sunday (ISO 8601 numbering). 96 closes Saturday and Sunday. calendar_days rows override a date: is_business_day false closes it, true opens it.';
ALTER TABLE market_data.date_schedule_versions
  ADD COLUMN calendar_catalog_id uuid,
  ADD COLUMN calendar_revision_id uuid,
  ADD COLUMN calendar_code ref_data.code,
  ADD CONSTRAINT schedule_calendar_version FOREIGN KEY (calendar_catalog_id, calendar_revision_id, calendar_code)
    REFERENCES ref_data.calendars(catalog_id, revision_id, code) ON DELETE RESTRICT,
  DROP CONSTRAINT date_schedule_versions_engine_version_check,
  ADD CONSTRAINT schedule_engine_calendar CHECK (
    (engine_version = 'date_schedule_v1' AND calendar_catalog_id IS NULL AND calendar_revision_id IS NULL
      AND calendar_code IS NULL AND jsonb_typeof(definition->'calendar') = 'object')
    OR (engine_version = 'date_schedule_v2' AND calendar_catalog_id IS NOT NULL AND calendar_revision_id IS NOT NULL
      AND calendar_code IS NOT NULL AND coalesce(jsonb_typeof(definition->'calendar'), 'null') = 'null'));
-- Drafts are working material: readers see published versions only; authors see drafts too.
ALTER POLICY scoped_read ON market_data.date_schedule_versions
  USING (security.market_access(catalog_id,'ReadMarketData') AND (state='published'
    OR security.market_access(catalog_id,'WriteMarketDefinitions') OR security.market_access(catalog_id,'SealMarketDefinitions')));
-- A runtime writer may bind only a calendar from a reference catalog it can read.
ALTER POLICY scoped_insert ON market_data.date_schedule_versions
  WITH CHECK (state='draft' AND publication_order IS NULL AND security.market_access(catalog_id,'WriteMarketDefinitions')
    AND (calendar_catalog_id IS NULL OR security.reference_access(calendar_catalog_id,'ReadMarketData')));
ALTER POLICY scoped_update ON market_data.date_schedule_versions
  USING (state='draft' AND security.market_access(catalog_id,'WriteMarketDefinitions'))
  WITH CHECK (state='draft' AND security.market_access(catalog_id,'WriteMarketDefinitions')
    AND (calendar_catalog_id IS NULL OR security.reference_access(calendar_catalog_id,'ReadMarketData')));
-- Only sealed reference revisions are immutable, so a schedule may bind only those.
-- Checked as the security owner so sealing is judged independently of the writer's
-- visibility; the row-security policies above judge catalog scope.
CREATE FUNCTION market_data.guard_schedule_calendar() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.calendar_code IS NOT NULL AND NOT EXISTS(SELECT 1 FROM ref_data.revisions r
     WHERE r.catalog_id=NEW.calendar_catalog_id AND r.id=NEW.calendar_revision_id AND r.state='sealed') THEN
   RAISE EXCEPTION 'Schedule calendars must come from a sealed reference revision' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
ALTER FUNCTION market_data.guard_schedule_calendar() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION market_data.guard_schedule_calendar() FROM PUBLIC;
CREATE TRIGGER guard_schedule_calendar BEFORE INSERT OR UPDATE ON market_data.date_schedule_versions
  FOR EACH ROW EXECUTE FUNCTION market_data.guard_schedule_calendar();
GRANT UPDATE (engine_version, calendar_catalog_id, calendar_revision_id, calendar_code)
  ON market_data.date_schedule_versions TO openetrm_runtime;
COMMIT;
