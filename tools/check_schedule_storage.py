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
        query(f"INSERT INTO market_data.date_schedule_versions(catalog_id,schedule_id,version,generation,state,definition,selection,effective_from,effective_to,engine_version,publication_order,published_at,publication_xid) SELECT catalog_id,schedule_id,3,1,'draft',definition,selection,effective_from,effective_to,engine_version,NULL,NULL,NULL FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=2;")
        query(expect(f"UPDATE market_data.date_schedule_versions SET definition=jsonb_set(definition,'{{name}}','\"Changed\"') WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '40001'))
        check('draft edits must advance optimistic generation in database')
        query(expect(f"UPDATE market_data.date_schedule_versions SET effective_from='-infinity',generation=generation+1 WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=3;", '23514'))
        check('effective intervals reject infinite business dates')
        query(runtime(issue('viewer'), expect(f"PERFORM security.publish_date_schedule('{catalog}','{schedule}',3,1);", '42501')))
        check('raw SQL publisher function enforces current permission')
        query(runtime(issue(), expect(f"PERFORM security.publish_date_schedule('{catalog}','{schedule}',3,NULL);", '40001')))
        check('raw SQL publisher rejects a missing optimistic generation')
        hidden, hidden_schedule = str(uuid4()), str(uuid4())
        query(f"INSERT INTO market_data.catalogs VALUES('{hidden}','hidden_schedule_test'); INSERT INTO market_data.date_schedules VALUES('{hidden}','{hidden_schedule}','oe.ng'); INSERT INTO market_data.date_schedule_versions(catalog_id,schedule_id,version,generation,state,definition,selection,effective_from,effective_to,engine_version,publication_order,published_at,publication_xid) SELECT '{hidden}','{hidden_schedule}',version,generation,state,definition,selection,effective_from,effective_to,engine_version,10000,published_at,publication_xid FROM market_data.date_schedule_versions WHERE catalog_id='{catalog}' AND schedule_id='{schedule}' AND version=1;")
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
