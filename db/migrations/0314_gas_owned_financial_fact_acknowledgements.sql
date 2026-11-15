-- Current consumer: D238 original dispatch/loss/repayment after an accepted quantity revision.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$DECLARE spec record;p pg_proc;BEGIN
 IF to_regprocedure('trading.gas_owned_consumption_fact(uuid,uuid,text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'gas_owned_fact_upgrade: existing entry point';END IF;
 FOR spec IN SELECT * FROM(VALUES
  ('security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)','add12fb0ae4dfc215f34b775c6c9e4cb','jsonb',true,'v',
   ARRAY['catalog','operation','action','account','body','as_of','context','policy','policy_version','automatic'],
   '{openetrm_security_owner=X/openetrm_security_owner,openetrm_runtime=X/openetrm_security_owner}'),
  ('trading.gas_owned_outcome(uuid,uuid,text,jsonb,jsonb,boolean)','f66d9ec51bf31b34634b2524b43c3771','jsonb',false,'v',
   ARRAY['catalog','account','action','body','outcome','acknowledged'],'{openetrm_security_owner=X/openetrm_security_owner}')
,
  ('trading.gas_owned_keys(jsonb,text[])','aeb8cea840529fab77eb05ba2fdf95ad','void',false,'i',ARRAY['body','keys'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_quantity(text)','cef7c2f42f5a781744628b110910c5be','numeric',false,'i',ARRAY['value'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_at(text)','2144c9f5d513f1c8ade102d1c8af4078','timestamptz',false,'i',ARRAY['value'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_fact(jsonb)','8bbc2f1ee2d9049d8c69beebc5f393ab','jsonb',false,'i',ARRAY['body'],'{openetrm_security_owner=X/openetrm_security_owner}')
 )v(signature,source_hash,result_type,definer,volatility,names,acl) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(spec.signature);
  IF NOT FOUND OR md5(p.prosrc) IS DISTINCT FROM spec.source_hash OR p.proowner<>'openetrm_security_owner'::regrole
   OR p.prorettype<>spec.result_type::regtype OR p.prokind<>'f' OR p.proretset OR p.proisstrict OR p.proleakproof
   OR p.prosecdef IS DISTINCT FROM spec.definer OR p.provolatile<>spec.volatility OR p.proparallel<>'u' OR p.provariadic<>0
   OR p.proargnames IS DISTINCT FROM spec.names OR p.proallargtypes IS NOT NULL OR p.proargmodes IS NOT NULL
   OR p.pronargs<>cardinality(spec.names) OR p.pronargdefaults<>0 OR p.proargdefaults IS NOT NULL OR p.procost<>100 OR p.prorows<>0
   OR p.prosupport<>0 OR p.probin IS NOT NULL OR p.prosqlbody IS NOT NULL OR p.protrftypes IS NOT NULL
   OR(SELECT lanname FROM pg_language WHERE oid=p.prolang)<>'plpgsql' OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
   OR p.proacl::text IS DISTINCT FROM spec.acl
  THEN RAISE EXCEPTION 'gas_owned_fact_upgrade: %',spec.signature;END IF;
 END LOOP;
END$guard$;

CREATE FUNCTION trading.gas_owned_consumption_fact(catalog uuid,account uuid,action text,body jsonb) RETURNS trading.gas_owned_commands
 LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE matches_sql constant text=$matches$
 SELECT seed.request_id,used.id consumption_id,q.revision acknowledged_revision,head.revision current_revision,
  q.quantity acknowledged_quantity,head.quantity current_quantity
 FROM trading.gas_owned_commands seed
 LEFT JOIN trading.gas_owned_repayments repayment ON $3='repay' AND(repayment.catalog_id,repayment.id)=($1,(seed.outcome->>'id')::uuid)
 JOIN trading.gas_owned_consumptions used ON(used.catalog_id,used.id)=($1,CASE WHEN $3='repay' THEN repayment.consumption_id ELSE(seed.outcome->>'id')::uuid END)
 JOIN trading.gas_owned_consumption_quantities q ON(q.catalog_id,q.consumption_id)=(used.catalog_id,used.id)
 CROSS JOIN LATERAL(SELECT h.* FROM trading.gas_owned_consumption_quantities h
  WHERE(h.catalog_id,h.consumption_id)=(used.catalog_id,used.id) ORDER BY h.revision DESC LIMIT 1)head
 WHERE(seed.catalog_id,seed.account_id,seed.request->>'action')=($1,$2,$3)
  AND seed.outcome->'changed'='true'::jsonb AND seed.outcome->>'action'=$3
  AND used.kind=CASE $3 WHEN 'dispatch' THEN 'delivery' WHEN 'loss' THEN 'loss' ELSE 'return' END
  AND used.effective_at=trading.gas_owned_at($4->>'effectiveAt')
  AND q.quantity=trading.gas_owned_quantity($4->>'quantity') AND q.evidence_id=($4->>'evidenceId')::uuid AND q.lot_id=($4->>'lotId')::uuid
  AND q.reservation_id IS NOT DISTINCT FROM($4->>'reservationId')::uuid
  AND((seed.request->'body')-ARRAY['quantity','evidenceId','lotId','reservationId'])=($4-ARRAY['quantity','evidenceId','lotId','reservationId'])
  AND seed.request->'body'=trading.gas_owned_fact(jsonb_build_object('lotId',used.lot_id,'quantity',trim_scale(used.quantity)::text,
   'evidenceId',used.evidence_id,'reservationId',used.reservation_id,
   'effectiveAt',to_char(used.effective_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
   ||CASE WHEN $3='repay' THEN jsonb_build_object('loanId',repayment.loan_id) ELSE '{}'::jsonb END)
$matches$;ids uuid[];chosen record;result trading.gas_owned_commands;BEGIN
 IF action NOT IN('dispatch','loss','repay') THEN RETURN NULL;END IF;
 PERFORM trading.gas_owned_keys(body,CASE WHEN action='repay' THEN ARRAY['loanId','lotId','evidenceId','quantity','reservationId','effectiveAt']
  ELSE ARRAY['lotId','evidenceId','quantity','reservationId','effectiveAt'] END);
 -- A retired zero snapshot is not a legal new positive-performance command.
 IF trading.gas_owned_quantity(body->>'quantity')<=0 THEN RETURN NULL;END IF;
 EXECUTE 'SELECT array_agg(consumption_id) FROM(SELECT DISTINCT consumption_id FROM('||matches_sql||')facts LIMIT 2)distinct_facts'
  INTO ids USING catalog,account,action,body;
 IF coalesce(cardinality(ids),0)=0 THEN RETURN NULL;END IF;
 IF cardinality(ids)>1 THEN RAISE EXCEPTION 'gas_owned_fact_ambiguous';END IF;
 EXECUTE 'SELECT * FROM('||matches_sql||')facts WHERE consumption_id=$5 ORDER BY acknowledged_revision,request_id LIMIT 1'
  INTO STRICT chosen USING catalog,account,action,body,ids[1];
 SELECT * INTO STRICT result FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.request_id)=(catalog,chosen.request_id);
 result.outcome=result.outcome||jsonb_build_object('consumptionId',ids[1],
  'acknowledgedFinancialRevision',chosen.acknowledged_revision,'currentFinancialRevision',chosen.current_revision,
  'acknowledgedQuantity',trim_scale(chosen.acknowledged_quantity)::text,'currentQuantity',trim_scale(chosen.current_quantity)::text,
  'effect',(result.outcome->'effect')||jsonb_build_object('performedQuantity',trim_scale(chosen.acknowledged_quantity)::text));
 RETURN result;
END$$;
ALTER FUNCTION trading.gas_owned_consumption_fact(uuid,uuid,text,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION trading.gas_owned_consumption_fact(uuid,uuid,text,jsonb) FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;

DO $patch$DECLARE original regprocedure='security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)'::regprocedure;
 definition text;needle constant text=$old$
  SELECT * INTO same_fact FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.account_id)=(catalog,account)
   AND c.request->>'action'=action AND((c.request->'body')-'expectedRevision')=(body-'expectedRevision') ORDER BY c.request_id LIMIT 1;
  IF FOUND THEN
$old$;replacement constant text=$new$
  same_fact=trading.gas_owned_consumption_fact(catalog,account,action,body);
  IF same_fact.request_id IS NULL THEN
   SELECT * INTO same_fact FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.account_id)=(catalog,account)
    AND c.request->>'action'=action AND((c.request->'body')-'expectedRevision')=(body-'expectedRevision') ORDER BY c.request_id LIMIT 1;
  END IF;
  IF same_fact.request_id IS NOT NULL THEN
$new$;BEGIN
 definition=pg_get_functiondef(original);
 IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_owned_fact_upgrade: record body';END IF;
 EXECUTE replace(definition,needle,replacement);
END$patch$;
COMMIT;
