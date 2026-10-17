-- Qualified commit-time knowledge for independent schedules. Stock PG16+.
-- Apply before publications; pre-existing publications need verified migration evidence.
BEGIN;
DO $$ BEGIN
 IF current_setting('track_commit_timestamp')<>'on' THEN RAISE EXCEPTION 'Enable track_commit_timestamp before temporal installation'; END IF;
 IF EXISTS(SELECT 1 FROM market_data.date_schedule_versions WHERE state='published') THEN
   RAISE EXCEPTION 'Existing publications require verified full-XID migration evidence';
 END IF;
END $$;
ALTER TABLE market_data.date_schedule_versions ADD COLUMN publication_xid xid8;
ALTER TABLE market_data.date_schedule_versions ADD CONSTRAINT publication_xid_state CHECK((state='published')=(publication_xid IS NOT NULL));
ALTER TABLE market_data.date_schedule_versions ADD CONSTRAINT publication_transaction_identity UNIQUE(catalog_id,publication_order,publication_xid);
GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_system(),pg_catalog.pg_control_checkpoint() TO openetrm_security_owner;
CREATE TABLE market_data.knowledge_clocks (
 catalog_id uuid PRIMARY KEY REFERENCES market_data.catalogs(id), origin_xid xid8 NOT NULL,
 system_identifier text NOT NULL, timeline_id integer NOT NULL,
 coverage_from timestamptz, certified_through timestamptz, certified_head integer NOT NULL DEFAULT 0 CHECK(certified_head>=0),
 CHECK((coverage_from IS NULL)=(certified_through IS NULL)),
 CHECK(coverage_from IS NULL OR (isfinite(coverage_from) AND coverage_from<=certified_through AND certified_through<TIMESTAMPTZ '9999-12-31 00:00:00+00'))
);
CREATE TABLE market_data.knowledge_publications (
 catalog_id uuid NOT NULL, publication_order integer NOT NULL, publication_xid xid8 NOT NULL,
 known_from timestamptz NOT NULL CHECK(isfinite(known_from) AND known_from<TIMESTAMPTZ '9999-12-31 00:00:00+00'),
 PRIMARY KEY(catalog_id,publication_order),
 FOREIGN KEY(catalog_id,publication_order,publication_xid) REFERENCES market_data.date_schedule_versions(catalog_id,publication_order,publication_xid)
);
CREATE TABLE market_data.temporal_contexts (
 catalog_id uuid NOT NULL REFERENCES market_data.catalogs(id), id uuid NOT NULL,
 effective_on date NOT NULL CHECK(isfinite(effective_on) AND effective_on>=DATE '0001-01-01' AND effective_on<DATE '9999-12-31'),
 known_at timestamptz NOT NULL CHECK(isfinite(known_at)), known_through integer NOT NULL CHECK(known_through>=0),
 coverage_from timestamptz NOT NULL, certified_through timestamptz NOT NULL,
 PRIMARY KEY(catalog_id,id), UNIQUE(catalog_id,effective_on,known_at), CHECK(coverage_from<=known_at AND known_at<=certified_through)
);
CREATE FUNCTION market_data.guard_knowledge_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'Knowledge receipts are immutable' USING ERRCODE='55000'; END $$;
CREATE TRIGGER immutable_publication_receipt BEFORE UPDATE OR DELETE ON market_data.knowledge_publications
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
CREATE TRIGGER immutable_temporal_context BEFORE UPDATE OR DELETE ON market_data.temporal_contexts
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
REVOKE ALL ON FUNCTION market_data.guard_knowledge_receipt() FROM PUBLIC;
INSERT INTO market_data.knowledge_clocks(catalog_id,origin_xid,system_identifier,timeline_id) SELECT id,pg_current_xact_id(),(pg_control_system()).system_identifier::text,(pg_control_checkpoint()).timeline_id FROM market_data.catalogs;
CREATE FUNCTION security.initialize_knowledge_clock() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN INSERT INTO market_data.knowledge_clocks(catalog_id,origin_xid,system_identifier,timeline_id) VALUES(NEW.id,pg_current_xact_id(),(pg_control_system()).system_identifier::text,(pg_control_checkpoint()).timeline_id); RETURN NEW; END $$;
ALTER FUNCTION security.initialize_knowledge_clock() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.initialize_knowledge_clock() FROM PUBLIC;
CREATE TRIGGER initialize_knowledge_clock AFTER INSERT ON market_data.catalogs FOR EACH ROW EXECUTE FUNCTION security.initialize_knowledge_clock();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['knowledge_clocks','knowledge_publications','temporal_contexts'] LOOP
  EXECUTE format('ALTER TABLE market_data.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE market_data.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY scoped_read ON market_data.%I FOR SELECT TO openetrm_runtime USING(security.market_access(catalog_id,''ReadMarketData''))',t);
  EXECUTE format('GRANT SELECT ON market_data.%I TO openetrm_runtime',t);
 END LOOP;
END $$;
GRANT SELECT,INSERT ON market_data.knowledge_publications,market_data.temporal_contexts TO openetrm_security_owner;
GRANT SELECT,INSERT,UPDATE ON market_data.knowledge_clocks TO openetrm_security_owner;

CREATE FUNCTION security.checked_commit_time(full_xid xid8) RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE distance numeric; result timestamptz;
BEGIN
 IF current_setting('track_commit_timestamp')<>'on' THEN RAISE EXCEPTION 'knowledge_tracking' USING ERRCODE='P0001'; END IF;
 distance=pg_snapshot_xmax(pg_current_snapshot())::text::numeric-full_xid::text::numeric;
 IF distance<=0 OR distance>=2147483648 THEN RAISE EXCEPTION 'knowledge_retention' USING ERRCODE='P0001'; END IF;
 result=pg_xact_commit_timestamp(((full_xid::text::numeric % 4294967296)::bigint::text)::xid);
 IF result IS NULL THEN RAISE EXCEPTION 'knowledge_retention' USING ERRCODE='P0001'; END IF;
 IF NOT isfinite(result) OR result>=TIMESTAMPTZ '9999-12-31 00:00:00+00' THEN RAISE EXCEPTION 'knowledge_clock' USING ERRCODE='P0001'; END IF;
 RETURN result;
END $$;
ALTER FUNCTION security.checked_commit_time(xid8) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.checked_commit_time(xid8) FROM PUBLIC;

CREATE OR REPLACE FUNCTION security.publish_date_schedule(catalog uuid, schedule uuid, requested_version integer, expected_generation integer)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE row market_data.date_schedule_versions; next_order integer;
BEGIN
 IF NOT security.market_access(catalog,'SealMarketDefinitions') THEN RAISE EXCEPTION 'No current publishing permission' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT * INTO row FROM market_data.date_schedule_versions WHERE catalog_id=catalog AND schedule_id=schedule AND version=requested_version FOR UPDATE;
 IF row.schedule_id IS NULL OR row.generation IS DISTINCT FROM expected_generation THEN RAISE EXCEPTION 'Stale schedule version' USING ERRCODE='40001'; END IF;
 IF NOT security.market_access(catalog,'SealMarketDefinitions') THEN RAISE EXCEPTION 'Publishing authority expired during admission' USING ERRCODE='42501'; END IF;
 IF row.state='published' THEN RETURN row.publication_order; END IF;
 IF current_setting('track_commit_timestamp')<>'on' THEN RAISE EXCEPTION 'knowledge_tracking' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO next_order FROM market_data.date_schedule_versions WHERE catalog_id=catalog;
 UPDATE market_data.date_schedule_versions SET state='published',publication_order=next_order,published_at=clock_timestamp(),publication_xid=pg_current_xact_id()
  WHERE catalog_id=catalog AND schedule_id=schedule AND version=requested_version;
 RETURN next_order;
END $$;

CREATE FUNCTION security.capture_date_context(catalog uuid,effective_date date,requested_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE clock market_data.knowledge_clocks; row record; commit_at timestamptz; last_commit timestamptz; captured_at timestamptz; cutoff timestamptz; head integer; token uuid;
BEGIN
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'No current temporal read permission' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT * INTO clock FROM market_data.knowledge_clocks WHERE catalog_id=catalog FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'Temporal authority expired during admission' USING ERRCODE='42501'; END IF;
 IF current_setting('track_commit_timestamp')<>'on' THEN RAISE EXCEPTION 'knowledge_tracking' USING ERRCODE='P0001'; END IF;
 IF pg_is_in_recovery() OR clock.system_identifier IS DISTINCT FROM (pg_control_system()).system_identifier::text OR clock.timeline_id IS DISTINCT FROM (pg_control_checkpoint()).timeline_id THEN RAISE EXCEPTION 'knowledge_timeline' USING ERRCODE='P0001'; END IF;
 IF clock.coverage_from IS NULL THEN clock.coverage_from=security.checked_commit_time(clock.origin_xid); END IF;
 SELECT known_from INTO last_commit FROM market_data.knowledge_publications WHERE catalog_id=catalog ORDER BY publication_order DESC LIMIT 1;
 last_commit=coalesce(last_commit,clock.coverage_from);
 FOR row IN SELECT publication_order,publication_xid FROM market_data.date_schedule_versions
   WHERE catalog_id=catalog AND state='published' AND publication_order>clock.certified_head ORDER BY publication_order LOOP
  IF row.publication_order<>clock.certified_head+1 THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
  commit_at=security.checked_commit_time(row.publication_xid);
  -- A later commit must never enter an already certified knowledge interval.
  IF commit_at<last_commit OR (clock.certified_through IS NOT NULL AND commit_at<=clock.certified_through) THEN
   RAISE EXCEPTION 'knowledge_clock' USING ERRCODE='P0001';
  END IF;
  INSERT INTO market_data.knowledge_publications VALUES(catalog,row.publication_order,row.publication_xid,commit_at);
  clock.certified_head=row.publication_order;last_commit=commit_at;
 END LOOP;
 captured_at=clock_timestamp();
 IF captured_at<last_commit OR (clock.certified_through IS NOT NULL AND captured_at<clock.certified_through) THEN RAISE EXCEPTION 'knowledge_clock' USING ERRCODE='P0001'; END IF;
 cutoff=coalesce(requested_at,captured_at);
 IF NOT isfinite(cutoff) OR cutoff<clock.coverage_from OR cutoff>captured_at OR captured_at>=TIMESTAMPTZ '9999-12-31 00:00:00+00' THEN
  RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001';
 END IF;
 UPDATE market_data.knowledge_clocks SET coverage_from=clock.coverage_from,certified_through=captured_at,certified_head=clock.certified_head WHERE catalog_id=catalog;
 SELECT coalesce(max(publication_order),0) INTO head FROM market_data.knowledge_publications WHERE catalog_id=catalog AND known_from<=cutoff;
 SELECT id INTO token FROM market_data.temporal_contexts WHERE catalog_id=catalog AND effective_on=effective_date AND known_at=cutoff;
 IF token IS NOT NULL THEN
  IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'Temporal authority expired during certification' USING ERRCODE='42501'; END IF;
  RETURN token;
 END IF;
 IF (SELECT count(*) FROM market_data.temporal_contexts WHERE catalog_id=catalog)>=4096 THEN RAISE EXCEPTION 'knowledge_limit' USING ERRCODE='P0001'; END IF;
 token=gen_random_uuid();
 INSERT INTO market_data.temporal_contexts VALUES(catalog,token,effective_date,cutoff,head,clock.coverage_from,captured_at);
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'Temporal authority expired during certification' USING ERRCODE='42501'; END IF;
 RETURN token;
END $$;
ALTER FUNCTION security.capture_date_context(uuid,date,timestamptz) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.capture_date_context(uuid,date,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.capture_date_context(uuid,date,timestamptz) TO openetrm_runtime;

-- Partition the business axis at all retained boundaries, then close each
-- assertion's knowledge interval at its next correction for that exact segment.
-- Defining this view does not rewrite the original published version or receipt.
CREATE FUNCTION market_data.date_schedule_facts_at(catalog uuid,head integer)
RETURNS TABLE(catalog_id uuid,schedule_id uuid,version integer,generation integer,state text,definition jsonb,selection text,engine_version text,
 publication_order integer,published_at timestamptz,effective_from date,effective_to date,known_from timestamptz,known_to timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
WITH assertions AS (
 SELECT v.*, k.known_from FROM market_data.date_schedule_versions v JOIN market_data.knowledge_publications k USING(catalog_id,publication_order)
 WHERE v.catalog_id=$1 AND v.publication_order<=$2
), boundaries AS (
 SELECT a.catalog_id,a.schedule_id,a.effective_from AS point FROM assertions a UNION SELECT a.catalog_id,a.schedule_id,a.effective_to FROM assertions a
), segments AS (
 SELECT b.catalog_id,b.schedule_id,b.point AS effective_from,lead(b.point) OVER(PARTITION BY b.catalog_id,b.schedule_id ORDER BY b.point) AS effective_to FROM boundaries b
), rectangles AS (
 SELECT a.catalog_id,a.schedule_id,a.version,a.generation,a.state,a.definition,a.selection,a.engine_version,a.publication_order,a.published_at,
 s.effective_from,s.effective_to,a.known_from,
 coalesce(lead(a.known_from) OVER(PARTITION BY a.catalog_id,a.schedule_id,s.effective_from ORDER BY a.publication_order),TIMESTAMPTZ '9999-12-31 00:00:00+00') AS known_to
 FROM assertions a JOIN segments s ON s.catalog_id=a.catalog_id AND s.schedule_id=a.schedule_id
 AND a.effective_from<=s.effective_from AND s.effective_to<=a.effective_to WHERE s.effective_to IS NOT NULL
)
SELECT * FROM rectangles r WHERE r.known_from<r.known_to;
$$;
REVOKE ALL ON FUNCTION market_data.date_schedule_facts_at(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION market_data.date_schedule_facts_at(uuid,integer) TO openetrm_runtime;
CREATE VIEW market_data.date_schedule_facts WITH(security_invoker=true) AS
 SELECT facts.* FROM (SELECT DISTINCT catalog_id FROM market_data.knowledge_publications) c
 CROSS JOIN LATERAL market_data.date_schedule_facts_at(c.catalog_id,2147483647) facts;
GRANT SELECT ON market_data.date_schedule_facts TO openetrm_runtime;
COMMENT ON VIEW market_data.date_schedule_facts IS 'Half-open effective/known rectangles over immutable version assertions. Known time is certified engine-recorded commit time on the primary, not replica/client visibility.';
COMMIT;
