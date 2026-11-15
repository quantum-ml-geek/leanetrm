"""Independent published-clock boundaries and immutable reference admission."""
import hashlib
import json
from uuid import uuid4


def run_checks(query, manifest):
    assert query("SELECT to_regclass('ref_data.clock_captures') IS NOT NULL;") == 't', 'Power clock captures must be published reference definitions, not untrusted booking assertions.'
    reference=manifest['referenceCatalogId'];revision=str(uuid4())
    draft=str(uuid4());product=str(uuid4())
    query(f"""BEGIN;
      INSERT INTO ref_data.revisions(catalog_id,id,revision_key) VALUES('{reference}','{draft}','synthetic_uncaptured_clock');
      INSERT INTO ref_data.clock_rules VALUES('{reference}','{draft}','synthetic_uncaptured','fixed_offset',0,NULL,NULL);
      UPDATE ref_data.revisions SET state='sealed' WHERE(catalog_id,id)=('{reference}','{draft}');
      INSERT INTO market_data.tou_products VALUES('{manifest['catalogId']}','{product}','synthetic_uncaptured');
      DO $$BEGIN BEGIN
       INSERT INTO market_data.tou_product_versions(catalog_id,product_id,version,generation,state,name,clock_catalog_id,clock_revision_id,clock_code,peak_start_hour,peak_end_hour,peak_saturday,calendar_catalog_id,calendar_revision_id,calendar_code,holiday_treatment)
       VALUES('{manifest['catalogId']}','{product}',1,1,'draft','Synthetic uncaptured clock','{reference}','{draft}','synthetic_uncaptured',7,23,false,'{reference}','{manifest['referenceRevisionId']}','test_utc_every_day','weekly_mask_explicit_closures_v1');
       RAISE EXCEPTION 'TOU without published clock capture accepted';
       EXCEPTION WHEN foreign_key_violation THEN NULL;END;END$$;ROLLBACK;""")
    payload=json.dumps(dict(Implementation='captured_power_grid_clock_v1',Id='synthetic_plus_one',
        From='2026-12-31T23:00:00+00:00',To='2027-01-31T23:00:00+00:00',
        Runs=[dict(From='2026-12-31T23:00:00+00:00',Minutes=60)]),separators=(',',':'))
    digest=hashlib.sha256(payload.encode()).hexdigest()
    # Preserve wire bytes: jsonb normalization must not admit syntax that the
    # managed published-clock reader cannot execute.
    for number, invalid in enumerate([payload.replace('"Minutes":60', '"Minutes":60e0'),
                                      payload.replace('T23:00:00', ' 23:00:00'),
                                      payload.replace('T23:00:00', 'T23:00:00.0000001'),
                                      payload.replace('"Minutes":60', '"Minutes":60,"Minutes":60'),
                                      payload.replace('"Minutes":60', '"Minutes":"invalid","Minutes":60'),
                                      payload.replace('"Implementation":', '"Implementation":"captured_power_grid_clock_v1","Implementation":')]):
        draft=str(uuid4());invalid_digest=hashlib.sha256(invalid.encode()).hexdigest()
        query(f"""BEGIN;
          INSERT INTO ref_data.revisions(catalog_id,id,revision_key) VALUES('{reference}','{draft}','synthetic_invalid_clock_{number}');
          INSERT INTO ref_data.clock_rules VALUES('{reference}','{draft}','synthetic_plus_one','fixed_offset',3600,NULL,NULL);
          DO $$BEGIN
           BEGIN INSERT INTO ref_data.clock_captures VALUES('{reference}','{draft}','synthetic_plus_one','2027-01-01','2027-02-01','{invalid}',decode('{invalid_digest}','hex'),NULL);
            RAISE EXCEPTION 'invalid clock wire accepted';
           EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'clock_capture' THEN RAISE;END IF;END;
          END$$;ROLLBACK;""")
    query(f"""BEGIN;
      INSERT INTO ref_data.revisions(catalog_id,id,revision_key) VALUES('{reference}','{revision}','synthetic_clock_capture');
      INSERT INTO ref_data.clock_rules VALUES('{reference}','{revision}','synthetic_plus_one','fixed_offset',3600,NULL,NULL);
      INSERT INTO ref_data.clock_captures VALUES('{reference}','{revision}','synthetic_plus_one','2027-01-01','2027-02-01','{payload}',decode('{digest}','hex'),NULL);
      UPDATE ref_data.revisions SET state='sealed' WHERE(catalog_id,id)=('{reference}','{revision}');COMMIT;""")
    query(f"SELECT ref_data.publish_clock_capture('{reference}','{revision}','synthetic_plus_one','2027-01-01','2027-02-01','{payload}',decode('{digest}','hex'),NULL);")
    assert query(f"SELECT count(*) FROM ref_data.clock_captures WHERE(catalog_id,revision_id)=('{reference}','{revision}');")=='1'
    assert query(f"SELECT to_char(ref_data.clock_boundary('{reference}','{revision}','synthetic_plus_one','2027-02-01') AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS');")=='2027-01-31 23:00:00'
    query(f"""DO $$BEGIN
      BEGIN PERFORM ref_data.clock_boundary('{reference}','{revision}','synthetic_plus_one','2027-02-02');RAISE EXCEPTION 'uncovered clock accepted';
       EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'clock_coverage' THEN RAISE;END IF;END;
      BEGIN PERFORM ref_data.publish_clock_capture('{reference}','{revision}','synthetic_plus_one','2027-01-01','2027-02-02','{payload}',decode('{digest}','hex'),NULL);RAISE EXCEPTION 'changed retry accepted';
       EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'clock_capture_conflict' THEN RAISE;END IF;END;
      BEGIN UPDATE ref_data.clock_captures SET payload=replace(payload,'60','120') WHERE(catalog_id,revision_id)=('{reference}','{revision}');RAISE EXCEPTION 'clock edit accepted';
       EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
    END$$;""")
    assert query(f"SELECT to_char(ref_data.clock_local('{reference}','{revision}','synthetic_plus_one','2027-01-31T23:00:00Z'),'YYYY-MM-DD HH24:MI:SS');")=='2027-02-01 00:00:00'
    assert query(f"SELECT market_data.ppa_day_boundary('2027-01-31T23:00:00Z','{reference}','{revision}','synthetic_plus_one');")=='t'
    assert query(f"SELECT market_data.ppa_day_boundary('2027-01-31T22:00:00Z','{reference}','{revision}','synthetic_plus_one');")=='f'
    # An arbitrary 24-hour interval is not a contractual operating day.
    for start, end, fingerprint in [('2027-01-01T00:00:00Z','2027-01-02T00:00:00Z',digest),
                                    ('2026-12-31T23:00:00Z','2027-01-01T23:00:00Z','a'*64)]:
        query(f"""DO $$BEGIN BEGIN
          INSERT INTO power_data.operating_days VALUES('{reference}','{revision}','synthetic_plus_one','2027-01-01','{start}','{end}','{fingerprint}');
          RAISE EXCEPTION 'divergent operating day accepted';
          EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'collection_clock' THEN RAISE;END IF;END;END$$;""")
    for _ in range(2):
        query(f"SELECT power_data.publish_operating_day('{reference}','{revision}','synthetic_plus_one','2027-01-01');")
    assert query(f"SELECT count(*) FROM power_data.operating_days WHERE(reference_catalog_id,reference_revision_id)=('{reference}','{revision}');")=='1'
    assert query(f"SELECT to_char(starts_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS')||'|'||to_char(ends_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS') FROM power_data.operating_days WHERE(reference_catalog_id,reference_revision_id)=('{reference}','{revision}');")=='2026-12-31 23:00:00|2027-01-01 23:00:00'
    assert query("SELECT has_function_privilege('openetrm_collector','power_data.publish_operating_day(uuid,uuid,text,date)','EXECUTE');")=='f'
    assert query("SELECT has_table_privilege('openetrm_runtime','ref_data.clock_captures','UPDATE'),has_table_privilege('openetrm_runtime','ref_data.clock_captures','INSERT');")=='f|f'
    assert query("SELECT has_function_privilege('openetrm_runtime','ref_data.publish_clock_capture(uuid,uuid,text,date,date,text,bytea,text)','EXECUTE');")=='f'
    assert query("SELECT array_position(security.reference_display_tables(),'clock_captures')>array_position(security.reference_display_tables(),'clock_rules');")=='t'
    assert query("SET SESSION AUTHORIZATION preview_runtime;SELECT count(*) FROM ref_data.clock_captures;")=='0'
    print('PASS published clock: exact positive-offset boundary, inclusive endpoint, coverage refusal, immutable capture and unbound authority',flush=True)
