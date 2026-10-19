"""Model-provider administration and write-only credential custody; owned synthetic preview only."""
import json
import os
import secrets
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from uuid import UUID, uuid4
from preview_client import PreviewClient

VENDORS = ['anthropic', 'openai', 'google', 'xai', 'meta']
ISSUER = 'https://preview.invalid'
REPLACE = 'settings/ai/providers/key'


def run_checks(url, query, psql, manifest, temporary, environment, dotnet):
    tenant, workspace = (str(UUID(manifest[key])) for key in ('tenantId', 'workspaceId'))
    passed = 0

    def check(name, condition=True):
        nonlocal passed
        assert condition, name
        passed += 1
        print('PASS ' + name, flush=True)

    def expect(sql, code):
        return f"DO $$ BEGIN {sql} RAISE EXCEPTION 'Expected rejection'; EXCEPTION WHEN SQLSTATE '{code}' THEN NULL; END $$;"

    def runtime(profile, statement):
        token = query("SET SESSION AUTHORIZATION preview_authenticator; SELECT security.issue_context("
                      f"'{ISSUER}','{profile}','human_interactive','{tenant}','{workspace}',NULL,'preview_runtime',60);")
        return query(f"SET SESSION AUTHORIZATION preview_runtime; BEGIN; SELECT security.use_context('{token}'); {statement} COMMIT;")

    def rolled_back(setup, subject, login_kind, context_workspace, delegation, statement):
        # Identities made for one check live only in a transaction that binds their context and rolls back.
        return query(f"BEGIN; {setup}\nSET SESSION AUTHORIZATION preview_authenticator;\n"
                     f"SELECT security.issue_context('{ISSUER}','{subject}','{login_kind}','{tenant}','{context_workspace}',{delegation},"
                     "'preview_runtime',60) AS token \\gset\n"
                     f"SET SESSION AUTHORIZATION preview_runtime;\nSELECT security.use_context(:'token');\n{statement}\nROLLBACK;")

    administrator = query(f"SELECT principal_id FROM security.identity_bindings WHERE issuer='{ISSUER}' AND subject='admin';")
    role = "(SELECT id FROM security.roles WHERE code='access_administrator')"
    window = "CURRENT_TIMESTAMP-INTERVAL '1 day',CURRENT_TIMESTAMP+INTERVAL '1 day'"

    check('only the access administrator role manages model providers',
          query("SELECT string_agg(r.code,',') FROM security.role_permissions p JOIN security.roles r ON r.id=p.role_id "
                "WHERE p.permission='ManageModelProviders';") == 'access_administrator')
    tables = "FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='assistant' AND c.relkind='r'"
    check('every model administration table forces row security',
          query(f"SELECT count(*) {tables};") == query(f"SELECT count(*) {tables} AND c.relrowsecurity AND c.relforcerowsecurity;") == '3')
    functions = "SELECT string_agg(proname,',' ORDER BY proname) FROM pg_proc WHERE pronamespace='assistant'::regnamespace"
    check('the three administration operations are the only definers and all the runtime may execute',
          query(f"{functions} AND prosecdef;") == query(f"{functions} AND has_function_privilege('preview_runtime',oid,'EXECUTE');")
          == 'credential_slot,provider_directory,replace_credential')
    for table in ('providers', 'credentials', 'administration_audit'):
        runtime('admin', expect(f'PERFORM 1 FROM assistant.{table};', '42501'))
        check(f'the runtime reads {table} only through administration operations')
    runtime('viewer', expect('PERFORM assistant.provider_directory();', '42501'))
    check('administration operations recheck ManageModelProviders in the database')
    agent, delegation = uuid4(), uuid4()
    rolled_back(f"INSERT INTO security.principals VALUES('{agent}','agent',true);"
                f"INSERT INTO security.identity_bindings VALUES('{ISSUER}','provider_agent','{agent}','agent_credential');"
                f"INSERT INTO security.workspace_memberships VALUES('{tenant}','{workspace}','{agent}','provider_agent','Synthetic agent',true,1);"
                f"INSERT INTO security.role_grants VALUES('{uuid4()}','{agent}',{role},'{tenant}','{workspace}',{window},false);"
                f"INSERT INTO security.agent_delegations VALUES('{delegation}','{agent}','{administrator}','{tenant}','{workspace}',{window},false);"
                f"INSERT INTO security.delegation_permissions VALUES('{delegation}','ManageModelProviders');",
                'provider_agent', 'agent_credential', workspace, f"'{delegation}'",
                "DO $$ BEGIN IF NOT security.has_permission('ManageModelProviders') THEN RAISE EXCEPTION 'Delegation is not current'; END IF; "
                "PERFORM assistant.provider_directory(); RAISE EXCEPTION 'Expected rejection'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END $$;")
    check('an agent never administers providers, even under a current delegation of ManageModelProviders')
    for arguments in ("'00000000-0000-0000-0000-000000000000','anthropic',0,repeat('0',64)",
                      f"'{uuid4()}','anthropic',-1,repeat('0',64)", f"'{uuid4()}','anthropic',0,'not-a-digest'"):
        runtime('admin', f"DO $$ BEGIN PERFORM assistant.credential_slot({arguments}); RAISE EXCEPTION 'Expected rejection'; "
                         "EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'model_admin_input' THEN RAISE; END IF; END $$;")
    check('the database itself refuses an empty operation, a negative version or a malformed digest')

    admin, again, viewer = PreviewClient(url), PreviewClient(url), PreviewClient(url)
    for client, profile in ((admin, 'admin'), (again, 'admin'), (viewer, 'viewer')):
        client.bootstrap(); client.call('profile', {'profile': profile})
    denied = [viewer.call('settings/ai/providers', expected=403),
              viewer.call(REPLACE, {'operationId': str(uuid4()), 'vendor': 'anthropic', 'expectedVersion': 0,
                                    'key': 'sk-synthetic-denied-0000'}, expected=403)]
    check('provider administration requires ManageModelProviders', all(d['code'] == 'access_denied' for d in denied))
    directory = admin.call('settings/ai/providers')
    check('every vendor is listed unqualified, without a credential or audit entry',
          [p['vendor'] for p in directory['providers']] == VENDORS and directory['audit'] == []
          and all(not p['qualified'] and p['credential'] is None and p['version'] == 0 for p in directory['providers']))

    secret_parts = [secrets.token_hex(16) for _ in range(7)]
    keys = ['sk-synthetic-' + part + suffix for part, suffix in zip(secret_parts, ('WXYZ', 'ABCD', 'QRST', 'LMNO', 'EFGH', 'IJKL', 'MNOP'))]
    log_settings = ("ALTER SYSTEM SET log_statement='all';", "ALTER SYSTEM SET log_parameter_max_length=-1;")
    for setting in log_settings:
        query(setting)
    query('SELECT pg_reload_conf();'); time.sleep(.5)
    try:
        def request(key, expected_version, vendor='anthropic'):
            return {'operationId': str(uuid4()), 'vendor': vendor, 'expectedVersion': expected_version, 'key': key}

        def conflict(body):
            return admin.call(REPLACE, body, expected=409)['code'] == 'model_admin_conflict'

        def credentials(vendor):
            return query(f"SELECT count(*) FROM assistant.credentials c JOIN assistant.providers p ON p.id=c.provider_id WHERE p.vendor='{vendor}';")

        def counts():
            return query("SELECT (SELECT count(*) FROM assistant.credentials)||'/'||(SELECT count(*) FROM assistant.administration_audit);")

        initial = request(keys[0], 0)
        first = admin.call(REPLACE, initial)
        check('replacing a key stores only its last four characters and a new credential version',
              first['vendor'] == 'anthropic' and first['version'] == 1
              and first['credential']['version'] == 1 and first['credential']['lastFour'] == 'WXYZ')
        check('an identical retry returns the original outcome', admin.call(REPLACE, initial) == first)
        check('an operation identity cannot be reused for another key, vendor or version',
              all(conflict({**initial, **changed}) for changed in ({'key': keys[1]}, {'vendor': 'openai'}, {'expectedVersion': 1})))
        check('a stale expected version is a conflict', conflict(request(keys[1], 0)))
        replacement = request(keys[1], 1)
        second = admin.call(REPLACE, replacement)
        check('a replacement advances the provider and credential versions',
              second['version'] == 2 and second['credential']['version'] == 2 and second['credential']['lastFour'] == 'ABCD')
        separate = request(keys[2], 0, vendor='openai')
        other = admin.call(REPLACE, separate)
        check('each vendor keeps its own credential versions', other['version'] == 1 and other['credential']['version'] == 1)
        directory = admin.call('settings/ai/providers')
        providers = {p['vendor']: p for p in directory['providers']}
        check('the directory reports each current credential, never the key',
              providers['anthropic']['credential']['lastFour'] == 'ABCD' and providers['anthropic']['version'] == 2
              and providers['openai']['credential']['lastFour'] == 'QRST' and providers['google']['credential'] is None
              and providers['anthropic']['credential']['setBy'] and providers['anthropic']['credential']['setAt'])
        check('the audit lists each replacement once, newest first, without the key',
              [(a['action'], a['vendor']) for a in directory['audit']] == [('replace_key', 'openai'), ('replace_key', 'anthropic'), ('replace_key', 'anthropic')]
              and all(a['actor'] for a in directory['audit']))

        sealed = "decode(repeat('00',12),'hex'),decode(repeat('00',16),'hex'),decode(repeat('00',16),'hex'),'ABCD',repeat('0',64)"
        anthropic, openai = (query(f"SELECT id FROM assistant.providers WHERE vendor='{vendor}';") for vendor in ('anthropic', 'openai'))
        for arguments in (f"gen_random_uuid(),'anthropic',2,'{openai}',3,{sealed}", f"gen_random_uuid(),'anthropic',2,'{anthropic}',4,{sealed}",
                          f"gen_random_uuid(),'meta',0,gen_random_uuid(),2,{sealed}"):
            runtime('admin', f"DO $$ BEGIN PERFORM assistant.replace_credential({arguments}); RAISE EXCEPTION 'Expected rejection'; "
                             "EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'model_admin_conflict' THEN RAISE; END IF; END $$;")
        check('the database stores a credential only in the slot it hands out: its provider, the next version, and 1 for a new provider')

        before = counts()
        refusals = [admin.call(REPLACE, {**request(keys[2], 0, vendor='google'), **body}, expected=422)
                    for body in ({'vendor': 'acme'}, {'key': 'short'}, {'key': 'sk-synthetic with spaces'}, {'key': None},
                                 {'key': 'k' * 513}, {'key': keys[2] + '\n'}, {'operationId': str(UUID(int=0))},
                                 {'expectedVersion': -1}, {'expectedVersion': None})]
        admin.call(REPLACE, {**request(keys[2], 0, vendor='google'), 'note': 'unlisted'}, expected=400)
        check('malformed provider, key, operation or version input is refused before any write',
              all(r['code'] == 'model_admin_input' for r in refusals) and counts() == before)

        for variable in ('OPENETRM_PREVIEW_CREDENTIAL_KEY', 'OPENETRM_PREVIEW_CREDENTIAL_RETRY_KEY'):
            key_file = Path(environment[variable])
            os.chmod(key_file, 0o640)
            try:
                refused = admin.call(REPLACE, request(keys[2], 0, vendor='google'), expected=422)
            finally:
                os.chmod(key_file, 0o600)
            check(f'a key file readable beyond its owner is credential_unavailable: {key_file.name}',
                  refused['code'] == 'credential_unavailable')
        check('an unavailable key file writes nothing', counts() == before)

        def holding_credentials(work):
            # Another session holds credential storage, so a replacement waits after its slot was read.
            holder = subprocess.Popen(psql, env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                holder.stdin.write("BEGIN; LOCK TABLE assistant.credentials IN EXCLUSIVE MODE;\n\\echo LOCKED\n")
                holder.stdin.flush()
                while holder.stdout.readline().strip() != 'LOCKED':
                    assert holder.poll() is None, holder.stderr.read()
                return work()
            finally:
                if holder.poll() is None:
                    holder.stdin.write('ROLLBACK;\n'); holder.stdin.close()
                holder.wait(timeout=10)

        def waiting(count):
            deadline = time.monotonic() + 4
            while query("SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%assistant.replace_credential(%';") != str(count):
                assert time.monotonic() < deadline, f'{count} replacement(s) did not reach credential storage'
                time.sleep(.05)

        colleague = PreviewClient(url); colleague.bootstrap(); colleague.call('profile', {'profile': 'admin'})
        colleague.call('admin/create', {'operationId': str(uuid4()), 'login': 'provider_admin', 'name': 'Synthetic provider administrator',
                                        'kind': 'human', 'roles': ['access_administrator']})
        colleague.call('profile', {'profile': 'provider_admin'})
        check("another administrator cannot reuse an administrator's request identity",
              colleague.call(REPLACE, initial, expected=409)['code'] == 'model_admin_conflict')

        timed_out, overlapping = request(keys[3], 0, vendor='google'), request(keys[4], 0, vendor='xai')
        first_meta, second_meta = request(keys[5], 0, vendor='meta'), request(keys[6], 0, vendor='meta')
        with ThreadPoolExecutor(2) as pool:
            def stalled():
                pending = pool.submit(admin.call, REPLACE, timed_out, expected=503)
                waiting(1)
                return pending.result(timeout=20)
            unknown = holding_credentials(stalled)
            check('a replacement held at credential storage past its deadline reports an unknown outcome',
                  unknown['code'] == 'model_admin_outcome_unknown')
            retried = admin.call(REPLACE, timed_out)
            check('the same request after an unknown outcome stores the key exactly once',
                  retried['credential']['version'] == 1 and retried['credential']['lastFour'] == 'LMNO' and credentials('google') == '1')

            def overlap():
                original = pool.submit(admin.call, REPLACE, overlapping)
                waiting(1)
                duplicate = pool.submit(again.call, REPLACE, overlapping)
                waiting(2)
                return original, duplicate
            original, duplicate = holding_credentials(overlap)
            outcomes = original.result(timeout=20), duplicate.result(timeout=20)
            check('a retry that overlaps its original waits for it and replays its outcome',
                  outcomes[0] == outcomes[1] and outcomes[0]['credential']['lastFour'] == 'EFGH' and credentials('xai') == '1')

            def race():
                winner = pool.submit(admin.call, REPLACE, first_meta)
                waiting(1)
                loser = pool.submit(colleague.call, REPLACE, second_meta, expected=409)
                waiting(2)
                return winner, loser
            winner, loser = holding_credentials(race)
            won, lost = winner.result(timeout=20), loser.result(timeout=20)
            check("two administrators adding a vendor's first key at once store exactly one",
                  won['credential']['lastFour'] == 'IJKL' and lost['code'] == 'model_admin_conflict' and credentials('meta') == '1')

        digest = query(f"SELECT key_digest FROM assistant.administration_audit WHERE operation_id='{initial['operationId']}';")
        second_workspace = uuid4()
        isolated = json.loads(rolled_back(
            f"INSERT INTO security.workspaces VALUES('{tenant}','{second_workspace}','provider_isolation');"
            f"INSERT INTO security.workspace_memberships VALUES('{tenant}','{second_workspace}','{administrator}','admin','Synthetic administrator',true,1);"
            f"INSERT INTO security.role_grants VALUES('{uuid4()}','{administrator}',{role},'{tenant}','{second_workspace}',{window},false);",
            'admin', 'human_interactive', second_workspace, 'NULL',
            "SELECT jsonb_build_object('directory',assistant.provider_directory(),"
            f"'slot',assistant.credential_slot('{initial['operationId']}','anthropic',0,'{digest}'));").splitlines()[-1])
        check("another workspace sees none of this workspace's providers, credentials, audit or request identities",
              isolated['directory'] == {'providers': [], 'audit': []} and 'replayed' not in isolated['slot']
              and isolated['slot']['credentialVersion'] == 1 and isolated['slot']['providerId'] != anthropic)

        stored = query("SELECT string_agg(row_to_json(c)::text,'') FROM assistant.credentials c;") + \
            query("SELECT string_agg(row_to_json(a)::text,'') FROM assistant.administration_audit a;") + \
            query("SELECT string_agg(row_to_json(p)::text,'') FROM assistant.providers p;")
        check('stored credentials keep a sealed key of the key length, never the key',
              query("SELECT bool_and(octet_length(nonce)=12 AND octet_length(tag)=16 AND "
                    f"octet_length(ciphertext)={len(keys[0])}) FROM assistant.credentials;") == 't')
        check('the audit keeps a redaction marker and a keyed digest for each replacement',
              query("SELECT bool_and(request->>'key'='redacted' AND key_digest~'^[0-9a-f]{64}$') FROM assistant.administration_audit;") == 't')
        submitted = {body['operationId']: body for body in (initial, replacement, separate, timed_out, overlapping, first_meta)}
        rows = json.loads(query(
            "SELECT json_build_object('credentials',(SELECT json_agg(json_build_object('providerId',p.id,'vendor',p.vendor,'version',c.version,"
            "'nonce',encode(c.nonce,'hex'),'ciphertext',encode(c.ciphertext,'hex'),'tag',encode(c.tag,'hex'))) "
            "FROM assistant.credentials c JOIN assistant.providers p ON p.id=c.provider_id),"
            "'audit',(SELECT json_agg(json_build_object('tenantId',tenant_id,'workspaceId',workspace_id,'operationId',operation_id,"
            "'vendor',request->>'vendor','digest',key_digest)) FROM assistant.administration_audit));"))
        expected_keys = {('anthropic', 1): keys[0], ('anthropic', 2): keys[1], ('openai', 1): keys[2], ('google', 1): keys[3], ('xai', 1): keys[4],
                         ('meta', 1): keys[5]}
        assert sorted((r['vendor'], r['version']) for r in rows['credentials']) == sorted(expected_keys)
        assert sorted(r['operationId'] for r in rows['audit']) == sorted(submitted)
        for row in rows['credentials']:
            row['key'] = expected_keys[(row['vendor'], row['version'])]
        for row in rows['audit']:
            row['key'] = submitted[row['operationId']]['key']
        fixture = Path(temporary) / 'stored-credentials.json'
        fixture.write_text(json.dumps(rows))
        subprocess.run([str(dotnet), 'run', '--project', 'tests/OpenEtrm.Api.Checks', '--', '--stored-credentials', str(fixture)],
                       cwd=Path(__file__).resolve().parents[1], env=environment, check=True, timeout=120)
        check('every stored credential opens to its submitted key and every audit digest identifies its own request')

        query('SELECT pg_sleep(.2);')
        logs = (Path(temporary) / 'postgres.log').read_text(errors='replace')
        check('statement logging records the credential operations and their bind parameters',
              'assistant.replace_credential' in logs and 'parameters:' in logs)
        responses = str([first, second, other, directory, unknown, retried, outcomes, won, lost, admin.call('settings/ai/providers')])
        for part in secret_parts:
            for name, text in (('responses', responses), ('stored rows', stored),
                               ('database statements and parameters', logs),
                               ('application log', (Path(temporary) / 'app.log').read_text(errors='replace'))):
                # Binary columns and parameters appear hex-encoded, so both encodings are absent.
                assert part not in text and part.encode().hex() not in text.lower(), name
        check('no key reaches a response, stored row, SQL statement or parameter, or the application log')
    finally:
        for setting in ('log_statement', 'log_parameter_max_length'):
            query(f'ALTER SYSTEM RESET {setting};')
        query('SELECT pg_reload_conf();')

    provider = query("SELECT id FROM assistant.providers WHERE vendor='anthropic';")
    for statement in (f"UPDATE assistant.credentials SET last_four='0000' WHERE provider_id='{provider}';",
                      f"DELETE FROM assistant.credentials WHERE provider_id='{provider}';",
                      "UPDATE assistant.administration_audit SET request='{}';",
                      "DELETE FROM assistant.administration_audit;",
                      f"DELETE FROM assistant.providers WHERE id='{provider}';",
                      # Advancing the version leaves only the identity rule to refuse a changed vendor.
                      f"UPDATE assistant.providers SET vendor='google',version=version+1 WHERE id='{provider}';",
                      f"UPDATE assistant.providers SET version=version+2 WHERE id='{provider}';"):
        query(expect(statement, '55000'))
    check('credentials and audit are immutable and a provider changes only by advancing its version, even for the owner')
    print(f'{passed} model provider checks passed.', flush=True)
