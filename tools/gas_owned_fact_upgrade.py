"""Original financial fact acknowledgement preserves exact native boundaries."""


def checks(query,migration):
    if migration.name!='0314_gas_owned_financial_fact_acknowledgements.sql':return
    from assistant_context import migration_body
    body=migration_body(migration.read_text())
    signatures=['security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)',
        'trading.gas_owned_outcome(uuid,uuid,text,jsonb,jsonb,boolean)','trading.gas_owned_keys(jsonb,text[])',
        'trading.gas_owned_quantity(text)','trading.gas_owned_at(text)','trading.gas_owned_fact(jsonb)']
    count=0
    for signature in signatures:
        for change in [f"ALTER FUNCTION {signature} SET work_mem='64kB';",f'ALTER FUNCTION {signature} STRICT;',
            f'ALTER FUNCTION {signature} LEAKPROOF;',f'ALTER FUNCTION {signature} PARALLEL SAFE;',
            f'ALTER FUNCTION {signature} COST 1;',f'ALTER FUNCTION {signature} OWNER TO CURRENT_USER;',
            f'GRANT EXECUTE ON FUNCTION {signature} TO PUBLIC;',
            f"UPDATE pg_proc SET proargmodes=array_fill('i'::\"char\",ARRAY[pronargs]) WHERE oid='{signature}'::regprocedure;",
            f"UPDATE pg_proc SET prorows=1 WHERE oid='{signature}'::regprocedure;",
            f"UPDATE pg_proc SET prosrc=prosrc||E'\\n-- Synthetic changed source' WHERE oid='{signature}'::regprocedure;"]:
            try:query('BEGIN;'+change+body+'ROLLBACK;')
            except RuntimeError as error:assert 'gas_owned_fact_upgrade: '+signature in str(error),str(error)
            else:raise AssertionError('Original fact acknowledgement accepted changed native execution identity: '+signature)
            count+=1
    shadow="CREATE FUNCTION trading.gas_owned_consumption_fact(uuid,uuid,text,jsonb) RETURNS trading.gas_owned_commands LANGUAGE sql AS $$SELECT NULL::trading.gas_owned_commands$$;"
    try:query('BEGIN;'+shadow+body+'ROLLBACK;')
    except RuntimeError as error:assert 'gas_owned_fact_upgrade: existing entry point' in str(error),str(error)
    else:raise AssertionError('Original fact acknowledgement replaced a pre-existing helper.')
    query('BEGIN;SET LOCAL search_path=security,public;'+body+'ROLLBACK;')
    print(f'PASS original fact acknowledgement exact predecessor guards ({count} drifts), helper absence and caller search path',flush=True)
