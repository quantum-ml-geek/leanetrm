-- Current consumer: original owned-title and loan-principal commands after accepted quantity revisions.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$DECLARE spec record;p pg_proc;BEGIN
 IF to_regprocedure('trading.gas_owned_title_fact(uuid,uuid,text,jsonb)') IS NOT NULL
 THEN RAISE EXCEPTION 'gas_owned_title_fact_upgrade: existing entry point';END IF;
 FOR spec IN SELECT * FROM(VALUES
  ('security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)','9b46ac3bc24ecb57eabf4c6fe265d72e','jsonb',true,'v',
   ARRAY['catalog','operation','action','account','body','as_of','context','policy','policy_version','automatic'],
   '{openetrm_security_owner=X/openetrm_security_owner,openetrm_runtime=X/openetrm_security_owner}'),
  ('trading.gas_owned_outcome(uuid,uuid,text,jsonb,jsonb,boolean)','f66d9ec51bf31b34634b2524b43c3771','jsonb',false,'v',
   ARRAY['catalog','account','action','body','outcome','acknowledged'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_keys(jsonb,text[])','aeb8cea840529fab77eb05ba2fdf95ad','void',false,'i',ARRAY['body','keys'],
   '{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_quantity(text)','cef7c2f42f5a781744628b110910c5be','numeric',false,'i',ARRAY['value'],
   '{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_at(text)','2144c9f5d513f1c8ade102d1c8af4078','timestamptz',false,'i',ARRAY['value'],
   '{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_fact(jsonb)','8bbc2f1ee2d9049d8c69beebc5f393ab','jsonb',false,'i',ARRAY['body'],
   '{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_consumption_fact(uuid,uuid,text,jsonb)','ce322d0f5260d6d98550dc60106d0904','trading.gas_owned_commands',false,'v',
   ARRAY['catalog','account','action','body'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_operator_fact(uuid,uuid,text,jsonb)','c7772e77b49ea74f4e0092b2589c4f77','trading.gas_owned_commands',false,'v',
   ARRAY['catalog','account','action','body'],'{openetrm_security_owner=X/openetrm_security_owner}')
 )v(signature,source_hash,result_type,definer,volatility,names,acl) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(spec.signature);
  IF NOT FOUND OR md5(p.prosrc) IS DISTINCT FROM spec.source_hash OR p.proowner<>'openetrm_security_owner'::regrole
   OR p.prorettype<>spec.result_type::regtype OR p.prokind<>'f' OR p.proretset OR p.proisstrict OR p.proleakproof
   OR p.prosecdef IS DISTINCT FROM spec.definer OR p.provolatile<>spec.volatility
   OR p.proparallel<>'u' OR p.provariadic<>0 OR p.proargnames IS DISTINCT FROM spec.names OR p.proallargtypes IS NOT NULL
   OR p.proargmodes IS NOT NULL OR p.pronargs<>cardinality(spec.names) OR p.pronargdefaults<>0 OR p.proargdefaults IS NOT NULL
   OR p.procost<>100 OR p.prorows<>0 OR p.prosupport<>0 OR p.probin IS NOT NULL OR p.prosqlbody IS NOT NULL OR p.protrftypes IS NOT NULL
   OR(SELECT lanname FROM pg_language WHERE oid=p.prolang)<>'plpgsql' OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
   OR p.proacl::text IS DISTINCT FROM spec.acl
  THEN RAISE EXCEPTION 'gas_owned_title_fact_upgrade: %',spec.signature;END IF;
 END LOOP;
END$guard$;

CREATE FUNCTION trading.gas_owned_title_fact(catalog uuid,account uuid,action text,body jsonb) RETURNS trading.gas_owned_commands
 LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE matches_sql constant text=$matches$
 SELECT seed.request_id,stock.id native_id,q.revision acknowledged_revision,head.revision current_revision,
  q.quantity acknowledged_quantity,head.quantity current_quantity
 FROM trading.gas_owned_commands seed
 JOIN trading.gas_owned_positions stock ON(stock.catalog_id,stock.id,stock.account_id)=($1,(seed.outcome->>'id')::uuid,$2)
 JOIN trading.gas_owned_lots lot ON(lot.catalog_id,lot.id,lot.account_id)=(stock.catalog_id,stock.id,stock.account_id)
 JOIN trading.gas_owned_position_quantities q ON(q.catalog_id,q.position_id,q.account_id)=(stock.catalog_id,stock.id,stock.account_id)
 CROSS JOIN LATERAL(SELECT h.* FROM trading.gas_owned_position_quantities h
  WHERE(h.catalog_id,h.position_id)=(stock.catalog_id,stock.id) ORDER BY h.revision DESC LIMIT 1)head
 WHERE $3='receive_title' AND(seed.catalog_id,seed.account_id,seed.request->>'action')=($1,$2,$3)
  AND seed.outcome->'changed'='true'::jsonb AND seed.outcome->'semanticAcknowledgement'='false'::jsonb AND seed.outcome->>'action'=$3
  AND stock.kind='owned_stock' AND stock.origin_policy='opening_owned_stock_v1' AND stock.settlement_mode='owned_stock_v1'
  AND stock.actor_id=seed.actor_id AND stock.effective_at=lot.title_at
  AND q.quantity=trading.gas_owned_quantity($4->>'quantity') AND NOT q.retracted AND q.evidence_id=($4->>'evidenceId')::uuid
  AND((seed.request->'body')-ARRAY['quantity','evidenceId'])=($4-ARRAY['quantity','evidenceId'])
  AND seed.request->'body'=trading.gas_owned_fact(jsonb_build_object('evidenceId',stock.evidence_id,'quantity',trim_scale(stock.quantity)::text,
   'titleAt',to_char(lot.title_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'availableAt',to_char(lot.available_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'originPolicy',stock.origin_policy,'carrying',stock.carrying))
 UNION ALL
 SELECT seed.request_id,loan.id,q.revision,head.revision,q.quantity,head.quantity
 FROM trading.gas_owned_commands seed
 JOIN trading.gas_owned_loans loan ON(loan.catalog_id,loan.id,loan.account_id)=($1,(seed.outcome->>'id')::uuid,$2)
 JOIN trading.gas_owned_positions stock ON(stock.catalog_id,stock.id,stock.account_id)=(loan.catalog_id,loan.received_lot_id,loan.account_id)
 JOIN trading.gas_owned_lots lot ON(lot.catalog_id,lot.id,lot.account_id)=(stock.catalog_id,stock.id,stock.account_id)
 JOIN trading.gas_owned_positions debt ON(debt.catalog_id,debt.id,debt.account_id)=(loan.catalog_id,loan.return_position_id,loan.account_id)
 JOIN trading.gas_owned_loan_quantities q ON(q.catalog_id,q.loan_id,q.account_id)=(loan.catalog_id,loan.id,loan.account_id)
 JOIN trading.gas_loan_fee_terms origin ON(origin.catalog_id,origin.loan_id,origin.revision,origin.origin_request_id,origin.account_id,origin.position_id)=
  (loan.catalog_id,loan.id,1,seed.request_id,loan.account_id,debt.id)
 CROSS JOIN LATERAL(SELECT h.* FROM trading.gas_owned_loan_quantities h
  WHERE(h.catalog_id,h.loan_id)=(loan.catalog_id,loan.id) ORDER BY h.revision DESC LIMIT 1)head
 WHERE $3='borrow' AND(seed.catalog_id,seed.account_id,seed.request->>'action')=($1,$2,$3)
  AND seed.outcome->'changed'='true'::jsonb AND seed.outcome->'semanticAcknowledgement'='false'::jsonb AND seed.outcome->>'action'=$3
  AND(seed.outcome->>'stockId')::uuid=stock.id AND(seed.outcome->>'returnId')::uuid=debt.id
  AND stock.kind='owned_stock' AND debt.kind='loan_return' AND stock.origin_policy='title_transfer_loan_v1' AND debt.origin_policy=stock.origin_policy
  AND stock.settlement_mode='owned_stock_v1' AND debt.settlement_mode='return_quantity_v1' AND stock.carrying='nominal_mark_v1'
  AND loan.title_policy='fungible_gas_title_transfer_return_v1'
  AND stock.quantity=loan.quantity AND debt.quantity=-loan.quantity AND stock.effective_at=lot.title_at AND debt.effective_at=lot.title_at
  AND debt.due_at=loan.return_at AND stock.actor_id=seed.actor_id AND debt.actor_id=seed.actor_id
  AND stock.publication_order=debt.publication_order AND origin.publication_order=stock.publication_order
  AND origin.effective_at=stock.effective_at AND origin.actor_id=seed.actor_id AND origin.implementation='native_fixed_loan_fee_origin_v1'
  AND q.quantity=trading.gas_owned_quantity($4->>'quantity') AND q.title_evidence_id=($4->>'evidenceId')::uuid
  AND q.agreement_evidence_id=($4->>'agreementId')::uuid
  AND((seed.request->'body')-ARRAY['quantity','evidenceId','agreementId'])=($4-ARRAY['quantity','evidenceId','agreementId'])
  AND seed.request->'body'=trading.gas_owned_fact(jsonb_build_object('agreementId',debt.evidence_id,'evidenceId',stock.evidence_id,
   'quantity',trim_scale(loan.quantity)::text,'titleAt',to_char(lot.title_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'availableAt',to_char(lot.available_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'returnAt',to_char(loan.return_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'returnMarkCurve',debt.mark_curve_code,'returnMarkContractId',debt.mark_contract_id,'carrying',debt.carrying,
   'feeAmount',trim_scale(origin.amount)::text,'feeDueAt',to_char(origin.due_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'lenderId',loan.lender_id,'lenderRevision',loan.lender_revision))
$matches$;ids uuid[];chosen record;result trading.gas_owned_commands;BEGIN
 IF action NOT IN('receive_title','borrow') THEN RETURN NULL;END IF;
 PERFORM trading.gas_owned_keys(body,CASE WHEN action='borrow' THEN
  ARRAY['agreementId','evidenceId','quantity','titleAt','availableAt','returnAt','returnMarkCurve','returnMarkContractId','carrying','feeAmount','feeDueAt','lenderId','lenderRevision']
  ELSE ARRAY['evidenceId','quantity','titleAt','availableAt','originPolicy','carrying'] END);
 -- A zero financial retraction is not a legal new title or borrow command.
 IF trading.gas_owned_quantity(body->>'quantity')<=0 THEN RETURN NULL;END IF;
 EXECUTE 'SELECT array_agg(native_id) FROM(SELECT DISTINCT native_id FROM('||matches_sql||')facts LIMIT 2)distinct_facts'
  INTO ids USING catalog,account,action,body;
 IF coalesce(cardinality(ids),0)=0 THEN RETURN NULL;END IF;
 IF cardinality(ids)>1 THEN RAISE EXCEPTION 'gas_owned_fact_ambiguous';END IF;
 EXECUTE 'SELECT * FROM('||matches_sql||')facts WHERE native_id=$5 ORDER BY acknowledged_revision,request_id LIMIT 1'
  INTO STRICT chosen USING catalog,account,action,body,ids[1];
 SELECT * INTO STRICT result FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.request_id)=(catalog,chosen.request_id);
 result.outcome=result.outcome||jsonb_build_object('acknowledgedFinancialRevision',chosen.acknowledged_revision,'currentFinancialRevision',chosen.current_revision,
  'acknowledgedQuantity',trim_scale(chosen.acknowledged_quantity)::text,'currentQuantity',trim_scale(chosen.current_quantity)::text,
  'effect',(result.outcome->'effect')||CASE WHEN action='borrow' THEN jsonb_build_object(
   'stockQuantity',trim_scale(chosen.acknowledged_quantity)::text,'returnQuantity',trim_scale(-chosen.acknowledged_quantity)::text)
   ELSE jsonb_build_object('performedQuantity',trim_scale(chosen.acknowledged_quantity)::text) END);
 RETURN result;
END$$;
ALTER FUNCTION trading.gas_owned_title_fact(uuid,uuid,text,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION trading.gas_owned_title_fact(uuid,uuid,text,jsonb) FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;

DO $patch$DECLARE original regprocedure='security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)'::regprocedure;
 definition text;needle constant text=$old$  IF same_fact.request_id IS NULL THEN same_fact=trading.gas_owned_operator_fact(catalog,account,action,body);END IF;$old$;
 replacement constant text=needle||E'\n  IF same_fact.request_id IS NULL THEN same_fact=trading.gas_owned_title_fact(catalog,account,action,body);END IF;';
 context_check constant text=$context$ IF context IS NULL OR NOT EXISTS(SELECT 1 FROM market_data.temporal_contexts t JOIN trading.contexts x ON(x.catalog_id,x.context_id)=(t.catalog_id,t.id)
  WHERE(t.catalog_id,t.id)=(catalog,context) AND security.trading_context_day_matches(catalog,context,as_of))
 THEN RAISE EXCEPTION 'gas_owned_context';END IF;$context$;
 lookup_start constant text=$lookup$ IF action<>'account' THEN
  same_fact=trading.gas_owned_consumption_fact(catalog,account,action,body);$lookup$;BEGIN
 definition=pg_get_functiondef(original);
 IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1
 THEN RAISE EXCEPTION 'gas_owned_title_fact_upgrade: record body';END IF;
 definition=replace(definition,needle,replacement);
 IF(length(definition)-length(replace(definition,context_check,'')))/length(context_check)<>1
  OR(length(definition)-length(replace(definition,lookup_start,'')))/length(lookup_start)<>1
 THEN RAISE EXCEPTION 'gas_owned_title_fact_upgrade: source boundary';END IF;
 -- Recover the exact first receipt before source reads. Fresh nonces retain
 -- their declared certified day without requiring a current financial head.
 definition=replace(definition,context_check,'');
 EXECUTE replace(definition,lookup_start,context_check||E'\n'||lookup_start);
END$patch$;
COMMIT;
