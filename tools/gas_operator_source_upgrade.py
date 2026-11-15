"""Current operator source bridges preserve every qualified execution identity."""
import json

SIGNATURES=(
    'trading.check_gas_owned_integrity()',
    'trading.check_gas_quantity_revision()',
    'trading.require_gas_owned_quantity_head(uuid,uuid,uuid,timestamptz)',
    'security.read_gas_owned_holdings_original(uuid,uuid,timestamptz,uuid[])',
    'security.read_gas_owned_operations(uuid,uuid,timestamptz,uuid)',
    'security.read_gas_owned_known_history_pre_risk(uuid,uuid,timestamptz,uuid[])',
    'security.gas_physical_journal_source(uuid,uuid,timestamptz,uuid[],uuid[])',
    'trading.gas_owned_applied_source_conflicts(uuid,uuid,timestamptz,uuid[],uuid[])',
    'trading.gas_owned_applied_observation_conflicts(uuid,uuid,timestamptz,uuid[],uuid[])',
    'trading.gas_quantity_source_result(uuid,uuid,timestamptz,jsonb)',
    'trading.check_gas_loan_fee_change()')
retained=None


def _identities(query):
    selected=','.join("'"+name+"'::regprocedure" for name in SIGNATURES)
    # Parsed default expressions retain their meaning; the parse tree's source
    # offsets may legitimately change when pg_get_functiondef is executed.
    return json.loads(query("SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('metadata',"
        "(to_jsonb(p)-ARRAY['prosrc','proargdefaults'])||jsonb_build_object('defaultExpression',pg_get_expr(p.proargdefaults,0)),"
        f"'sourceHash',md5(p.prosrc))) FROM pg_proc p WHERE p.oid=ANY(ARRAY[{selected}]);"))


def checks(query,migration):
    global retained
    if migration.name!='0309_gas_operator_quantity_reconciliation.sql':return
    from assistant_context import migration_body
    body=migration_body(migration.read_text());accepted=[];count=0
    for signature in SIGNATURES:
        target="'"+signature+"'::regprocedure"
        changes=[('body',f"UPDATE pg_proc SET prosrc=prosrc||E'\\n-- Synthetic predecessor drift' WHERE oid={target};"),
            ('owner',f'ALTER FUNCTION {signature} OWNER TO CURRENT_USER;'),
            ('public_acl',f'GRANT EXECUTE ON FUNCTION {signature} TO PUBLIC;'),
            ('worker_acl',f'GRANT EXECUTE ON FUNCTION {signature} TO openetrm_risk_worker;'),
            ('owner_execute',f'REVOKE EXECUTE ON FUNCTION {signature} FROM openetrm_security_owner;'),
            ('grant_option',f'GRANT EXECUTE ON FUNCTION {signature} TO openetrm_runtime WITH GRANT OPTION;'),
            ('cost',f'ALTER FUNCTION {signature} COST 1;'),
            ('rows',f'UPDATE pg_proc SET prorows=1 WHERE oid={target};'),
            ('support',f"UPDATE pg_proc SET prosupport='pg_catalog.textlike_support(internal)'::regprocedure WHERE oid={target};"),
            ('config',f"ALTER FUNCTION {signature} SET work_mem='64kB';"),
            ('definer',f'ALTER FUNCTION {signature} SECURITY INVOKER;'),
            ('strict',f'ALTER FUNCTION {signature} STRICT;'),
            ('leakproof',f'ALTER FUNCTION {signature} LEAKPROOF;'),
            ('parallel',f'ALTER FUNCTION {signature} PARALLEL SAFE;'),
            ('volatility',f'ALTER FUNCTION {signature} IMMUTABLE;'),
            ('argument_names',f"UPDATE pg_proc SET proargnames=ARRAY['changed'] WHERE oid={target};"),
            ('argument_modes',f"UPDATE pg_proc SET proargmodes=array_fill('i'::\"char\",ARRAY[pronargs]) WHERE oid={target};"),
            ('all_argument_types',f"UPDATE pg_proc SET proallargtypes=ARRAY['uuid'::regtype::oid] WHERE oid={target};"),
            ('variadic',f"UPDATE pg_proc SET provariadic='uuid'::regtype WHERE oid={target};"),
            ('default_count',f'UPDATE pg_proc SET pronargdefaults=pronargdefaults+1 WHERE oid={target};'),
            ('returns_set',f'UPDATE pg_proc SET proretset=true WHERE oid={target};'),
            ('return_type',f"UPDATE pg_proc SET prorettype='boolean'::regtype WHERE oid={target};"),
            ('language',f"UPDATE pg_proc SET prolang=(SELECT oid FROM pg_language WHERE lanname=CASE WHEN (SELECT lanname FROM pg_language WHERE oid=p.prolang)='sql' THEN 'plpgsql' ELSE 'sql' END) FROM pg_proc p WHERE pg_proc.oid={target} AND p.oid=pg_proc.oid;"),
            ('binary',f"UPDATE pg_proc SET probin='synthetic_source' WHERE oid={target};"),
            ('transform',f"UPDATE pg_proc SET protrftypes=ARRAY['json'::regtype::oid] WHERE oid={target};")]
        runtime='REVOKE' if signature.startswith('security.read_gas_owned_operations(') else 'GRANT'
        changes.append(('runtime_acl',f'{runtime} EXECUTE ON FUNCTION {signature} '+('FROM' if runtime=='REVOKE' else 'TO')+' openetrm_runtime;'))
        for label,change in changes:
            try:query('BEGIN;'+change+body+'ROLLBACK;')
            except RuntimeError as error:
                assert 'gas_operator_quantity_upgrade' in str(error),(signature,label,str(error))
            else:
                accepted.append(signature+':'+label)
                print('Observed accepted operator source metadata drift: '+signature+':'+label,flush=True)
            count+=1
    assert not accepted,'Operator source upgrade accepted changed predecessor metadata: '+', '.join(accepted)
    query('BEGIN;SET LOCAL search_path=security,public;'+body+'ROLLBACK;')
    retained=_identities(query)
    assert len(retained)==len(SIGNATURES)
    print(f'PASS operator source upgrade: {count} exact predecessor body/owner/ACL/execution-shape refusals and caller search path',flush=True)


def verify(query):
    assert retained is not None
    current=_identities(query)
    assert set(current)==set(retained)
    for signature,before in retained.items():
        assert current[signature]['metadata']==before['metadata'],signature
        assert current[signature]['sourceHash']!=before['sourceHash'],signature
    print('PASS actual operator source upgrade retains all eleven public/private OIDs, owners, ACLs and execution metadata',flush=True)
