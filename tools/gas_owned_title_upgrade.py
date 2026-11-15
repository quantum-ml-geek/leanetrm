"""Title/principal acknowledgements retain the qualified native command boundary."""
import json
from gas_operator_native_upgrade import _changes,_view

MIGRATION='0317_gas_owned_title_fact_acknowledgements.sql'
RECORD='security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)'
SIGNATURES=(RECORD,
    'trading.gas_owned_outcome(uuid,uuid,text,jsonb,jsonb,boolean)',
    'trading.gas_owned_keys(jsonb,text[])','trading.gas_owned_quantity(text)',
    'trading.gas_owned_at(text)','trading.gas_owned_fact(jsonb)',
    'trading.gas_owned_consumption_fact(uuid,uuid,text,jsonb)',
    'trading.gas_owned_operator_fact(uuid,uuid,text,jsonb)')
PRESERVED=SIGNATURES+('trading.apply_gas_owned_financial(uuid,uuid,text,jsonb,timestamptz,uuid,uuid,integer)',
    'trading.check_gas_owned_integrity()')
retained=None


def _identities(query):
    selected=','.join("('"+name+"')" for name in PRESERVED)
    return json.loads(query("SELECT jsonb_object_agg(s.signature,jsonb_build_object('metadata',"
        "(to_jsonb(p)-ARRAY['prosrc','proargdefaults'])||jsonb_build_object('defaultExpression',pg_get_expr(p.proargdefaults,0)),"
        f"'sourceHash',md5(p.prosrc))) FROM(VALUES{selected})s(signature) JOIN pg_proc p ON p.oid=s.signature::regprocedure;"))


def checks(query,migration):
    global retained
    if migration.name!=MIGRATION:return
    from assistant_context import migration_body
    body=migration_body(migration.read_text());accepted=[];count=0
    for signature in SIGNATURES:
        for label,change in _changes(signature):
            try:query('BEGIN;'+change+body+'ROLLBACK;')
            except RuntimeError as error:assert 'gas_owned_title_fact_upgrade: '+signature in str(error),(signature,label,str(error))
            else:accepted.append(signature+':'+label)
            count+=1
    shadow='CREATE FUNCTION trading.gas_owned_title_fact(uuid,uuid,text,jsonb) RETURNS trading.gas_owned_commands LANGUAGE sql AS $$SELECT NULL::trading.gas_owned_commands$$;'
    try:query('BEGIN;'+shadow+body+'ROLLBACK;')
    except RuntimeError as error:assert 'gas_owned_title_fact_upgrade: existing entry point' in str(error),str(error)
    else:accepted.append('existing_entry_point')
    count+=1
    assert not accepted,'Title/principal acknowledgement adopted changed predecessor metadata: '+', '.join(accepted)
    query('BEGIN;SET LOCAL search_path=security,public;'+body+'ROLLBACK;')
    retained=(_identities(query),_view(query))
    assert len(retained[0])==len(PRESERVED)
    print(f'PASS title/principal upgrade: {count} exact dependency/body/owner/ACL/execution and helper-shadow refusals',flush=True)


def verify(query):
    assert retained is not None,'Capture title/principal predecessor identities before its actual migration.'
    prior,view=retained;current=_identities(query)
    assert set(current)==set(prior)
    for signature,before in prior.items():
        assert current[signature]['metadata']==before['metadata'],signature
        assert (current[signature]['sourceHash']!=before['sourceHash'])==(signature==RECORD),signature
    assert _view(query)==view,'A title/principal acknowledgement changed the selected operator settlement view.'
    private=query("SELECT jsonb_build_object('owner',p.proowner::regrole::text,'definer',p.prosecdef,'acl',p.proacl::text,"
        "'runtime',has_function_privilege('openetrm_runtime',p.oid,'EXECUTE'),'worker',has_function_privilege('openetrm_risk_worker',p.oid,'EXECUTE')) "
        "FROM pg_proc p WHERE p.oid='trading.gas_owned_title_fact(uuid,uuid,text,jsonb)'::regprocedure;")
    assert json.loads(private)==dict(owner='openetrm_security_owner',definer=False,
        acl='{openetrm_security_owner=X/openetrm_security_owner}',runtime=False,worker=False),private
    print('PASS title/principal actual upgrade retains ten native OIDs/metadata/ACLs, changes only record, preserves the operator view and keeps its new helper private',flush=True)
