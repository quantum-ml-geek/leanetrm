-- Current consumers: identity-only assistant reports and editable guidance for
-- REC inventory, the standalone REC ticket and saved structured-trade inspectors.
-- No new agent financial authority.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='15s';
SET LOCAL search_path=pg_catalog;
DO $page$
DECLARE helper pg_proc;definition text;before text:='''physical_power'');';
BEGIN
 SELECT * INTO STRICT helper FROM pg_proc WHERE oid='assistant.is_prompt_page(text)'::regprocedure;
 IF encode(sha256(convert_to(helper.prosrc,'UTF8')),'hex')<>'e9887c63aefb57c00edf71713fa53e24702d0732b16819fd3770d8d0edc93acc'
  OR helper.proowner<>'openetrm_security_owner'::regrole OR helper.prosecdef OR helper.provolatile<>'i'
  OR helper.proisstrict OR helper.proleakproof OR helper.proparallel<>'u'
  OR helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
  OR(SELECT array_agg(a::text ORDER BY a::text) FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner)))a)
    IS DISTINCT FROM ARRAY['openetrm_security_owner=X/openetrm_security_owner']
 THEN RAISE EXCEPTION 'rec_page_predecessor';END IF;
 definition=pg_get_functiondef(helper.oid);
 IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'rec_page_predecessor';END IF;
 EXECUTE replace(definition,before,'''physical_power'',''rec_inventory'',''blotter_new_rec'',''blotter_operating_right'',''blotter_rec_forward'');');
END$page$;
COMMIT;
