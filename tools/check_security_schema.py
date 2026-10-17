"""Security/RLS checks in the runner's newly owned disposable cluster only."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CAT = '40000000-0000-0000-0000-000000000001'
REV = '60000000-0000-0000-0000-000000000001'
RCAT = '10000000-0000-0000-0000-000000000001'
RREV = '20000000-0000-0000-0000-000000000001'
TENANT = 'b0000000-0000-0000-0000-000000000001'
OTHER = 'b0000000-0000-0000-0000-000000000002'
WS = 'b1000000-0000-0000-0000-000000000001'
WS2 = 'b1000000-0000-0000-0000-000000000002'
DELEGATION = 'b4000000-0000-0000-0000-000000000001'


def principal(n): return f'b2000000-0000-0000-0000-{n:012d}'
def grant(n): return f'b3000000-0000-0000-0000-{n:012d}'


def run_checks(query, reject, connection, wait_for_lock, psql, environment, children):
    query((ROOT / 'db/migrations/0003_security.sql').read_text(), label='security/RLS migration applies')
    sql = [f"INSERT INTO security.tenants VALUES ('{TENANT}','synthetic'),('{OTHER}','other');",
           f"INSERT INTO security.workspaces VALUES ('{TENANT}','{WS}','primary'),('{TENANT}','{WS2}','other'),('{OTHER}','{WS}','primary');"]
    for n, kind, login, role in [(1,'human','human_interactive',3),(2,'human','human_interactive',4),
                               (3,'human','human_interactive',1),(4,'human','human_interactive',5),
                               (5,'human','human_interactive',6),(6,'agent','agent_credential',3)]:
        sql.extend([f"INSERT INTO security.principals VALUES ('{principal(n)}','{kind}',true);",
          f"INSERT INTO security.identity_bindings VALUES ('https://identity.invalid','subject_{n}','{principal(n)}','{login}');",
          f"INSERT INTO security.role_grants VALUES ('{grant(n)}','{principal(n)}','a0000000-0000-0000-0000-{role:012d}',"
          f"'{TENANT}','{WS}',CURRENT_TIMESTAMP-INTERVAL '1 day',CURRENT_TIMESTAMP+INTERVAL '1 day',false);"])
    sql.extend([
      f"INSERT INTO security.role_grants VALUES ('{grant(30)}','{principal(3)}','a0000000-0000-0000-0000-000000000001','{TENANT}','{WS2}',CURRENT_TIMESTAMP-INTERVAL '1 day',CURRENT_TIMESTAMP+INTERVAL '1 day',false);",
      f"INSERT INTO security.market_catalog_scopes VALUES ('{CAT}','{TENANT}','{WS}');",
      f"INSERT INTO security.reference_catalog_scopes VALUES ('{RCAT}','{TENANT}','{WS}','owner');",
      f"INSERT INTO security.agent_delegations VALUES ('{DELEGATION}','{principal(6)}','{principal(1)}','{TENANT}','{WS}',CURRENT_TIMESTAMP-INTERVAL '1 day',CURRENT_TIMESTAMP+INTERVAL '1 day',false);",
      f"INSERT INTO security.delegation_permissions VALUES ('{DELEGATION}','ReadMarketData');"])
    query('\n'.join(sql), label='synthetic identities/scoped grants and agent delegation load')
    assert query('SELECT count(*) FROM security.roles;') == '6'
    assert query("SELECT count(*) FROM security.role_permissions p JOIN security.roles r ON r.id=p.role_id WHERE r.code='access_administrator' AND p.permission='ReadMarketData';") == '0'
    query('SELECT 1;', label='six common role templates; access admin has no implicit market-data access')
    # Copy complete hidden data to a second tenant, including the same UUID labels.
    hidden = '40000000-0000-0000-0000-000000000002'
    sql = [f"INSERT INTO market_data.catalogs VALUES ('{hidden}','hidden');",
           f"INSERT INTO market_data.revisions VALUES ('{hidden}','{REV}','{RCAT}','{RREV}','draft',0);"]
    for table in ('contracts','curves','series','curve_members','curve_inputs','constituent_mappings'):
        columns = query("SELECT column_name FROM information_schema.columns "
            f"WHERE table_schema='market_data' AND table_name='{table}' ORDER BY ordinal_position;").splitlines()
        values = [f"'{hidden}'" if c == 'catalog_id' else c for c in columns]
        sql.append(f"INSERT INTO market_data.{table} ({','.join(columns)}) SELECT {','.join(values)} FROM market_data.{table} WHERE catalog_id='{CAT}' AND revision_id='{REV}';")
    sql.extend([f"UPDATE market_data.revisions SET state='sealed' WHERE catalog_id='{hidden}' AND id='{REV}';",
                f"INSERT INTO security.market_catalog_scopes VALUES ('{hidden}','{OTHER}','{WS}');"])
    query('\n'.join(sql), label='second-tenant graph uses isolated exact catalog keys')

    def issue(n=3, tenant=TENANT, workspace=WS, delegation=None, login=None, runtime_login="openetrm_runtime"):
        login = login or ('agent_credential' if n == 6 else 'human_interactive')
        d = f"'{delegation}'" if delegation else 'NULL'
        return query("SET SESSION AUTHORIZATION openetrm_authenticator; SELECT security.issue_context("
            f"'https://identity.invalid','subject_{n}','{login}','{tenant}','{workspace}',{d},'{runtime_login}',60);")

    def runtime(token, statement):
        return f"SET SESSION AUTHORIZATION openetrm_runtime; BEGIN; SELECT security.use_context('{token}'); {statement} COMMIT;"

    count = f"SELECT count(*) FROM market_data.curves WHERE catalog_id='{CAT}' AND revision_id='{REV}';"
    assert query('SET SESSION AUTHORIZATION openetrm_runtime; ' + count) == '0'
    query('SELECT 1;', label='RLS denies access without bound current context')
    assert query(f"SET SESSION AUTHORIZATION openetrm_runtime; SET app.principal_id='{principal(3)}'; SET app.tenant_id='{TENANT}'; " + count) == '0'
    query('SELECT 1;', label='spoofed session settings cannot establish identity')
    assert query(runtime(issue(), count)).strip() == '9'
    query('SELECT 1;', label='viewer reads exactly its workspace graph')
    assert query(runtime(issue(), f"SELECT count(*) FROM market_data.curves WHERE catalog_id='{hidden}';")).strip() == '0'
    assert query(runtime(issue(workspace=WS2), count)).strip() == '0'
    assert query(runtime(issue(tenant=OTHER), count)).strip() == '0'
    query('SELECT 1;', label='RLS isolates tenants and workspaces including permitted alternate workspace')
    assert query(runtime(issue(n=5), count)).strip() == '0'
    query('SELECT 1;', label='access administrator does not inherit business-data access')
    assert query(runtime(issue(n=6, delegation=DELEGATION), count)).strip() == '9'
    assert query(runtime(issue(n=6), count)).strip() == '0'
    query('SELECT 1;', label='agent requires own identity/grant plus explicit current delegation')
    reject('verified login kind must match stored agent binding',
        "SET SESSION AUTHORIZATION openetrm_authenticator; SELECT security.issue_context("
        f"'https://identity.invalid','subject_6','human_interactive','{TENANT}','{WS}',NULL,'openetrm_runtime',60);", '42501')
    for label, statement in [
        ('runtime cannot issue its own identity context', "SELECT security.issue_context('x','x','human_interactive',NULL,NULL,NULL,'openetrm_runtime',60);"),
        ('runtime cannot read private capabilities', 'SELECT * FROM security.request_contexts;'),
        ('runtime cannot grant itself permissions', 'UPDATE security.role_grants SET revoked=false;'),
        ('runtime cannot switch into trusted authenticator', 'SET ROLE openetrm_authenticator;'),
        ('runtime cannot bypass RLS', 'ALTER TABLE market_data.curves DISABLE ROW LEVEL SECURITY;')]:
        reject(label, 'SET SESSION AUTHORIZATION openetrm_runtime; ' + statement, '42501')
    token=issue()
    assert query(runtime(token,count)).strip() == '9'
    reject('committed context cannot be replayed in another transaction', runtime(token,count), '42501')
    assert query(runtime(issue(), count) + count).splitlines()[-1] == '0'
    query('SELECT 1;', label='transaction end clears access for a pooled connection')
    reject('repeatable-read runtime context rejected', runtime(issue(), count).replace('BEGIN;', 'BEGIN ISOLATION LEVEL REPEATABLE READ;'), '25000')

    append = (f"INSERT INTO market_data.observations VALUES ('{CAT}','70000000-0000-0000-0000-000000000090','{REV}',"
              f"'90000000-0000-0000-0000-000000000001','{RCAT}','{RREV}','fixture','security_append','1',"
              "'daily_settlement','final','2040-12-18 16:00:00+00','2040-12-19 16:00:00+00',3.01,NULL);")
    reject('viewer cannot import prices', runtime(issue(),append), '42501')
    query(runtime(issue(n=2),append), label='market-data editor can append permitted observations')
    reject('editor cannot directly seal through state-column update', runtime(issue(n=2),
        f"UPDATE market_data.revisions SET state='sealed' WHERE catalog_id='{CAT}' AND id='{REV}';"), '42501')
    reject('editor cannot use approver sealing operation', runtime(issue(n=2),
        f"SELECT security.seal_market_revision('{CAT}','{REV}');"), '42501')
    newrev='60000000-0000-0000-0000-000000000090'
    query(runtime(issue(n=2),f"INSERT INTO market_data.revisions VALUES ('{CAT}','{newrev}','{RCAT}','{RREV}','draft',0);"
        f"INSERT INTO market_data.curves SELECT catalog_id,'{newrev}',code,reference_catalog_id,reference_revision_id,commodity_code,location_code,quote_code,profile_code,settlement_target_code,rule,direct_source_code,direct_role FROM market_data.curves WHERE catalog_id='{CAT}' AND revision_id='{REV}' AND code='future';"),
        label='editor inserts draft definitions through generation locks and RLS')
    reject('approver cannot seal structurally incomplete graph', runtime(issue(n=4),f"SELECT security.seal_market_revision('{CAT}','{newrev}');"),'23514')
    emptyrev='60000000-0000-0000-0000-000000000091'
    query(f"INSERT INTO market_data.revisions VALUES ('{CAT}','{emptyrev}','{RCAT}','{RREV}','draft',0);")
    query(runtime(issue(n=4),f"SELECT security.seal_market_revision('{CAT}','{emptyrev}');"), label='approver can freeze a valid draft through checked operation')

    # Reference sharing grants read visibility, never draft-write ownership.
    query(f"INSERT INTO security.reference_catalog_scopes VALUES ('{RCAT}','{TENANT}','{WS2}','read_only');"
        f"INSERT INTO security.role_grants VALUES ('{grant(20)}','{principal(2)}','a0000000-0000-0000-0000-000000000004','{TENANT}','{WS2}',CURRENT_TIMESTAMP-INTERVAL '1 day',CURRENT_TIMESTAMP+INTERVAL '1 day',false);")
    reference_draft='20000000-0000-0000-0000-000000000090'
    query(f"INSERT INTO ref_data.revisions (catalog_id,id,revision_key) VALUES ('{RCAT}','{reference_draft}','security_draft');")
    write_currency=f"INSERT INTO ref_data.currencies VALUES ('{RCAT}','{reference_draft}','security_currency','SEC','Synthetic security currency',2);"
    reject('read-only shared reference catalog cannot be edited by a recipient editor', runtime(issue(n=2,workspace=WS2),write_currency),'55000')
    query(runtime(issue(n=2),write_currency),label='owner workspace editor can write a reference draft')
    # Exercise real non-superuser session_user through a private-socket LOGIN.
    query('CREATE ROLE fixture_runtime LOGIN NOSUPERUSER NOCREATEROLE NOBYPASSRLS INHERIT IN ROLE openetrm_runtime;')
    actual_psql=list(psql); actual_psql[actual_psql.index('-U')+1]='fixture_runtime'
    def actual(sql, expected=None):
        result=subprocess.run(actual_psql,input=sql,env=environment,text=True,capture_output=True,timeout=15)
        if expected:
            assert result.returncode != 0 and expected+':' in result.stderr,result.stderr
        else:
            assert result.returncode == 0,result.stderr
        return result.stdout.strip()
    assert actual("SELECT current_user=session_user AND session_user='fixture_runtime';")=='t'
    token=issue(runtime_login='fixture_runtime')
    assert actual(f"BEGIN; SELECT security.use_context('{token}'); "+count+' COMMIT;')=='9'
    actual(f"SELECT security.use_context('{issue()}');",'42501')
    actual('SET SESSION AUTHORIZATION reference_test;','42501')
    actual('SET ROLE openetrm_authenticator;','42501')
    assert actual('RESET ROLE; '+count)=='0'
    query('SELECT 1;',label='real unprivileged LOGIN enforces exact binding and cannot reset into bootstrap authority')

    # All protected tables have both flags, and runtime is neither owner nor bypass role.
    assert query("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('ref_data','market_data') AND c.relkind='r' AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity);") == '0'
    assert query("SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname='openetrm_runtime';") == 'f'
    query('SELECT 1;', label='every reference/market table forces RLS under non-owner runtime')
    reject('security grants enforce workspace tenant foreign key',
        f"INSERT INTO security.role_grants VALUES (gen_random_uuid(),'{principal(3)}','a0000000-0000-0000-0000-000000000001','{OTHER}','{WS2}',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP+INTERVAL '1 day',false);")
    reject('agent cannot be configured with human login kind',
        f"INSERT INTO security.identity_bindings VALUES ('https://identity.invalid','wrong','{principal(6)}','human_interactive');",'23514')

    # Revocation serializes with the request transaction in BOTH orders.
    for request_first in (True,False):
        query(f"UPDATE security.role_grants SET revoked=false WHERE id='{grant(3)}';")
        token=issue()
        revoke=f"UPDATE security.role_grants SET revoked=true WHERE id='{grant(3)}';"
        request_sql=f"SET SESSION AUTHORIZATION openetrm_runtime; BEGIN; DO $$ BEGIN PERFORM security.use_context('{token}'); END $$;"
        first=connection(request_sql if request_first else 'BEGIN; '+revoke, 'rls_first')
        second_sql='BEGIN; '+revoke+' COMMIT;' if request_first else request_sql+' '+count+' COMMIT;'
        second=subprocess.Popen(psql, env={**environment,'PGAPPNAME':'rls_second'},stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        children.append(second); second.stdin.write(second_sql); second.stdin.close(); second.stdin=None
        wait_for_lock('rls_second')
        first.stdin.write('COMMIT;\n'); first.stdin.flush()
        _,error=first.communicate(timeout=10); assert first.returncode==0,error
        output,error=second.communicate(timeout=10); assert second.returncode==0,error
        if not request_first: assert output.strip()=='0',output
        assert query(runtime(issue(),count)).strip()=='0'
        query('SELECT 1;',label=f'current revocation race request_first={request_first}')
    # Current state also applies to retained historic values.
    assert query(runtime(issue(),"SET LOCAL app.known_at='2040-01-01'; "+count)).strip()=='0'
    query('SELECT 1;',label='historical context cannot restore revoked authority')

    # Expiry is checked using actual trusted time AFTER an admission lock wait.
    for expiration in ('capability','grant'):
        query(f"UPDATE security.role_grants SET revoked=false,granted_to=CURRENT_TIMESTAMP+INTERVAL '1 day' WHERE id='{grant(3)}';")
        token=issue()
        first=connection('BEGIN; UPDATE security.epoch SET generation=generation+1 WHERE id=true;', 'expiry_fence')
        second=subprocess.Popen(psql,env={**environment,'PGAPPNAME':'expiry_waiter'},stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        children.append(second)
        second.stdin.write(runtime(token,count)); second.stdin.close(); second.stdin=None
        wait_for_lock('expiry_waiter')
        boundary="(SELECT query_start+INTERVAL '1 microsecond' FROM pg_stat_activity WHERE application_name='expiry_waiter')"
        if expiration=='capability':
            query(f"UPDATE security.request_contexts SET expires_at={boundary} WHERE id='{token}';")
            first.stdin.write('COMMIT;\n')
        else:
            first.stdin.write(f"UPDATE security.role_grants SET granted_to={boundary} WHERE id='{grant(3)}'; COMMIT;\n")
        first.stdin.flush(); _,error=first.communicate(timeout=10); assert first.returncode==0,error
        output,error=second.communicate(timeout=10)
        if expiration=='capability': assert second.returncode != 0 and '42501:' in error,error
        else: assert second.returncode==0 and output.strip()=='0',(output,error)
        query('SELECT 1;',label=f'{expiration} expiry during admission wait is enforced using actual current time')
