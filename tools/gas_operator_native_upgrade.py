"""Native operator continuation adopts only its qualified dependencies."""
import json

MIGRATION='0316_gas_operator_native_continuation.sql'
SIGNATURES=(
    'security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)',
    'trading.apply_gas_owned_financial(uuid,uuid,text,jsonb,timestamptz,uuid,uuid,integer)',
    'trading.check_gas_owned_integrity()',
    'trading.check_gas_operator_settlement_quantity()',
    'trading.gas_operator_original_cash(uuid,uuid,numeric)',
    'trading.gas_owned_keys(jsonb,text[])',
    'trading.gas_owned_quantity(text)',
    'trading.gas_owned_at(text)',
    'trading.gas_owned_fact(jsonb)')
REWRITTEN=frozenset(SIGNATURES[:3])
VIEW='trading.gas_operator_settlements_current'
retained=None


def _identities(query):
    selected=','.join("('"+name+"')" for name in SIGNATURES)
    # Source offsets in stored default parse trees can change during deparsing.
    # Preserve every execution property and compare the default expression.
    return json.loads(query("SELECT jsonb_object_agg(s.signature,jsonb_build_object('metadata',"
        "(to_jsonb(p)-ARRAY['prosrc','proargdefaults'])||jsonb_build_object('defaultExpression',pg_get_expr(p.proargdefaults,0)),"
        f"'sourceHash',md5(p.prosrc))) FROM(VALUES{selected})s(signature) JOIN pg_proc p ON p.oid=s.signature::regprocedure;"))


def _view(query):
    return json.loads(query("SELECT jsonb_build_object('metadata',to_jsonb(c),'definitionHash',md5(pg_get_viewdef(c.oid,true)),"
        "'columns',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0)) "
        f"FROM pg_class c WHERE c.oid='{VIEW}'::regclass;"))


def _changes(signature):
    target="'"+signature+"'::regprocedure"
    runtime='REVOKE' if signature==SIGNATURES[0] else 'GRANT'
    return [
        ('body',f"UPDATE pg_proc SET prosrc=prosrc||E'\\n-- Synthetic predecessor drift' WHERE oid={target};"),
        ('owner',f'ALTER FUNCTION {signature} OWNER TO CURRENT_USER;'),
        ('public_acl',f'GRANT EXECUTE ON FUNCTION {signature} TO PUBLIC;'),
        ('worker_acl',f'GRANT EXECUTE ON FUNCTION {signature} TO openetrm_risk_worker;'),
        ('runtime_acl',f'{runtime} EXECUTE ON FUNCTION {signature} '+('FROM' if runtime=='REVOKE' else 'TO')+' openetrm_runtime;'),
        ('owner_execute',f'REVOKE EXECUTE ON FUNCTION {signature} FROM openetrm_security_owner;'),
        ('grant_option',f'GRANT EXECUTE ON FUNCTION {signature} TO openetrm_runtime WITH GRANT OPTION;'),
        ('cost',f'ALTER FUNCTION {signature} COST 1;'),
        ('rows',f'UPDATE pg_proc SET prorows=1 WHERE oid={target};'),
        ('support',f"UPDATE pg_proc SET prosupport='pg_catalog.textlike_support(internal)'::regprocedure WHERE oid={target};"),
        ('config',f"ALTER FUNCTION {signature} SET work_mem='64kB';"),
        ('definer',f'UPDATE pg_proc SET prosecdef=NOT prosecdef WHERE oid={target};'),
        ('strict',f'ALTER FUNCTION {signature} STRICT;'),
        ('leakproof',f'ALTER FUNCTION {signature} LEAKPROOF;'),
        ('parallel',f'ALTER FUNCTION {signature} PARALLEL SAFE;'),
        ('volatility',f"UPDATE pg_proc SET provolatile=CASE provolatile WHEN 'i' THEN 'v'::\"char\" ELSE 'i'::\"char\" END WHERE oid={target};"),
        ('argument_names',f"UPDATE pg_proc SET proargnames=ARRAY['changed'] WHERE oid={target};"),
        ('argument_modes',f"UPDATE pg_proc SET proargmodes=array_fill('i'::\"char\",ARRAY[pronargs]) WHERE oid={target};"),
        ('all_argument_types',f"UPDATE pg_proc SET proallargtypes=ARRAY['uuid'::regtype::oid] WHERE oid={target};"),
        ('variadic',f"UPDATE pg_proc SET provariadic='uuid'::regtype WHERE oid={target};"),
        ('default_count',f'UPDATE pg_proc SET pronargdefaults=pronargdefaults+1 WHERE oid={target};'),
        ('default_expression',"CREATE FUNCTION pg_temp.synthetic_operator_default(chosen integer DEFAULT 1) RETURNS integer LANGUAGE sql AS $$SELECT chosen$$;"
            +f"UPDATE pg_proc SET proargdefaults=(SELECT proargdefaults FROM pg_proc WHERE oid='pg_temp.synthetic_operator_default(integer)'::regprocedure) WHERE oid={target};"),
        ('returns_set',f'UPDATE pg_proc SET proretset=true WHERE oid={target};'),
        ('return_type',f"UPDATE pg_proc SET prorettype=CASE prorettype WHEN 'boolean'::regtype THEN 'integer'::regtype ELSE 'boolean'::regtype END WHERE oid={target};"),
        ('kind',f"UPDATE pg_proc SET prokind='p' WHERE oid={target};"),
        ('language',f"UPDATE pg_proc SET prolang=(SELECT oid FROM pg_language WHERE lanname=CASE WHEN (SELECT lanname FROM pg_language WHERE oid=p.prolang)='sql' THEN 'plpgsql' ELSE 'sql' END) FROM pg_proc p WHERE pg_proc.oid={target} AND p.oid=pg_proc.oid;"),
        ('binary',f"UPDATE pg_proc SET probin='synthetic_source' WHERE oid={target};"),
        ('parsed_body',"CREATE FUNCTION pg_temp.synthetic_operator_parsed(chosen integer) RETURNS integer LANGUAGE sql RETURN chosen;"
            +f"UPDATE pg_proc SET prosqlbody=(SELECT prosqlbody FROM pg_proc WHERE oid='pg_temp.synthetic_operator_parsed(integer)'::regprocedure) WHERE oid={target};"),
        ('transform',f"UPDATE pg_proc SET protrftypes=ARRAY['json'::regtype::oid] WHERE oid={target};")]


def checks(query,migration):
    global retained
    if migration.name!=MIGRATION:return
    from assistant_context import migration_body
    body=migration_body(migration.read_text());accepted=[];count=0
    def refused(label,change):
        nonlocal count
        try:query('BEGIN;'+change+body+'ROLLBACK;')
        except RuntimeError as error:
            assert 'gas_operator_native_upgrade' in str(error),(label,str(error))
        else:
            accepted.append(label)
            print('Observed accepted operator continuation dependency drift: '+label,flush=True)
        count+=1
    for signature in SIGNATURES:
        for label,change in _changes(signature):refused(signature+':'+label,change)
    refused('permissive_original_cash',"UPDATE pg_proc SET prosrc='SELECT true' "
        "WHERE oid='trading.gas_operator_original_cash(uuid,uuid,numeric)'::regprocedure;")
    original=query(f"SELECT pg_get_viewdef('{VIEW}'::regclass,true);").strip().removesuffix(';')
    view_changes=[
        ('filtered_source',f'CREATE OR REPLACE VIEW {VIEW} AS SELECT * FROM({original}) retained_current WHERE false;'),
        ('owner',f'ALTER VIEW {VIEW} OWNER TO CURRENT_USER;'),
        ('public_acl',f'GRANT SELECT ON {VIEW} TO PUBLIC;'),
        ('worker_acl',f'GRANT SELECT ON {VIEW} TO openetrm_risk_worker;'),
        ('owner_select',f'REVOKE SELECT ON {VIEW} FROM openetrm_security_owner;'),
        ('barrier',f'ALTER VIEW {VIEW} SET(security_barrier=true);'),
        ('invoker',f'ALTER VIEW {VIEW} SET(security_invoker=true);'),
        ('rls',f"UPDATE pg_class SET relrowsecurity=true WHERE oid='{VIEW}'::regclass;"),
        ('force_rls',f"UPDATE pg_class SET relforcerowsecurity=true WHERE oid='{VIEW}'::regclass;")]
    for label,change in view_changes:refused(VIEW+':'+label,change)
    refused('existing_entry_point',"CREATE FUNCTION trading.gas_owned_operator_fact(uuid,uuid,text,jsonb) RETURNS trading.gas_owned_commands "
        "LANGUAGE sql AS $$SELECT NULL::trading.gas_owned_commands$$;")
    assert not accepted,'Operator continuation accepted changed predecessor dependencies: '+', '.join(accepted)
    query('BEGIN;SET LOCAL search_path=security,public;'+body+'ROLLBACK;')
    retained=(_identities(query),_view(query))
    assert len(retained[0])==len(SIGNATURES)
    print(f'PASS native operator continuation upgrade: {count} dependency/body/owner/ACL/metadata/view and entry-point refusals',flush=True)


def verify(query):
    assert retained is not None,'Capture native operator predecessor identities before its actual migration.'
    before,view=retained;after=_identities(query)
    assert set(after)==set(before)
    for signature,prior in before.items():
        assert after[signature]['metadata']==prior['metadata'],signature
        assert (after[signature]['sourceHash']!=prior['sourceHash'])==(signature in REWRITTEN),signature
    assert _view(query)==view,'Native continuation replaced or changed its qualified current-settlement view.'
    print('PASS native operator continuation retains all nine OIDs/execution metadata/ACLs, changes only its three qualified bodies, and preserves the exact view',flush=True)
