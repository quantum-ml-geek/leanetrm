-- Current consumer: identity-only assistant reports and guidance for the
-- Operating facilities screen. This admits no financial operation or navigation.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='15s';
SET LOCAL search_path=pg_catalog;
DO $page$
DECLARE helper pg_proc;definition text;before text:='''lifecycle'');';
BEGIN
 SELECT * INTO STRICT helper FROM pg_proc WHERE oid='assistant.is_prompt_page(text)'::regprocedure;
 IF encode(sha256(convert_to(helper.prosrc,'UTF8')),'hex')<>'014b7efdfdbf88e677edbab9e85d05a713702f95750cf3003428089f37b205a4'
  OR helper.proowner<>'openetrm_security_owner'::regrole OR helper.prosecdef OR helper.provolatile<>'i'
  OR helper.proisstrict OR helper.proleakproof OR helper.proparallel<>'u'
  OR helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
  OR(SELECT array_agg(a::text ORDER BY a::text) FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner)))a)
    IS DISTINCT FROM ARRAY['openetrm_security_owner=X/openetrm_security_owner']
 THEN RAISE EXCEPTION 'operating_page_predecessor';END IF;
 definition=pg_get_functiondef(helper.oid);
 IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'operating_page_predecessor';END IF;
 EXECUTE replace(definition,before,'''lifecycle'',''physical_power'');');
END$page$;
-- A valid capped battery is an executable setup consumer, not a placeholder.
DO $upgrade$ DECLARE source text;BEGIN
 SELECT pg_get_functiondef(p.oid) INTO STRICT source FROM pg_proc p WHERE p.oid='physical.power_operating_command(jsonb)'::regprocedure
 AND md5(p.prosrc)='82fde2529a49a5569224f57e22c2a6f4'
 AND p.proowner='openetrm_security_owner'::regrole AND NOT p.prosecdef AND p.provolatile='i'
 AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u'
 AND p.proconfig=ARRAY['search_path=pg_catalog']
 AND(SELECT array_agg(a::text ORDER BY a::text) FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner)))a)
  =ARRAY['openetrm_security_owner=X/openetrm_security_owner'];
 IF(length(source)-length(replace(source,'names=names||''maximumThroughputMwh''','')))/length('names=names||''maximumThroughputMwh''')<>1
 THEN RAISE EXCEPTION 'operating_facility_upgrade';END IF;
 EXECUTE replace(source,'names=names||''maximumThroughputMwh''','names=array_append(names,''maximumThroughputMwh'')');
EXCEPTION WHEN no_data_found THEN RAISE EXCEPTION 'operating_facility_upgrade';END $upgrade$;
COMMIT;
