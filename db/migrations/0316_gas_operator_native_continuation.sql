-- Current consumer: original operator performance after accepted quantity corrections.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$DECLARE spec record;p pg_proc;current_view pg_class;BEGIN
 IF to_regprocedure('trading.gas_owned_operator_fact(uuid,uuid,text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'gas_operator_native_upgrade';END IF;
 FOR spec IN SELECT * FROM(VALUES
  ('security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)','deab65cfd4892e9495624b2746da534a','jsonb',true,'v','plpgsql',
   ARRAY['catalog','operation','action','account','body','as_of','context','policy','policy_version','automatic'],'{openetrm_security_owner=X/openetrm_security_owner,openetrm_runtime=X/openetrm_security_owner}'),
  ('trading.apply_gas_owned_financial(uuid,uuid,text,jsonb,timestamptz,uuid,uuid,integer)','700058321b80fd4195338773fb3178a9','jsonb',false,'v','plpgsql',
   ARRAY['catalog','account','action','body','as_of','context','actor','publication'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.check_gas_owned_integrity()','4eda0e536f717b248827d5136b30a75a','trigger',true,'v','plpgsql',
   NULL,'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.check_gas_operator_settlement_quantity()','ff3206af35d13d1746a5ce99ac5e4831','trigger',true,'v','plpgsql',
   NULL,'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_operator_original_cash(uuid,uuid,numeric)','eb5131eaa8c11c1a79de320883a1ead1','boolean',true,'s','sql',
   ARRAY['catalog','settlement','amount'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_keys(jsonb,text[])','aeb8cea840529fab77eb05ba2fdf95ad','void',false,'i','plpgsql',
   ARRAY['body','keys'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_quantity(text)','cef7c2f42f5a781744628b110910c5be','numeric',false,'i','plpgsql',
   ARRAY['value'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_at(text)','2144c9f5d513f1c8ade102d1c8af4078','timestamptz',false,'i','plpgsql',
   ARRAY['value'],'{openetrm_security_owner=X/openetrm_security_owner}'),
  ('trading.gas_owned_fact(jsonb)','8bbc2f1ee2d9049d8c69beebc5f393ab','jsonb',false,'i','plpgsql',
   ARRAY['body'],'{openetrm_security_owner=X/openetrm_security_owner}')
 )v(signature,source_hash,result_type,definer,volatility,language,names,acl) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(spec.signature);
  IF NOT FOUND OR md5(p.prosrc) IS DISTINCT FROM spec.source_hash OR p.proowner<>'openetrm_security_owner'::regrole
   OR p.prorettype<>spec.result_type::regtype OR p.prokind<>'f' OR p.proretset OR p.proisstrict OR p.proleakproof
   OR p.prosecdef IS DISTINCT FROM spec.definer OR p.provolatile<>spec.volatility OR p.proparallel<>'u' OR p.provariadic<>0
   OR p.proargnames IS DISTINCT FROM spec.names OR p.proallargtypes IS NOT NULL OR p.proargmodes IS NOT NULL
   OR p.pronargs<>coalesce(cardinality(spec.names),0) OR p.pronargdefaults<>0 OR p.proargdefaults IS NOT NULL OR p.procost<>100 OR p.prorows<>0
   OR p.prosupport<>0 OR p.probin IS NOT NULL OR p.prosqlbody IS NOT NULL OR p.protrftypes IS NOT NULL
   OR(SELECT lanname FROM pg_language WHERE oid=p.prolang)<>spec.language OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
   OR p.proacl::text IS DISTINCT FROM spec.acl
  THEN RAISE EXCEPTION 'gas_operator_native_upgrade: %',spec.signature;END IF;
 END LOOP;
 SELECT * INTO current_view FROM pg_class WHERE oid=to_regclass('trading.gas_operator_settlements_current');
 IF NOT FOUND OR current_view.relkind<>'v' OR current_view.relowner<>'openetrm_security_owner'::regrole
  OR current_view.relpersistence<>'p' OR current_view.relrowsecurity OR current_view.relforcerowsecurity OR current_view.reloptions IS NOT NULL
  OR current_view.relacl::text IS DISTINCT FROM '{openetrm_security_owner=arwdDxt/openetrm_security_owner}'
  OR md5(pg_get_viewdef(current_view.oid,true)) IS DISTINCT FROM 'af1cd5ddea802d263ca288b3dc77642c'
 THEN RAISE EXCEPTION 'gas_operator_native_upgrade: current settlement view';END IF;
END$guard$;

CREATE FUNCTION trading.gas_owned_operator_fact(catalog uuid,account uuid,action text,body jsonb) RETURNS trading.gas_owned_commands
 LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE matches_sql constant text=$matches$
 SELECT seed.request_id,native.id settlement_id,q.revision acknowledged_revision,head.revision current_revision,
  q.quantity acknowledged_quantity,head.quantity current_quantity,q.cash_amount,head.cash_amount current_cash_amount
 FROM trading.gas_owned_commands seed JOIN trading.gas_owned_claim_settlements native
  ON(native.catalog_id,native.id)=(seed.catalog_id,(seed.outcome->>'id')::uuid)
 JOIN trading.gas_operator_settlement_quantities q ON(q.catalog_id,q.settlement_id,q.origin_request_id)=(native.catalog_id,native.id,seed.request_id)
 CROSS JOIN LATERAL(SELECT h.* FROM trading.gas_operator_settlement_quantities h
  WHERE(h.catalog_id,h.settlement_id)=(native.catalog_id,native.id) ORDER BY h.revision DESC LIMIT 1)head
 LEFT JOIN trading.gas_owned_consumption_quantities used
  ON(used.catalog_id,used.consumption_id,used.revision)=(q.catalog_id,q.consumption_id,q.consumption_revision)
 LEFT JOIN trading.gas_owned_positions receipt ON(receipt.catalog_id,receipt.id)=(native.catalog_id,native.receipt_lot_id)
 LEFT JOIN trading.gas_owned_lots receipt_lot ON(receipt_lot.catalog_id,receipt_lot.id)=(receipt.catalog_id,receipt.id)
 LEFT JOIN trading.gas_owned_consumptions original_use ON(original_use.catalog_id,original_use.id)=(native.catalog_id,native.consumption_id)
 LEFT JOIN trading.gas_owned_positions original_stock ON(original_stock.catalog_id,original_stock.id)=(original_use.catalog_id,original_use.lot_id)
 WHERE(seed.catalog_id,seed.account_id,seed.request->>'action')=($1,$2,'operator_settle')
  AND seed.outcome->'changed'='true'::jsonb AND seed.outcome->>'semanticAcknowledgement'='false' AND seed.outcome->>'action'='operator_settle'
  AND(native.actor_id,native.position_id,native.effective_at)=(seed.actor_id,($3->>'positionId')::uuid,trading.gas_owned_at($3->>'effectiveAt'))
  AND q.quantity=trading.gas_owned_quantity($3->>'quantity') AND q.evidence_id=($3->>'evidenceId')::uuid
  AND q.source_observation_id IS NOT DISTINCT FROM($3->>'sourceObservationId')::uuid
  AND(q.consumption_id IS NULL AND $3->>'lotId' IS NULL AND $3->>'reservationId' IS NULL
   OR q.consumption_id IS NOT NULL AND used.lot_id=($3->>'lotId')::uuid AND used.reservation_id IS NOT DISTINCT FROM($3->>'reservationId')::uuid)
  AND((seed.request->'body')-ARRAY['quantity','evidenceId','lotId','reservationId','sourceObservationId'])=
   ($3-ARRAY['quantity','evidenceId','lotId','reservationId','sourceObservationId'])
  AND seed.request->'body'=trading.gas_owned_fact(jsonb_build_object('positionId',native.position_id,'quantity',trim_scale(native.quantity)::text,
   'ownedAccountId',coalesce(receipt.account_id,original_stock.account_id),'lotId',original_use.lot_id,'reservationId',original_use.reservation_id,
   'evidenceId',native.evidence_id,'effectiveAt',to_char(native.effective_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'availableAt',CASE WHEN receipt_lot.id IS NOT NULL THEN to_char(receipt_lot.available_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
   'sourceObservationId',native.source_observation_id))
$matches$;ids uuid[];chosen record;result trading.gas_owned_commands;BEGIN
 IF action<>'operator_settle' THEN RETURN NULL;END IF;
 PERFORM trading.gas_owned_keys(body,ARRAY['positionId','quantity','ownedAccountId','lotId','reservationId','evidenceId','effectiveAt','availableAt','sourceObservationId']);
 IF trading.gas_owned_quantity(body->>'quantity')<=0 THEN RETURN NULL;END IF;
 EXECUTE 'SELECT array_agg(settlement_id) FROM(SELECT DISTINCT settlement_id FROM('||matches_sql||')facts LIMIT 2)distinct_facts'
  INTO ids USING catalog,account,body;
 IF coalesce(cardinality(ids),0)=0 THEN RETURN NULL;END IF;
 IF cardinality(ids)>1 THEN RAISE EXCEPTION 'gas_owned_fact_ambiguous';END IF;
 EXECUTE 'SELECT * FROM('||matches_sql||')facts WHERE settlement_id=$4 ORDER BY acknowledged_revision,request_id LIMIT 1'
  INTO STRICT chosen USING catalog,account,body,ids[1];
 SELECT * INTO STRICT result FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.request_id)=(catalog,chosen.request_id);
 result.outcome=result.outcome||jsonb_build_object('settlementId',ids[1],
  'acknowledgedFinancialRevision',chosen.acknowledged_revision,'currentFinancialRevision',chosen.current_revision,
  'acknowledgedQuantity',trim_scale(chosen.acknowledged_quantity)::text,'currentQuantity',trim_scale(chosen.current_quantity)::text,
  'originalCashAmount',CASE WHEN result.outcome->>'cashId' IS NOT NULL THEN result.outcome#>>'{effect,cashAmount}' END,
  'acknowledgedCashAmount',trim_scale(chosen.cash_amount)::text,'currentCashAmount',trim_scale(chosen.current_cash_amount)::text,
  'effect',(result.outcome->'effect')||jsonb_build_object('performedQuantity',trim_scale(chosen.acknowledged_quantity)::text));
 RETURN result;
END$$;
ALTER FUNCTION trading.gas_owned_operator_fact(uuid,uuid,text,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION trading.gas_owned_operator_fact(uuid,uuid,text,jsonb) FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;

DO $patch$DECLARE target regprocedure;definition text;needle text;replacement text;branch text;at_index integer;end_index integer;BEGIN
 target='security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)'::regprocedure;
 definition=pg_get_functiondef(target);
 needle='  same_fact=trading.gas_owned_consumption_fact(catalog,account,action,body);';
 replacement=needle||E'\n  IF same_fact.request_id IS NULL THEN same_fact=trading.gas_owned_operator_fact(catalog,account,action,body);END IF;';
 IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_native_upgrade: record';END IF;
 EXECUTE replace(definition,needle,replacement);
 target='trading.apply_gas_owned_financial(uuid,uuid,text,jsonb,timestamptz,uuid,uuid,integer)'::regprocedure;
 definition=pg_get_functiondef(target);at_index=strpos(definition,E' ELSIF action=''operator_settle'' THEN');end_index=strpos(definition,E' ELSIF action=''fee_payment'' THEN');
 IF at_index=0 OR end_index<=at_index THEN RAISE EXCEPTION 'gas_operator_native_upgrade: operator branch';END IF;
 branch=substring(definition FROM at_index FOR end_index-at_index);
 needle=$branch$ ELSIF action='operator_settle' THEN$branch$;
 branch=replace(branch,needle,needle||E'\n  PERFORM trading.require_gas_owned_quantity_head(catalog,account,context,as_of);');
 needle='  PERFORM trading.require_gas_owned_head(catalog,owned.id,context,as_of);';
 IF(length(branch)-length(replace(branch,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_native_upgrade: counterpart head';END IF;
 branch=replace(branch,needle,needle||E'\n  PERFORM trading.require_gas_owned_quantity_head(catalog,owned.id,context,as_of);');
 needle='FROM trading.gas_owned_claim_settlements s WHERE';
 IF(length(branch)-length(replace(branch,needle,'')))/length(needle)<>2 THEN RAISE EXCEPTION 'gas_operator_native_upgrade: prefix';END IF;
 branch=replace(branch,needle,'FROM trading.gas_operator_settlements_current s WHERE');
 definition=substring(definition FROM 1 FOR at_index-1)||branch||substring(definition FROM end_index);
 EXECUTE definition;
 target='trading.check_gas_owned_integrity()'::regprocedure;definition=pg_get_functiondef(target);
 needle='   OR coalesce(f.amount,0)<>sign(p.quantity)*(trading.crude_round_cash((prior_total.quantity+s.quantity)*o.value*q.multiplier,2)-trading.crude_round_cash(prior_total.quantity*o.value*q.multiplier,2))';
 replacement=$cash$   OR NOT EXISTS(SELECT 1 FROM trading.gas_operator_settlement_quantities birth
    WHERE(birth.catalog_id,birth.settlement_id,birth.revision)=(s.catalog_id,s.id,1)
     AND trading.gas_operator_original_cash(s.catalog_id,s.id,birth.cash_amount) IS TRUE)$cash$;
 IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_native_upgrade: original cash';END IF;
 definition=replace(definition,needle,replacement);
 needle=$prior$  CROSS JOIN LATERAL(SELECT coalesce(sum(prior.quantity),0) quantity FROM trading.gas_owned_claim_settlements prior
   WHERE(prior.catalog_id,prior.position_id)=(s.catalog_id,s.position_id) AND prior.publication_order<s.publication_order)prior_total
$prior$;
 IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_native_upgrade: obsolete raw prefix';END IF;
 EXECUTE replace(definition,needle,'');
END$patch$;
COMMIT;
