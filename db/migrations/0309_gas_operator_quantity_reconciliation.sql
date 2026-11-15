-- Source preparation for exact operator entitlement and settlement counterparts.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
SELECT pg_advisory_xact_lock(730849102);
INSERT INTO lifecycle.action_kinds(code,automatic,configuration_permission,execution_permission)
 VALUES('gas.operator.reconcile_quantity',false,'ConfigureGasOwnedHoldings','RecordGasOwnedHoldings');

-- Exact accepted operator terms and their immutable cashout prefix geometry.
ALTER TABLE trading.gas_owned_claim_settlements ADD CONSTRAINT gas_operator_exact_parent UNIQUE(catalog_id,id,position_id);
CREATE TABLE trading.gas_operator_quantity_corrections(
 catalog_id uuid NOT NULL,operation_id uuid NOT NULL,account_id uuid NOT NULL,root_claim_id uuid NOT NULL,
 publication_order integer,read_publication_order integer NOT NULL,source_context_id uuid NOT NULL,as_of ref_data.instant NOT NULL,
 actor_id uuid NOT NULL REFERENCES security.principals(id),changed boolean NOT NULL,
 implementation text NOT NULL CHECK(implementation='gas_operator_quantity_reconciliation_v1'),
 ordering_policy text NOT NULL CHECK(ordering_policy='replay_original_settlement_publication_prefix_v1'),adjustment_due_at ref_data.instant,
 PRIMARY KEY(catalog_id,operation_id),UNIQUE(catalog_id,operation_id,account_id),UNIQUE(catalog_id,operation_id,publication_order,actor_id),
 FOREIGN KEY(catalog_id,account_id) REFERENCES trading.gas_owned_accounts(catalog_id,id),
 FOREIGN KEY(catalog_id,root_claim_id,account_id) REFERENCES trading.gas_owned_positions(catalog_id,id,account_id),
 FOREIGN KEY(catalog_id,source_context_id) REFERENCES market_data.temporal_contexts(catalog_id,id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order),
 FOREIGN KEY(catalog_id,read_publication_order) REFERENCES trading.publications(catalog_id,publication_order),
 FOREIGN KEY(catalog_id,operation_id) REFERENCES trading.gas_owned_commands(catalog_id,request_id) DEFERRABLE INITIALLY DEFERRED,
 CHECK(changed=(publication_order IS NOT NULL))
);
CREATE TABLE trading.gas_operator_settlement_quantities(
 catalog_id uuid NOT NULL,settlement_id uuid NOT NULL,claim_id uuid NOT NULL,revision integer NOT NULL CHECK(revision>0),previous_revision integer,
 quantity ref_data.exact_number NOT NULL CHECK(quantity>=0),evidence_id uuid NOT NULL,source_observation_id uuid,
 receipt_lot_id uuid,receipt_revision integer,consumption_id uuid,consumption_revision integer,
 source_allocation text NOT NULL CHECK(source_allocation IN('initial_native_source_enrollment_v1','preserve_unallocated_source_quantity_v1','withdraw_all_source_allocations_v1')),
 previous_settlement_id uuid,previous_settlement_revision integer,cumulative_quantity numeric NOT NULL CHECK(cumulative_quantity>=0),
 price numeric,exact_total numeric,rounded_total numeric,cash_amount ref_data.exact_number,
 origin_request_id uuid NOT NULL,operation_id uuid,actor_id uuid NOT NULL REFERENCES security.principals(id),publication_order integer NOT NULL,
 PRIMARY KEY(catalog_id,settlement_id,revision),UNIQUE(catalog_id,claim_id,settlement_id,revision),UNIQUE(catalog_id,settlement_id,publication_order),
 FOREIGN KEY(catalog_id,settlement_id,claim_id) REFERENCES trading.gas_owned_claim_settlements(catalog_id,id,position_id),
 FOREIGN KEY(catalog_id,settlement_id,previous_revision) REFERENCES trading.gas_operator_settlement_quantities(catalog_id,settlement_id,revision),
 FOREIGN KEY(catalog_id,claim_id,previous_settlement_id,previous_settlement_revision) REFERENCES trading.gas_operator_settlement_quantities(catalog_id,claim_id,settlement_id,revision),
 FOREIGN KEY(catalog_id,evidence_id) REFERENCES trading.gas_owned_evidence(catalog_id,id),
 FOREIGN KEY(catalog_id,source_observation_id) REFERENCES market_data.observations(catalog_id,id),
 FOREIGN KEY(catalog_id,receipt_lot_id,receipt_revision) REFERENCES trading.gas_owned_position_quantities(catalog_id,position_id,revision),
 FOREIGN KEY(catalog_id,consumption_id,consumption_revision) REFERENCES trading.gas_owned_consumption_quantities(catalog_id,consumption_id,revision),
 FOREIGN KEY(catalog_id,origin_request_id) REFERENCES trading.gas_owned_commands(catalog_id,request_id),
 FOREIGN KEY(catalog_id,operation_id,publication_order,actor_id) REFERENCES trading.gas_operator_quantity_corrections(catalog_id,operation_id,publication_order,actor_id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order),
 CHECK((receipt_lot_id IS NULL)=(receipt_revision IS NULL)),CHECK((consumption_id IS NULL)=(consumption_revision IS NULL)),
 CHECK((previous_settlement_id IS NULL)=(previous_settlement_revision IS NULL)),
 CHECK(num_nonnulls(receipt_lot_id,consumption_id)=1 AND source_observation_id IS NULL AND num_nonnulls(price,exact_total,rounded_total,cash_amount)=0
  OR num_nonnulls(receipt_lot_id,consumption_id)=0 AND source_observation_id IS NOT NULL AND num_nonnulls(price,exact_total,rounded_total,cash_amount)=4),
 CHECK(revision=1 AND previous_revision IS NULL AND operation_id IS NULL AND source_allocation='initial_native_source_enrollment_v1'
  OR revision>1 AND previous_revision=revision-1 AND operation_id IS NOT NULL AND source_allocation<>'initial_native_source_enrollment_v1')
);
CREATE TABLE trading.gas_operator_claim_members(
 catalog_id uuid NOT NULL,operation_id uuid NOT NULL,account_id uuid NOT NULL,claim_id uuid NOT NULL,
 previous_revision integer NOT NULL,acknowledged_revision integer NOT NULL,current_revision integer NOT NULL,changed boolean NOT NULL,
 PRIMARY KEY(catalog_id,operation_id,claim_id),
 FOREIGN KEY(catalog_id,operation_id,account_id) REFERENCES trading.gas_operator_quantity_corrections(catalog_id,operation_id,account_id),
 FOREIGN KEY(catalog_id,claim_id,account_id) REFERENCES trading.gas_owned_positions(catalog_id,id,account_id),
 FOREIGN KEY(catalog_id,claim_id,previous_revision) REFERENCES trading.gas_owned_position_quantities(catalog_id,position_id,revision),
 FOREIGN KEY(catalog_id,claim_id,acknowledged_revision) REFERENCES trading.gas_owned_position_quantities(catalog_id,position_id,revision),
 FOREIGN KEY(catalog_id,claim_id,current_revision) REFERENCES trading.gas_owned_position_quantities(catalog_id,position_id,revision)
);
ALTER TABLE trading.gas_operator_quantity_corrections ADD FOREIGN KEY(catalog_id,operation_id,root_claim_id)
 REFERENCES trading.gas_operator_claim_members(catalog_id,operation_id,claim_id) DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE trading.gas_operator_settlement_members(
 catalog_id uuid NOT NULL,operation_id uuid NOT NULL,claim_id uuid NOT NULL,settlement_id uuid NOT NULL,
 previous_revision integer NOT NULL,acknowledged_revision integer NOT NULL,current_revision integer NOT NULL,changed boolean NOT NULL,
 PRIMARY KEY(catalog_id,operation_id,settlement_id),UNIQUE(catalog_id,operation_id,claim_id,settlement_id),
 FOREIGN KEY(catalog_id,operation_id,claim_id) REFERENCES trading.gas_operator_claim_members(catalog_id,operation_id,claim_id),
 FOREIGN KEY(catalog_id,claim_id,settlement_id,previous_revision) REFERENCES trading.gas_operator_settlement_quantities(catalog_id,claim_id,settlement_id,revision),
 FOREIGN KEY(catalog_id,claim_id,settlement_id,acknowledged_revision) REFERENCES trading.gas_operator_settlement_quantities(catalog_id,claim_id,settlement_id,revision),
 FOREIGN KEY(catalog_id,claim_id,settlement_id,current_revision) REFERENCES trading.gas_operator_settlement_quantities(catalog_id,claim_id,settlement_id,revision)
);
CREATE TABLE trading.gas_operator_consumption_members(
 catalog_id uuid NOT NULL,operation_id uuid NOT NULL,consumption_id uuid NOT NULL,
 previous_revision integer NOT NULL,acknowledged_revision integer NOT NULL,current_revision integer NOT NULL,changed boolean NOT NULL,
 PRIMARY KEY(catalog_id,operation_id,consumption_id),
 FOREIGN KEY(catalog_id,operation_id) REFERENCES trading.gas_operator_quantity_corrections(catalog_id,operation_id),
 FOREIGN KEY(catalog_id,consumption_id,previous_revision) REFERENCES trading.gas_owned_consumption_quantities(catalog_id,consumption_id,revision),
 FOREIGN KEY(catalog_id,consumption_id,acknowledged_revision) REFERENCES trading.gas_owned_consumption_quantities(catalog_id,consumption_id,revision),
 FOREIGN KEY(catalog_id,consumption_id,current_revision) REFERENCES trading.gas_owned_consumption_quantities(catalog_id,consumption_id,revision)
);
CREATE TABLE trading.gas_operator_cash_members(
 catalog_id uuid NOT NULL,operation_id uuid NOT NULL,claim_id uuid NOT NULL,settlement_id uuid NOT NULL,cash_id uuid NOT NULL,
 PRIMARY KEY(catalog_id,operation_id,settlement_id),UNIQUE(catalog_id,cash_id),
 FOREIGN KEY(catalog_id,operation_id,claim_id,settlement_id) REFERENCES trading.gas_operator_settlement_members(catalog_id,operation_id,claim_id,settlement_id),
 FOREIGN KEY(catalog_id,cash_id) REFERENCES trading.gas_owned_fees(catalog_id,id)
);

CREATE FUNCTION trading.gas_operator_point_price(catalog uuid,claim uuid,observation uuid) RETURNS numeric
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT o.value*q.multiplier FROM trading.gas_owned_positions p JOIN trading.gas_owned_accounts a ON(a.catalog_id,a.id)=(p.catalog_id,p.account_id)
 JOIN trading.gas_owned_cashout_terms t ON(t.catalog_id,t.position_id)=(p.catalog_id,p.id)
 JOIN market_data.curves c ON(c.catalog_id,c.revision_id,c.code)=(p.catalog_id,p.definition_revision_id,p.mark_curve_code)
 JOIN ref_data.quote_specifications q ON(q.catalog_id,q.revision_id,q.code)=(a.reference_catalog_id,a.reference_revision_id,c.quote_code)
 JOIN market_data.observations o ON(o.catalog_id,o.id)=(p.catalog_id,$3)
 JOIN market_data.series s ON(s.catalog_id,s.revision_id,s.id,s.contract_id,s.quote_code)=(p.catalog_id,p.definition_revision_id,o.series_id,p.mark_contract_id,c.quote_code)
 WHERE(p.catalog_id,p.id,p.kind,p.settlement_mode)=($1,$2,'operator_claim','cashout_final_price_v1')
 AND(o.definition_revision_id,o.reference_catalog_id,o.reference_revision_id,o.source_code,o.role,o.observed_at,o.publication_state)=
  (p.definition_revision_id,a.reference_catalog_id,a.reference_revision_id,t.source_code,t.role,t.observed_at,'final')
$$;
-- The original cash membership keeps the settlement's own birth coordinates.
CREATE FUNCTION trading.gas_operator_original_cash(catalog uuid,settlement uuid,amount numeric) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT CASE WHEN $3=0 THEN native.cash_id IS NULL ELSE EXISTS(
  SELECT 1 FROM trading.gas_owned_fees cash WHERE(cash.catalog_id,cash.id)=(native.catalog_id,native.cash_id)
   AND(cash.position_id,cash.loan_id,cash.amount,cash.reference_catalog_id,cash.reference_revision_id,cash.currency_code,
    cash.due_at,cash.actor_id,cash.publication_order,cash.effective_at) IS NOT DISTINCT FROM
    (native.position_id,NULL::uuid,$3,owner.reference_catalog_id,owner.reference_revision_id,owner.currency_code,
     terms.cash_due_at,native.actor_id,native.publication_order,native.effective_at)) END
 FROM trading.gas_owned_claim_settlements native JOIN trading.gas_owned_positions claim
  ON(claim.catalog_id,claim.id,claim.kind,claim.settlement_mode)=(native.catalog_id,native.position_id,'operator_claim','cashout_final_price_v1')
 JOIN trading.gas_owned_accounts owner ON(owner.catalog_id,owner.id)=(claim.catalog_id,claim.account_id)
 JOIN trading.gas_owned_cashout_terms terms ON(terms.catalog_id,terms.position_id)=(claim.catalog_id,claim.id)
 WHERE(native.catalog_id,native.id)=($1,$2)
$$;
CREATE FUNCTION trading.capture_operator_settlement_origin(command trading.gas_owned_commands) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE native trading.gas_owned_claim_settlements;owner trading.gas_owned_positions;prior trading.gas_operator_settlement_quantities;
 receipt_revision integer;consumption_revision integer;price_value numeric;total numeric;rounded numeric;contribution numeric;quantity numeric;BEGIN
 IF command.request->>'action' IS DISTINCT FROM 'operator_settle' OR command.outcome->>'changed' IS DISTINCT FROM 'true'
  OR command.outcome->>'semanticAcknowledgement' IS DISTINCT FROM 'false' THEN RETURN;END IF;
 SELECT * INTO STRICT native FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.id)=(command.catalog_id,(command.outcome->>'id')::uuid);
 SELECT * INTO STRICT owner FROM trading.gas_owned_positions p WHERE(p.catalog_id,p.id,p.account_id,p.kind)=(native.catalog_id,native.position_id,command.account_id,'operator_claim');
 IF native.actor_id<>command.actor_id OR(command.request#>>'{body,positionId}')::uuid<>owner.id
  OR trading.gas_owned_quantity(command.request#>>'{body,quantity}')<>native.quantity
  OR(command.request#>>'{body,evidenceId}')::uuid<>native.evidence_id
  OR trading.gas_owned_at(command.request#>>'{body,effectiveAt}')<>native.effective_at
  OR(command.request#>>'{body,sourceObservationId}')::uuid IS DISTINCT FROM native.source_observation_id
 THEN RAISE EXCEPTION 'gas_operator_quantity_origin';END IF;
 SELECT q.* INTO prior FROM trading.gas_owned_claim_settlements s JOIN LATERAL(SELECT v.* FROM trading.gas_operator_settlement_quantities v
  WHERE(v.catalog_id,v.settlement_id)=(s.catalog_id,s.id) AND v.publication_order<=native.publication_order ORDER BY revision DESC LIMIT 1)q ON true
 WHERE(s.catalog_id,s.position_id)=(native.catalog_id,owner.id) AND s.publication_order<native.publication_order ORDER BY s.publication_order DESC LIMIT 1;
 quantity=coalesce(prior.cumulative_quantity,0)+native.quantity;
 IF native.source_observation_id IS NOT NULL THEN
  price_value=trading.gas_operator_point_price(native.catalog_id,owner.id,native.source_observation_id);
  IF price_value IS NULL THEN RAISE EXCEPTION 'gas_operator_quantity_origin';END IF;
  total=sign(owner.quantity)*quantity*price_value;rounded=trading.crude_round_cash(total,2);contribution=rounded-coalesce(prior.rounded_total,0);
  IF trading.gas_operator_original_cash(native.catalog_id,native.id,contribution) IS NOT TRUE
  THEN RAISE EXCEPTION 'gas_operator_quantity_origin';END IF;
 ELSE
  IF native.receipt_lot_id IS NOT NULL THEN SELECT q.revision INTO STRICT receipt_revision FROM trading.gas_owned_position_quantities q
   WHERE(q.catalog_id,q.position_id)=(native.catalog_id,native.receipt_lot_id) AND q.publication_order<=native.publication_order ORDER BY q.revision DESC LIMIT 1;END IF;
  IF native.consumption_id IS NOT NULL THEN SELECT q.revision INTO STRICT consumption_revision FROM trading.gas_owned_consumption_quantities q
   WHERE(q.catalog_id,q.consumption_id)=(native.catalog_id,native.consumption_id) AND q.publication_order<=native.publication_order ORDER BY q.revision DESC LIMIT 1;END IF;
 END IF;
 INSERT INTO trading.gas_operator_settlement_quantities VALUES(native.catalog_id,native.id,owner.id,1,NULL,native.quantity,native.evidence_id,native.source_observation_id,
  native.receipt_lot_id,receipt_revision,native.consumption_id,consumption_revision,'initial_native_source_enrollment_v1',prior.settlement_id,prior.revision,
  quantity,price_value,total,rounded,contribution,command.request_id,NULL,native.actor_id,native.publication_order);
END$$;
DO $$DECLARE item trading.gas_owned_commands;BEGIN
 FOR item IN WITH origins AS MATERIALIZED(SELECT c.* FROM trading.gas_owned_commands c
  WHERE c.request->>'action'='operator_settle' AND c.outcome->>'changed'='true' AND c.outcome->>'semanticAcknowledgement'='false')
  SELECT c.* FROM origins c JOIN trading.gas_owned_claim_settlements s ON(s.catalog_id,s.id)=(c.catalog_id,(c.outcome->>'id')::uuid) ORDER BY s.publication_order LOOP PERFORM trading.capture_operator_settlement_origin(item);END LOOP;
 IF(SELECT count(*) FROM trading.gas_operator_settlement_quantities)<>(SELECT count(*) FROM trading.gas_owned_claim_settlements)
 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade: missing exact native settlement origin';END IF;
END$$;
CREATE FUNCTION trading.seed_operator_settlement_origin() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN PERFORM trading.capture_operator_settlement_origin(NEW);RETURN NEW;END$$;
CREATE TRIGGER operator_settlement_origin AFTER INSERT ON trading.gas_owned_commands FOR EACH ROW EXECUTE FUNCTION trading.seed_operator_settlement_origin();

DO $$DECLARE name text;BEGIN
 FOREACH name IN ARRAY ARRAY['gas_operator_quantity_corrections','gas_operator_settlement_quantities','gas_operator_claim_members','gas_operator_settlement_members','gas_operator_consumption_members','gas_operator_cash_members'] LOOP
  EXECUTE format('ALTER TABLE trading.%I OWNER TO openetrm_security_owner',name);
  EXECUTE format('ALTER TABLE trading.%I ENABLE ROW LEVEL SECURITY',name);EXECUTE format('ALTER TABLE trading.%I FORCE ROW LEVEL SECURITY',name);
  EXECUTE format('CREATE POLICY owner_all ON trading.%I TO openetrm_security_owner USING(true) WITH CHECK(true)',name);
  EXECUTE format('REVOKE ALL ON trading.%I FROM PUBLIC,openetrm_runtime,openetrm_risk_worker',name);
  EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.%I FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt()',name);
 END LOOP;
END$$;
CREATE TRIGGER native_publication BEFORE INSERT ON trading.gas_operator_settlement_quantities FOR EACH ROW EXECUTE FUNCTION trading.guard_gas_owned_publication();

CREATE TABLE trading.gas_operator_source_members(
 catalog_id uuid NOT NULL,operation_id uuid NOT NULL,account_id uuid NOT NULL,source_evidence_id uuid NOT NULL,previous_evidence_id uuid NOT NULL,
 source_allocation text NOT NULL CHECK(source_allocation IN('preserve_unallocated_source_quantity_v1','withdraw_all_source_allocations_v1')),
 PRIMARY KEY(catalog_id,operation_id,source_evidence_id),
 FOREIGN KEY(catalog_id,operation_id) REFERENCES trading.gas_operator_quantity_corrections(catalog_id,operation_id),
 FOREIGN KEY(catalog_id,account_id,source_evidence_id) REFERENCES trading.gas_owned_evidence(catalog_id,account_id,id),
 FOREIGN KEY(catalog_id,account_id,previous_evidence_id) REFERENCES trading.gas_owned_evidence(catalog_id,account_id,id)
);

-- Closed transport normalization is separate from deferred validation: the
-- latter must not open exception subtransactions while COMMIT is running.
CREATE FUNCTION trading.gas_operator_quantity_terms(body jsonb) RETURNS jsonb
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE claim jsonb;step jsonb;claims jsonb='[]';steps jsonb;uses jsonb='[]';members integer;name text;BEGIN
 PERFORM trading.gas_owned_projection_keys(body,ARRAY['implementation','rootClaimId','claims','consumptions','cashout','evidence'],ARRAY[]::text[]);
 IF body->>'implementation' IS DISTINCT FROM 'gas_operator_quantity_reconciliation_v1'
  OR jsonb_typeof(body->'rootClaimId') IS DISTINCT FROM 'string' OR(body->>'rootClaimId')::uuid='00000000-0000-0000-0000-000000000000'::uuid
  OR jsonb_typeof(body->'claims') IS DISTINCT FROM 'array' OR jsonb_array_length(body->'claims') NOT BETWEEN 1 AND 16384
  OR jsonb_typeof(body->'consumptions') IS DISTINCT FROM 'array'
  OR jsonb_typeof(body->'evidence') IS DISTINCT FROM 'string' OR length(btrim(body->>'evidence')) NOT BETWEEN 1 AND 2000
  OR octet_length(convert_to(body::text,'UTF8'))>8388608 THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
 members=jsonb_array_length(body->'claims')+jsonb_array_length(body->'consumptions');
 FOR claim IN SELECT value FROM jsonb_array_elements(body->'claims') LOOP
  PERFORM trading.gas_owned_projection_keys(claim,ARRAY['claimId','expectedRevision','quantity','evidenceId','sourceAllocation','settlements'],ARRAY[]::text[]);
  IF jsonb_typeof(claim->'claimId') IS DISTINCT FROM 'string' OR(claim->>'claimId')::uuid='00000000-0000-0000-0000-000000000000'::uuid
   OR jsonb_typeof(claim->'evidenceId') IS DISTINCT FROM 'string' OR(claim->>'evidenceId')::uuid='00000000-0000-0000-0000-000000000000'::uuid
   OR jsonb_typeof(claim->'expectedRevision') IS DISTINCT FROM 'number' OR claim->>'expectedRevision'!~'^[1-9][0-9]{0,8}$'
   OR jsonb_typeof(claim->'quantity') IS DISTINCT FROM 'string'
   OR claim->>'sourceAllocation' IS NULL OR claim->>'sourceAllocation' NOT IN('preserve_unallocated_source_quantity_v1','withdraw_all_source_allocations_v1')
   OR jsonb_typeof(claim->'settlements') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
  members=members+jsonb_array_length(claim->'settlements');steps='[]';
  FOR step IN SELECT value FROM jsonb_array_elements(claim->'settlements') LOOP
   PERFORM trading.gas_owned_projection_keys(step,ARRAY['settlementId','expectedRevision','quantity','evidenceId','sourceObservationId',
    'expectedReceiptRevision','expectedConsumptionRevision','lotId','reservationId','sourceAllocation'],
    ARRAY['sourceObservationId','expectedReceiptRevision','expectedConsumptionRevision','lotId','reservationId']);
   IF jsonb_typeof(step->'settlementId') IS DISTINCT FROM 'string' OR(step->>'settlementId')::uuid='00000000-0000-0000-0000-000000000000'::uuid
    OR jsonb_typeof(step->'evidenceId') IS DISTINCT FROM 'string' OR(step->>'evidenceId')::uuid='00000000-0000-0000-0000-000000000000'::uuid
    OR jsonb_typeof(step->'expectedRevision') IS DISTINCT FROM 'number' OR step->>'expectedRevision'!~'^[1-9][0-9]{0,8}$'
    OR jsonb_typeof(step->'quantity') IS DISTINCT FROM 'string' OR trading.gas_owned_quantity(step->>'quantity')<0
    OR step->>'sourceAllocation' IS NULL OR step->>'sourceAllocation' NOT IN('preserve_unallocated_source_quantity_v1','withdraw_all_source_allocations_v1')
   THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
   FOREACH name IN ARRAY ARRAY['sourceObservationId','lotId','reservationId'] LOOP
    IF step->>name IS NOT NULL AND(jsonb_typeof(step->name) IS DISTINCT FROM 'string' OR(step->>name)::uuid='00000000-0000-0000-0000-000000000000'::uuid)
    THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
   END LOOP;
   FOREACH name IN ARRAY ARRAY['expectedReceiptRevision','expectedConsumptionRevision'] LOOP
    IF step->>name IS NOT NULL AND(jsonb_typeof(step->name) IS DISTINCT FROM 'number' OR step->>name!~'^[1-9][0-9]{0,8}$')
    THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
   END LOOP;
   steps=steps||jsonb_build_array(step||jsonb_build_object('quantity',trim_scale(trading.gas_owned_quantity(step->>'quantity'))::text));
  END LOOP;
  IF jsonb_array_length(steps)<>(SELECT count(DISTINCT(value->>'settlementId')::uuid) FROM jsonb_array_elements(steps)) THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
  claims=claims||jsonb_build_array(claim||jsonb_build_object('quantity',trim_scale(trading.gas_owned_quantity(claim->>'quantity'))::text,'settlements',steps));
 END LOOP;
 IF members>16384 OR jsonb_array_length(claims)<>(SELECT count(DISTINCT(value->>'claimId')::uuid) FROM jsonb_array_elements(claims))
  OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(claims)c WHERE c->>'claimId'=body->>'rootClaimId') THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
 PERFORM trading.gas_owned_projection_keys(body->'cashout',ARRAY['ordering','adjustmentDueAt'],ARRAY['adjustmentDueAt']);
 IF body#>>'{cashout,ordering}' IS DISTINCT FROM 'replay_original_settlement_publication_prefix_v1'
  OR jsonb_typeof(body#>'{cashout,adjustmentDueAt}') NOT IN('string','null') THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
 IF body#>>'{cashout,adjustmentDueAt}' IS NOT NULL THEN PERFORM trading.gas_owned_at(body#>>'{cashout,adjustmentDueAt}');END IF;
 IF jsonb_array_length(body->'consumptions')>0 THEN uses=trading.gas_owned_quantity_terms(jsonb_build_object('positions','[]'::jsonb,
  'consumptions',body->'consumptions','evidence',body->>'evidence'))->'consumptions';END IF;
 RETURN body||jsonb_build_object('claims',(SELECT jsonb_agg(value ORDER BY(value->>'claimId')::uuid) FROM jsonb_array_elements(claims)),'consumptions',uses);
END$$;
CREATE FUNCTION trading.gas_operator_quantity_fact(body jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN RETURN trading.gas_operator_quantity_terms(body);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RAISE EXCEPTION 'gas_operator_quantity_input';END$$;

-- Original publication order is the immutable causal order. Financial head
-- publication supplies knowledge, never a replacement ordering of settlements.
CREATE FUNCTION trading.gas_operator_settlements_through(catalog uuid,through_publication integer)
 RETURNS SETOF trading.gas_owned_claim_settlements LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT s.catalog_id,s.id,s.position_id,q.quantity,s.receipt_lot_id,s.consumption_id,s.cash_id,q.evidence_id,q.source_observation_id,
  s.actor_id,s.publication_order,s.effective_at FROM trading.gas_owned_claim_settlements s
 JOIN LATERAL(SELECT v.* FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id)=(s.catalog_id,s.id)
  AND v.publication_order<=$2 ORDER BY v.revision DESC LIMIT 1)q ON true WHERE s.catalog_id=$1 AND s.publication_order<=$2
$$;
CREATE FUNCTION trading.gas_operator_claim_snapshot(catalog uuid,item jsonb,through_publication integer) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT q.revision FROM trading.gas_owned_position_quantities q WHERE(q.catalog_id,q.position_id,q.quantity,q.evidence_id)=
  ($1,($2->>'claimId')::uuid,trading.gas_owned_quantity($2->>'quantity'),($2->>'evidenceId')::uuid)
 AND q.publication_order<=$3 AND(q.revision=1 AND $2->>'sourceAllocation'='preserve_unallocated_source_quantity_v1' OR EXISTS(
  SELECT 1 FROM trading.gas_operator_claim_members m JOIN trading.gas_owned_commands c ON(c.catalog_id,c.request_id)=(m.catalog_id,m.operation_id)
  CROSS JOIN LATERAL jsonb_array_elements(c.request#>'{body,claims}')i
  WHERE(m.catalog_id,m.claim_id,m.acknowledged_revision)=(q.catalog_id,q.position_id,q.revision)
   AND(i->>'claimId')::uuid=q.position_id AND i->>'sourceAllocation'=$2->>'sourceAllocation')) ORDER BY q.revision LIMIT 1
$$;
CREATE FUNCTION trading.gas_operator_settlement_snapshot(catalog uuid,item jsonb,previous_id uuid,previous_version integer,through_publication integer) RETURNS integer
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT q.revision FROM trading.gas_operator_settlement_quantities q
 LEFT JOIN trading.gas_owned_consumption_quantities used ON(used.catalog_id,used.consumption_id,used.revision)=(q.catalog_id,q.consumption_id,q.consumption_revision)
 WHERE(q.catalog_id,q.settlement_id,q.quantity,q.evidence_id)=($1,($2->>'settlementId')::uuid,trading.gas_owned_quantity($2->>'quantity'),($2->>'evidenceId')::uuid)
 AND q.publication_order<=$5 AND q.source_observation_id IS NOT DISTINCT FROM($2->>'sourceObservationId')::uuid
 AND(q.previous_settlement_id,q.previous_settlement_revision) IS NOT DISTINCT FROM($3,$4)
 AND used.lot_id IS NOT DISTINCT FROM($2->>'lotId')::uuid AND used.reservation_id IS NOT DISTINCT FROM($2->>'reservationId')::uuid
 AND(q.source_allocation=$2->>'sourceAllocation' OR q.revision=1 AND $2->>'sourceAllocation'='preserve_unallocated_source_quantity_v1') ORDER BY q.revision LIMIT 1
$$;
CREATE FUNCTION trading.gas_operator_consumption_snapshot(catalog uuid,item jsonb,through_publication integer) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT q.revision FROM trading.gas_owned_consumption_quantities q WHERE(q.catalog_id,q.consumption_id,q.lot_id,q.quantity,q.evidence_id,q.retracted)=
 ($1,($2->>'consumptionId')::uuid,($2->>'lotId')::uuid,trading.gas_owned_quantity($2->>'quantity'),($2->>'evidenceId')::uuid,($2->>'retracted')::boolean)
 AND q.publication_order<=$3 AND q.reservation_id IS NOT DISTINCT FROM($2->>'reservationId')::uuid AND(q.revision=trading.gas_owned_consumption_quantity_snapshot($1,$2) OR EXISTS(
 SELECT 1 FROM trading.gas_operator_consumption_members m JOIN trading.gas_owned_commands c ON(c.catalog_id,c.request_id)=(m.catalog_id,m.operation_id)
 CROSS JOIN LATERAL jsonb_array_elements(c.request#>'{body,consumptions}')i WHERE(m.catalog_id,m.consumption_id,m.acknowledged_revision)=(q.catalog_id,q.consumption_id,q.revision)
 AND(i->>'consumptionId')::uuid=q.consumption_id AND i->>'sourceAllocation'=$2->>'sourceAllocation')) ORDER BY q.revision LIMIT 1
$$;

CREATE FUNCTION trading.require_gas_operator_use_references(catalog uuid,body jsonb,as_of timestamptz) RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE item jsonb;used trading.gas_owned_consumptions;stock trading.gas_owned_positions;original_stock trading.gas_owned_positions;BEGIN
 FOR item IN SELECT value FROM jsonb_array_elements(body->'consumptions') LOOP
  SELECT * INTO used FROM trading.gas_owned_consumptions c WHERE(c.catalog_id,c.id)=(catalog,(item->>'consumptionId')::uuid);
  IF NOT FOUND OR used.kind NOT IN('delivery','loss') OR used.effective_at>as_of
   OR EXISTS(SELECT 1 FROM trading.gas_owned_claim_settlements x WHERE(x.catalog_id,x.consumption_id)=(catalog,used.id))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_repayments x WHERE(x.catalog_id,x.consumption_id)=(catalog,used.id))
   OR EXISTS(SELECT 1 FROM trading.gas_futures_performance_quantity_supplies x WHERE(x.catalog_id,x.consumption_id)=(catalog,used.id))
  THEN RAISE EXCEPTION 'gas_operator_quantity_closure';END IF;
  SELECT * INTO stock FROM trading.gas_owned_positions v WHERE(v.catalog_id,v.id,v.kind)=(catalog,(item->>'lotId')::uuid,'owned_stock');
  SELECT * INTO STRICT original_stock FROM trading.gas_owned_positions v WHERE(v.catalog_id,v.id)=(catalog,used.lot_id);
  IF stock.id IS NULL OR stock.account_id<>original_stock.account_id OR NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(body->'claims')selected JOIN trading.gas_owned_claim_settlements settled
    ON(settled.catalog_id,settled.position_id)=(catalog,(selected->>'claimId')::uuid)
   JOIN trading.gas_owned_positions parent_stock ON parent_stock.catalog_id=settled.catalog_id
    AND(parent_stock.id=settled.receipt_lot_id OR parent_stock.id IN(SELECT c.lot_id FROM trading.gas_owned_consumptions c
     WHERE(c.catalog_id,c.id)=(settled.catalog_id,settled.consumption_id)))
   WHERE parent_stock.account_id=stock.account_id)
   OR NOT EXISTS(SELECT 1 FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.account_id,e.id)=(catalog,stock.account_id,(item->>'evidenceId')::uuid))
  THEN RAISE EXCEPTION 'gas_operator_quantity_closure';END IF;
 END LOOP;
END$$;

CREATE FUNCTION trading.require_gas_operator_references(catalog uuid,account uuid,body jsonb,as_of timestamptz) RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE owner trading.gas_owned_accounts;claim jsonb;step jsonb;native trading.gas_owned_positions;related trading.gas_owned_accounts;BEGIN
 PERFORM trading.require_gas_operator_use_references(catalog,body,as_of);
 SELECT * INTO owner FROM trading.gas_owned_accounts x WHERE(x.catalog_id,x.id)=(catalog,account);
 IF NOT FOUND OR owner.kind<>'operator_balance' THEN RAISE EXCEPTION 'gas_operator_quantity_source';END IF;
 FOR claim IN SELECT value FROM jsonb_array_elements(body->'claims') LOOP
  SELECT * INTO native FROM trading.gas_owned_positions p WHERE(p.catalog_id,p.account_id,p.id,p.kind)=(catalog,account,(claim->>'claimId')::uuid,'operator_claim');
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.account_id,e.id)=(catalog,account,(claim->>'evidenceId')::uuid))
  THEN RAISE EXCEPTION 'gas_operator_quantity_source';END IF;
  FOR step IN SELECT value FROM jsonb_array_elements(claim->'settlements') LOOP
   IF native.settlement_mode='cashout_final_price_v1' AND(step->>'sourceObservationId' IS NULL OR step->>'expectedReceiptRevision' IS NOT NULL
      OR step->>'expectedConsumptionRevision' IS NOT NULL OR step->>'lotId' IS NOT NULL OR step->>'reservationId' IS NOT NULL)
    OR native.settlement_mode='return_quantity_v1' AND(step->>'sourceObservationId' IS NOT NULL
      OR native.quantity>0 AND(step->>'expectedReceiptRevision' IS NULL OR step->>'expectedConsumptionRevision' IS NOT NULL OR step->>'lotId' IS NOT NULL OR step->>'reservationId' IS NOT NULL)
      OR native.quantity<0 AND(step->>'expectedReceiptRevision' IS NOT NULL OR step->>'expectedConsumptionRevision' IS NULL OR step->>'lotId' IS NULL))
   THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
   IF NOT EXISTS(SELECT 1 FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.id,s.position_id)=(catalog,(step->>'settlementId')::uuid,native.id))
    OR NOT EXISTS(SELECT 1 FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.id)=(catalog,(step->>'evidenceId')::uuid))
    OR step->>'sourceObservationId' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM market_data.observations o WHERE(o.catalog_id,o.id)=(catalog,(step->>'sourceObservationId')::uuid))
   THEN RAISE EXCEPTION 'gas_operator_quantity_source';END IF;
  END LOOP;
 END LOOP;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(body->'claims')i JOIN trading.gas_owned_positions p
  ON(p.catalog_id,p.id)=(catalog,(i->>'claimId')::uuid) WHERE p.settlement_mode='cashout_final_price_v1') IS DISTINCT FROM(body#>>'{cashout,adjustmentDueAt}' IS NOT NULL)
 THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
 FOR related IN SELECT DISTINCT a.* FROM trading.gas_owned_accounts a WHERE a.catalog_id=catalog AND(a.id=account OR a.id IN(
  SELECT p.account_id FROM trading.gas_owned_positions p JOIN trading.gas_owned_claim_settlements s ON(s.catalog_id,s.receipt_lot_id)=(p.catalog_id,p.id)
   WHERE s.catalog_id=catalog AND s.position_id IN(SELECT(value->>'claimId')::uuid FROM jsonb_array_elements(body->'claims'))
  UNION SELECT p.account_id FROM trading.gas_owned_positions p JOIN trading.gas_owned_consumptions c ON(c.catalog_id,c.lot_id)=(p.catalog_id,p.id)
   JOIN trading.gas_owned_claim_settlements s ON(s.catalog_id,s.consumption_id)=(c.catalog_id,c.id)
   WHERE s.catalog_id=catalog AND s.position_id IN(SELECT(value->>'claimId')::uuid FROM jsonb_array_elements(body->'claims')))) LOOP
  IF security.reference_version_visible(related.reference_catalog_id,related.reference_revision_id) IS NOT TRUE
   OR security.market_fact_visible(catalog,related.definition_revision_id,NULL) IS NOT TRUE THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 END LOOP;
END$$;

CREATE FUNCTION trading.gas_operator_quantity_plan(catalog uuid,body jsonb,through_publication integer) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claim jsonb;step jsonb;owner trading.gas_owned_positions;current_claim trading.gas_owned_position_quantities;
 head trading.gas_operator_settlement_quantities;stock trading.gas_owned_position_quantities;used trading.gas_owned_consumption_quantities;receipt_version integer;consumption_version integer;ack integer;claim_ack integer;previous_id uuid;previous_version integer;previous_ack integer;
 quantity numeric;cumulative numeric;price numeric;total numeric;rounded numeric;prior_rounded numeric;contribution numeric;different boolean;
 claims jsonb='[]';steps jsonb;use_states jsonb='[]';all_ack boolean=true;BEGIN
 FOR claim IN SELECT value FROM jsonb_array_elements(body->'claims') LOOP
  SELECT * INTO STRICT owner FROM trading.gas_owned_positions p WHERE(p.catalog_id,p.id)=(catalog,(claim->>'claimId')::uuid);
  SELECT * INTO STRICT current_claim FROM trading.gas_owned_position_quantities q WHERE(q.catalog_id,q.position_id)=(catalog,owner.id)
   AND q.publication_order<=through_publication ORDER BY revision DESC LIMIT 1;
  claim_ack=trading.gas_operator_claim_snapshot(catalog,claim,through_publication);all_ack=all_ack AND claim_ack IS NOT NULL;
  previous_id=NULL;previous_version=NULL;previous_ack=NULL;cumulative=0;prior_rounded=0;steps='[]';
  FOR step IN SELECT choice.value FROM jsonb_array_elements(claim->'settlements')choice(value)
   JOIN trading.gas_owned_claim_settlements origin ON(origin.catalog_id,origin.id)=(catalog,(choice.value->>'settlementId')::uuid) ORDER BY origin.publication_order LOOP
   SELECT * INTO STRICT head FROM trading.gas_operator_settlement_quantities q WHERE(q.catalog_id,q.settlement_id)=(catalog,(step->>'settlementId')::uuid)
    AND q.publication_order<=through_publication ORDER BY revision DESC LIMIT 1;
   quantity=trading.gas_owned_quantity(step->>'quantity');cumulative=cumulative+quantity;
   receipt_version=NULL;consumption_version=NULL;
   IF head.receipt_lot_id IS NOT NULL THEN
    SELECT * INTO STRICT stock FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.position_id)=(catalog,head.receipt_lot_id)
     AND v.publication_order<=through_publication ORDER BY revision DESC LIMIT 1;
    receipt_version=stock.revision+(CASE WHEN(stock.quantity,stock.evidence_id) IS DISTINCT FROM(quantity,(step->>'evidenceId')::uuid) THEN 1 ELSE 0 END);
   ELSIF head.consumption_id IS NOT NULL THEN
    SELECT * INTO STRICT used FROM trading.gas_owned_consumption_quantities v WHERE(v.catalog_id,v.consumption_id)=(catalog,head.consumption_id)
     AND v.publication_order<=through_publication ORDER BY revision DESC LIMIT 1;
    consumption_version=used.revision+(CASE WHEN(used.lot_id,used.quantity,used.evidence_id,used.reservation_id) IS DISTINCT FROM
     ((step->>'lotId')::uuid,quantity,(step->>'evidenceId')::uuid,(step->>'reservationId')::uuid) THEN 1 ELSE 0 END);
   END IF;
   price=NULL;total=NULL;rounded=NULL;contribution=NULL;
   IF step->>'sourceObservationId' IS NOT NULL THEN
    price=trading.gas_operator_point_price(catalog,owner.id,(step->>'sourceObservationId')::uuid);
    IF price IS NULL THEN RAISE EXCEPTION 'gas_operator_final_source';END IF;
    total=sign(owner.quantity)*cumulative*price;rounded=trading.crude_round_cash(total,2);contribution=rounded-prior_rounded;
   END IF;
   different=(head.quantity,head.evidence_id,head.source_observation_id,head.previous_settlement_id,head.previous_settlement_revision,
    head.cumulative_quantity,head.price,head.exact_total,head.rounded_total,head.cash_amount,head.receipt_revision,head.consumption_revision) IS DISTINCT FROM
    (quantity,(step->>'evidenceId')::uuid,(step->>'sourceObservationId')::uuid,previous_id,previous_version,cumulative,price,total,rounded,contribution,receipt_version,consumption_version)
    OR NOT(head.source_allocation=step->>'sourceAllocation' OR head.revision=1 AND step->>'sourceAllocation'='preserve_unallocated_source_quantity_v1');
   ack=trading.gas_operator_settlement_snapshot(catalog,step,previous_id,previous_ack,through_publication);
   all_ack=all_ack AND ack IS NOT NULL;
   steps=steps||jsonb_build_array(jsonb_build_object('selection',step,'previousRevision',head.revision,'acknowledgedRevision',ack,
    'currentRevision',head.revision+(CASE WHEN different THEN 1 ELSE 0 END),'changed',different,
    'receiptLotId',head.receipt_lot_id,'receiptRevision',receipt_version,'consumptionId',head.consumption_id,'consumptionRevision',consumption_version,
    'previousSettlementId',previous_id,'previousSettlementRevision',previous_version,'cumulativeQuantity',trim_scale(cumulative)::text,
    'price',trim_scale(price)::text,'exactTotal',trim_scale(total)::text,'roundedTotal',trim_scale(rounded)::text,'cashAmount',trim_scale(contribution)::text));
   previous_id=head.settlement_id;previous_version=head.revision+(CASE WHEN different THEN 1 ELSE 0 END);previous_ack=ack;prior_rounded=rounded;
  END LOOP;
  claims=claims||jsonb_build_array(jsonb_build_object('selection',claim,'previousRevision',current_claim.revision,'acknowledgedRevision',claim_ack,
   'currentRevision',current_claim.revision+(CASE WHEN claim_ack IS NULL THEN 1 ELSE 0 END),'settlements',steps));
 END LOOP;
 FOR step IN SELECT value FROM jsonb_array_elements(body->'consumptions') LOOP
  SELECT * INTO STRICT used FROM trading.gas_owned_consumption_quantities v WHERE(v.catalog_id,v.consumption_id)=(catalog,(step->>'consumptionId')::uuid)
   AND v.publication_order<=through_publication ORDER BY v.revision DESC LIMIT 1;
  ack=trading.gas_operator_consumption_snapshot(catalog,step,through_publication);all_ack=all_ack AND ack IS NOT NULL;
  use_states=use_states||jsonb_build_array(jsonb_build_object('selection',step,'previousRevision',used.revision,'acknowledgedRevision',ack,
   'currentRevision',used.revision+(CASE WHEN ack IS NULL THEN 1 ELSE 0 END),'changed',ack IS NULL));
 END LOOP;
 RETURN jsonb_build_object('claims',claims,'consumptions',use_states,'allAcknowledged',all_ack);
END$$;

CREATE FUNCTION trading.require_gas_operator_uses(catalog uuid,body jsonb,context uuid,as_of timestamptz,through_publication integer) RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE item jsonb;native trading.gas_owned_consumptions;head trading.gas_owned_consumption_quantities;stock trading.gas_owned_positions;
 owner trading.gas_owned_accounts;old_source trading.gas_owned_evidence;new_source trading.gas_owned_evidence;BEGIN
 PERFORM trading.require_gas_operator_use_references(catalog,body,as_of);
 FOR item IN SELECT value FROM jsonb_array_elements(body->'consumptions') LOOP
  SELECT * INTO STRICT native FROM trading.gas_owned_consumptions c WHERE(c.catalog_id,c.id)=(catalog,(item->>'consumptionId')::uuid);
  SELECT * INTO STRICT head FROM trading.gas_owned_consumption_quantities v WHERE(v.catalog_id,v.consumption_id)=(catalog,native.id)
   AND v.publication_order<=through_publication ORDER BY v.revision DESC LIMIT 1;
  SELECT * INTO STRICT stock FROM trading.gas_owned_positions v WHERE(v.catalog_id,v.id)=(catalog,(item->>'lotId')::uuid);
  SELECT * INTO STRICT owner FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(catalog,stock.account_id);
  IF head.revision<>(item->>'expectedRevision')::integer
   OR security.reference_version_visible(owner.reference_catalog_id,owner.reference_revision_id) IS NOT TRUE
   OR security.market_fact_visible(catalog,owner.definition_revision_id,NULL) IS NOT TRUE
   OR NOT trading.gas_owned_visible(catalog,owner.publication_order,owner.effective_at,context,as_of)
   OR NOT trading.gas_owned_visible(catalog,head.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of)
   OR NOT trading.gas_owned_visible(catalog,stock.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of)
  THEN RAISE EXCEPTION 'gas_quantity_revision';END IF;
  PERFORM settlement_data.require_futures_margin_source(catalog,context,as_of,owner.definition_revision_id);
  IF EXISTS(SELECT 1 FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.account_id)=(catalog,owner.id)
    AND v.publication_order<=through_publication AND NOT trading.gas_owned_visible(catalog,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_consumption_quantities v JOIN trading.gas_owned_positions p ON(p.catalog_id,p.id)=(v.catalog_id,v.lot_id)
    WHERE(v.catalog_id,p.account_id)=(catalog,owner.id) AND v.publication_order<=through_publication
     AND NOT trading.gas_owned_visible(catalog,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of))
  THEN RAISE EXCEPTION 'gas_quantity_revision';END IF;
  SELECT * INTO STRICT old_source FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.id)=(catalog,head.evidence_id);
  SELECT * INTO STRICT new_source FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.account_id,e.id)=(catalog,owner.id,(item->>'evidenceId')::uuid);
  IF(new_source.account_id,new_source.source_key,new_source.kind,new_source.occurred_at) IS DISTINCT FROM
    (old_source.account_id,old_source.source_key,CASE native.kind WHEN 'loss' THEN 'physical_loss' ELSE 'physical_delivery' END,native.effective_at)
   OR abs(new_source.quantity)<trading.gas_owned_quantity(item->>'quantity')
   OR NOT trading.gas_owned_visible(catalog,new_source.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of)
   OR EXISTS(SELECT 1 FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.account_id,e.source_key)=(catalog,owner.id,new_source.source_key)
    AND e.revision>new_source.revision AND e.publication_order<=through_publication)
  THEN RAISE EXCEPTION 'gas_quantity_evidence';END IF;
  IF item->>'reservationId' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM trading.gas_owned_reservations r
   WHERE(r.catalog_id,r.id,r.lot_id)=(catalog,(item->>'reservationId')::uuid,stock.id) AND r.effective_at<=native.effective_at
    AND trading.gas_owned_visible(catalog,r.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of))
  THEN RAISE EXCEPTION 'gas_stock_reservation';END IF;
 END LOOP;
END$$;

CREATE FUNCTION trading.require_gas_operator_amendment(catalog uuid,account uuid,body jsonb,context uuid,as_of timestamptz,policy uuid,policy_revision integer) RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE owner trading.gas_owned_accounts;claim jsonb;step jsonb;p trading.gas_owned_positions;head trading.gas_owned_position_quantities;
 native trading.gas_owned_claim_settlements;q trading.gas_operator_settlement_quantities;old_source trading.gas_owned_evidence;new_source trading.gas_owned_evidence;
 binding trading.gas_owned_action_bindings;selected_ids uuid[];required_ids uuid[];source_id uuid;source_kind text;source_account uuid;
 stock trading.gas_owned_positions;stock_head trading.gas_owned_position_quantities;used trading.gas_owned_consumption_quantities;other trading.gas_owned_accounts;BEGIN
 SELECT * INTO STRICT owner FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(catalog,account);
 IF NOT security.trading_context_day_matches(catalog,context,as_of) OR trading.gas_owned_visible(catalog,owner.publication_order,owner.effective_at,context,as_of) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_owned_context';END IF;
 PERFORM settlement_data.require_futures_margin_source(catalog,context,as_of,owner.definition_revision_id);
 PERFORM trading.require_gas_owned_head(catalog,account,context,as_of);PERFORM trading.require_gas_owned_quantity_head(catalog,account,context,as_of);
 SELECT * INTO binding FROM trading.gas_owned_action_bindings b WHERE(b.catalog_id,b.account_id,b.action)=(catalog,account,'gas.operator.reconcile_quantity') ORDER BY revision DESC LIMIT 1;
 IF(binding.policy_id,binding.policy_revision) IS DISTINCT FROM(policy,policy_revision) THEN RAISE EXCEPTION 'gas_owned_policy_changed';END IF;
 PERFORM lifecycle.require_policy(catalog,policy,policy_revision,'gas.operator.reconcile_quantity',as_of,false);
 PERFORM trading.require_gas_operator_uses(catalog,body,context,as_of,(SELECT max(publication_row.publication_order) FROM trading.publications publication_row WHERE publication_row.catalog_id=catalog));
 FOR claim IN SELECT value FROM jsonb_array_elements(body->'claims') LOOP
  SELECT * INTO STRICT p FROM trading.gas_owned_positions x WHERE(x.catalog_id,x.id,x.account_id)=(catalog,(claim->>'claimId')::uuid,account);
  SELECT * INTO STRICT head FROM trading.gas_owned_position_quantities x WHERE(x.catalog_id,x.position_id)=(catalog,p.id) ORDER BY revision DESC LIMIT 1;
  IF head.revision<>(claim->>'expectedRevision')::integer OR p.effective_at>as_of
   OR trading.gas_owned_visible(catalog,head.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of) IS NOT TRUE
   OR trading.gas_owned_quantity(claim->>'quantity')<>0 AND sign(trading.gas_owned_quantity(claim->>'quantity'))<>sign(p.quantity)
  THEN RAISE EXCEPTION 'gas_quantity_revision';END IF;
  SELECT * INTO STRICT old_source FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.id)=(catalog,head.evidence_id);
  SELECT * INTO STRICT new_source FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.account_id,e.id)=(catalog,account,(claim->>'evidenceId')::uuid);
  IF(new_source.source_key,new_source.kind,new_source.occurred_at) IS DISTINCT FROM(old_source.source_key,'operator_statement',old_source.occurred_at)
   OR abs(new_source.quantity)<abs(trading.gas_owned_quantity(claim->>'quantity'))
   OR trading.gas_owned_quantity(claim->>'quantity')<>0 AND sign(new_source.quantity)<>sign(trading.gas_owned_quantity(claim->>'quantity'))
   OR trading.gas_owned_visible(catalog,new_source.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of) IS NOT TRUE
   OR EXISTS(SELECT 1 FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.account_id,e.source_key)=(catalog,account,new_source.source_key) AND e.revision>new_source.revision)
  THEN RAISE EXCEPTION 'gas_quantity_evidence';END IF;
  SELECT coalesce(array_agg((value->>'settlementId')::uuid ORDER BY(value->>'settlementId')::uuid),'{}') INTO selected_ids FROM jsonb_array_elements(claim->'settlements');
  SELECT coalesce(array_agg(s.id ORDER BY s.id),'{}') INTO required_ids FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.position_id)=(catalog,p.id);
  IF selected_ids<>required_ids OR(SELECT coalesce(sum(trading.gas_owned_quantity(value->>'quantity')),0) FROM jsonb_array_elements(claim->'settlements'))>
   abs(trading.gas_owned_quantity(claim->>'quantity')) THEN RAISE EXCEPTION 'gas_operator_quantity_closure';END IF;
  source_id=NULL;
  FOR step IN SELECT value FROM jsonb_array_elements(claim->'settlements') LOOP
   SELECT * INTO STRICT native FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.id,s.position_id)=(catalog,(step->>'settlementId')::uuid,p.id);
   SELECT * INTO STRICT q FROM trading.gas_operator_settlement_quantities s WHERE(s.catalog_id,s.settlement_id)=(catalog,native.id) ORDER BY revision DESC LIMIT 1;
   IF q.revision<>(step->>'expectedRevision')::integer OR trading.gas_owned_visible(catalog,q.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of) IS NOT TRUE
   THEN RAISE EXCEPTION 'gas_quantity_revision';END IF;
   IF p.settlement_mode='cashout_final_price_v1' THEN
    IF step->>'sourceObservationId' IS NULL OR source_id IS NOT NULL AND source_id<>(step->>'sourceObservationId')::uuid THEN RAISE EXCEPTION 'gas_operator_quantity_closure';END IF;
    source_id=(step->>'sourceObservationId')::uuid;source_account=account;source_kind='cashout_determination';
    PERFORM trading.gas_owned_cashout_price(catalog,p.id,source_id,native.effective_at,context);
   ELSE
    source_kind=CASE WHEN p.quantity>0 THEN 'title_receipt' ELSE 'physical_delivery' END;
    IF p.quantity>0 THEN
     SELECT * INTO STRICT stock FROM trading.gas_owned_positions x WHERE(x.catalog_id,x.id,x.kind,x.origin_policy)=(catalog,native.receipt_lot_id,'owned_stock','operator_balance_transfer_v1');
     SELECT * INTO STRICT stock_head FROM trading.gas_owned_position_quantities x WHERE(x.catalog_id,x.position_id)=(catalog,stock.id) ORDER BY revision DESC LIMIT 1;
     IF stock_head.revision<>(step->>'expectedReceiptRevision')::integer OR(q.receipt_lot_id,q.receipt_revision,q.quantity,q.evidence_id) IS DISTINCT FROM
       (stock.id,stock_head.revision,stock_head.quantity,stock_head.evidence_id)
      OR trading.gas_owned_visible(catalog,stock_head.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of) IS NOT TRUE
     THEN RAISE EXCEPTION 'gas_operator_quantity_closure';END IF;
    ELSE
     SELECT * INTO STRICT used FROM trading.gas_owned_consumption_quantities x WHERE(x.catalog_id,x.consumption_id)=(catalog,native.consumption_id) ORDER BY revision DESC LIMIT 1;
     SELECT * INTO STRICT stock FROM trading.gas_owned_positions x WHERE(x.catalog_id,x.id,x.kind)=(catalog,(step->>'lotId')::uuid,'owned_stock');
     IF used.revision<>(step->>'expectedConsumptionRevision')::integer OR(q.consumption_id,q.consumption_revision,q.quantity,q.evidence_id) IS DISTINCT FROM
       (used.consumption_id,used.revision,used.quantity,used.evidence_id)
      OR trading.gas_owned_visible(catalog,used.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of) IS NOT TRUE
      OR EXISTS(SELECT 1 FROM trading.gas_owned_repayments r WHERE(r.catalog_id,r.consumption_id)=(catalog,native.consumption_id))
      OR EXISTS(SELECT 1 FROM trading.gas_futures_performance_quantity_supplies r WHERE(r.catalog_id,r.consumption_id)=(catalog,native.consumption_id))
     THEN RAISE EXCEPTION 'gas_operator_quantity_closure';END IF;
     IF step->>'reservationId' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM trading.gas_owned_reservations r WHERE(r.catalog_id,r.id,r.lot_id)=(catalog,(step->>'reservationId')::uuid,stock.id)
      AND r.effective_at<=native.effective_at AND trading.gas_owned_visible(catalog,r.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of))
     THEN RAISE EXCEPTION 'gas_stock_reservation';END IF;
    END IF;
    SELECT * INTO STRICT other FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(catalog,stock.account_id);
    IF(other.kind,other.legal_entity_id,other.legal_entity_revision,other.reference_catalog_id,other.reference_revision_id,other.quantity_code,other.location_code,other.currency_code)
     IS DISTINCT FROM('owned_inventory',owner.legal_entity_id,owner.legal_entity_revision,owner.reference_catalog_id,owner.reference_revision_id,owner.quantity_code,owner.location_code,owner.currency_code)
     OR trading.gas_owned_visible(catalog,other.publication_order,other.effective_at,context,as_of) IS NOT TRUE
     OR trading.gas_owned_visible(catalog,stock.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of) IS NOT TRUE
    THEN RAISE EXCEPTION 'gas_operator_quantity_closure';END IF;
    PERFORM trading.require_gas_owned_head(catalog,other.id,context,as_of);PERFORM trading.require_gas_owned_quantity_head(catalog,other.id,context,as_of);
    PERFORM settlement_data.require_futures_margin_source(catalog,context,as_of,other.definition_revision_id);
    source_account=other.id;
   END IF;
   SELECT * INTO STRICT old_source FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.id)=(catalog,q.evidence_id);
   SELECT * INTO STRICT new_source FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.id,e.account_id)=(catalog,(step->>'evidenceId')::uuid,source_account);
   IF(new_source.account_id,new_source.source_key,new_source.kind,new_source.occurred_at) IS DISTINCT FROM(old_source.account_id,old_source.source_key,source_kind,native.effective_at)
    OR abs(new_source.quantity)<trading.gas_owned_quantity(step->>'quantity') OR source_kind='title_receipt' AND new_source.quantity<0
    OR trading.gas_owned_visible(catalog,new_source.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of) IS NOT TRUE
    OR EXISTS(SELECT 1 FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.account_id,e.source_key)=(catalog,source_account,new_source.source_key) AND e.revision>new_source.revision)
   THEN RAISE EXCEPTION 'gas_quantity_evidence';END IF;
  END LOOP;
 END LOOP;
END$$;

-- Allocation proof includes all native allocations of a document, including
-- other explicitly selected claims. No peer allocation is resized implicitly.
CREATE FUNCTION trading.gas_operator_allocations_through(catalog uuid,through_publication integer)
 RETURNS TABLE(family text,id uuid,account_id uuid,source_key text,kind text,evidence_id uuid,quantity numeric)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT 'position',q.position_id,e.account_id,e.source_key,e.kind,q.evidence_id,abs(q.quantity)
 FROM trading.gas_owned_position_quantities q JOIN trading.gas_owned_evidence e ON(e.catalog_id,e.id)=(q.catalog_id,q.evidence_id)
 WHERE q.catalog_id=$1 AND q.revision=(SELECT max(v.revision) FROM trading.gas_owned_position_quantities v
  WHERE(v.catalog_id,v.position_id)=(q.catalog_id,q.position_id) AND v.publication_order<=$2)
 UNION ALL SELECT 'consumption',q.consumption_id,e.account_id,e.source_key,e.kind,q.evidence_id,q.quantity
 FROM trading.gas_owned_consumption_quantities q JOIN trading.gas_owned_evidence e ON(e.catalog_id,e.id)=(q.catalog_id,q.evidence_id)
 WHERE q.catalog_id=$1 AND q.revision=(SELECT max(v.revision) FROM trading.gas_owned_consumption_quantities v
  WHERE(v.catalog_id,v.consumption_id)=(q.catalog_id,q.consumption_id) AND v.publication_order<=$2)
 UNION ALL SELECT 'cashout',q.settlement_id,e.account_id,e.source_key,e.kind,q.evidence_id,q.quantity
 FROM trading.gas_operator_settlement_quantities q JOIN trading.gas_owned_evidence e ON(e.catalog_id,e.id)=(q.catalog_id,q.evidence_id)
 WHERE q.catalog_id=$1 AND q.source_observation_id IS NOT NULL AND q.revision=(SELECT max(v.revision) FROM trading.gas_operator_settlement_quantities v
  WHERE(v.catalog_id,v.settlement_id)=(q.catalog_id,q.settlement_id) AND v.publication_order<=$2)
$$;
CREATE FUNCTION trading.gas_operator_allocation_facts(catalog uuid,operation uuid,body jsonb) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE h trading.gas_operator_quantity_corrections;key record;item record;old_sources uuid[];new_sources uuid[];policies text[];
 old_amount numeric;new_amount numeric;old_source trading.gas_owned_evidence;new_source trading.gas_owned_evidence;owner trading.gas_owned_accounts;
 selected_policy text;fact jsonb;result jsonb='[]';BEGIN
 SELECT * INTO STRICT h FROM trading.gas_operator_quantity_corrections r WHERE(r.catalog_id,r.operation_id)=(catalog,operation);
 FOR key IN SELECT DISTINCT e.account_id,e.source_key,e.kind FROM trading.gas_owned_evidence e WHERE e.catalog_id=catalog AND e.id IN(
  SELECT(value->>'evidenceId')::uuid FROM jsonb_array_elements(body->'claims') UNION SELECT(step->>'evidenceId')::uuid FROM jsonb_array_elements(body->'claims')c
  CROSS JOIN LATERAL jsonb_array_elements(c->'settlements')step UNION SELECT(i->>'evidenceId')::uuid FROM jsonb_array_elements(body->'consumptions')i) ORDER BY e.account_id,e.source_key,e.kind LOOP
  SELECT * INTO STRICT owner FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(catalog,key.account_id);
  SELECT array_agg(DISTINCT a.evidence_id),coalesce(sum(a.quantity),0) INTO old_sources,old_amount
   FROM trading.gas_operator_allocations_through(catalog,h.read_publication_order)a WHERE(a.account_id,a.source_key,a.kind)=(key.account_id,key.source_key,key.kind);
  SELECT array_agg(DISTINCT a.evidence_id),coalesce(sum(a.quantity),0) INTO new_sources,new_amount
   FROM trading.gas_operator_allocations_through(catalog,h.publication_order)a WHERE(a.account_id,a.source_key,a.kind)=(key.account_id,key.source_key,key.kind);
  policies='{}';
  FOR item IN SELECT DISTINCT a.family,a.id FROM trading.gas_operator_allocations_through(catalog,h.read_publication_order)a
    WHERE(a.account_id,a.source_key,a.kind)=(key.account_id,key.source_key,key.kind)
   UNION SELECT DISTINCT a.family,a.id FROM trading.gas_operator_allocations_through(catalog,h.publication_order)a
    WHERE(a.account_id,a.source_key,a.kind)=(key.account_id,key.source_key,key.kind) LOOP
   selected_policy=NULL;
   IF item.family='position' AND key.kind='operator_statement' THEN
    SELECT i->>'sourceAllocation' INTO selected_policy FROM jsonb_array_elements(body->'claims')i WHERE(i->>'claimId')::uuid=item.id;
   ELSIF item.family='position' AND key.kind='title_receipt' THEN
    SELECT i->>'sourceAllocation' INTO selected_policy FROM jsonb_array_elements(body->'claims')c CROSS JOIN LATERAL jsonb_array_elements(c->'settlements')i
     JOIN trading.gas_owned_claim_settlements native ON(native.catalog_id,native.id,native.receipt_lot_id)=(catalog,(i->>'settlementId')::uuid,item.id);
   ELSIF item.family='consumption' AND key.kind='physical_delivery' THEN
    SELECT i->>'sourceAllocation' INTO selected_policy FROM jsonb_array_elements(body->'claims')c CROSS JOIN LATERAL jsonb_array_elements(c->'settlements')i
     JOIN trading.gas_owned_claim_settlements native ON(native.catalog_id,native.id,native.consumption_id)=(catalog,(i->>'settlementId')::uuid,item.id);
   ELSIF item.family='cashout' AND key.kind='cashout_determination' THEN
    SELECT i->>'sourceAllocation' INTO selected_policy FROM jsonb_array_elements(body->'claims')c CROSS JOIN LATERAL jsonb_array_elements(c->'settlements')i
     WHERE(i->>'settlementId')::uuid=item.id;
   END IF;
   IF selected_policy IS NULL AND item.family='consumption' THEN
    SELECT i->>'sourceAllocation' INTO selected_policy FROM jsonb_array_elements(body->'consumptions')i WHERE(i->>'consumptionId')::uuid=item.id;
   END IF;
   IF selected_policy IS NULL THEN RAISE EXCEPTION 'gas_quantity_source_scope';END IF;policies=array_append(policies,selected_policy);
  END LOOP;
  IF cardinality(old_sources)<>1 OR cardinality(new_sources)<>1 OR cardinality(policies)=0 OR(SELECT count(DISTINCT v) FROM unnest(policies)v)<>1
  THEN RAISE EXCEPTION 'gas_quantity_source_scope';END IF;
  SELECT * INTO STRICT old_source FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.id)=(catalog,old_sources[1]);
  SELECT * INTO STRICT new_source FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.id)=(catalog,new_sources[1]);
  IF(old_source.account_id,old_source.source_key,old_source.kind,old_source.occurred_at) IS DISTINCT FROM
    (new_source.account_id,new_source.source_key,new_source.kind,new_source.occurred_at)
   OR trading.gas_owned_visible(catalog,old_source.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',h.source_context_id,h.as_of) IS NOT TRUE
   OR trading.gas_owned_visible(catalog,new_source.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',h.source_context_id,h.as_of) IS NOT TRUE
   OR EXISTS(SELECT 1 FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.account_id,e.source_key)=(catalog,key.account_id,key.source_key)
    AND e.revision>new_source.revision AND e.publication_order<=h.read_publication_order)
  THEN RAISE EXCEPTION 'gas_operator_quantity_source';END IF;
  fact=jsonb_build_object('accountId',key.account_id,'sourceKey',key.source_key,'kind',key.kind,'oldEvidenceId',old_source.id,'sourceEvidenceId',new_source.id,
   'oldCapacity',trim_scale(abs(old_source.quantity))::text,'capacity',trim_scale(abs(new_source.quantity))::text,
   'oldAllocated',trim_scale(old_amount)::text,'allocated',trim_scale(new_amount)::text,'newEnrollment',false,
   'referenceCatalogId',owner.reference_catalog_id,'referenceRevisionId',owner.reference_revision_id,'quantity',owner.quantity_code);
  PERFORM trading.require_gas_source_allocation(policies[1],jsonb_build_array(fact));result=result||jsonb_build_array(fact||jsonb_build_object('sourceAllocation',policies[1]));
 END LOOP;
 RETURN result;
END$$;

CREATE FUNCTION trading.gas_operator_correction_outcome(catalog uuid,operation uuid,body jsonb) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE h trading.gas_operator_quantity_corrections;cm trading.gas_operator_claim_members;sm trading.gas_operator_settlement_members;
 cp trading.gas_owned_position_quantities;q trading.gas_operator_settlement_quantities;claim jsonb;step jsonb;steps jsonb;claims jsonb='[]';uses jsonb;cash jsonb;facts jsonb;through_publication integer;BEGIN
 SELECT * INTO STRICT h FROM trading.gas_operator_quantity_corrections r WHERE(r.catalog_id,r.operation_id)=(catalog,operation);
 through_publication=coalesce(h.publication_order,h.read_publication_order);
 FOR claim IN SELECT value FROM jsonb_array_elements(body->'claims') LOOP
  SELECT * INTO STRICT cm FROM trading.gas_operator_claim_members m WHERE(m.catalog_id,m.operation_id,m.claim_id)=(catalog,operation,(claim->>'claimId')::uuid);
  SELECT * INTO STRICT cp FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.position_id,v.revision)=(catalog,cm.claim_id,cm.current_revision);
  steps='[]';
  FOR step IN SELECT choice.value FROM jsonb_array_elements(claim->'settlements')choice(value)
   JOIN trading.gas_owned_claim_settlements origin ON(origin.catalog_id,origin.id)=(catalog,(choice.value->>'settlementId')::uuid) ORDER BY origin.publication_order LOOP
   SELECT * INTO STRICT sm FROM trading.gas_operator_settlement_members m WHERE(m.catalog_id,m.operation_id,m.settlement_id)=(catalog,operation,(step->>'settlementId')::uuid);
   SELECT * INTO STRICT q FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id,v.revision)=(catalog,sm.settlement_id,sm.current_revision);
   steps=steps||jsonb_build_array(jsonb_build_object('settlementId',sm.settlement_id,'acknowledgedRevision',sm.acknowledged_revision,
    'currentRevision',q.revision,'currentQuantity',trim_scale(q.quantity)::text,'changed',sm.changed,'evidenceId',q.evidence_id,'sourceObservationId',q.source_observation_id,
    'receiptLotId',q.receipt_lot_id,'receiptRevision',q.receipt_revision,'consumptionId',q.consumption_id,'consumptionRevision',q.consumption_revision,
    'previousSettlementId',q.previous_settlement_id,'previousSettlementRevision',q.previous_settlement_revision,'cumulativeQuantity',trim_scale(q.cumulative_quantity)::text,
    'price',trim_scale(q.price)::text,'exactTotal',trim_scale(q.exact_total)::text,'roundedTotal',trim_scale(q.rounded_total)::text,'cashAmount',trim_scale(q.cash_amount)::text));
  END LOOP;
  claims=claims||jsonb_build_array(jsonb_build_object('claimId',cm.claim_id,'acknowledgedRevision',cm.acknowledged_revision,'currentRevision',cp.revision,
   'currentQuantity',trim_scale(cp.quantity)::text,'changed',cm.changed,'settlements',steps));
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('settlementId',m.settlement_id,'positionId',m.claim_id,'cashId',f.id,'amount',trim_scale(f.amount)::text,
  'currency',f.currency_code,'referenceCatalogId',f.reference_catalog_id,'referenceRevisionId',f.reference_revision_id,'dueAt',f.due_at,'effectiveAt',f.effective_at)
  ORDER BY s.publication_order),'[]') INTO cash FROM trading.gas_operator_cash_members m JOIN trading.gas_owned_fees f ON(f.catalog_id,f.id)=(m.catalog_id,m.cash_id)
  JOIN trading.gas_owned_claim_settlements s ON(s.catalog_id,s.id)=(m.catalog_id,m.settlement_id) WHERE(m.catalog_id,m.operation_id)=(catalog,operation);
 SELECT coalesce(jsonb_agg(jsonb_build_object('consumptionId',m.consumption_id,'acknowledgedRevision',m.acknowledged_revision,
  'currentRevision',v.revision,'currentQuantity',trim_scale(v.quantity)::text,'evidenceId',v.evidence_id,'lotId',v.lot_id,
  'reservationId',v.reservation_id,'retracted',v.retracted,'changed',m.changed) ORDER BY m.consumption_id),'[]') INTO uses
 FROM trading.gas_operator_consumption_members m JOIN trading.gas_owned_consumption_quantities v
  ON(v.catalog_id,v.consumption_id,v.revision)=(m.catalog_id,m.consumption_id,m.current_revision)
 WHERE(m.catalog_id,m.operation_id)=(catalog,operation);
 IF h.changed THEN facts=trading.gas_operator_allocation_facts(catalog,operation,body);END IF;
 RETURN jsonb_build_object('operationId',operation,'accountId',h.account_id,'rootClaimId',h.root_claim_id,'action','operator_quantity_reconciliation',
  'changed',h.changed,'semanticAcknowledgement',NOT h.changed,'publicationOrder',h.publication_order,'claims',claims,'consumptions',uses,
  'cashChanges',cash,'sourceAllocations',facts);
END$$;

CREATE FUNCTION security.reconcile_gas_operator_quantities(catalog uuid,operation uuid,account uuid,body jsonb,as_of timestamptz,context uuid,
 policy uuid,policy_revision integer,receipt_only boolean) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE admission jsonb;actor uuid;canonical jsonb;prior trading.gas_owned_commands;owner trading.gas_owned_accounts;plan jsonb;
 claim_state jsonb;step_state jsonb;claim jsonb;step jsonb;head trading.gas_owned_position_quantities;q trading.gas_operator_settlement_quantities;
 native trading.gas_owned_claim_settlements;stock trading.gas_owned_position_quantities;used trading.gas_owned_consumption_quantities;all_ack boolean;publication integer;read_publication integer;claim_version integer;version integer;cash_id uuid;
 delta numeric;outcome jsonb;fact jsonb;BEGIN
 admission=security.gas_owned_admission(catalog,'operator_quantity_reconciliation',body,false);
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR account IS NULL OR context IS NULL OR policy IS NULL
  OR policy_revision IS NULL OR policy_revision<1 OR as_of IS NULL OR NOT isfinite(as_of) OR receipt_only IS NULL THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
 body=trading.gas_operator_quantity_fact(body);
 SELECT actor_id INTO STRICT actor FROM security.request_contexts r WHERE r.backend_pid=pg_backend_pid()
  AND r.transaction_id=pg_current_xact_id_if_assigned() AND r.runtime_login=session_user;
 PERFORM pg_advisory_xact_lock(hashtextextended('gas_owned:'||catalog::text||':'||operation::text,0));
 PERFORM trading.require_gas_operator_references(catalog,account,body,as_of);
 IF NOT EXISTS(SELECT 1 FROM lifecycle.action_policies p WHERE(p.catalog_id,p.id,p.revision,p.action)=(catalog,policy,policy_revision,'gas.operator.reconcile_quantity'))
 THEN RAISE EXCEPTION 'gas_owned_policy';END IF;
 canonical=jsonb_build_object('action','operator_quantity_reconciliation','accountId',account,'body',body,'asOf',as_of,'contextId',context,
  'policyId',policy,'policyRevision',policy_revision,'automatic',false);
 SELECT * INTO prior FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.request_id)=(catalog,operation);
 IF FOUND THEN
  IF prior.actor_id IS DISTINCT FROM actor OR prior.request IS DISTINCT FROM canonical THEN RAISE EXCEPTION 'gas_owned_conflict';END IF;
  PERFORM security.require_gas_owned_commit(catalog,(admission->>'until')::timestamptz,false,false);
  IF receipt_only THEN RETURN jsonb_build_object('outcome',prior.outcome);END IF;RETURN prior.outcome;
 END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT max(p.publication_order) INTO STRICT read_publication FROM trading.publications p WHERE p.catalog_id=catalog;
 plan=trading.gas_operator_quantity_plan(catalog,body,read_publication);all_ack=(plan->>'allAcknowledged')::boolean;
 IF NOT all_ack AND receipt_only THEN
  PERFORM security.require_gas_owned_commit(catalog,(admission->>'until')::timestamptz,false,false);RETURN NULL;
 END IF;
 IF NOT security.trading_context_day_matches(catalog,context,as_of) THEN RAISE EXCEPTION 'gas_owned_context';END IF;
 IF NOT all_ack THEN
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(plan->'claims')c WHERE c->>'acknowledgedRevision' IS NOT NULL AND c->>'acknowledgedRevision'<>c->>'previousRevision')
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(plan->'claims')c CROSS JOIN LATERAL jsonb_array_elements(c->'settlements')s
    WHERE s->>'acknowledgedRevision' IS NOT NULL AND s->>'acknowledgedRevision'<>s->>'previousRevision')
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(plan->'consumptions')s WHERE s->>'acknowledgedRevision' IS NOT NULL AND s->>'acknowledgedRevision'<>s->>'previousRevision') THEN RAISE EXCEPTION 'gas_quantity_batch_history';END IF;
  PERFORM trading.require_gas_operator_amendment(catalog,account,body,context,as_of,policy,policy_revision);
  publication=read_publication+1;INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());
 END IF;
 INSERT INTO trading.gas_operator_quantity_corrections VALUES(catalog,operation,account,(body->>'rootClaimId')::uuid,publication,read_publication,context,as_of,
  actor,NOT all_ack,body->>'implementation',body#>>'{cashout,ordering}',CASE WHEN body#>>'{cashout,adjustmentDueAt}' IS NULL THEN NULL ELSE trading.gas_owned_at(body#>>'{cashout,adjustmentDueAt}') END);
 SELECT * INTO STRICT owner FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(catalog,account);
 FOR claim_state IN SELECT value FROM jsonb_array_elements(plan->'claims') LOOP
  claim=claim_state->'selection';
  SELECT * INTO STRICT head FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.position_id,v.revision)=(catalog,(claim->>'claimId')::uuid,(claim_state->>'previousRevision')::integer);
  claim_version=CASE WHEN all_ack THEN head.revision ELSE(claim_state->>'currentRevision')::integer END;
  IF claim_version<>head.revision THEN
   INSERT INTO trading.gas_owned_position_quantities VALUES(catalog,head.position_id,account,claim_version,head.revision,
    trading.gas_owned_quantity(claim->>'quantity'),(claim->>'evidenceId')::uuid,trading.gas_owned_quantity(claim->>'quantity')=0,actor,publication);
  END IF;
  INSERT INTO trading.gas_operator_claim_members VALUES(catalog,operation,account,head.position_id,head.revision,
   CASE WHEN all_ack THEN(claim_state->>'acknowledgedRevision')::integer ELSE claim_version END,claim_version,claim_version<>head.revision);
  FOR step_state IN SELECT value FROM jsonb_array_elements(claim_state->'settlements') LOOP
   step=step_state->'selection';
   SELECT * INTO STRICT q FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id,v.revision)=(catalog,(step->>'settlementId')::uuid,(step_state->>'previousRevision')::integer);
   version=CASE WHEN all_ack THEN q.revision ELSE(step_state->>'currentRevision')::integer END;
   IF version<>q.revision THEN
    IF q.receipt_lot_id IS NOT NULL THEN
     SELECT * INTO STRICT stock FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.position_id)=(catalog,q.receipt_lot_id) ORDER BY revision DESC LIMIT 1;
     IF(step_state->>'receiptRevision')::integer<>stock.revision THEN
      INSERT INTO trading.gas_owned_position_quantities VALUES(catalog,stock.position_id,stock.account_id,stock.revision+1,stock.revision,
       trading.gas_owned_quantity(step->>'quantity'),(step->>'evidenceId')::uuid,trading.gas_owned_quantity(step->>'quantity')=0,actor,publication);
     END IF;
    ELSIF q.consumption_id IS NOT NULL THEN
     SELECT * INTO STRICT used FROM trading.gas_owned_consumption_quantities v WHERE(v.catalog_id,v.consumption_id)=(catalog,q.consumption_id) ORDER BY revision DESC LIMIT 1;
     IF(step_state->>'consumptionRevision')::integer<>used.revision THEN
      INSERT INTO trading.gas_owned_consumption_quantities VALUES(catalog,used.consumption_id,used.revision+1,used.revision,(step->>'lotId')::uuid,
       trading.gas_owned_quantity(step->>'quantity'),(step->>'evidenceId')::uuid,(step->>'reservationId')::uuid,trading.gas_owned_quantity(step->>'quantity')=0,actor,publication);
     END IF;
    END IF;
    INSERT INTO trading.gas_operator_settlement_quantities VALUES(catalog,q.settlement_id,q.claim_id,version,q.revision,
     trading.gas_owned_quantity(step->>'quantity'),(step->>'evidenceId')::uuid,(step->>'sourceObservationId')::uuid,
     q.receipt_lot_id,(step_state->>'receiptRevision')::integer,q.consumption_id,(step_state->>'consumptionRevision')::integer,step->>'sourceAllocation',
     (step_state->>'previousSettlementId')::uuid,(step_state->>'previousSettlementRevision')::integer,(step_state->>'cumulativeQuantity')::numeric,
     (step_state->>'price')::numeric,(step_state->>'exactTotal')::numeric,(step_state->>'roundedTotal')::numeric,(step_state->>'cashAmount')::numeric,
     q.origin_request_id,operation,actor,publication);
   END IF;
   INSERT INTO trading.gas_operator_settlement_members VALUES(catalog,operation,q.claim_id,q.settlement_id,q.revision,
    CASE WHEN all_ack THEN(step_state->>'acknowledgedRevision')::integer ELSE version END,version,version<>q.revision);
   IF version<>q.revision THEN
    delta=(step_state->>'cashAmount')::numeric-q.cash_amount;
    IF delta<>0 THEN
     cash_id=gen_random_uuid();SELECT * INTO STRICT native FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.id)=(catalog,q.settlement_id);
     INSERT INTO trading.gas_owned_fees VALUES(catalog,cash_id,q.claim_id,NULL,delta,owner.reference_catalog_id,owner.reference_revision_id,owner.currency_code,
      trading.gas_owned_at(body#>>'{cashout,adjustmentDueAt}'),actor,publication,native.effective_at);
     INSERT INTO trading.gas_operator_cash_members VALUES(catalog,operation,q.claim_id,q.settlement_id,cash_id);
    END IF;
   END IF;
  END LOOP;
 END LOOP;
 FOR step_state IN SELECT value FROM jsonb_array_elements(plan->'consumptions') LOOP
  step=step_state->'selection';
  SELECT * INTO STRICT used FROM trading.gas_owned_consumption_quantities v WHERE(v.catalog_id,v.consumption_id,v.revision)=
   (catalog,(step->>'consumptionId')::uuid,(step_state->>'previousRevision')::integer);
  version=CASE WHEN all_ack THEN used.revision ELSE(step_state->>'currentRevision')::integer END;
  IF version<>used.revision THEN
   INSERT INTO trading.gas_owned_consumption_quantities VALUES(catalog,used.consumption_id,version,used.revision,(step->>'lotId')::uuid,
    trading.gas_owned_quantity(step->>'quantity'),(step->>'evidenceId')::uuid,(step->>'reservationId')::uuid,(step->>'retracted')::boolean,actor,publication);
  END IF;
  INSERT INTO trading.gas_operator_consumption_members VALUES(catalog,operation,used.consumption_id,used.revision,
   CASE WHEN all_ack THEN(step_state->>'acknowledgedRevision')::integer ELSE version END,version,version<>used.revision);
 END LOOP;
 IF NOT all_ack THEN
  FOR fact IN SELECT value FROM jsonb_array_elements(trading.gas_operator_allocation_facts(catalog,operation,body)) LOOP
   INSERT INTO trading.gas_operator_source_members VALUES(catalog,operation,(fact->>'accountId')::uuid,(fact->>'sourceEvidenceId')::uuid,(fact->>'oldEvidenceId')::uuid,fact->>'sourceAllocation');
  END LOOP;
 END IF;
 outcome=trading.gas_operator_correction_outcome(catalog,operation,body);
 INSERT INTO trading.gas_owned_commands VALUES(catalog,actor,operation,account,canonical,outcome,(admission->>'until')::timestamptz,false,false);
 PERFORM security.require_gas_owned_commit(catalog,(admission->>'until')::timestamptz,false,false);
 IF receipt_only THEN RETURN jsonb_build_object('outcome',outcome);END IF;RETURN outcome;
END$$;

CREATE FUNCTION trading.gas_operator_position_proof(catalog uuid,position_id uuid,version integer) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM trading.gas_operator_quantity_corrections h JOIN trading.publications pub
  ON(pub.catalog_id,pub.publication_order,pub.publication_xid)=(h.catalog_id,h.publication_order,pg_current_xact_id_if_assigned())
  JOIN trading.gas_owned_position_quantities q ON(q.catalog_id,q.position_id,q.revision,q.publication_order,q.actor_id)=($1,$2,$3,h.publication_order,h.actor_id)
  WHERE h.catalog_id=$1 AND h.changed AND(EXISTS(SELECT 1 FROM trading.gas_operator_claim_members m
   WHERE(m.catalog_id,m.operation_id,m.claim_id,m.current_revision,m.changed)=(h.catalog_id,h.operation_id,$2,$3,true))
   OR EXISTS(SELECT 1 FROM trading.gas_operator_settlement_members m JOIN trading.gas_operator_settlement_quantities s
    ON(s.catalog_id,s.settlement_id,s.revision)=(m.catalog_id,m.settlement_id,m.current_revision)
    JOIN trading.gas_owned_positions native ON(native.catalog_id,native.id,native.kind,native.origin_policy)=($1,$2,'owned_stock','operator_balance_transfer_v1')
    WHERE(m.catalog_id,m.operation_id,m.changed,s.receipt_lot_id,s.receipt_revision,s.quantity,s.evidence_id)=
     (h.catalog_id,h.operation_id,true,$2,$3,q.quantity,q.evidence_id))))
$$;
CREATE FUNCTION trading.gas_operator_consumption_proof(catalog uuid,consumption uuid,version integer) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM trading.gas_operator_quantity_corrections h JOIN trading.publications pub
  ON(pub.catalog_id,pub.publication_order,pub.publication_xid)=(h.catalog_id,h.publication_order,pg_current_xact_id_if_assigned())
  JOIN trading.gas_owned_consumption_quantities q ON(q.catalog_id,q.consumption_id,q.revision,q.publication_order,q.actor_id)=($1,$2,$3,h.publication_order,h.actor_id)
  WHERE h.catalog_id=$1 AND h.changed AND(EXISTS(SELECT 1 FROM trading.gas_operator_consumption_members m
   WHERE(m.catalog_id,m.operation_id,m.consumption_id,m.current_revision,m.changed)=(h.catalog_id,h.operation_id,$2,$3,true))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_consumptions native JOIN trading.gas_operator_settlement_members m
    ON(m.catalog_id,m.operation_id,m.changed)=(h.catalog_id,h.operation_id,true)
    JOIN trading.gas_operator_settlement_quantities s ON(s.catalog_id,s.settlement_id,s.revision)=(m.catalog_id,m.settlement_id,m.current_revision)
    WHERE(native.catalog_id,native.id,native.kind,s.consumption_id,s.consumption_revision,s.quantity,s.evidence_id)=($1,$2,'delivery',$2,$3,q.quantity,q.evidence_id))))
$$;
CREATE VIEW trading.gas_operator_settlements_current AS
 SELECT(jsonb_populate_record(native,jsonb_build_object('quantity',q.quantity,'evidence_id',q.evidence_id,'source_observation_id',q.source_observation_id))).*
 FROM trading.gas_owned_claim_settlements native JOIN LATERAL(SELECT v.* FROM trading.gas_operator_settlement_quantities v
  WHERE(v.catalog_id,v.settlement_id)=(native.catalog_id,native.id) ORDER BY v.revision DESC LIMIT 1)q ON true;
ALTER VIEW trading.gas_operator_settlements_current OWNER TO openetrm_security_owner;
REVOKE ALL ON trading.gas_operator_settlements_current FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;

CREATE FUNCTION trading.check_gas_operator_settlement_origin() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE origin trading.gas_operator_settlement_quantities;command trading.gas_owned_commands;BEGIN
 SELECT * INTO origin FROM trading.gas_operator_settlement_quantities q WHERE(q.catalog_id,q.settlement_id,q.revision)=(NEW.catalog_id,NEW.id,1);
 IF NOT FOUND OR(origin.claim_id,origin.actor_id,origin.publication_order) IS DISTINCT FROM(NEW.position_id,NEW.actor_id,NEW.publication_order)
 THEN RAISE EXCEPTION 'gas_operator_quantity_origin';END IF;
 SELECT * INTO STRICT command FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.request_id)=(NEW.catalog_id,origin.origin_request_id);
 IF command.request->>'action' IS DISTINCT FROM 'operator_settle' OR command.outcome->>'id' IS DISTINCT FROM NEW.id::text
  OR command.outcome->>'changed' IS DISTINCT FROM 'true' OR command.outcome->>'semanticAcknowledgement' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'gas_operator_quantity_origin';END IF;
 PERFORM security.require_gas_owned_commit(NEW.catalog_id,command.authority_until,command.configuring,command.requires_jobs);
 IF command.authority_until IS NULL OR NOT isfinite(command.authority_until) OR clock_timestamp()>=command.authority_until
 THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 RETURN NULL;
END$$;

CREATE FUNCTION trading.check_gas_operator_settlement_quantity() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE native trading.gas_owned_claim_settlements;owner trading.gas_owned_positions;previous trading.gas_operator_settlement_quantities;
 predecessor trading.gas_owned_claim_settlements;before_claim trading.gas_owned_position_quantities;receipt trading.gas_owned_position_quantities;taken trading.gas_owned_consumption_quantities;command trading.gas_owned_commands;price numeric;total numeric;rounded numeric;contribution numeric;BEGIN
 SELECT * INTO STRICT native FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.id,s.position_id)=(NEW.catalog_id,NEW.settlement_id,NEW.claim_id);
 SELECT * INTO STRICT owner FROM trading.gas_owned_positions p WHERE(p.catalog_id,p.id,p.kind)=(NEW.catalog_id,NEW.claim_id,'operator_claim');
 SELECT * INTO predecessor FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.position_id)=(NEW.catalog_id,NEW.claim_id)
  AND s.publication_order<native.publication_order ORDER BY s.publication_order DESC LIMIT 1;
 IF predecessor.id IS NOT NULL THEN
  SELECT * INTO STRICT previous FROM trading.gas_operator_settlement_quantities q WHERE(q.catalog_id,q.settlement_id)=(NEW.catalog_id,predecessor.id)
   AND q.publication_order<=NEW.publication_order ORDER BY q.revision DESC LIMIT 1;
 END IF;
 IF(NEW.previous_settlement_id,NEW.previous_settlement_revision,NEW.cumulative_quantity) IS DISTINCT FROM
  (previous.settlement_id,previous.revision,coalesce(previous.cumulative_quantity,0)+NEW.quantity) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 IF NEW.source_observation_id IS NOT NULL THEN
  price=trading.gas_operator_point_price(NEW.catalog_id,NEW.claim_id,NEW.source_observation_id);
  total=sign(owner.quantity)*NEW.cumulative_quantity*price;rounded=trading.crude_round_cash(total,2);contribution=rounded-coalesce(previous.rounded_total,0);
  IF price IS NULL OR(NEW.price,NEW.exact_total,NEW.rounded_total,NEW.cash_amount) IS DISTINCT FROM(price,total,rounded,contribution)
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 END IF;
 IF NEW.receipt_lot_id IS NOT NULL THEN
  SELECT * INTO STRICT receipt FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.position_id,v.revision)=(NEW.catalog_id,NEW.receipt_lot_id,NEW.receipt_revision);
  IF(receipt.quantity,receipt.evidence_id,receipt.retracted) IS DISTINCT FROM(NEW.quantity,NEW.evidence_id,NEW.quantity=0)
   OR receipt.publication_order>NEW.publication_order OR NEW.receipt_lot_id IS DISTINCT FROM native.receipt_lot_id
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 ELSIF NEW.consumption_id IS NOT NULL THEN
  SELECT * INTO STRICT taken FROM trading.gas_owned_consumption_quantities v WHERE(v.catalog_id,v.consumption_id,v.revision)=(NEW.catalog_id,NEW.consumption_id,NEW.consumption_revision);
  IF(taken.quantity,taken.evidence_id,taken.retracted) IS DISTINCT FROM(NEW.quantity,NEW.evidence_id,NEW.quantity=0)
   OR taken.publication_order>NEW.publication_order OR NEW.consumption_id IS DISTINCT FROM native.consumption_id
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 END IF;
 SELECT * INTO STRICT command FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.request_id)=(NEW.catalog_id,NEW.origin_request_id);
 IF command.request->>'action' IS DISTINCT FROM 'operator_settle' OR command.outcome->>'id' IS DISTINCT FROM NEW.settlement_id::text
  OR command.outcome->>'changed' IS DISTINCT FROM 'true' OR command.outcome->>'semanticAcknowledgement' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'gas_operator_quantity_origin';END IF;
 IF NEW.revision=1 THEN
  IF(NEW.quantity,NEW.evidence_id,NEW.source_observation_id,NEW.receipt_lot_id,NEW.consumption_id,NEW.actor_id,NEW.publication_order) IS DISTINCT FROM
   (native.quantity,native.evidence_id,native.source_observation_id,native.receipt_lot_id,native.consumption_id,native.actor_id,native.publication_order)
   OR NEW.source_observation_id IS NOT NULL AND trading.gas_operator_original_cash(NEW.catalog_id,NEW.settlement_id,NEW.cash_amount) IS NOT TRUE
  THEN RAISE EXCEPTION 'gas_operator_quantity_origin';END IF;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM trading.gas_operator_settlement_members m JOIN trading.gas_operator_quantity_corrections h
   ON(h.catalog_id,h.operation_id)=(m.catalog_id,m.operation_id) JOIN trading.publications pub
   ON(pub.catalog_id,pub.publication_order,pub.publication_xid)=(h.catalog_id,h.publication_order,pg_current_xact_id())
   WHERE(m.catalog_id,m.settlement_id,m.current_revision,m.changed,h.operation_id,h.publication_order,h.actor_id)=
    (NEW.catalog_id,NEW.settlement_id,NEW.revision,true,NEW.operation_id,NEW.publication_order,NEW.actor_id)) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 END IF;
 SELECT * INTO STRICT before_claim FROM trading.gas_owned_position_quantities q WHERE(q.catalog_id,q.position_id)=(NEW.catalog_id,NEW.claim_id)
  AND q.publication_order<=NEW.publication_order ORDER BY revision DESC LIMIT 1;
 IF(SELECT sum(s.quantity) FROM trading.gas_operator_settlements_through(NEW.catalog_id,NEW.publication_order)s WHERE s.position_id=NEW.claim_id)>abs(before_claim.quantity)
 THEN RAISE EXCEPTION 'gas_operator_capacity';END IF;
 IF NEW.revision=1 THEN
  PERFORM security.require_gas_owned_commit(NEW.catalog_id,command.authority_until,command.configuring,command.requires_jobs);
  IF command.authority_until IS NULL OR NOT isfinite(command.authority_until) OR clock_timestamp()>=command.authority_until
  THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 END IF;
 RETURN NULL;
END$$;

CREATE FUNCTION trading.check_gas_operator_quantity_correction() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE operation uuid;h trading.gas_operator_quantity_corrections;c trading.gas_owned_commands;body jsonb;plan jsonb;claim_state jsonb;step_state jsonb;
 claim jsonb;step jsonb;cm trading.gas_operator_claim_members;sm trading.gas_operator_settlement_members;q trading.gas_operator_settlement_quantities;
 before_q trading.gas_operator_settlement_quantities;cp trading.gas_owned_position_quantities;cash trading.gas_owned_fees;native trading.gas_owned_claim_settlements;
 owner trading.gas_owned_accounts;binding trading.gas_owned_action_bindings;um trading.gas_operator_consumption_members;use_head trading.gas_owned_consumption_quantities;expected_version integer;all_ack boolean;delta numeric;facts jsonb;fact jsonb;BEGIN
 IF TG_TABLE_NAME='gas_owned_commands' THEN
  IF NEW.request->>'action' IS DISTINCT FROM 'operator_quantity_reconciliation' THEN RETURN NULL;END IF;operation=NEW.request_id;
 ELSE operation=NEW.operation_id;END IF;
 SELECT * INTO STRICT h FROM trading.gas_operator_quantity_corrections x WHERE(x.catalog_id,x.operation_id)=(NEW.catalog_id,operation);
 SELECT * INTO STRICT c FROM trading.gas_owned_commands x WHERE(x.catalog_id,x.request_id)=(h.catalog_id,h.operation_id);
 PERFORM security.require_gas_owned_commit(h.catalog_id,c.authority_until,false,false);
 PERFORM trading.gas_owned_projection_keys(c.request,ARRAY['action','accountId','body','asOf','contextId','policyId','policyRevision','automatic'],ARRAY[]::text[]);
 body=c.request->'body';
 IF jsonb_typeof(body) IS DISTINCT FROM 'object' OR jsonb_typeof(body->'claims') IS DISTINCT FROM 'array'
  OR jsonb_typeof(body->'consumptions') IS DISTINCT FROM 'array' OR trading.gas_operator_quantity_terms(body) IS DISTINCT FROM body
  OR(c.actor_id,c.account_id,c.configuring,c.requires_jobs,c.request->>'action',(c.request->>'accountId')::uuid,(c.request->>'asOf')::timestamptz,
   (c.request->>'contextId')::uuid,(c.request->>'automatic')::boolean,(body->>'rootClaimId')::uuid,body->>'implementation',body#>>'{cashout,ordering}') IS DISTINCT FROM
   (h.actor_id,h.account_id,false,false,'operator_quantity_reconciliation',h.account_id,h.as_of,h.source_context_id,false,h.root_claim_id,h.implementation,h.ordering_policy)
  OR h.adjustment_due_at IS DISTINCT FROM (CASE WHEN body#>>'{cashout,adjustmentDueAt}' IS NULL THEN NULL ELSE trading.gas_owned_at(body#>>'{cashout,adjustmentDueAt}') END)
 THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 IF NOT h.changed AND(EXISTS(SELECT 1 FROM trading.gas_operator_source_members m WHERE(m.catalog_id,m.operation_id)=(h.catalog_id,h.operation_id))
  OR EXISTS(SELECT 1 FROM trading.gas_operator_cash_members m WHERE(m.catalog_id,m.operation_id)=(h.catalog_id,h.operation_id)))
 THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 PERFORM trading.require_gas_operator_references(h.catalog_id,h.account_id,body,h.as_of);
 IF security.trading_context_day_matches(h.catalog_id,h.source_context_id,h.as_of) IS NOT TRUE THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 SELECT * INTO STRICT owner FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(h.catalog_id,h.account_id);
 PERFORM settlement_data.require_futures_margin_source(h.catalog_id,h.source_context_id,h.as_of,owner.definition_revision_id);
 plan=trading.gas_operator_quantity_plan(h.catalog_id,body,h.read_publication_order);all_ack=(plan->>'allAcknowledged')::boolean;
 IF h.changed IS DISTINCT FROM (NOT all_ack) OR jsonb_array_length(body->'claims')<>(SELECT count(*) FROM trading.gas_operator_claim_members m WHERE(m.catalog_id,m.operation_id)=(h.catalog_id,h.operation_id))
  OR(SELECT count(*) FROM jsonb_array_elements(body->'claims')x CROSS JOIN LATERAL jsonb_array_elements(x->'settlements'))<>
   (SELECT count(*) FROM trading.gas_operator_settlement_members m WHERE(m.catalog_id,m.operation_id)=(h.catalog_id,h.operation_id))
  OR jsonb_array_length(body->'consumptions')<>(SELECT count(*) FROM trading.gas_operator_consumption_members m WHERE(m.catalog_id,m.operation_id)=(h.catalog_id,h.operation_id))
 THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 IF h.changed THEN
  IF h.publication_order<>h.read_publication_order+1 OR NOT EXISTS(SELECT 1 FROM trading.publications p
   WHERE(p.catalog_id,p.publication_order,p.publication_xid)=(h.catalog_id,h.publication_order,pg_current_xact_id())) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  SELECT * INTO binding FROM trading.gas_owned_action_bindings b WHERE(b.catalog_id,b.account_id,b.action)=(h.catalog_id,h.account_id,'gas.operator.reconcile_quantity')
   AND b.publication_order<=h.publication_order ORDER BY revision DESC LIMIT 1;
  IF(binding.policy_id,binding.policy_revision) IS DISTINCT FROM((c.request->>'policyId')::uuid,(c.request->>'policyRevision')::integer)
  THEN RAISE EXCEPTION 'gas_owned_policy_changed';END IF;
  PERFORM lifecycle.require_policy(h.catalog_id,binding.policy_id,binding.policy_revision,'gas.operator.reconcile_quantity',h.as_of,false);
 END IF;
 SELECT * INTO STRICT owner FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(h.catalog_id,h.account_id);
 FOR claim_state IN SELECT value FROM jsonb_array_elements(plan->'claims') LOOP
  claim=claim_state->'selection';
  SELECT * INTO STRICT cm FROM trading.gas_operator_claim_members m WHERE(m.catalog_id,m.operation_id,m.claim_id)=(h.catalog_id,h.operation_id,(claim->>'claimId')::uuid);
  expected_version=CASE WHEN all_ack THEN(claim_state->>'previousRevision')::integer ELSE(claim_state->>'currentRevision')::integer END;
  IF(cm.previous_revision,cm.acknowledged_revision,cm.current_revision,cm.changed) IS DISTINCT FROM
   ((claim_state->>'previousRevision')::integer,CASE WHEN all_ack THEN(claim_state->>'acknowledgedRevision')::integer ELSE expected_version END,
    expected_version,expected_version<>(claim_state->>'previousRevision')::integer) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  IF h.changed AND NOT EXISTS(SELECT 1 FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.position_id,v.revision)=(h.catalog_id,cm.claim_id,cm.previous_revision)
   AND trading.gas_owned_visible(h.catalog_id,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',h.source_context_id,h.as_of))
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  SELECT * INTO STRICT cp FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.position_id,v.revision)=(h.catalog_id,cm.claim_id,cm.acknowledged_revision);
  IF(cp.quantity,cp.evidence_id) IS DISTINCT FROM(trading.gas_owned_quantity(claim->>'quantity'),(claim->>'evidenceId')::uuid)
   OR cp.publication_order>coalesce(h.publication_order,h.read_publication_order) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  FOR step_state IN SELECT value FROM jsonb_array_elements(claim_state->'settlements') LOOP
   step=step_state->'selection';
   SELECT * INTO STRICT sm FROM trading.gas_operator_settlement_members m WHERE(m.catalog_id,m.operation_id,m.settlement_id)=(h.catalog_id,h.operation_id,(step->>'settlementId')::uuid);
   expected_version=CASE WHEN all_ack THEN(step_state->>'previousRevision')::integer ELSE(step_state->>'currentRevision')::integer END;
   IF(sm.previous_revision,sm.acknowledged_revision,sm.current_revision,sm.changed) IS DISTINCT FROM
    ((step_state->>'previousRevision')::integer,CASE WHEN all_ack THEN(step_state->>'acknowledgedRevision')::integer ELSE expected_version END,
     expected_version,expected_version<>(step_state->>'previousRevision')::integer) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
   SELECT * INTO STRICT q FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id,v.revision)=(h.catalog_id,sm.settlement_id,sm.acknowledged_revision);
   IF(q.quantity,q.evidence_id,q.source_observation_id) IS DISTINCT FROM
    (trading.gas_owned_quantity(step->>'quantity'),(step->>'evidenceId')::uuid,(step->>'sourceObservationId')::uuid)
    OR q.publication_order>coalesce(h.publication_order,h.read_publication_order) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
   IF h.changed THEN
    IF NOT EXISTS(SELECT 1 FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id,v.revision)=(h.catalog_id,sm.settlement_id,sm.previous_revision)
      AND trading.gas_owned_visible(h.catalog_id,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',h.source_context_id,h.as_of))
     OR step->>'expectedReceiptRevision' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM trading.gas_owned_position_quantities v JOIN trading.gas_owned_claim_settlements original
      ON(original.catalog_id,original.receipt_lot_id)=(v.catalog_id,v.position_id) WHERE(original.catalog_id,original.id,v.revision)=(h.catalog_id,sm.settlement_id,(step->>'expectedReceiptRevision')::integer)
      AND v.revision=(SELECT max(x.revision) FROM trading.gas_owned_position_quantities x WHERE(x.catalog_id,x.position_id)=(v.catalog_id,v.position_id) AND x.publication_order<=h.read_publication_order)
      AND trading.gas_owned_visible(h.catalog_id,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',h.source_context_id,h.as_of))
     OR step->>'expectedConsumptionRevision' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM trading.gas_owned_consumption_quantities v JOIN trading.gas_owned_claim_settlements original
      ON(original.catalog_id,original.consumption_id)=(v.catalog_id,v.consumption_id) WHERE(original.catalog_id,original.id,v.revision)=(h.catalog_id,sm.settlement_id,(step->>'expectedConsumptionRevision')::integer)
      AND v.revision=(SELECT max(x.revision) FROM trading.gas_owned_consumption_quantities x WHERE(x.catalog_id,x.consumption_id)=(v.catalog_id,v.consumption_id) AND x.publication_order<=h.read_publication_order)
      AND trading.gas_owned_visible(h.catalog_id,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',h.source_context_id,h.as_of))
     OR step->>'lotId' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM trading.gas_owned_position_quantities v JOIN trading.gas_owned_positions original
      ON(original.catalog_id,original.id)=(v.catalog_id,v.position_id) WHERE(v.catalog_id,v.position_id)=(h.catalog_id,(step->>'lotId')::uuid)
      AND v.revision=(SELECT max(x.revision) FROM trading.gas_owned_position_quantities x WHERE(x.catalog_id,x.position_id)=(v.catalog_id,v.position_id) AND x.publication_order<=h.read_publication_order)
      AND trading.gas_owned_visible(h.catalog_id,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',h.source_context_id,h.as_of)
      AND trading.gas_owned_visible(h.catalog_id,original.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',h.source_context_id,h.as_of))
    THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
   END IF;
   IF sm.changed THEN
    SELECT * INTO STRICT before_q FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id,v.revision)=(h.catalog_id,sm.settlement_id,sm.previous_revision);
    IF(q.previous_settlement_id,q.previous_settlement_revision,q.cumulative_quantity,q.price,q.exact_total,q.rounded_total,q.cash_amount,q.source_allocation,q.operation_id,q.actor_id,q.publication_order,q.receipt_revision,q.consumption_revision) IS DISTINCT FROM
     ((step_state->>'previousSettlementId')::uuid,(step_state->>'previousSettlementRevision')::integer,(step_state->>'cumulativeQuantity')::numeric,
      (step_state->>'price')::numeric,(step_state->>'exactTotal')::numeric,(step_state->>'roundedTotal')::numeric,(step_state->>'cashAmount')::numeric,
      step->>'sourceAllocation',h.operation_id,h.actor_id,h.publication_order,(step_state->>'receiptRevision')::integer,(step_state->>'consumptionRevision')::integer) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
    delta=q.cash_amount-before_q.cash_amount;
    SELECT f.* INTO cash FROM trading.gas_operator_cash_members m JOIN trading.gas_owned_fees f ON(f.catalog_id,f.id)=(m.catalog_id,m.cash_id)
     WHERE(m.catalog_id,m.operation_id,m.settlement_id)=(h.catalog_id,h.operation_id,sm.settlement_id);
    IF q.source_observation_id IS NULL AND cash.id IS NOT NULL
     OR q.source_observation_id IS NOT NULL AND(delta=0) IS DISTINCT FROM(cash.id IS NULL) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
    IF cash.id IS NOT NULL THEN
     SELECT * INTO STRICT native FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.id)=(h.catalog_id,sm.settlement_id);
     IF(cash.position_id,cash.loan_id,cash.amount,cash.due_at,cash.effective_at,cash.actor_id,cash.publication_order,
      cash.reference_catalog_id,cash.reference_revision_id,cash.currency_code) IS DISTINCT FROM
      (sm.claim_id,NULL::uuid,delta,h.adjustment_due_at,native.effective_at,h.actor_id,h.publication_order,owner.reference_catalog_id,owner.reference_revision_id,owner.currency_code)
     THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
    END IF;
   ELSIF EXISTS(SELECT 1 FROM trading.gas_operator_cash_members m WHERE(m.catalog_id,m.operation_id,m.settlement_id)=(h.catalog_id,h.operation_id,sm.settlement_id))
   THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  END LOOP;
 END LOOP;
 FOR step_state IN SELECT value FROM jsonb_array_elements(plan->'consumptions') LOOP
  step=step_state->'selection';
  SELECT * INTO STRICT um FROM trading.gas_operator_consumption_members m WHERE(m.catalog_id,m.operation_id,m.consumption_id)=
   (h.catalog_id,h.operation_id,(step->>'consumptionId')::uuid);
  expected_version=CASE WHEN all_ack THEN(step_state->>'previousRevision')::integer ELSE(step_state->>'currentRevision')::integer END;
  IF(um.previous_revision,um.acknowledged_revision,um.current_revision,um.changed) IS DISTINCT FROM
   ((step_state->>'previousRevision')::integer,CASE WHEN all_ack THEN(step_state->>'acknowledgedRevision')::integer ELSE expected_version END,
    expected_version,expected_version<>(step_state->>'previousRevision')::integer)
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  SELECT * INTO STRICT use_head FROM trading.gas_owned_consumption_quantities v WHERE(v.catalog_id,v.consumption_id,v.revision)=
   (h.catalog_id,um.consumption_id,um.acknowledged_revision);
  IF(use_head.quantity,use_head.evidence_id,use_head.lot_id,use_head.reservation_id,use_head.retracted) IS DISTINCT FROM
   (trading.gas_owned_quantity(step->>'quantity'),(step->>'evidenceId')::uuid,(step->>'lotId')::uuid,(step->>'reservationId')::uuid,(step->>'retracted')::boolean)
   OR use_head.publication_order>coalesce(h.publication_order,h.read_publication_order)
   OR um.changed AND(use_head.previous_revision,use_head.actor_id,use_head.publication_order) IS DISTINCT FROM(um.previous_revision,h.actor_id,h.publication_order)
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 END LOOP;
 IF h.changed THEN
  PERFORM trading.require_gas_operator_uses(h.catalog_id,body,h.source_context_id,h.as_of,h.read_publication_order);
  IF(SELECT count(*) FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.publication_order)=(h.catalog_id,h.publication_order))<>
    (SELECT count(*) FROM trading.gas_operator_settlement_members m WHERE(m.catalog_id,m.operation_id,m.changed)=(h.catalog_id,h.operation_id,true))
   OR(SELECT count(*) FROM trading.gas_owned_fees f WHERE(f.catalog_id,f.publication_order)=(h.catalog_id,h.publication_order))<>
    (SELECT count(*) FROM trading.gas_operator_cash_members m WHERE(m.catalog_id,m.operation_id)=(h.catalog_id,h.operation_id))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_position_quantities v WHERE(v.catalog_id,v.publication_order)=(h.catalog_id,h.publication_order)
    AND NOT trading.gas_operator_position_proof(v.catalog_id,v.position_id,v.revision))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_consumption_quantities v WHERE(v.catalog_id,v.publication_order)=(h.catalog_id,h.publication_order)
    AND NOT trading.gas_operator_consumption_proof(v.catalog_id,v.consumption_id,v.revision))
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  IF false
   OR EXISTS(SELECT 1 FROM trading.gas_instruments p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_trade_revisions p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_quantity_series p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_quantity_revisions p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_cash_determinations p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_service_accounts p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_service_versions p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_nomination_requests p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_balance_statements p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_imbalance_agreements p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_operation_responses p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_nomination_applications p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_imbalance_applications p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_cash_payments p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_accounts p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_evidence p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_positions p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_reservations p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_releases p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_consumptions p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_claim_settlements p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_fee_payments p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_action_bindings p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_mark_bindings p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_projection_profiles p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_futures_delivery_terms p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_futures_delivery_performances p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_futures_delivery_principal_runs p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_futures_delivery_cash p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_futures_delivery_payments p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_futures_performance_quantities p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_futures_quantity_batches p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_quantity_corrections p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_quantity_bundles p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_owned_loan_quantities p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_loan_quantity_corrections p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM settlement_data.futures_margin_policies p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM settlement_data.futures_margin_policy_occurrences p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM settlement_data.futures_margin_adoptions p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM settlement_data.futures_delivery_profiles p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM settlement_data.futures_margin_runs p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM settlement_data.futures_margin_determinations p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM settlement_data.cash_payment_revisions p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_loan_fee_terms p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
   OR EXISTS(SELECT 1 FROM trading.gas_loan_fee_changes p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  facts=trading.gas_operator_allocation_facts(h.catalog_id,h.operation_id,body);
  IF jsonb_array_length(facts)<>(SELECT count(*) FROM trading.gas_operator_source_members m WHERE(m.catalog_id,m.operation_id)=(h.catalog_id,h.operation_id))
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  FOR fact IN SELECT value FROM jsonb_array_elements(facts) LOOP
   IF NOT EXISTS(SELECT 1 FROM trading.gas_operator_source_members m WHERE(m.catalog_id,m.operation_id,m.account_id,m.source_evidence_id,m.previous_evidence_id,m.source_allocation)=
    (h.catalog_id,h.operation_id,(fact->>'accountId')::uuid,(fact->>'sourceEvidenceId')::uuid,(fact->>'oldEvidenceId')::uuid,fact->>'sourceAllocation'))
   THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
  END LOOP;
 END IF;
 IF c.outcome IS DISTINCT FROM trading.gas_operator_correction_outcome(h.catalog_id,h.operation_id,body) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 PERFORM security.require_gas_owned_commit(h.catalog_id,c.authority_until,false,false);
 RETURN NULL;
END$$;

CREATE FUNCTION trading.guard_gas_operator_member() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE h trading.gas_operator_quantity_corrections;actor uuid;BEGIN
 IF TG_TABLE_NAME='gas_operator_quantity_corrections' THEN
  h=NEW;
  IF h.read_publication_order IS DISTINCT FROM(SELECT max(publication_row.publication_order)-(CASE WHEN h.changed THEN 1 ELSE 0 END)
   FROM trading.publications publication_row WHERE publication_row.catalog_id=h.catalog_id)
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 ELSE
  SELECT * INTO STRICT h FROM trading.gas_operator_quantity_corrections x WHERE(x.catalog_id,x.operation_id)=(NEW.catalog_id,NEW.operation_id);
  IF EXISTS(SELECT 1 FROM trading.gas_owned_commands c WHERE(c.catalog_id,c.request_id)=(h.catalog_id,h.operation_id))
   OR NOT h.changed AND TG_TABLE_NAME IN('gas_operator_source_members','gas_operator_cash_members')
  THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 END IF;
 SELECT actor_id INTO STRICT actor FROM security.request_contexts r WHERE r.backend_pid=pg_backend_pid()
  AND r.transaction_id=pg_current_xact_id_if_assigned() AND r.runtime_login=session_user;
 IF actor<>h.actor_id OR h.changed AND NOT EXISTS(SELECT 1 FROM trading.publications p
  WHERE(p.catalog_id,p.publication_order,p.publication_xid)=(h.catalog_id,h.publication_order,pg_current_xact_id())) THEN RAISE EXCEPTION 'gas_operator_quantity_seal';END IF;
 RETURN NEW;
END$$;

CREATE FUNCTION trading.gas_operator_source_result(catalog uuid,context uuid,as_of timestamptz,result jsonb) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE item jsonb;rows jsonb='[]';head trading.gas_operator_settlement_quantities;native trading.gas_owned_claim_settlements;known timestamptz;BEGIN
 IF NOT result?'settlements' THEN RETURN result;END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(result->'settlements') LOOP
  SELECT * INTO STRICT native FROM trading.gas_owned_claim_settlements s WHERE(s.catalog_id,s.id)=(catalog,(item->>'id')::uuid);
  SELECT * INTO STRICT head FROM trading.gas_operator_settlement_quantities q WHERE(q.catalog_id,q.settlement_id)=(catalog,native.id)
   AND trading.gas_owned_visible(catalog,q.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of) ORDER BY revision DESC LIMIT 1;
  IF(head.quantity,head.evidence_id,head.source_observation_id) IS DISTINCT FROM
    ((item->>'quantity')::numeric,(item->>'evidence_id')::uuid,(item->>'source_observation_id')::uuid)
   OR(item->>'publication_order')::integer<>native.publication_order THEN RAISE EXCEPTION 'gas_operator_quantity_source';END IF;
  SELECT k.known_from INTO STRICT known FROM trading.knowledge_receipts k WHERE(k.catalog_id,k.publication_order)=(catalog,head.publication_order);
  rows=rows||jsonb_build_array(item||jsonb_build_object('financial_revision',head.revision,'retracted',head.quantity=0,
   'financial_publication_order',head.publication_order,'original_publication_order',native.publication_order,'known_at',known,
   'original_quantity',native.quantity,'original_evidence_id',native.evidence_id,'original_source_observation_id',native.source_observation_id,
   'cumulative_quantity',head.cumulative_quantity,'price',head.price,'exact_total',head.exact_total,'rounded_total',head.rounded_total,'cash_amount',head.cash_amount,
   'previous_settlement_id',head.previous_settlement_id,'previous_settlement_revision',head.previous_settlement_revision));
 END LOOP;
 result=jsonb_set(result,ARRAY['settlements'],rows)||jsonb_build_object('operatorQuantityStateProfile','recorded_operator_settlement_quantities_v1');
 IF octet_length(convert_to(result::text,'UTF8'))>16777216 THEN RAISE EXCEPTION 'gas_owned_scope';END IF;RETURN result;
END$$;
ALTER FUNCTION trading.gas_operator_source_result(uuid,uuid,timestamptz,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION trading.gas_operator_source_result(uuid,uuid,timestamptz,jsonb) FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;

CREATE FUNCTION trading.gas_operator_settlements_at(catalog uuid,context uuid,as_of timestamptz)
 RETURNS SETOF trading.gas_owned_claim_settlements LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT s.catalog_id,s.id,s.position_id,q.quantity,s.receipt_lot_id,s.consumption_id,s.cash_id,q.evidence_id,q.source_observation_id,
  s.actor_id,s.publication_order,s.effective_at FROM trading.gas_owned_claim_settlements s
 JOIN LATERAL(SELECT v.* FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id)=(s.catalog_id,s.id)
  AND trading.gas_owned_visible($1,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$2,$3) ORDER BY v.revision DESC LIMIT 1)q ON true
 WHERE s.catalog_id=$1
$$;

-- One fixed row projection serves streamed size admission and the final result.
CREATE FUNCTION trading.gas_operator_financial_settlements_at(catalog uuid,context uuid,as_of timestamptz)
 RETURNS SETOF trading.gas_owned_claim_settlements LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT(jsonb_populate_record(native,jsonb_build_object('publication_order',head.publication_order))).*
 FROM trading.gas_operator_settlements_at($1,$2,$3)native JOIN LATERAL(
  SELECT q.publication_order FROM trading.gas_operator_settlement_quantities q WHERE(q.catalog_id,q.settlement_id)=(native.catalog_id,native.id)
   AND trading.gas_owned_visible($1,q.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$2,$3) ORDER BY q.revision DESC LIMIT 1)head ON true
$$;

-- Future-effective accepted facts stay known, in original settlement order.
CREATE FUNCTION trading.gas_operator_reconciliation_rows(catalog uuid,claim uuid,context uuid,as_of timestamptz,statistics boolean) RETURNS jsonb
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE rows_sql constant text=$rows$
 WITH chosen AS MATERIALIZED(
  SELECT p.*,q.revision financial_revision,origin.quantity original_quantity,origin.publication_order original_publication_order,k.known_from
  FROM trading.gas_owned_positions_at($1,$3,$4)p
  JOIN trading.gas_owned_positions origin ON(origin.catalog_id,origin.id)=(p.catalog_id,p.id)
  JOIN trading.gas_owned_position_quantities q ON(q.catalog_id,q.position_id,q.publication_order)=(p.catalog_id,p.id,p.publication_order)
  JOIN trading.knowledge_receipts k ON(k.catalog_id,k.publication_order)=(p.catalog_id,p.publication_order)
  WHERE(p.catalog_id,p.id,p.kind)=($1,$2,'operator_claim')),
 settlements AS MATERIALIZED(SELECT s.*,q.revision financial_revision,q.cumulative_quantity,q.price,q.exact_total,q.rounded_total,q.cash_amount,
  q.previous_settlement_id,q.previous_settlement_revision,q.receipt_revision,q.consumption_revision,k.known_from,
  original.quantity original_quantity,original.evidence_id original_evidence_id,original.source_observation_id original_source_observation_id
  FROM trading.gas_operator_settlements_at($1,$3,$4)s
  JOIN trading.gas_owned_claim_settlements original ON(original.catalog_id,original.id)=(s.catalog_id,s.id)
  JOIN LATERAL(SELECT v.* FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id)=(s.catalog_id,s.id)
   AND trading.gas_owned_visible($1,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4) ORDER BY v.revision DESC LIMIT 1)q ON true
  JOIN chosen p ON(p.catalog_id,p.id)=(s.catalog_id,s.position_id)
  JOIN trading.knowledge_receipts k ON(k.catalog_id,k.publication_order)=(q.catalog_id,q.publication_order)
  WHERE trading.gas_owned_visible($1,s.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4)),
 lot_ids AS(SELECT receipt_lot_id id FROM settlements WHERE receipt_lot_id IS NOT NULL
  UNION SELECT c.lot_id FROM trading.gas_owned_consumptions_at($1,$3,$4)c WHERE c.id IN(SELECT consumption_id FROM settlements)
  UNION SELECT c.lot_id FROM trading.gas_owned_consumptions c WHERE c.catalog_id=$1 AND c.id IN(SELECT consumption_id FROM settlements)),
 uses AS MATERIALIZED(SELECT c.* FROM trading.gas_owned_consumptions_at($1,$3,$4)c
  WHERE c.lot_id IN(SELECT id FROM lot_ids) OR c.id IN(SELECT consumption_id FROM settlements)
   OR c.id IN(SELECT o.id FROM trading.gas_owned_consumptions o WHERE o.catalog_id=$1 AND o.lot_id IN(SELECT id FROM lot_ids))),
 positions AS MATERIALIZED(SELECT p.*,q.revision financial_revision,o.publication_order original_publication_order,k.known_from
  FROM trading.gas_owned_positions_at($1,$3,$4)p
  JOIN trading.gas_owned_positions o ON(o.catalog_id,o.id)=(p.catalog_id,p.id)
  JOIN trading.gas_owned_position_quantities q ON(q.catalog_id,q.position_id,q.publication_order)=(p.catalog_id,p.id,p.publication_order)
  JOIN trading.knowledge_receipts k ON(k.catalog_id,k.publication_order)=(p.catalog_id,p.publication_order)
  WHERE p.id IN(SELECT id FROM lot_ids UNION SELECT lot_id FROM uses)),
 reservations AS MATERIALIZED(SELECT r.* FROM trading.gas_owned_reservations r WHERE r.catalog_id=$1 AND r.lot_id IN(SELECT id FROM positions)
  AND trading.gas_owned_visible($1,r.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4)),
 cash AS MATERIALIZED(SELECT f.* FROM trading.gas_owned_fees f JOIN chosen p ON(p.catalog_id,p.id)=(f.catalog_id,f.position_id)
  WHERE trading.gas_owned_visible($1,f.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4)),
 required_evidence AS(SELECT evidence_id id FROM chosen UNION SELECT evidence_id FROM settlements UNION SELECT evidence_id FROM positions
  UNION SELECT evidence_id FROM uses UNION SELECT o.evidence_id FROM trading.gas_owned_positions o WHERE o.catalog_id=$1 AND o.id IN(SELECT id FROM chosen UNION SELECT id FROM positions)
  UNION SELECT o.evidence_id FROM trading.gas_owned_consumptions o WHERE o.catalog_id=$1 AND o.id IN(SELECT id FROM uses)),
 keys AS(SELECT DISTINCT e.account_id,e.source_key FROM trading.gas_owned_evidence e WHERE e.catalog_id=$1 AND e.id IN(SELECT id FROM required_evidence)),
 allocations AS MATERIALIZED(
  SELECT 'position' allocation_kind,p.id,p.account_id,p.kind,p.quantity,p.evidence_id,q.revision financial_revision,NULL::uuid claim_id
  FROM trading.gas_owned_positions_at($1,$3,$4)p JOIN trading.gas_owned_evidence e ON(e.catalog_id,e.id)=(p.catalog_id,p.evidence_id)
  JOIN keys s ON(s.account_id,s.source_key)=(e.account_id,e.source_key)
  JOIN trading.gas_owned_position_quantities q ON(q.catalog_id,q.position_id,q.publication_order)=(p.catalog_id,p.id,p.publication_order)
  UNION ALL SELECT 'consumption',c.id,p.account_id,c.kind,c.quantity,c.evidence_id,q.revision,NULL::uuid
  FROM trading.gas_owned_consumptions_at($1,$3,$4)c JOIN trading.gas_owned_evidence e ON(e.catalog_id,e.id)=(c.catalog_id,c.evidence_id)
  JOIN keys s ON(s.account_id,s.source_key)=(e.account_id,e.source_key)
  JOIN trading.gas_owned_positions p ON(p.catalog_id,p.id)=(c.catalog_id,c.lot_id)
  JOIN trading.gas_owned_consumption_quantities q ON(q.catalog_id,q.consumption_id,q.publication_order)=(c.catalog_id,c.id,c.publication_order)
  UNION ALL SELECT 'cashout_settlement',s.id,p.account_id,p.settlement_mode,s.quantity,s.evidence_id,q.revision,p.id
  FROM trading.gas_operator_settlements_at($1,$3,$4)s JOIN trading.gas_owned_positions p ON(p.catalog_id,p.id)=(s.catalog_id,s.position_id)
  JOIN LATERAL(SELECT v.revision FROM trading.gas_operator_settlement_quantities v WHERE(v.catalog_id,v.settlement_id)=(s.catalog_id,s.id)
   AND trading.gas_owned_visible($1,v.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4) ORDER BY v.revision DESC LIMIT 1)q ON true
  JOIN trading.gas_owned_evidence e ON(e.catalog_id,e.id)=(s.catalog_id,s.evidence_id)
  JOIN keys k ON(k.account_id,k.source_key)=(e.account_id,e.source_key)
  WHERE(s.catalog_id,p.kind,p.settlement_mode)=($1,'operator_claim','cashout_final_price_v1')
   AND trading.gas_owned_visible($1,s.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4)
   AND trading.gas_owned_visible($1,p.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4)),
 evidence_ids AS(SELECT id FROM required_evidence UNION SELECT evidence_id FROM allocations),
 heads AS(SELECT h.id FROM keys s CROSS JOIN LATERAL(SELECT e.id FROM trading.gas_owned_evidence e
  WHERE(e.catalog_id,e.account_id,e.source_key)=($1,s.account_id,s.source_key)
   AND trading.gas_owned_visible($1,e.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4) ORDER BY e.revision DESC LIMIT 1)h),
 points AS(SELECT DISTINCT o.definition_revision_id,o.series_id,o.source_code,o.role,o.observed_at
  FROM market_data.observations o WHERE o.catalog_id=$1 AND o.id IN(SELECT source_observation_id FROM settlements UNION SELECT original_source_observation_id FROM settlements)),
 observed AS MATERIALIZED(SELECT o.*,k.known_from FROM market_data.observations o JOIN points p
  ON(p.definition_revision_id,p.series_id,p.source_code,p.role,p.observed_at)=(o.definition_revision_id,o.series_id,o.source_code,o.role,o.observed_at)
  JOIN market_data.knowledge_events e ON(e.catalog_id,e.observation_id)=(o.catalog_id,o.id)
  JOIN market_data.market_knowledge_receipts k ON(k.catalog_id,k.event_order,k.publication_xid)=(e.catalog_id,e.event_order,e.publication_xid)
  JOIN market_data.market_contexts m ON m.catalog_id=$1 AND m.context_id=$3
  JOIN market_data.temporal_contexts t ON(t.catalog_id,t.id)=($1,$3)
  WHERE o.catalog_id=$1 AND e.event_order<=m.known_through AND k.known_from<=t.known_at)
 SELECT 'claim' kind,to_jsonb(p)||jsonb_build_object('quantity',trim_scale(p.quantity)::text,'evidenceId',p.evidence_id,'originalQuantity',trim_scale(p.original_quantity)::text,
  'expectedRevision',p.financial_revision,'originalPublicationOrder',p.original_publication_order,'knownAt',p.known_from,
  'remainingQuantity',trim_scale(CASE WHEN p.effective_at>$4 THEN 0 ELSE p.quantity-sign(p.quantity)*coalesce((
   SELECT sum(s.quantity) FROM settlements s WHERE s.effective_at<=$4),0) END)::text) value FROM chosen p
 UNION ALL SELECT 'cashoutTerms',to_jsonb(t) FROM trading.gas_owned_cashout_terms t JOIN chosen p ON(p.catalog_id,p.id)=(t.catalog_id,t.position_id)
 UNION ALL SELECT 'settlements',to_jsonb(s)||jsonb_build_object('quantity',trim_scale(s.quantity)::text,'evidenceId',s.evidence_id,'expectedRevision',s.financial_revision,
  'cashAmount',trim_scale(s.cash_amount)::text,'cumulativeQuantity',trim_scale(s.cumulative_quantity)::text,'price',trim_scale(s.price)::text,
  'exactTotal',trim_scale(s.exact_total)::text,'roundedTotal',trim_scale(s.rounded_total)::text,
  'previousSettlementId',s.previous_settlement_id,'previousSettlementRevision',s.previous_settlement_revision,
  'receiptRevision',s.receipt_revision,'consumptionRevision',s.consumption_revision,
  'originalQuantity',trim_scale(s.original_quantity)::text,'originalEvidenceId',s.original_evidence_id,'originalSourceObservationId',s.original_source_observation_id,
  'originalPublicationOrder',s.publication_order,'effectiveAt',s.effective_at,'knownAt',s.known_from,
  'receiptLotId',s.receipt_lot_id,'consumptionId',s.consumption_id,'cashId',s.cash_id,'sourceObservationId',s.source_observation_id) FROM settlements s
 UNION ALL SELECT 'positions',to_jsonb(p)||jsonb_build_object('quantity',trim_scale(p.quantity)::text,'evidenceId',p.evidence_id,'expectedRevision',p.financial_revision,
  'originalPublicationOrder',p.original_publication_order,'knownAt',p.known_from) FROM positions p
 UNION ALL SELECT 'consumptions',to_jsonb(c)||jsonb_build_object('quantity',trim_scale(c.quantity)::text,'evidenceId',c.evidence_id,'expectedRevision',q.revision,
  'lotId',c.lot_id,'effectiveAt',c.effective_at,'originalPublicationOrder',o.publication_order,'knownAt',k.known_from,
  'editable',c.kind IN('delivery','loss') AND c.effective_at<=$4
   AND NOT EXISTS(SELECT 1 FROM trading.gas_owned_claim_settlements settled WHERE(settled.catalog_id,settled.consumption_id)=($1,c.id)
    AND trading.gas_owned_visible($1,settled.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4))
   AND NOT EXISTS(SELECT 1 FROM trading.gas_futures_performance_quantity_supplies supplied
    JOIN trading.gas_futures_performance_quantities performance ON(performance.catalog_id,performance.performance_id,performance.revision)=
     (supplied.catalog_id,supplied.performance_id,supplied.performance_revision)
    WHERE(supplied.catalog_id,supplied.consumption_id)=($1,c.id)
     AND trading.gas_owned_visible($1,performance.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4))) FROM uses c
  JOIN trading.gas_owned_consumptions o ON(o.catalog_id,o.id)=(c.catalog_id,c.id)
  JOIN trading.gas_owned_consumption_quantities q ON(q.catalog_id,q.consumption_id,q.publication_order)=(c.catalog_id,c.id,c.publication_order)
  JOIN trading.knowledge_receipts k ON(k.catalog_id,k.publication_order)=(c.catalog_id,c.publication_order)
 UNION ALL SELECT 'reservations',to_jsonb(r)||jsonb_build_object('quantity',trim_scale(r.quantity)::text) FROM reservations r
 UNION ALL SELECT 'releases',to_jsonb(r) FROM trading.gas_owned_releases r WHERE r.catalog_id=$1 AND r.reservation_id IN(SELECT id FROM reservations)
  AND trading.gas_owned_visible($1,r.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4)
 UNION ALL SELECT 'cash',to_jsonb(f)||jsonb_build_object('amount',trim_scale(f.amount)::text) FROM cash f
 UNION ALL SELECT 'payments',to_jsonb(p)||jsonb_build_object('amount',trim_scale(p.amount)::text) FROM trading.gas_owned_fee_payments p
  WHERE p.catalog_id=$1 AND p.fee_id IN(SELECT id FROM cash)
   AND trading.gas_owned_visible($1,p.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4)
 UNION ALL SELECT 'allocations',to_jsonb(a)||jsonb_build_object('quantity',trim_scale(a.quantity)::text) FROM allocations a
 UNION ALL SELECT 'evidence',to_jsonb(e)||jsonb_build_object('quantity',trim_scale(e.quantity)::text,'knownAt',k.known_from,'capturedHead',e.id IN(SELECT id FROM heads))
  FROM trading.gas_owned_evidence e JOIN trading.knowledge_receipts k ON(k.catalog_id,k.publication_order)=(e.catalog_id,e.publication_order)
  WHERE e.catalog_id=$1 AND(e.id IN(SELECT id FROM evidence_ids) OR e.id IN(SELECT id FROM heads))
   AND trading.gas_owned_visible($1,e.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',$3,$4)
 UNION ALL SELECT 'observations',to_jsonb(o)||jsonb_build_object('value',trim_scale(o.value)::text,'knownAt',o.known_from,
  'capturedHead',NOT EXISTS(SELECT 1 FROM observed n WHERE n.corrects_id=o.id)) FROM observed o
  WHERE o.id IN(SELECT source_observation_id FROM settlements UNION SELECT original_source_observation_id FROM settlements) OR NOT EXISTS(SELECT 1 FROM observed n WHERE n.corrects_id=o.id)
 UNION ALL SELECT 'accounts',to_jsonb(a) FROM trading.gas_owned_accounts a WHERE a.catalog_id=$1
  AND a.id IN(SELECT account_id FROM chosen UNION SELECT account_id FROM positions UNION SELECT account_id FROM allocations)
$rows$;result jsonb;BEGIN
 IF statistics IS NULL THEN RAISE EXCEPTION 'gas_operator_quantity_input';END IF;
 IF statistics THEN
  EXECUTE 'WITH rows AS('||rows_sql||'),sizes AS(SELECT kind,count(*) n,sum(octet_length(convert_to(value::text,''UTF8''))) bytes FROM rows GROUP BY kind)
   SELECT jsonb_build_object(''counts'',coalesce(jsonb_object_agg(kind,n),''{}''),''bytes'',coalesce(sum(bytes),0),''count'',coalesce(sum(n),0)) FROM sizes'
   INTO result USING catalog,claim,context,as_of;
 ELSE
  EXECUTE 'SELECT jsonb_build_object(''claim'',(jsonb_agg(value) FILTER(WHERE kind=''claim''))->0,
   ''cashoutTerms'',(jsonb_agg(value) FILTER(WHERE kind=''cashoutTerms''))->0,
   ''settlements'',coalesce(jsonb_agg(value ORDER BY (value->>''originalPublicationOrder'')::integer) FILTER(WHERE kind=''settlements''),''[]''),
   ''positions'',coalesce(jsonb_agg(value ORDER BY value->>''id'') FILTER(WHERE kind=''positions''),''[]''),
   ''consumptions'',coalesce(jsonb_agg(value ORDER BY value->>''id'') FILTER(WHERE kind=''consumptions''),''[]''),
   ''reservations'',coalesce(jsonb_agg(value ORDER BY value->>''id'') FILTER(WHERE kind=''reservations''),''[]''),
   ''releases'',coalesce(jsonb_agg(value ORDER BY value->>''reservation_id'') FILTER(WHERE kind=''releases''),''[]''),
   ''cash'',coalesce(jsonb_agg(value ORDER BY value->>''id'') FILTER(WHERE kind=''cash''),''[]''),
   ''payments'',coalesce(jsonb_agg(value ORDER BY value->>''fee_id'',value->>''business_key'',(value->>''revision'')::integer) FILTER(WHERE kind=''payments''),''[]''),
   ''allocations'',coalesce(jsonb_agg(value ORDER BY value->>''allocation_kind'',value->>''id'') FILTER(WHERE kind=''allocations''),''[]''),
   ''evidence'',coalesce(jsonb_agg(value ORDER BY value->>''account_id'',value->>''source_key'',(value->>''revision'')::integer) FILTER(WHERE kind=''evidence''),''[]''),
   ''observations'',coalesce(jsonb_agg(value ORDER BY value->>''id'') FILTER(WHERE kind=''observations''),''[]''),
   ''accounts'',coalesce(jsonb_agg(value ORDER BY value->>''id'') FILTER(WHERE kind=''accounts''),''[]'')) FROM('||rows_sql||')rows'
   INTO result USING catalog,claim,context,as_of;
 END IF;RETURN result;
END$$;

CREATE FUNCTION security.read_gas_operator_quantity_reconciliation(catalog uuid,claim uuid,context uuid,as_of timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE until_at timestamptz;selected trading.gas_owned_positions;owner trading.gas_owned_accounts;stats jsonb;entry record;account jsonb;result jsonb;BEGIN
 until_at=security.gas_futures_delivery_discovery_authority(catalog);
 PERFORM security.require_gas_owned_read(catalog,context,as_of,until_at);
 SELECT * INTO STRICT selected FROM trading.gas_owned_positions_at(catalog,context,as_of)p
  WHERE(p.catalog_id,p.id,p.kind)=(read_gas_operator_quantity_reconciliation.catalog,read_gas_operator_quantity_reconciliation.claim,'operator_claim');
 SELECT * INTO STRICT owner FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(read_gas_operator_quantity_reconciliation.catalog,selected.account_id)
  AND trading.gas_owned_visible(a.catalog_id,a.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of);
 IF security.reference_version_visible(owner.reference_catalog_id,owner.reference_revision_id) IS NOT TRUE
  OR security.market_fact_visible(catalog,owner.definition_revision_id,NULL) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 PERFORM settlement_data.require_futures_margin_source(catalog,context,as_of,owner.definition_revision_id);
 stats=trading.gas_operator_reconciliation_rows(catalog,claim,context,as_of,true);
 FOR entry IN SELECT key,value FROM jsonb_each(stats->'counts') LOOP
  IF entry.key NOT IN('claim','cashoutTerms','accounts','settlements','positions','consumptions','reservations','releases','cash','payments','allocations','evidence','observations')
   OR(entry.value#>>'{}')::bigint NOT BETWEEN 0 AND 16384 THEN RAISE EXCEPTION 'gas_owned_scope';END IF;
 END LOOP;
 IF coalesce((stats#>>'{counts,claim}')::integer,0)<>1
  OR coalesce((stats#>>'{counts,cashoutTerms}')::integer,0)<>(CASE WHEN selected.settlement_mode='cashout_final_price_v1' THEN 1 ELSE 0 END)
  OR(stats->>'bytes')::bigint+4*(stats->>'count')::bigint+4096>16777216
 THEN RAISE EXCEPTION 'gas_owned_scope';END IF;
 result=jsonb_build_object('implementation','gas_operator_quantity_reconciliation_source_v1','scope','gas_operator_reconciliation_dependency_facts_v1',
  'claimId',claim,'accountId',owner.id,'contextId',context,'asOf',as_of,'authorityUntil',until_at)
  ||trading.gas_operator_reconciliation_rows(catalog,claim,context,as_of,false);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements((result->'positions')||(result->'consumptions')||(result->'settlements')||jsonb_build_array(result->'claim')) s
  WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'evidence') e WHERE e->>'id'=s->>'evidenceId'))
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(result->'settlements') s WHERE s->>'sourceObservationId' IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(result->'observations') o WHERE o->>'id'=s->>'sourceObservationId'))
 THEN RAISE EXCEPTION 'gas_operator_quantity_source';END IF;
 FOR account IN SELECT value FROM jsonb_array_elements(result->'accounts') LOOP
  IF security.reference_version_visible((account->>'reference_catalog_id')::uuid,(account->>'reference_revision_id')::uuid) IS NOT TRUE
   OR security.market_fact_visible(catalog,(account->>'definition_revision_id')::uuid,NULL) IS NOT TRUE
   OR NOT trading.gas_owned_visible(catalog,(account->>'publication_order')::integer,TIMESTAMPTZ '0001-01-01 00:00:00+00',context,as_of)
  THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 END LOOP;
 IF octet_length(convert_to(result::text,'UTF8'))>16777216 THEN RAISE EXCEPTION 'gas_owned_scope';END IF;
 PERFORM security.require_gas_owned_read(catalog,context,as_of,until_at);
 IF until_at IS NULL OR NOT isfinite(until_at) OR clock_timestamp()>=until_at THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 RETURN result;
EXCEPTION WHEN NO_DATA_FOUND THEN
 PERFORM security.require_gas_owned_read(catalog,context,as_of,until_at);
 IF until_at IS NULL OR NOT isfinite(until_at) OR clock_timestamp()>=until_at THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 RAISE EXCEPTION 'gas_operator_quantity_source';
END$$;

ALTER FUNCTION trading.gas_operator_reconciliation_rows(uuid,uuid,uuid,timestamptz,boolean) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION trading.gas_operator_reconciliation_rows(uuid,uuid,uuid,timestamptz,boolean) FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;
ALTER FUNCTION security.read_gas_operator_quantity_reconciliation(uuid,uuid,uuid,timestamptz) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.read_gas_operator_quantity_reconciliation(uuid,uuid,uuid,timestamptz) FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;
GRANT EXECUTE ON FUNCTION security.read_gas_operator_quantity_reconciliation(uuid,uuid,uuid,timestamptz) TO openetrm_runtime;

DO $$DECLARE name text;f regprocedure;BEGIN
 FOREACH name IN ARRAY ARRAY['gas_operator_quantity_corrections','gas_operator_claim_members','gas_operator_settlement_members','gas_operator_consumption_members','gas_operator_cash_members'] LOOP
  EXECUTE format('CREATE TRIGGER native_member BEFORE INSERT ON trading.%I FOR EACH ROW EXECUTE FUNCTION trading.guard_gas_operator_member()',name);
 END LOOP;
 ALTER TABLE trading.gas_operator_source_members OWNER TO openetrm_security_owner;
 ALTER TABLE trading.gas_operator_source_members ENABLE ROW LEVEL SECURITY;ALTER TABLE trading.gas_operator_source_members FORCE ROW LEVEL SECURITY;
 CREATE POLICY owner_all ON trading.gas_operator_source_members TO openetrm_security_owner USING(true) WITH CHECK(true);
 REVOKE ALL ON trading.gas_operator_source_members FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;
 CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.gas_operator_source_members FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
 CREATE TRIGGER native_member BEFORE INSERT ON trading.gas_operator_source_members FOR EACH ROW EXECUTE FUNCTION trading.guard_gas_operator_member();
 FOREACH f IN ARRAY ARRAY['trading.gas_operator_allocations_through(uuid,integer)'::regprocedure,'trading.gas_operator_position_proof(uuid,uuid,integer)'::regprocedure,'trading.gas_operator_consumption_proof(uuid,uuid,integer)'::regprocedure,'trading.gas_operator_point_price(uuid,uuid,uuid)'::regprocedure,'trading.gas_operator_original_cash(uuid,uuid,numeric)'::regprocedure,'trading.capture_operator_settlement_origin(trading.gas_owned_commands)'::regprocedure,'trading.seed_operator_settlement_origin()'::regprocedure,'trading.gas_operator_quantity_terms(jsonb)'::regprocedure,'trading.gas_operator_quantity_fact(jsonb)'::regprocedure,'trading.gas_operator_settlements_through(uuid,integer)'::regprocedure,'trading.gas_operator_claim_snapshot(uuid,jsonb,integer)'::regprocedure,'trading.gas_operator_settlement_snapshot(uuid,jsonb,uuid,integer,integer)'::regprocedure,'trading.gas_operator_consumption_snapshot(uuid,jsonb,integer)'::regprocedure,'trading.require_gas_operator_use_references(uuid,jsonb,timestamptz)'::regprocedure,'trading.require_gas_operator_references(uuid,uuid,jsonb,timestamptz)'::regprocedure,'trading.gas_operator_quantity_plan(uuid,jsonb,integer)'::regprocedure,'trading.require_gas_operator_uses(uuid,jsonb,uuid,timestamptz,integer)'::regprocedure,'trading.require_gas_operator_amendment(uuid,uuid,jsonb,uuid,timestamptz,uuid,integer)'::regprocedure,'trading.gas_operator_allocation_facts(uuid,uuid,jsonb)'::regprocedure,'trading.gas_operator_correction_outcome(uuid,uuid,jsonb)'::regprocedure,'security.reconcile_gas_operator_quantities(uuid,uuid,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)'::regprocedure,'trading.check_gas_operator_settlement_origin()'::regprocedure,'trading.check_gas_operator_settlement_quantity()'::regprocedure,'trading.check_gas_operator_quantity_correction()'::regprocedure,'trading.guard_gas_operator_member()'::regprocedure,'trading.gas_operator_financial_settlements_at(uuid,uuid,timestamptz)'::regprocedure,'trading.gas_operator_settlements_at(uuid,uuid,timestamptz)'::regprocedure] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,openetrm_runtime,openetrm_risk_worker',f);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION security.reconcile_gas_operator_quantities(uuid,uuid,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean) TO openetrm_runtime;
CREATE CONSTRAINT TRIGGER sealed_operator_origin AFTER INSERT ON trading.gas_owned_claim_settlements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trading.check_gas_operator_settlement_origin();
CREATE CONSTRAINT TRIGGER sealed_operator_quantity AFTER INSERT ON trading.gas_operator_settlement_quantities DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trading.check_gas_operator_settlement_quantity();
CREATE CONSTRAINT TRIGGER sealed_operator_correction AFTER INSERT ON trading.gas_operator_quantity_corrections DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trading.check_gas_operator_quantity_correction();
CREATE CONSTRAINT TRIGGER sealed_operator_correction AFTER INSERT ON trading.gas_owned_commands DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trading.check_gas_operator_quantity_correction();
DO $$DECLARE name text;BEGIN
 FOREACH name IN ARRAY ARRAY['gas_operator_claim_members','gas_operator_settlement_members','gas_operator_consumption_members','gas_operator_cash_members','gas_operator_source_members'] LOOP
  EXECUTE format('CREATE CONSTRAINT TRIGGER sealed_operator_member AFTER INSERT ON trading.%I DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trading.check_gas_operator_quantity_correction()',name);
 END LOOP;
END$$;



-- Exact qualified predecessor bodies and complete function metadata fence the
-- existing ordinary/known source and quantity proof bridges. OIDs and ACLs stay.
DO $operator_sources$DECLARE spec record;p pg_proc;definition text;replacement text;needle text;boundary integer;BEGIN
 FOR spec IN SELECT * FROM(VALUES
  ('trading.check_gas_owned_integrity()','c276ce7eb91d96405305beed6bab3917','trigger','plpgsql',true,'v',NULL,0,NULL,'integrity','at_time',false),
  ('trading.check_gas_quantity_revision()','5bb7c6550f93c61afee81f0caafe7240','trigger','plpgsql',true,'v',NULL,0,NULL,'proof','at_time',false),
  ('trading.require_gas_owned_quantity_head(uuid,uuid,uuid,timestamptz)','76c97bd4ea3ac4d497e81a115a46c42f','void','plpgsql',true,'s',ARRAY['catalog','account','context','as_of'],0,NULL,'head','as_of',false),
  ('security.read_gas_owned_holdings_original(uuid,uuid,timestamptz,uuid[])','69483bbea74b9c7f1053cadcd05ef47a','jsonb','plpgsql',true,'v',ARRAY['catalog','context','at_time','books'],0,NULL,'source','at_time',false),
  ('security.read_gas_owned_operations(uuid,uuid,timestamptz,uuid)','b7cb585a57944eb9bb65e457f0eeac10','jsonb','plpgsql',true,'v',ARRAY['catalog','context','as_of','account'],0,NULL,'source','as_of',true),
  ('security.read_gas_owned_known_history_pre_risk(uuid,uuid,timestamptz,uuid[])','f6ea01dd23142f4257b060b16a1d1d0a','jsonb','plpgsql',true,'v',ARRAY['catalog','context','at_time','books'],0,NULL,'source','at_time',false),
  ('security.gas_physical_journal_source(uuid,uuid,timestamptz,uuid[],uuid[])','9152ac820fdd676cb00e5d24e8283f11','jsonb','plpgsql',true,'v',ARRAY['catalog','context','at_time','books','selected_positions'],0,NULL,'source','at_time',false),
  ('trading.gas_owned_applied_source_conflicts(uuid,uuid,timestamptz,uuid[],uuid[])','e249927a8489ca70202c76c2ab423fe0','jsonb','sql',true,'v',ARRAY['catalog','context','at_time','books','positions'],1,'NULL::uuid[]','financial','at_time',false),
  ('trading.gas_owned_applied_observation_conflicts(uuid,uuid,timestamptz,uuid[],uuid[])','b3d07db1c19c9d591305087be31f50e5','jsonb','sql',true,'v',ARRAY['catalog','context','at_time','books','positions'],1,'NULL::uuid[]','financial','at_time',false),
  ('trading.gas_quantity_source_result(uuid,uuid,timestamptz,jsonb)','8cf83d9a7ea84cbc8c3fc6ea18bd6130','jsonb','plpgsql',true,'s',ARRAY['catalog','context','as_of','result'],0,NULL,'result','as_of',false)
 )s(signature,source_hash,result_type,language,definer,volatility,names,defaults,default_expression,mode,time_name,runtime_execute) LOOP
  SELECT * INTO STRICT p FROM pg_proc WHERE oid=spec.signature::regprocedure;
  IF md5(p.prosrc)<>spec.source_hash OR p.proowner<>'openetrm_security_owner'::regrole OR p.prorettype<>spec.result_type::regtype
   OR p.proretset OR p.provariadic<>0 OR p.proargmodes IS NOT NULL OR p.prokind<>'f' OR p.proisstrict OR p.proleakproof
   OR p.proargnames IS DISTINCT FROM spec.names OR p.proallargtypes IS NOT NULL OR p.pronargdefaults<>spec.defaults
   OR pg_get_expr(p.proargdefaults,0) IS DISTINCT FROM spec.default_expression
   OR p.provolatile::text<>spec.volatility OR p.proparallel<>'u' OR p.prosecdef IS DISTINCT FROM spec.definer
   OR p.procost<>100 OR p.prorows<>0 OR p.prosupport<>0 OR p.probin IS NOT NULL OR p.prosqlbody IS NOT NULL OR p.protrftypes IS NOT NULL
   OR(SELECT lanname FROM pg_language WHERE oid=p.prolang)<>spec.language OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
   OR has_function_privilege('openetrm_runtime',p.oid,'EXECUTE') IS DISTINCT FROM spec.runtime_execute
   OR has_function_privilege('openetrm_risk_worker',p.oid,'EXECUTE')
   OR NOT EXISTS(SELECT 1 FROM aclexplode(p.proacl)a WHERE a.grantor=p.proowner AND a.grantee=p.proowner AND a.privilege_type='EXECUTE' AND NOT a.is_grantable)
   OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a WHERE a.grantor<>p.proowner OR a.is_grantable OR a.privilege_type<>'EXECUTE'
    OR a.grantee NOT IN(p.proowner,CASE WHEN spec.runtime_execute THEN 'openetrm_runtime'::regrole ELSE p.proowner END))
  THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade: unexpected helper %',spec.signature;END IF;
  definition=pg_get_functiondef(p.oid);
  IF spec.mode='proof' THEN
   needle='IF NOT trading.gas_loan_quantity_position_proof(NEW.catalog_id,NEW.position_id,NEW.revision)';
   IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade';END IF;
   definition=replace(definition,needle,'IF NOT trading.gas_operator_position_proof(NEW.catalog_id,NEW.position_id,NEW.revision) AND NOT trading.gas_loan_quantity_position_proof(NEW.catalog_id,NEW.position_id,NEW.revision)');
   needle='ELSIF NOT trading.gas_loan_quantity_consumption_proof(NEW.catalog_id,NEW.consumption_id,NEW.revision)';
   IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade';END IF;
   definition=replace(definition,needle,'ELSIF NOT trading.gas_operator_consumption_proof(NEW.catalog_id,NEW.consumption_id,NEW.revision) AND NOT trading.gas_loan_quantity_consumption_proof(NEW.catalog_id,NEW.consumption_id,NEW.revision)');
  ELSIF spec.mode='head' THEN
   needle='SELECT q.publication_order FROM trading.gas_owned_position_quantities q WHERE';
   IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade';END IF;
   definition=replace(definition,needle,'SELECT oq.publication_order FROM trading.gas_operator_settlement_quantities oq JOIN trading.gas_owned_positions origin ON(origin.catalog_id,origin.id)=(oq.catalog_id,oq.claim_id) WHERE(origin.catalog_id,origin.account_id)=(catalog,account) AND oq.revision>1 UNION ALL SELECT q.publication_order FROM trading.gas_owned_position_quantities q WHERE');
  ELSIF spec.mode='integrity' THEN
   -- Original cash is still proved against its own immutable original prefix.
   -- Current quantity/counterpart tests use the exact selected financial heads.
   boundary=strpos(definition,E' IF EXISTS(SELECT 1 FROM trading.gas_owned_claim_settlements s\n  JOIN trading.gas_owned_positions_current p');
   IF boundary=0 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade: original cash proof';END IF;
   replacement=substring(definition FROM 1 FOR boundary-1);
   replacement=replace(replace(replacement,'FROM trading.gas_owned_claim_settlements ','FROM trading.gas_operator_settlements_current '),
    'JOIN trading.gas_owned_claim_settlements ','JOIN trading.gas_operator_settlements_current ');
   needle='s.receipt_lot_id IS NOT NULL AND(p.quantity<=0 OR';
   IF(length(replacement)-length(replace(replacement,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade: receipt polarity';END IF;
   replacement=replace(replacement,needle,'s.receipt_lot_id IS NOT NULL AND(p.quantity<0 OR(p.quantity=0 AND s.quantity<>0) OR');
   needle='s.consumption_id IS NOT NULL AND(p.quantity>=0 OR';
   IF(length(replacement)-length(replace(replacement,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade: use polarity';END IF;
   replacement=replace(replacement,needle,'s.consumption_id IS NOT NULL AND(p.quantity>0 OR(p.quantity=0 AND s.quantity<>0) OR');
   definition=replacement||substring(definition FROM boundary);
  ELSIF spec.mode='result' THEN
   needle='IF pg_column_size(result)>16777216';
   IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade';END IF;
   definition=replace(definition,needle,'result=trading.gas_operator_source_result(catalog,context,as_of,result); IF pg_column_size(result)>16777216');
  ELSE
   replacement=(CASE WHEN spec.mode='financial' THEN 'trading.gas_operator_financial_settlements_at' ELSE 'trading.gas_operator_settlements_at' END)
    ||'(catalog,context,'||spec.time_name||')';
   IF strpos(definition,'FROM trading.gas_owned_claim_settlements ')=0 AND strpos(definition,'JOIN trading.gas_owned_claim_settlements ')=0
   THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade: settlement source';END IF;
   definition=replace(replace(definition,'FROM trading.gas_owned_claim_settlements ','FROM '||replacement||' '),
    'JOIN trading.gas_owned_claim_settlements ','JOIN '||replacement||' ');
  END IF;
  IF definition=pg_get_functiondef(p.oid) THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade: missing bridge';END IF;
  EXECUTE definition;
 END LOOP;
END$operator_sources$;

-- Adding the operator financial family extends the preceding fee consumer's
-- closed publication boundary without changing its OID, owner or ACL.
DO $upgrade$DECLARE p pg_proc;definition text;needle constant text='OR EXISTS(SELECT 1 FROM settlement_data.cash_payment_revisions p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))';BEGIN
 SELECT * INTO STRICT p FROM pg_proc WHERE oid='trading.check_gas_loan_fee_change()'::regprocedure;
 IF md5(p.prosrc)<>'9ca8bade7e50869ba3fdf73087ad3913' OR p.proowner<>'openetrm_security_owner'::regrole OR p.prorettype<>'trigger'::regtype
  OR p.proretset OR p.provariadic<>0 OR p.proargmodes IS NOT NULL OR p.prokind<>'f' OR p.proisstrict OR p.proleakproof
  OR p.proargnames IS NOT NULL OR p.proallargtypes IS NOT NULL OR p.pronargdefaults<>0 OR p.proargdefaults IS NOT NULL
  OR p.provolatile<>'v' OR p.proparallel<>'u' OR NOT p.prosecdef OR p.procost<>100 OR p.prorows<>0
  OR(SELECT lanname FROM pg_language WHERE oid=p.prolang)<>'plpgsql' OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
  OR p.prosupport<>0 OR p.probin IS NOT NULL OR p.prosqlbody IS NOT NULL OR p.protrftypes IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM aclexplode(p.proacl)a WHERE a.grantor=p.proowner AND a.grantee=p.proowner AND a.privilege_type='EXECUTE' AND NOT a.is_grantable)
   OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a
   WHERE a.grantor<>p.proowner OR a.grantee<>p.proowner OR a.is_grantable OR a.privilege_type<>'EXECUTE')
 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade: unexpected fee seal';END IF;
 definition=pg_get_functiondef(p.oid);
 IF(length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'gas_operator_quantity_upgrade';END IF;
 EXECUTE replace(definition,needle,needle||E'\n   OR EXISTS(SELECT 1 FROM trading.gas_operator_quantity_corrections p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))\n   OR EXISTS(SELECT 1 FROM trading.gas_operator_settlement_quantities p WHERE(p.catalog_id,p.publication_order)=(h.catalog_id,h.publication_order))');
END$upgrade$;

COMMIT;
