"""The shared gas read boundary must check the original bound after final source work."""
from concurrent.futures import ThreadPoolExecutor
import json
import re
import time
from uuid import uuid4
from gas_loan_source_authority import _state

SIGNATURE='security.require_gas_owned_read(uuid,uuid,timestamptz,timestamptz)'


def checks(query,manifest,state):
    catalog,tenant,workspace=(manifest[key] for key in ('catalogId','tenantId','workspaceId'))
    issuer=manifest['identityIssuer'];account=state['account'];at=state['at'];context=state['currentContextId']
    def literal(value):return "'"+json.dumps(value).replace("'","''")+"'::jsonb"
    def call(sql):
        token=query("SET SESSION AUTHORIZATION preview_authenticator;SELECT security.issue_context("
            f"'{issuer}','trader','human_interactive','{tenant}','{workspace}',NULL,'preview_runtime',60);")
        return query(f"SET SESSION AUTHORIZATION preview_runtime;BEGIN;SELECT security.use_context('{token}');{sql}COMMIT;")
    def read():
        return call(f"SELECT security.use_market_context('{catalog}','{context}');SELECT security.use_trading_context('{catalog}','{at}');"
            f"SELECT security.read_gas_owned_quantity_choices('{catalog}','{context}','{at}','{account}')::text;")
    original=query(f"SELECT pg_get_functiondef('{SIGNATURE}'::regprocedure);")
    metadata=query("SELECT jsonb_build_object('sourceHash',md5(p.prosrc),'owner',p.proowner::regrole::text,'acl',p.proacl::text,'cost',p.procost,'rows',p.prorows)::text "
        f"FROM pg_proc p WHERE p.oid='{SIGNATURE}'::regprocedure;")
    print('Shared gas read predecessor metadata '+metadata,flush=True)
    needle='PERFORM security.require_gas_owned_read_pre_risk(catalog,context,at_time,until_at);'
    assert original.count(needle)==1
    tag='gas_read_final_'+uuid4().hex
    query(f"CREATE SEQUENCE security.{tag};ALTER SEQUENCE security.{tag} OWNER TO openetrm_security_owner;REVOKE ALL ON SEQUENCE security.{tag} FROM PUBLIC;")
    actor=query(f"SELECT principal_id FROM security.identity_bindings WHERE(issuer,subject)=('{issuer}','trader');")
    saved=json.loads(query("SELECT coalesce(jsonb_agg(to_jsonb(p)),'[]') FROM security.role_permissions p WHERE p.permission='ReadGasOwnedHoldings' "
        f"AND p.role_id IN(SELECT role_id FROM security.role_grants WHERE principal_id='{actor}');"))
    assert actor and saved
    role,grant_a,grant_b=(str(uuid4()) for _ in range(3));before=_state(query,catalog)
    try:
        # Count this exact successful caller's helper invocations without any
        # delay. Then delay only its last source-complete helper return.
        query(original.replace(needle,needle+f"PERFORM nextval('security.{tag}');",1))
        positive=json.loads(read());assert positive['quantityChoiceProfile']=='ordinary_gas_quantity_choices_v1'
        last=int(query(f"SELECT last_value FROM security.{tag};"));assert last>=1
        query(f"ALTER SEQUENCE security.{tag} RESTART WITH 1;")
        delay=f"IF nextval('security.{tag}')={last} THEN PERFORM pg_sleep(greatest(0,extract(epoch FROM(granted_from-clock_timestamp())))+0.05) "\
            f"FROM security.role_grants WHERE id='{grant_b}';END IF;"
        query(original.replace(needle,needle+delay,1))
        query(f"BEGIN;INSERT INTO security.roles VALUES('{role}','{tag}','Synthetic final gas read');"
            "DELETE FROM security.role_permissions WHERE permission='ReadGasOwnedHoldings' "
            f"AND role_id IN(SELECT role_id FROM security.role_grants WHERE principal_id='{actor}');"
            f"INSERT INTO security.role_permissions VALUES('{role}','ReadGasOwnedHoldings');"
            f"INSERT INTO security.role_grants VALUES('{grant_a}','{actor}','{role}','{tenant}','{workspace}',clock_timestamp()-interval '1 day',clock_timestamp()+interval '4 seconds',false),"
            f"('{grant_b}','{actor}','{role}','{tenant}','{workspace}',clock_timestamp()+interval '5 seconds','9999-12-31',false);COMMIT;")
        def denied():
            try:read()
            except RuntimeError as error:assert re.search(r'ERROR:\s+(?:[A-Z0-9]{5}:\s+)?gas_owned_denied(?:\n|$)',str(error)),str(error)
            else:raise AssertionError('The ordinary choice reader returned after original gas authority expired inside its final shared read boundary.')
        with ThreadPoolExecutor(max_workers=1) as pool:
            worker=pool.submit(denied);deadline=time.monotonic()+3
            while query(f"SELECT is_called AND last_value={last} FROM security.{tag};")!='t':
                if worker.done():worker.result();raise AssertionError('The ordinary reader did not reach its final source-complete helper under original A.')
                assert time.monotonic()<deadline,'Original read work did not finish within the controlled A window.'
                time.sleep(.01)
            assert query(f"SELECT clock_timestamp()<a.granted_to AND clock_timestamp()<b.granted_from FROM security.role_grants a,security.role_grants b "
                f"WHERE a.id='{grant_a}' AND b.id='{grant_b}';")=='t'
            worker.result(timeout=10)
        assert call("SELECT security.has_permission('ReadGasOwnedHoldings');")=='t'
        assert json.loads(read())['quantityChoiceProfile']=='ordinary_gas_quantity_choices_v1'
    finally:
        query(original)
        query(f"BEGIN;DELETE FROM security.role_grants WHERE id IN('{grant_a}','{grant_b}');DELETE FROM security.role_permissions WHERE role_id='{role}';"
            f"DELETE FROM security.roles WHERE id='{role}';INSERT INTO security.role_permissions SELECT * FROM jsonb_populate_recordset(NULL::security.role_permissions,{literal(saved)}) ON CONFLICT DO NOTHING;COMMIT;")
        query(f"DROP SEQUENCE security.{tag};")
    assert _state(query,catalog)==before,'A read-only boundary probe changed financial/bank/receipt facts.'
    print('PASS ordinary choices retain original gas read expiry after the complete final shared source check; fresh B remains authorized',flush=True)
