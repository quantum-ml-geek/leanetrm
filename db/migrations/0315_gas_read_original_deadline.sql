-- Current consumer: ordinary gas choice reads and every shared gas read callback.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$DECLARE original regprocedure='security.require_gas_owned_read(uuid,uuid,timestamptz,timestamptz)'::regprocedure;
 p pg_proc;definition text;needle constant text=' PERFORM security.require_gas_owned_read_pre_risk(catalog,context,at_time,until_at);';BEGIN
 SELECT * INTO p FROM pg_proc WHERE oid=original;
 IF NOT FOUND OR md5(p.prosrc) IS DISTINCT FROM '74bc891cb506e76f2d6e3e38d9f24009'
  OR p.proowner<>'openetrm_security_owner'::regrole OR p.prorettype<>'void'::regtype OR p.prokind<>'f' OR p.proretset OR p.proisstrict OR p.proleakproof
  OR NOT p.prosecdef OR p.provolatile<>'v' OR p.proparallel<>'u' OR p.provariadic<>0
  OR p.proargnames IS DISTINCT FROM ARRAY['catalog','context','at_time','until_at'] OR p.proallargtypes IS NOT NULL OR p.proargmodes IS NOT NULL
  OR p.pronargs<>4 OR p.pronargdefaults<>0 OR p.proargdefaults IS NOT NULL OR p.procost<>100 OR p.prorows<>0
  OR p.prosupport<>0 OR p.probin IS NOT NULL OR p.prosqlbody IS NOT NULL OR p.protrftypes IS NOT NULL
  OR(SELECT lanname FROM pg_language WHERE oid=p.prolang)<>'plpgsql' OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
  OR p.proacl::text IS DISTINCT FROM '{openetrm_security_owner=X/openetrm_security_owner,openetrm_runtime=X/openetrm_security_owner,openetrm_risk_worker=X/openetrm_security_owner}'
  OR NOT has_function_privilege('openetrm_runtime',original,'EXECUTE') OR NOT has_function_privilege('openetrm_risk_worker',original,'EXECUTE')
  OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a WHERE a.grantor<>p.proowner OR a.is_grantable OR a.privilege_type<>'EXECUTE'
   OR a.grantee NOT IN(p.proowner,'openetrm_runtime'::regrole,'openetrm_risk_worker'::regrole))
 THEN RAISE EXCEPTION 'gas_read_deadline_upgrade: unexpected helper %',original;END IF;
 definition=pg_get_functiondef(original);
 IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_read_deadline_upgrade: unexpected helper %',original;END IF;
 EXECUTE replace(definition,needle,needle||E'\n IF until_at IS NULL OR NOT isfinite(until_at) OR clock_timestamp()>=until_at THEN RAISE EXCEPTION \'gas_owned_denied\' USING ERRCODE=\'42501\';END IF;');
END$guard$;
COMMIT;
