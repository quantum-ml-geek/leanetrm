"""Storage adversarial checks; called only in a newly owned preview cluster."""
import os
import subprocess
import time
from uuid import UUID, uuid4


def run_checks(query, psql, environment, manifest):
    catalog = str(UUID(manifest['catalogId'])); tenant = str(UUID(manifest['tenantId'])); workspace = str(UUID(manifest['workspaceId']))
    passed = 0
    children = []
    def check(name, condition=True):
        nonlocal passed
        assert condition, name
        passed += 1
        print('PASS ' + name, flush=True)
    def issue(profile='approver', seconds=60):
        return query("SET SESSION AUTHORIZATION preview_authenticator; SELECT security.issue_context("
                     f"'https://preview.invalid','{profile}','human_interactive','{tenant}','{workspace}',NULL,'preview_runtime',{seconds});")
    def runtime(token, statement):
        return f"SET SESSION AUTHORIZATION preview_runtime; BEGIN; SELECT security.use_context('{token}'); {statement} COMMIT;"
    def expect(sql, code):
        return f"DO $$ BEGIN {sql} RAISE EXCEPTION 'Expected rejection'; EXCEPTION WHEN SQLSTATE '{code}' THEN NULL; END $$;"
    def connection(sql, name):
        process = subprocess.Popen(psql, env={**environment, 'PGAPPNAME': name}, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        children.append(process); process.stdin.write(sql + "\n\\echo READY\n"); process.stdin.flush()
        while process.stdout.readline().strip() != 'READY':
            if process.poll() is not None:
                raise AssertionError(process.stderr.read())
        return process
    def wait_for_lock(name):
        for _ in range(100):
            if query(f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{name}' AND wait_event_type='Lock';") == '1':
                return
            time.sleep(.05)
        raise AssertionError('Test process did not reach expected lock: ' + name)
    try:
        schedule = str(UUID(query(f"SELECT schedule_id FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}' AND state='published' AND definition->>'symbol'='oe.ng' LIMIT 1;")))
        check('new schedule tables force runtime RLS', query("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='market_data' AND c.relname IN ('date_schedules','date_schedule_versions') AND c.relrowsecurity AND c.relforcerowsecurity;") == '2')
        check('schedule rows are invisible without a bound identity', query('SET SESSION AUTHORIZATION preview_runtime; SELECT count(*) FROM market_data.date_schedule_versions;') == '0')
        query(expect(f"UPDATE market_data.date_schedule_versions SET generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=1;", '55000'))
        check('published version mutation rejected even for bootstrap owner')
        query(expect(f"DELETE FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=1;", '55000'))
        check('published version deletion rejected by storage guard')
        query(expect(f"UPDATE market_data.date_schedules SET symbol='oe.changed' WHERE catalog_id='{catalog}' AND id='{schedule}';", '55000'))
        check('canonical schedule identity cannot change after a rename')
        query(f"INSERT INTO market_data.date_schedule_versions(catalog_id,schedule_id,version,generation,state,definition,selection,effective_from,effective_to,engine_version,calendar_catalog_id,calendar_revision_id,calendar_code,publication_order,published_at,publication_xid) SELECT catalog_id,schedule_id,3,1,'draft',definition,selection,effective_from,effective_to,engine_version,calendar_catalog_id,calendar_revision_id,calendar_code,NULL,NULL,NULL FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=2;")
        query(expect(f"UPDATE market_data.date_schedule_versions SET definition=jsonb_set(definition,'{{name}}','\"Changed\"') WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '40001'))
        check('draft edits must advance optimistic generation in database')
        query(expect(f"UPDATE market_data.date_schedule_versions SET effective_from='-infinity',generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '23514'))
        check('effective intervals reject infinite business dates')
        query(runtime(issue('viewer'), expect(f"PERFORM security.publish_date_schedule('{catalog}','{schedule}',3,1);", '42501')))
        check('raw SQL publisher function enforces current permission')
        query(runtime(issue(), expect(f"PERFORM security.publish_date_schedule('{catalog}','{schedule}',3,NULL);", '40001')))
        check('raw SQL publisher rejects a missing optimistic generation')
        query(expect(f"UPDATE market_data.date_schedule_versions SET calendar_code=NULL,generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '23514'))
        check('reference-calendar schedule versions cannot drop their calendar binding')
        query(expect(f"UPDATE market_data.date_schedule_versions SET engine_version='date_schedule_v1',generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '23514'))
        check('an engine version cannot be reinterpreted with the wrong calendar source')
        query(expect(f"UPDATE market_data.date_schedule_versions SET calendar_code='absent_calendar',generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '23503'))
        check('a schedule calendar must be an existing exact reference version')
        check('weekend mask meaning is recorded with the column', 'bit 0 Monday' in query("SELECT col_description('ref_data.calendars'::regclass,(SELECT attnum FROM pg_attribute WHERE attrelid='ref_data.calendars'::regclass AND attname='weekend_mask'));"))
        hidden_reference, hidden_revision = str(uuid4()), str(uuid4())
        query(f"INSERT INTO ref_data.catalogs VALUES('{hidden_reference}','hidden_calendar_test','Synthetic unscoped reference'); "
              f"INSERT INTO ref_data.revisions(catalog_id,id,revision_key) VALUES('{hidden_reference}','{hidden_revision}','hidden_v1'); "
              f"INSERT INTO ref_data.clock_rules(catalog_id,revision_id,code,kind,fixed_offset_seconds) VALUES('{hidden_reference}','{hidden_revision}','hidden_utc','fixed_offset',0); "
              f"INSERT INTO ref_data.calendars VALUES('{hidden_reference}','{hidden_revision}','hidden_calendar','hidden_utc',96,'2020-01-01','2022-01-01');")
        query(expect(f"UPDATE market_data.date_schedule_versions SET calendar_catalog_id='{hidden_reference}',calendar_revision_id='{hidden_revision}',calendar_code='hidden_calendar',generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '23514'))
        check('even the bootstrap owner cannot bind a calendar from an unsealed reference revision')
        pjm = 'd0000000-0000-0000-0000-000000000001'
        query(expect(f"INSERT INTO market_data.tou_product_versions(catalog_id,product_id,version,generation,state,name,clock_catalog_id,clock_revision_id,clock_code,peak_start_hour,peak_end_hour,peak_saturday) VALUES('{catalog}','{pjm}',9,1,'draft','Unsealed clock','{hidden_reference}','{hidden_revision}','hidden_utc',7,23,false);", '23514'))
        check('a TOU product cannot bind a clock from an unsealed reference revision')
        query(expect(f"UPDATE market_data.tou_product_versions SET peak_end_hour=22 WHERE catalog_id='{catalog}' AND product_id='{pjm}' AND version=1;", '55000'))
        query(expect(f"DELETE FROM market_data.tou_product_versions WHERE catalog_id='{catalog}' AND product_id='{pjm}' AND version=1;", '55000'))
        check('published TOU product versions cannot change or be removed, even by the bootstrap owner')
        # Seal it so the next check isolates the catalog-scope policy from the sealing trigger.
        query(f"UPDATE ref_data.revisions SET state='sealed' WHERE catalog_id='{hidden_reference}' AND id='{hidden_revision}';")
        check('TOU product tables carry the restrictive current-read and current-write policies', query("SELECT count(*) FROM pg_policies WHERE schemaname='market_data' AND tablename IN('tou_products','tou_product_versions') AND policyname IN('current_read','current_insert','current_update') AND permissive='RESTRICTIVE';") == '6')
        query(runtime(issue('editor'), expect(f"UPDATE market_data.date_schedule_versions SET calendar_catalog_id='{hidden_reference}',calendar_revision_id='{hidden_revision}',calendar_code='hidden_calendar',generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '42501')))
        check('a schedule writer cannot bind a calendar from an unscoped reference catalog')
        before = query(f"SELECT generation FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;")
        # Positive control in a rolled-back transaction: later checks rely on the draft's generation.
        rebound = query(f"SET SESSION AUTHORIZATION preview_runtime; BEGIN; SELECT security.use_context('{issue('editor')}'); UPDATE market_data.date_schedule_versions SET calendar_code=calendar_code,generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3 RETURNING generation; ROLLBACK;")
        check('the same writer can rebind a scoped reference calendar on its draft', rebound.splitlines()[-1] == str(int(before) + 1))
        query(runtime(issue('editor'), expect(f"INSERT INTO market_data.tou_product_versions(catalog_id,product_id,version,generation,state,name,clock_catalog_id,clock_revision_id,clock_code,peak_start_hour,peak_end_hour,peak_saturday) VALUES('{catalog}','{pjm}',9,1,'draft','Unscoped clock','{hidden_reference}','{hidden_revision}','hidden_utc',7,23,false);", '42501')))
        check('a TOU product writer cannot bind a clock from an unscoped reference catalog')
        query(expect(f"INSERT INTO market_data.tou_product_versions(catalog_id,product_id,version,generation,state,name,clock_catalog_id,clock_revision_id,clock_code,peak_start_hour,peak_end_hour,peak_saturday,published_at) SELECT catalog_id,product_id,9,1,'draft','Dated draft',clock_catalog_id,clock_revision_id,clock_code,7,23,false,now() FROM market_data.tou_product_versions WHERE catalog_id='{catalog}' AND product_id='{pjm}' AND version=1;", '23514'))
        check('a TOU product draft cannot carry a publication timestamp')
        drafts = "SELECT (SELECT count(*) FROM market_data.tou_product_versions WHERE state='draft')||','||(SELECT count(*) FROM market_data.date_schedule_versions WHERE state='draft');"
        check('readers see no drafts at the database, while authors still do',
              query(runtime(issue('viewer'), drafts)) == '0,0' and query(runtime(issue('editor'), drafts)) != '0,0')
        hidden, hidden_schedule = str(uuid4()), str(uuid4())
        query(f"INSERT INTO market_data.catalogs VALUES('{hidden}','hidden_schedule_test'); INSERT INTO market_data.date_schedules VALUES('{hidden}','{hidden_schedule}','oe.ng'); INSERT INTO market_data.date_schedule_versions(catalog_id,schedule_id,version,generation,state,definition,selection,effective_from,effective_to,engine_version,calendar_catalog_id,calendar_revision_id,calendar_code,publication_order,published_at,publication_xid) SELECT '{hidden}','{hidden_schedule}',version,generation,state,definition,selection,effective_from,effective_to,engine_version,calendar_catalog_id,calendar_revision_id,calendar_code,10000,published_at,publication_xid FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=1;")
        check('runtime schedule reads cannot cross catalog scope', query(runtime(issue('viewer'), f"SELECT count(*) FROM market_data.date_schedule_versions WHERE catalog_id='{hidden}';")).strip() == '0')
        # Hold publisher admission until a legitimately admitted two-second capability expires.
        locker = connection('BEGIN; SELECT pg_advisory_xact_lock(730849102);', 'schedule_expiry_lock')
        token = issue(seconds=2)
        waiter = subprocess.Popen(psql + ['-v', 'VERBOSITY=verbose'], env={**environment, 'PGAPPNAME': 'schedule_expiry_waiter'}, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        children.append(waiter)
        waiter.stdin.write(runtime(token, f"SELECT security.publish_date_schedule('{catalog}','{schedule}',3,1);")); waiter.stdin.close(); waiter.stdin = None
        wait_for_lock('schedule_expiry_waiter')
        for _ in range(100):
            if query(f"SELECT clock_timestamp()>expires_at FROM security.request_contexts WHERE id='{token}';") == 't': break
            time.sleep(.05)
        else: raise AssertionError('Capability did not expire within bounded test time')
        locker.stdin.write('COMMIT;\n'); locker.stdin.flush(); _, error = locker.communicate(timeout=10); assert locker.returncode == 0, error
        _, error = waiter.communicate(timeout=10)
        check('publication rechecks capability expiry after admission wait', waiter.returncode != 0 and '42501' in error)
        check('expired publication leaves draft and committed head unchanged', query(f"SELECT state FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;") == 'draft')
        expected_head = str(int(query(f"SELECT coalesce(max(publication_order),0)+1 FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}';")))
        head = query(runtime(issue(), f"SELECT security.publish_date_schedule('{catalog}','{schedule}',3,1);"))
        check('publication order is scoped and reveals no hidden catalog activity', head.strip() == expected_head)
        # Simulate uncertainty: published retry returns the same frozen publication order.
        check('publication retry cannot create another version or order', query(runtime(issue(), f"SELECT security.publish_date_schedule('{catalog}','{schedule}',3,1);")).strip() == expected_head)
        print(f'{passed} schedule storage checks passed.', flush=True)
    finally:
        for process in children:
            if process.poll() is None:
                process.kill(); process.wait(timeout=5)
