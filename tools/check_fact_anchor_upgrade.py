"""The bounded fact-anchor upgrade refuses changed definer boundaries."""
import json
from assistant_context import check_guard


def run_checks(query, migration, *, number='0223', guard='fact_anchor_upgrade', signatures=None):
    changes = []
    for signature in signatures or ('security.read_observation_facts(uuid,uuid,uuid[])',
                                    'security.observation_visibility_scope(uuid,uuid,uuid[])'):
        contract=json.loads(query(f"SELECT json_build_object('strict',proisstrict,'leakproof',proleakproof,'parallel',proparallel,'volatile',provolatile,'definer',prosecdef,'public',EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')) FROM pg_proc WHERE oid='{signature}'::regprocedure;"))
        strict='CALLED ON NULL INPUT' if contract['strict'] else 'STRICT'
        leakproof='NOT LEAKPROOF' if contract['leakproof'] else 'LEAKPROOF'
        parallel='UNSAFE' if contract['parallel']=='s' else 'SAFE'
        volatility='VOLATILE' if contract['volatile']!='v' else 'STABLE'
        security='INVOKER' if contract['definer'] else 'DEFINER'
        public=f"REVOKE EXECUTE ON FUNCTION {signature} FROM PUBLIC;" if contract['public'] else f"GRANT EXECUTE ON FUNCTION {signature} TO PUBLIC;"
        for change in (f"ALTER FUNCTION {signature} SET work_mem='64kB';",
                       f"ALTER FUNCTION {signature} {strict};",
                       f"ALTER FUNCTION {signature} {leakproof};",
                       f"ALTER FUNCTION {signature} PARALLEL {parallel};",
                       f"ALTER FUNCTION {signature} {volatility};",
                       f"ALTER FUNCTION {signature} SECURITY {security};",
                       public,
                       f"ALTER FUNCTION {signature} OWNER TO openetrm_runtime;",
                       f"DO $$DECLARE d text=pg_get_functiondef('{signature}'::regprocedure);BEGIN EXECUTE replace(d,'AS $function$','AS $function$ /* synthetic drift */ ');END$$;"):
            changes.append((change, signature))
    check_guard(query, migration.read_text(), number, guard, changes)
