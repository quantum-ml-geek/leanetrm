"""The shared final-read boundary preserves its admitted native execution identity."""


def checks(query,migration):
    if migration.name!='0315_gas_read_original_deadline.sql':return
    from assistant_context import migration_body
    body=migration_body(migration.read_text());signature='security.require_gas_owned_read(uuid,uuid,timestamptz,timestamptz)'
    changes=[f'ALTER FUNCTION {signature} SECURITY INVOKER;',f'ALTER FUNCTION {signature} OWNER TO CURRENT_USER;',
        f'ALTER FUNCTION {signature} STABLE;',f'ALTER FUNCTION {signature} PARALLEL SAFE;',f'ALTER FUNCTION {signature} STRICT;',
        f'ALTER FUNCTION {signature} LEAKPROOF;',f"ALTER FUNCTION {signature} SET work_mem='64kB';",f'ALTER FUNCTION {signature} COST 1;',
        f'GRANT EXECUTE ON FUNCTION {signature} TO PUBLIC;',f'GRANT EXECUTE ON FUNCTION {signature} TO openetrm_runtime WITH GRANT OPTION;',
        f'REVOKE EXECUTE ON FUNCTION {signature} FROM openetrm_runtime;',f'REVOKE EXECUTE ON FUNCTION {signature} FROM openetrm_risk_worker;',
        f"UPDATE pg_proc SET prosrc=prosrc||E'\\n-- Synthetic source drift' WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET prorows=1 WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET proargnames=ARRAY['changed','context','at_time','until_at'] WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET proargmodes=array_fill('i'::\"char\",ARRAY[pronargs]) WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET proallargtypes=ARRAY['uuid'::regtype::oid] WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET provariadic='uuid'::regtype WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET pronargdefaults=1 WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET proretset=true WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET prorettype='boolean'::regtype WHERE oid='{signature}'::regprocedure;",
        f"UPDATE pg_proc SET prolang=(SELECT oid FROM pg_language WHERE lanname='sql') WHERE oid='{signature}'::regprocedure;"]
    for change in changes:
        try:query('BEGIN;'+change+body+'ROLLBACK;')
        except RuntimeError as error:assert 'gas_read_deadline_upgrade: unexpected helper' in str(error),str(error)
        else:raise AssertionError('Shared gas read upgrade accepted changed source/execution/authority metadata.')
    query('BEGIN;SET LOCAL search_path=security,public;'+body+'ROLLBACK;')
    print(f'PASS shared gas read original-bound upgrade: {len(changes)} exact source/metadata/ACL refusals and caller search path',flush=True)
