-- Booked, title-transferring Park and Loan; native holdings own accepted effects.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
SELECT 1 FROM security.epoch WHERE id=true FOR UPDATE;
SELECT pg_advisory_xact_lock(730849102);
INSERT INTO lifecycle.action_kinds(code,automatic,configuration_permission,execution_permission)
 SELECT code,false,'ConfigureGasOwnedHoldings','RecordGasOwnedHoldings' FROM unnest(ARRAY[
  'gas.park_loan.advance','gas.park_loan.return','gas.park_loan.fee_payment'])code;

CREATE TABLE trading.gas_park_loan_instruments(
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,definition_revision_id uuid NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,quantity_code ref_data.code NOT NULL,
 location_code ref_data.code NOT NULL,currency_code ref_data.code NOT NULL,mark_curve_code ref_data.code NOT NULL,mark_contract_id uuid NOT NULL,
 service_kind text NOT NULL CHECK(service_kind IN('park','loan')),perspective text NOT NULL CHECK(perspective IN('customer','provider')),
 principal_direction integer NOT NULL CHECK(principal_direction IN(-1,1)),advance_at ref_data.instant NOT NULL,return_at ref_data.instant NOT NULL,
 fixed_fee_amount ref_data.exact_number NOT NULL,fee_direction text NOT NULL CHECK(fee_direction IN('pay','receive')),fee_due_at ref_data.instant,
 title_policy text NOT NULL CHECK(title_policy='fungible_gas_title_transfer_return_v1'),
 return_policy text NOT NULL CHECK(return_policy='same_quantity_partial_returns_v1'),
 return_timing text NOT NULL CHECK(return_timing='accepted_advance_then_returns_v1'),
 carrying text NOT NULL CHECK(carrying='nominal_mark_v1'),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,instrument_id),FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.instruments(catalog_id,id),
 FOREIGN KEY(catalog_id,definition_revision_id,mark_curve_code,mark_contract_id) REFERENCES market_data.curve_members(catalog_id,revision_id,curve_code,contract_id),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,quantity_code) REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,location_code) REFERENCES ref_data.locations(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,currency_code) REFERENCES ref_data.currencies(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order),
 CHECK(advance_at<return_at),CHECK((fixed_fee_amount=0)=(fee_due_at IS NULL)),
 CHECK(fee_due_at IS NULL OR fee_due_at>=advance_at),
 CHECK(fixed_fee_amount=0 OR sign(fixed_fee_amount)=CASE fee_direction WHEN 'pay' THEN -1 ELSE 1 END),
 CHECK(principal_direction=CASE WHEN(service_kind='loan' AND perspective='customer') OR(service_kind='park' AND perspective='provider') THEN 1 ELSE -1 END)
);
CREATE TABLE trading.gas_park_loan_trades(
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,revision integer NOT NULL CHECK(revision=1),instrument_id uuid NOT NULL,
 book_id uuid NOT NULL,operation_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),quantity ref_data.exact_number NOT NULL CHECK(quantity>0),
 owned_account_id uuid NOT NULL,claim_account_id uuid,legal_entity_id uuid NOT NULL,legal_entity_revision integer NOT NULL,
 counterparty_id uuid NOT NULL,counterparty_revision integer NOT NULL,publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,trade_id),UNIQUE(catalog_id,operation_id),UNIQUE(catalog_id,instrument_id),
 FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.trades(catalog_id,id),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.gas_park_loan_instruments(catalog_id,instrument_id),
 FOREIGN KEY(catalog_id,book_id) REFERENCES trading.books(catalog_id,id),
 FOREIGN KEY(catalog_id,owned_account_id) REFERENCES trading.gas_owned_accounts(catalog_id,id),
 FOREIGN KEY(catalog_id,claim_account_id) REFERENCES trading.gas_owned_accounts(catalog_id,id),
 FOREIGN KEY(catalog_id,legal_entity_id,legal_entity_revision) REFERENCES trading.legal_entities(catalog_id,id,revision),
 FOREIGN KEY(catalog_id,counterparty_id,counterparty_revision) REFERENCES trading.counterparties(catalog_id,id,revision),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.gas_park_loan_advances(
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,loan_id uuid,stock_id uuid,return_id uuid,claim_id uuid,dispatch_id uuid,fee_id uuid,
 agreement_evidence_id uuid NOT NULL,evidence_id uuid NOT NULL,claim_evidence_id uuid,
 actor_id uuid NOT NULL REFERENCES security.principals(id),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,trade_id),UNIQUE(catalog_id,loan_id),UNIQUE(catalog_id,claim_id),UNIQUE(catalog_id,fee_id),UNIQUE(catalog_id,dispatch_id),
 FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.gas_park_loan_trades(catalog_id,trade_id),
 FOREIGN KEY(catalog_id,loan_id) REFERENCES trading.gas_owned_loans(catalog_id,id),
 FOREIGN KEY(catalog_id,stock_id) REFERENCES trading.gas_owned_lots(catalog_id,id),
 FOREIGN KEY(catalog_id,return_id) REFERENCES trading.gas_owned_positions(catalog_id,id),
 FOREIGN KEY(catalog_id,claim_id) REFERENCES trading.gas_owned_positions(catalog_id,id),
 FOREIGN KEY(catalog_id,dispatch_id) REFERENCES trading.gas_owned_consumptions(catalog_id,id),
 FOREIGN KEY(catalog_id,fee_id) REFERENCES trading.gas_owned_fees(catalog_id,id),
 FOREIGN KEY(catalog_id,agreement_evidence_id) REFERENCES trading.gas_owned_evidence(catalog_id,id),
 FOREIGN KEY(catalog_id,evidence_id) REFERENCES trading.gas_owned_evidence(catalog_id,id),
 FOREIGN KEY(catalog_id,claim_evidence_id) REFERENCES trading.gas_owned_evidence(catalog_id,id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order),
 CHECK(num_nonnulls(loan_id,stock_id,return_id)=3 AND claim_id IS NULL AND dispatch_id IS NULL
  OR num_nonnulls(loan_id,stock_id,return_id)=0 AND claim_id IS NOT NULL AND dispatch_id IS NOT NULL)
);
CREATE TABLE trading.gas_park_loan_returns(
 catalog_id uuid NOT NULL,id uuid NOT NULL,trade_id uuid NOT NULL,business_key text NOT NULL CHECK(length(btrim(business_key)) BETWEEN 1 AND 128),
 repayment_id uuid,settlement_id uuid,quantity ref_data.exact_number NOT NULL CHECK(quantity>0),evidence_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES security.principals(id),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),UNIQUE(catalog_id,trade_id,business_key),UNIQUE(catalog_id,repayment_id),UNIQUE(catalog_id,settlement_id),
 FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.gas_park_loan_advances(catalog_id,trade_id),
 FOREIGN KEY(catalog_id,repayment_id) REFERENCES trading.gas_owned_repayments(catalog_id,id),
 FOREIGN KEY(catalog_id,settlement_id) REFERENCES trading.gas_owned_claim_settlements(catalog_id,id),
 FOREIGN KEY(catalog_id,evidence_id) REFERENCES trading.gas_owned_evidence(catalog_id,id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order),CHECK(num_nonnulls(repayment_id,settlement_id)=1)
);
CREATE TABLE trading.gas_park_loan_commands(
 catalog_id uuid NOT NULL,request_id uuid NOT NULL,trade_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),
 request jsonb NOT NULL,outcome jsonb NOT NULL,authority_until ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,request_id),FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.gas_park_loan_trades(catalog_id,trade_id)
);
DO $$DECLARE name text;BEGIN
 FOREACH name IN ARRAY ARRAY['gas_park_loan_instruments','gas_park_loan_trades','gas_park_loan_advances','gas_park_loan_returns','gas_park_loan_commands'] LOOP
  EXECUTE format('ALTER TABLE trading.%I OWNER TO openetrm_security_owner',name);
  EXECUTE format('ALTER TABLE trading.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('ALTER TABLE trading.%I FORCE ROW LEVEL SECURITY',name);
  EXECUTE format('CREATE POLICY owner_all ON trading.%I TO openetrm_security_owner USING(true) WITH CHECK(true)',name);
  EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.%I FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt()',name);
 END LOOP;
END$$;

CREATE FUNCTION security.gas_park_loan_authority(catalog uuid,writing boolean) RETURNS timestamptz
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;BEGIN
 deadline=least(security.authority_until('ReadMarketData'),security.authority_until('ReadTrades'),security.authority_until('ReadGasOwnedHoldings'));
 IF writing THEN deadline=least(deadline,security.authority_until('RecordGasOwnedHoldings'));END IF;
 PERFORM security.require_gas_owned(catalog,writing,false);
 IF deadline IS NULL OR clock_timestamp()>=deadline THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 RETURN deadline;
END$$;

CREATE FUNCTION trading.gas_park_loan_keys(body jsonb,keys text[],nullable text[]) RETURNS void
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
 IF jsonb_typeof(body) IS DISTINCT FROM 'object' OR NOT(body?&keys) OR EXISTS(SELECT 1 FROM jsonb_object_keys(body)k WHERE NOT(k=ANY(keys)))
  OR EXISTS(SELECT 1 FROM jsonb_each(body)e WHERE e.value='null'::jsonb AND NOT(e.key=ANY(nullable)))
 THEN RAISE EXCEPTION 'gas_park_loan_input';END IF;
END$$;

CREATE FUNCTION trading.gas_park_loan_fact(body jsonb) RETURNS jsonb
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE result jsonb=trading.gas_owned_fact(body);key text;BEGIN
 FOREACH key IN ARRAY ARRAY['agreementEvidenceId','claimEvidenceId','claimAccountId','contextId','snapshotId','operationId'] LOOP
  IF body->>key IS NOT NULL THEN result=result||jsonb_build_object(key,(body->>key)::uuid);END IF;
 END LOOP;
 IF body->>'fixedFeeAmount' IS NOT NULL THEN result=result||jsonb_build_object('fixedFeeAmount',trim_scale(trading.gas_owned_quantity(body->>'fixedFeeAmount'))::text);END IF;
 IF body->>'advanceAt' IS NOT NULL THEN result=result||jsonb_build_object('advanceAt',to_char(trading.gas_owned_at(body->>'advanceAt') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));END IF;
 RETURN result;
END$$;

CREATE FUNCTION security.require_gas_park_loan_worker_scope(catalog uuid,context uuid,as_of timestamptz,books uuid[],trades uuid[],selected_trade uuid) RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE job risk.jobs;book uuid;BEGIN
 IF NOT pg_has_role(session_user,'openetrm_risk_worker','MEMBER') THEN RETURN;END IF;
 job=risk.bound_lifecycle_reader();
 IF catalog IS DISTINCT FROM job.catalog_id OR context IS DISTINCT FROM job.context_id OR as_of IS DISTINCT FROM job.valuation_at
 THEN RAISE EXCEPTION 'risk_job_scope' USING ERRCODE='42501';END IF;
 IF books IS NOT NULL AND(SELECT array_agg(DISTINCT b ORDER BY b) FROM unnest(books)b)
  IS DISTINCT FROM(SELECT array_agg(value::uuid ORDER BY value::uuid) FROM jsonb_array_elements_text(job.request->'bookIds'))
 THEN RAISE EXCEPTION 'risk_job_scope' USING ERRCODE='42501';END IF;
 IF trades IS NOT NULL AND(SELECT array_agg(DISTINCT t ORDER BY t) FROM unnest(trades)t)
  IS DISTINCT FROM(SELECT array_agg(value::uuid ORDER BY value::uuid) FROM jsonb_array_elements_text(coalesce(NULLIF(job.request->'tradeIds','null'::jsonb),'[]'::jsonb)))
 THEN RAISE EXCEPTION 'risk_job_scope' USING ERRCODE='42501';END IF;
 IF selected_trade IS NOT NULL THEN
  SELECT t.book_id INTO book FROM trading.trades t WHERE(t.catalog_id,t.id)=(catalog,selected_trade);
  IF book IS NULL OR NOT(job.request->'bookIds' @> jsonb_build_array(book))
   OR NULLIF(job.request->'tradeIds','null'::jsonb) IS NOT NULL AND NOT(job.request->'tradeIds' @> jsonb_build_array(selected_trade))
  THEN RAISE EXCEPTION 'risk_job_scope' USING ERRCODE='42501';END IF;
 END IF;
END$$;

CREATE FUNCTION security.book_gas_park_loan(catalog uuid,body jsonb,valuation timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;actor uuid;prior trading.trades;owner trading.gas_owned_accounts;claim trading.gas_owned_accounts;
 operation uuid;context uuid;direction integer;quantity numeric;advance_at timestamptz;return_at timestamptz;fee numeric;fee_due timestamptz;
 publication integer;trade uuid=gen_random_uuid();instrument uuid=gen_random_uuid();BEGIN
 deadline=least(security.gas_park_loan_authority(catalog,false),security.authority_until('BookTrade'));
 IF security.trading_access(catalog,'BookTrade') IS NOT TRUE OR security.current_write_context() IS NOT TRUE OR clock_timestamp()>=deadline
 THEN RAISE EXCEPTION 'gas_park_loan_denied' USING ERRCODE='42501';END IF;
 PERFORM trading.gas_park_loan_keys(body,ARRAY['operationId','profile','convention','knowledgeMode','contextId','snapshotId','bookId','definitionRevisionId',
  'legalEntityId','legalEntityRevision','counterpartyId','counterpartyRevision','ownedAccountId','claimAccountId','serviceKind','perspective','quantity',
  'advanceAt','returnAt','fixedFeeAmount','feeDirection','feeDueAt','titlePolicy','returnPolicy','returnTiming','carrying'],ARRAY['claimAccountId','feeDueAt']);
 body=trading.gas_park_loan_fact(body);
 operation=(body->>'operationId')::uuid;context=(body->>'contextId')::uuid;
 SELECT actor_id INTO STRICT actor FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 PERFORM pg_advisory_xact_lock(730849102);
 IF clock_timestamp()>=deadline OR security.trading_access(catalog,'BookTrade') IS NOT TRUE THEN RAISE EXCEPTION 'gas_park_loan_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO prior FROM trading.trades t WHERE(t.catalog_id,t.operation_id)=(catalog,operation);
 IF FOUND THEN
  IF prior.actor_id<>actor OR prior.request IS DISTINCT FROM body OR NOT EXISTS(SELECT 1 FROM trading.gas_park_loan_trades t WHERE(t.catalog_id,t.trade_id)=(catalog,prior.id))
  THEN RAISE EXCEPTION 'gas_park_loan_conflict';END IF;
  RETURN jsonb_build_object('tradeId',prior.id,'instrumentId',(SELECT instrument_id FROM trading.gas_park_loan_trades WHERE(catalog_id,trade_id)=(catalog,prior.id)),
   'revision',1,'operationId',operation);
 END IF;
 quantity=trading.gas_owned_quantity(body->>'quantity');advance_at=trading.gas_owned_at(body->>'advanceAt');return_at=trading.gas_owned_at(body->>'returnAt');
 fee=trading.gas_owned_quantity(body->>'fixedFeeAmount');fee_due=CASE WHEN body->>'feeDueAt' IS NULL THEN NULL ELSE trading.gas_owned_at(body->>'feeDueAt') END;
 IF fee_due<advance_at THEN RAISE EXCEPTION 'gas_park_loan_fee';END IF;
 direction=CASE WHEN(body->>'serviceKind'='loan' AND body->>'perspective'='customer') OR(body->>'serviceKind'='park' AND body->>'perspective'='provider') THEN 1 ELSE -1 END;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR context IS NULL OR valuation IS NULL OR NOT isfinite(valuation)
  OR body->>'profile' IS DISTINCT FROM 'physical_gas_park_loan_v1' OR body->>'convention' IS DISTINCT FROM 'physical_gas_fixed_quantity_v4'
  OR body->>'knowledgeMode' IS DISTINCT FROM 'current' OR body->>'serviceKind' NOT IN('park','loan') OR body->>'perspective' NOT IN('customer','provider')
  OR body->>'titlePolicy' IS DISTINCT FROM 'fungible_gas_title_transfer_return_v1' OR body->>'returnPolicy' IS DISTINCT FROM 'same_quantity_partial_returns_v1'
  OR body->>'returnTiming' IS DISTINCT FROM 'accepted_advance_then_returns_v1' OR body->>'carrying' IS DISTINCT FROM 'nominal_mark_v1'
  OR body->>'feeDirection' NOT IN('pay','receive') OR quantity<=0 OR valuation>=advance_at OR advance_at>=return_at OR(fee=0)<>(fee_due IS NULL)
  OR(fee<>0 AND sign(fee)<>(CASE body->>'feeDirection' WHEN 'pay' THEN -1 ELSE 1 END))
  OR security.trading_context_day_matches(catalog,context,valuation) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_park_loan_input';END IF;
 SELECT * INTO owner FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(catalog,(body->>'ownedAccountId')::uuid);
 SELECT * INTO claim FROM trading.gas_owned_accounts a WHERE(a.catalog_id,a.id)=(catalog,(body->>'claimAccountId')::uuid);
 IF owner.id IS NULL OR owner.kind<>'owned_inventory' OR(owner.book_id,owner.legal_entity_id,owner.legal_entity_revision,owner.definition_revision_id)
  IS DISTINCT FROM((body->>'bookId')::uuid,(body->>'legalEntityId')::uuid,(body->>'legalEntityRevision')::integer,(body->>'definitionRevisionId')::uuid)
  OR trading.gas_owned_visible(catalog,owner.publication_order,owner.effective_at,context,valuation) IS NOT TRUE
  OR(direction=1)<>(claim.id IS NULL) OR direction=1 AND body->>'claimAccountId' IS NOT NULL
 THEN RAISE EXCEPTION 'gas_park_loan_account';END IF;
 IF direction=-1 AND(claim.kind<>'operator_balance' OR(claim.book_id,claim.legal_entity_id,claim.legal_entity_revision,claim.reference_catalog_id,claim.reference_revision_id,
  claim.quantity_code,claim.location_code,claim.currency_code,claim.definition_revision_id,claim.mark_curve_code,claim.mark_contract_id,claim.counterparty_id,claim.counterparty_revision)
  IS DISTINCT FROM(owner.book_id,owner.legal_entity_id,owner.legal_entity_revision,owner.reference_catalog_id,owner.reference_revision_id,owner.quantity_code,owner.location_code,
   owner.currency_code,owner.definition_revision_id,owner.mark_curve_code,owner.mark_contract_id,(body->>'counterpartyId')::uuid,(body->>'counterpartyRevision')::integer)
  OR trading.gas_owned_visible(catalog,claim.publication_order,claim.effective_at,context,valuation) IS NOT TRUE)
 THEN RAISE EXCEPTION 'gas_park_loan_account';END IF;
 IF security.reference_version_visible(owner.reference_catalog_id,owner.reference_revision_id) IS NOT TRUE OR security.market_fact_visible(catalog,owner.definition_revision_id,NULL) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 PERFORM settlement_data.require_futures_margin_source(catalog,context,valuation,owner.definition_revision_id);
 IF NOT EXISTS(SELECT 1 FROM trading.legal_entities p WHERE(p.catalog_id,p.id,p.revision)=(catalog,(body->>'legalEntityId')::uuid,(body->>'legalEntityRevision')::integer)
   AND trading.gas_owned_visible(catalog,p.publication_order,p.effective_at,context,valuation)) OR NOT EXISTS(
  SELECT 1 FROM trading.counterparties p WHERE(p.catalog_id,p.id,p.revision)=(catalog,(body->>'counterpartyId')::uuid,(body->>'counterpartyRevision')::integer)
   AND trading.gas_owned_visible(catalog,p.publication_order,p.effective_at,context,valuation))
 THEN RAISE EXCEPTION 'gas_owned_context';END IF;
 PERFORM security.require_trade_parties(catalog,jsonb_build_object('tradeDate',(clock_timestamp() AT TIME ZONE 'UTC')::date,
  'legalEntityId',body->'legalEntityId','legalEntityRevision',body->'legalEntityRevision','counterpartyId',body->'counterpartyId','counterpartyRevision',body->'counterpartyRevision'),valuation);
 SELECT coalesce(max(publication_order),0)+1 INTO publication FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());
 INSERT INTO trading.instruments VALUES(catalog,instrument,publication,valuation);
 INSERT INTO trading.gas_park_loan_instruments VALUES(catalog,instrument,owner.definition_revision_id,owner.reference_catalog_id,owner.reference_revision_id,
  owner.quantity_code,owner.location_code,owner.currency_code,owner.mark_curve_code,owner.mark_contract_id,body->>'serviceKind',body->>'perspective',direction,
  advance_at,return_at,fee,body->>'feeDirection',fee_due,body->>'titlePolicy',body->>'returnPolicy',body->>'returnTiming',body->>'carrying',publication,valuation);
 PERFORM security.stamp_trade_booking(catalog);
 INSERT INTO trading.trades VALUES(catalog,trade,owner.book_id,operation,actor,body,publication,valuation);
 INSERT INTO trading.gas_park_loan_trades VALUES(catalog,trade,1,instrument,owner.book_id,operation,actor,quantity,owner.id,claim.id,
  owner.legal_entity_id,owner.legal_entity_revision,(body->>'counterpartyId')::uuid,(body->>'counterpartyRevision')::integer,publication,valuation);
 PERFORM security.require_gas_owned_preview(catalog,deadline);
 IF security.trading_access(catalog,'BookTrade') IS NOT TRUE THEN RAISE EXCEPTION 'gas_park_loan_denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('tradeId',trade,'instrumentId',instrument,'revision',1,'operationId',operation);
END$$;

CREATE FUNCTION security.read_gas_park_loan(catalog uuid,trade uuid,context uuid,as_of timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;binding trading.gas_park_loan_trades;terms trading.gas_park_loan_instruments;advance trading.gas_park_loan_advances;
 returned numeric;paid numeric;version integer;result jsonb;BEGIN
 deadline=security.gas_park_loan_authority(catalog,false);
 PERFORM security.require_gas_park_loan_worker_scope(catalog,context,as_of,NULL,NULL,trade);
 PERFORM security.require_gas_owned_read(catalog,context,as_of,deadline);
 SELECT * INTO binding FROM trading.gas_park_loan_trades t WHERE(t.catalog_id,t.trade_id)=(catalog,trade)
  AND trading.gas_owned_visible(catalog,t.publication_order,t.effective_at,context,as_of);
 IF binding.trade_id IS NULL THEN RAISE EXCEPTION 'gas_park_loan_source';END IF;
 SELECT * INTO STRICT terms FROM trading.gas_park_loan_instruments i WHERE(i.catalog_id,i.instrument_id)=(catalog,binding.instrument_id);
 IF security.reference_version_visible(terms.reference_catalog_id,terms.reference_revision_id) IS NOT TRUE OR security.market_fact_visible(catalog,terms.definition_revision_id,NULL) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 PERFORM settlement_data.require_futures_margin_source(catalog,context,as_of,terms.definition_revision_id);
 SELECT * INTO advance FROM trading.gas_park_loan_advances a WHERE(a.catalog_id,a.trade_id)=(catalog,trade)
  AND trading.gas_owned_visible(catalog,a.publication_order,a.effective_at,context,as_of);
 IF(SELECT count(*) FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.trade_id)=(catalog,trade)
  AND trading.gas_owned_visible(catalog,r.publication_order,r.effective_at,context,as_of))>16384
 THEN RAISE EXCEPTION 'gas_park_loan_scope';END IF;
 SELECT coalesce(sum(r.quantity),0),coalesce(max(r.publication_order),0) INTO returned,version FROM trading.gas_park_loan_returns r
  WHERE(r.catalog_id,r.trade_id)=(catalog,trade) AND trading.gas_owned_visible(catalog,r.publication_order,r.effective_at,context,as_of);
 version=greatest(version,binding.publication_order,coalesce(advance.publication_order,0));
 SELECT coalesce(sum(p.amount),0) INTO paid FROM(SELECT DISTINCT ON(p.business_key)p.amount,p.paid_at FROM trading.gas_owned_fee_payments p
  WHERE(p.catalog_id,p.fee_id)=(catalog,advance.fee_id)
   AND trading.gas_owned_visible(catalog,p.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00Z',context,as_of)
  ORDER BY p.business_key,p.revision DESC)p WHERE p.paid_at<=as_of;
 result=jsonb_build_object('implementation','physical_gas_park_loan_v1','tradeId',trade,'instrumentId',binding.instrument_id,'revision',1,
  'bookId',binding.book_id,'quantity',trim_scale(binding.quantity)::text,'ownedAccountId',binding.owned_account_id,'claimAccountId',binding.claim_account_id,
  'operationId',binding.operation_id,'publicationOrder',binding.publication_order,'effectiveAt',binding.effective_at,
  'booking',(SELECT to_jsonb(f) FROM trading.booking_facts f WHERE(f.catalog_id,f.trade_id)=(catalog,trade)),
  'tradeReference',(SELECT reference_number FROM trading.trade_references WHERE(catalog_id,trade_id)=(catalog,trade)),
  'instrumentReference',(SELECT reference_number FROM trading.instrument_references WHERE(catalog_id,instrument_id)=(catalog,binding.instrument_id)),
  'legalEntityId',binding.legal_entity_id,'legalEntityRevision',binding.legal_entity_revision,'counterpartyId',binding.counterparty_id,'counterpartyRevision',binding.counterparty_revision,
  'contextId',context,'asOf',as_of,'authorityUntil',deadline,'stateVersion',version,
  'knownAt',(SELECT known_at FROM market_data.temporal_contexts WHERE(catalog_id,id)=(catalog,context)),
  'effectiveOn',(SELECT effective_on FROM market_data.temporal_contexts WHERE(catalog_id,id)=(catalog,context)),
  'terms',jsonb_build_object('serviceKind',terms.service_kind,'perspective',terms.perspective,'principalDirection',terms.principal_direction,
   'definitionRevisionId',terms.definition_revision_id,'referenceCatalogId',terms.reference_catalog_id,'referenceRevisionId',terms.reference_revision_id,
   'quantity',terms.quantity_code,'location',terms.location_code,'currency',terms.currency_code,'markCurve',terms.mark_curve_code,'markContractId',terms.mark_contract_id,
   'advanceAt',terms.advance_at,'returnAt',terms.return_at,'fixedFeeAmount',trim_scale(terms.fixed_fee_amount)::text,'feeDirection',terms.fee_direction,'feeDueAt',terms.fee_due_at,
   'feeRecognition','accepted_advance_v1',
   'titlePolicy',terms.title_policy,'returnPolicy',terms.return_policy,'returnTiming',terms.return_timing,'carrying',terms.carrying),
  'advance',CASE WHEN advance.trade_id IS NULL THEN 'null'::jsonb ELSE jsonb_build_object('loanId',advance.loan_id,'stockId',advance.stock_id,'returnId',advance.return_id,
   'claimId',advance.claim_id,'dispatchId',advance.dispatch_id,'feeId',advance.fee_id,'agreementEvidenceId',advance.agreement_evidence_id,
   'evidenceId',advance.evidence_id,'claimEvidenceId',advance.claim_evidence_id,'effectiveAt',advance.effective_at) END,
  'returns',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'businessKey',r.business_key,'repaymentId',r.repayment_id,'settlementId',r.settlement_id,
   'quantity',trim_scale(r.quantity)::text,'evidenceId',r.evidence_id,'effectiveAt',r.effective_at) ORDER BY r.effective_at,r.business_key)
   FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.trade_id)=(catalog,trade) AND trading.gas_owned_visible(catalog,r.publication_order,r.effective_at,context,as_of)),'[]'),
  'balances',jsonb_build_object('acceptedPrincipal',CASE WHEN advance.trade_id IS NULL THEN '0' ELSE trim_scale(binding.quantity)::text END,
   'acceptedReturn',trim_scale(returned)::text,'outstandingPrincipal',CASE WHEN advance.trade_id IS NULL THEN '0' ELSE trim_scale(binding.quantity-returned)::text END),
  'fee',jsonb_build_object('amount',trim_scale(terms.fixed_fee_amount)::text,'paid',trim_scale(paid)::text,'unpaid',trim_scale(terms.fixed_fee_amount-paid)::text,'dueAt',terms.fee_due_at),
  'reconciliationRequired',EXISTS(SELECT 1 FROM trading.gas_owned_evidence e JOIN trading.gas_owned_evidence n
   ON(n.catalog_id,n.account_id,n.source_key)=(e.catalog_id,e.account_id,e.source_key)
   WHERE e.catalog_id=catalog AND n.revision>e.revision AND(e.id IN(advance.agreement_evidence_id,advance.evidence_id,advance.claim_evidence_id)
    OR e.id IN(SELECT r.evidence_id FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.trade_id)=(catalog,trade)
     AND trading.gas_owned_visible(catalog,r.publication_order,r.effective_at,context,as_of)))
    AND trading.gas_owned_visible(catalog,n.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00Z',context,as_of)),
  'policies',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.account_id,p.action) FROM(SELECT DISTINCT ON(b.account_id,b.action)b.account_id,b.action,b.revision,b.policy_id,b.policy_revision
   FROM trading.gas_owned_action_bindings b WHERE b.catalog_id=catalog AND b.account_id IN(binding.owned_account_id,binding.claim_account_id)
    AND trading.gas_owned_visible(catalog,b.publication_order,b.effective_at,context,as_of) ORDER BY b.account_id,b.action,b.revision DESC)p),'[]'));
 IF pg_column_size(result)>16777216 THEN RAISE EXCEPTION 'gas_park_loan_scope';END IF;
 PERFORM security.require_gas_owned_read(catalog,context,as_of,deadline);RETURN result;
END$$;

CREATE FUNCTION trading.apply_park_loan_native(catalog uuid,operation uuid,account uuid,action text,body jsonb,as_of timestamptz,context uuid) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE binding trading.gas_owned_action_bindings;selected trading.gas_owned_action_bindings;code text;BEGIN
 code=CASE action WHEN 'borrow' THEN 'gas.loan.borrow' WHEN 'repay' THEN 'gas.loan.repay' WHEN 'dispatch' THEN 'gas.owned.dispatch'
  WHEN 'operator_claim' THEN 'gas.operator.record' WHEN 'operator_settle' THEN 'gas.operator.settle' WHEN 'fee_payment' THEN 'gas.cash.record_payment' END;
 SELECT * INTO binding FROM trading.gas_owned_action_bindings b WHERE(b.catalog_id,b.account_id,b.action)=(catalog,account,code) ORDER BY revision DESC LIMIT 1;
 SELECT * INTO selected FROM trading.gas_owned_action_bindings b WHERE(b.catalog_id,b.account_id,b.action)=(catalog,account,code)
  AND trading.gas_owned_visible(catalog,b.publication_order,b.effective_at,context,as_of) ORDER BY revision DESC LIMIT 1;
 IF binding.policy_id IS NULL OR(binding.revision,binding.policy_id,binding.policy_revision)
  IS DISTINCT FROM(selected.revision,selected.policy_id,selected.policy_revision) THEN RAISE EXCEPTION 'gas_owned_policy_changed';END IF;
 RETURN security.record_gas_owned(catalog,operation,action,account,body,as_of,context,binding.policy_id,binding.policy_revision,false);
END$$;

CREATE FUNCTION security.gas_park_loan_command_receipt(catalog uuid,operation uuid,trade uuid,action text,body jsonb,as_of timestamptz,context uuid) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;actor uuid;prior trading.gas_park_loan_commands;terms trading.gas_park_loan_instruments;canonical jsonb;BEGIN
 deadline=security.gas_park_loan_authority(catalog,true);
 SELECT actor_id INTO STRICT actor FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 canonical=jsonb_build_object('tradeId',trade,'action',action,'body',trading.gas_park_loan_fact(body),'asOf',as_of,'contextId',context);
 PERFORM pg_advisory_xact_lock(hashtextextended('gas_park_loan:'||catalog::text||':'||operation::text,0));
 PERFORM security.require_gas_owned_write(catalog,false,deadline);
 SELECT * INTO prior FROM trading.gas_park_loan_commands c WHERE(c.catalog_id,c.request_id)=(catalog,operation);
 IF prior.request_id IS NULL THEN RETURN NULL;END IF;
 IF prior.actor_id IS DISTINCT FROM actor OR prior.request IS DISTINCT FROM canonical THEN RAISE EXCEPTION 'gas_park_loan_conflict';END IF;
 SELECT i.* INTO STRICT terms FROM trading.gas_park_loan_trades t JOIN trading.gas_park_loan_instruments i
  ON(i.catalog_id,i.instrument_id)=(t.catalog_id,t.instrument_id) WHERE(t.catalog_id,t.trade_id)=(catalog,prior.trade_id);
 IF security.reference_version_visible(terms.reference_catalog_id,terms.reference_revision_id) IS NOT TRUE OR security.market_fact_visible(catalog,terms.definition_revision_id,NULL) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 PERFORM security.require_gas_owned_write(catalog,false,deadline);RETURN prior.outcome;
END$$;

CREATE FUNCTION security.record_gas_park_loan(catalog uuid,operation uuid,trade uuid,action text,body jsonb,as_of timestamptz,context uuid,preview boolean) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;actor uuid;canonical jsonb;same_fact trading.gas_park_loan_commands;
 binding trading.gas_park_loan_trades;terms trading.gas_park_loan_instruments;advance trading.gas_park_loan_advances;source jsonb;native jsonb;other jsonb;
 effective timestamptz;quantity numeric;returned numeric;publication integer;fee uuid;id uuid;outcome jsonb;BEGIN
 deadline=security.gas_park_loan_authority(catalog,true);
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR context IS NULL OR preview IS NULL OR trade IS NULL
  OR as_of IS NULL OR NOT isfinite(as_of) OR jsonb_typeof(body) IS DISTINCT FROM 'object' OR pg_column_size(body)>16384 OR action IS NULL OR action NOT IN('advance','return','fee_payment')
 THEN RAISE EXCEPTION 'gas_park_loan_input';END IF;
 IF preview THEN
  BEGIN
   outcome=security.record_gas_park_loan(catalog,operation,trade,action,body,as_of,context,false);
   RAISE EXCEPTION USING ERRCODE='GX001',DETAIL=outcome::text;
  EXCEPTION WHEN SQLSTATE 'GX001' THEN GET STACKED DIAGNOSTICS outcome=PG_EXCEPTION_DETAIL;RETURN outcome::jsonb;
  END;
 END IF;
 SELECT actor_id INTO STRICT actor FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 body=trading.gas_park_loan_fact(body);
 canonical=jsonb_build_object('tradeId',trade,'action',action,'body',body,'asOf',as_of,'contextId',context);
 PERFORM pg_advisory_xact_lock(hashtextextended('gas_park_loan:'||catalog::text||':'||operation::text,0));
 PERFORM security.require_gas_owned_write(catalog,false,deadline);
 outcome=security.gas_park_loan_command_receipt(catalog,operation,trade,action,body,as_of,context);
 IF outcome IS NOT NULL THEN
  PERFORM security.require_gas_owned_write(catalog,false,deadline);RETURN outcome;
 END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 PERFORM security.require_gas_owned_write(catalog,false,deadline);
 SELECT * INTO binding FROM trading.gas_park_loan_trades t WHERE(t.catalog_id,t.trade_id)=(catalog,trade);
 IF binding.trade_id IS NULL THEN RAISE EXCEPTION 'gas_park_loan_source';END IF;
 SELECT * INTO STRICT terms FROM trading.gas_park_loan_instruments i WHERE(i.catalog_id,i.instrument_id)=(catalog,binding.instrument_id);
 IF security.reference_version_visible(terms.reference_catalog_id,terms.reference_revision_id) IS NOT TRUE OR security.market_fact_visible(catalog,terms.definition_revision_id,NULL) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO same_fact FROM trading.gas_park_loan_commands c WHERE(c.catalog_id,c.trade_id,c.request->>'action')=(catalog,trade,action)
  AND((c.request->'body')-'expectedVersion')=(body-'expectedVersion') ORDER BY c.request_id LIMIT 1;
 IF FOUND THEN
  outcome=same_fact.outcome||jsonb_build_object('operationId',operation,'changed',false);
  INSERT INTO trading.gas_park_loan_commands VALUES(catalog,operation,trade,actor,canonical,outcome,deadline);
  PERFORM security.require_gas_owned_write(catalog,false,deadline);RETURN outcome;
 END IF;
 IF security.trading_context_day_matches(catalog,context,as_of) IS NOT TRUE OR
  trading.gas_owned_visible(catalog,binding.publication_order,binding.effective_at,context,as_of) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_owned_context';END IF;
 PERFORM settlement_data.require_futures_margin_source(catalog,context,as_of,terms.definition_revision_id);
 SELECT jsonb_build_object('stateVersion',greatest(binding.publication_order,
  coalesce((SELECT max(a.publication_order) FROM trading.gas_park_loan_advances a WHERE(a.catalog_id,a.trade_id)=(catalog,trade)
   AND trading.gas_owned_visible(catalog,a.publication_order,a.effective_at,context,as_of)),0),
  coalesce((SELECT max(r.publication_order) FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.trade_id)=(catalog,trade)
   AND trading.gas_owned_visible(catalog,r.publication_order,r.effective_at,context,as_of)),0))) INTO source;
 IF jsonb_typeof(body->'expectedVersion') IS DISTINCT FROM 'number' OR(body->>'expectedVersion')::numeric<>trunc((body->>'expectedVersion')::numeric)
  OR(body->>'expectedVersion')::numeric NOT BETWEEN 1 AND 2147483647 THEN RAISE EXCEPTION 'gas_park_loan_input';END IF;
 IF(body->>'expectedVersion')::integer IS DISTINCT FROM(source->>'stateVersion')::integer THEN RAISE EXCEPTION 'gas_park_loan_stale';END IF;
 PERFORM trading.require_gas_owned_head(catalog,binding.owned_account_id,context,as_of);
 IF binding.claim_account_id IS NOT NULL THEN PERFORM trading.require_gas_owned_head(catalog,binding.claim_account_id,context,as_of);END IF;
 SELECT * INTO advance FROM trading.gas_park_loan_advances a WHERE(a.catalog_id,a.trade_id)=(catalog,trade);
 IF action='advance' THEN
  PERFORM trading.gas_park_loan_keys(body,ARRAY['expectedVersion','agreementEvidenceId','evidenceId','claimEvidenceId','lotId','reservationId','effectiveAt'],ARRAY['claimEvidenceId','lotId','reservationId']);
  effective=trading.gas_owned_at(body->>'effectiveAt');
  IF advance.trade_id IS NOT NULL OR effective<terms.advance_at OR effective>=terms.return_at OR effective>as_of
  THEN RAISE EXCEPTION 'gas_park_loan_advance';END IF;
  IF terms.principal_direction=1 THEN
   IF body->>'lotId' IS NOT NULL OR body->>'reservationId' IS NOT NULL OR body->>'claimEvidenceId' IS NOT NULL THEN RAISE EXCEPTION 'gas_park_loan_input';END IF;
   native=trading.apply_park_loan_native(catalog,md5(operation::text||':borrow')::uuid,binding.owned_account_id,'borrow',jsonb_build_object(
    'agreementId',body->'agreementEvidenceId','evidenceId',body->'evidenceId','quantity',trim_scale(binding.quantity)::text,'titleAt',body->'effectiveAt','availableAt',body->'effectiveAt',
    'returnAt',to_char(terms.return_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'returnMarkCurve',terms.mark_curve_code,'returnMarkContractId',terms.mark_contract_id,'carrying',terms.carrying,
    'feeAmount','0','feeDueAt',NULL,'lenderId',binding.counterparty_id,'lenderRevision',binding.counterparty_revision),as_of,context);
  ELSE
   IF body->>'lotId' IS NULL OR body->>'claimEvidenceId' IS NULL OR body->>'agreementEvidenceId' IS NULL THEN RAISE EXCEPTION 'gas_park_loan_input';END IF;
   IF NOT EXISTS(SELECT 1 FROM trading.gas_owned_evidence e WHERE(e.catalog_id,e.id,e.account_id,e.kind)=(catalog,(body->>'agreementEvidenceId')::uuid,binding.owned_account_id,'loan_agreement')
    AND e.quantity>=binding.quantity AND e.occurred_at<=effective AND NOT EXISTS(SELECT 1 FROM trading.gas_owned_evidence n WHERE(n.catalog_id,n.account_id,n.source_key)=(e.catalog_id,e.account_id,e.source_key) AND n.revision>e.revision))
   THEN RAISE EXCEPTION 'gas_park_loan_agreement';END IF;
   other=trading.apply_park_loan_native(catalog,md5(operation::text||':dispatch')::uuid,binding.owned_account_id,'dispatch',jsonb_build_object(
    'lotId',body->'lotId','evidenceId',body->'evidenceId','quantity',trim_scale(binding.quantity)::text,'reservationId',body->'reservationId','effectiveAt',body->'effectiveAt'),as_of,context);
   native=trading.apply_park_loan_native(catalog,md5(operation::text||':claim')::uuid,binding.claim_account_id,'operator_claim',jsonb_build_object(
    'evidenceId',body->'claimEvidenceId','quantity',trim_scale(binding.quantity)::text,'effectiveAt',body->'effectiveAt','dueAt',to_char(terms.return_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'carrying',terms.carrying,
    'settlementMode','return_quantity_v1','cashout',NULL),as_of,context);
  END IF;
  SELECT coalesce(max(publication_order),0)+1 INTO publication FROM trading.publications WHERE catalog_id=catalog;
  INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());
  IF terms.fixed_fee_amount<>0 THEN
   fee=gen_random_uuid();
   INSERT INTO trading.gas_owned_fees VALUES(catalog,fee,CASE WHEN terms.principal_direction=1 THEN(native->>'returnId')::uuid ELSE(native->>'id')::uuid END,NULL,
    terms.fixed_fee_amount,terms.reference_catalog_id,terms.reference_revision_id,terms.currency_code,terms.fee_due_at,actor,publication,effective);
  END IF;
  INSERT INTO trading.gas_park_loan_advances VALUES(catalog,trade,CASE WHEN terms.principal_direction=1 THEN(native->>'id')::uuid END,
   (native->>'stockId')::uuid,(native->>'returnId')::uuid,CASE WHEN terms.principal_direction=-1 THEN(native->>'id')::uuid END,
   (other->>'id')::uuid,fee,(body->>'agreementEvidenceId')::uuid,(body->>'evidenceId')::uuid,(body->>'claimEvidenceId')::uuid,actor,publication,effective);
  outcome=jsonb_build_object('loanId',CASE WHEN terms.principal_direction=1 THEN native->'id' END,'stockId',native->'stockId','returnId',native->'returnId',
   'claimId',CASE WHEN terms.principal_direction=-1 THEN native->'id' END,'dispatchId',other->'id','feeId',fee);
 ELSIF action='return' THEN
  PERFORM trading.gas_park_loan_keys(body,ARRAY['expectedVersion','businessKey','evidenceId','lotId','reservationId','quantity','effectiveAt'],ARRAY['lotId','reservationId']);
  effective=trading.gas_owned_at(body->>'effectiveAt');quantity=trading.gas_owned_quantity(body->>'quantity');
  SELECT coalesce(sum(r.quantity),0) INTO returned FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.trade_id)=(catalog,trade);
  IF EXISTS(SELECT 1 FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.trade_id,r.business_key)=(catalog,trade,body->>'businessKey'))
  THEN RAISE EXCEPTION 'gas_park_loan_correction_required';END IF;
  IF advance.trade_id IS NULL OR effective<=advance.effective_at OR effective>as_of OR quantity<=0 OR returned+quantity>binding.quantity
  THEN RAISE EXCEPTION 'gas_park_loan_return';END IF;
  IF terms.principal_direction=1 THEN
   native=trading.apply_park_loan_native(catalog,md5(operation::text||':repay')::uuid,binding.owned_account_id,'repay',jsonb_build_object(
    'loanId',advance.loan_id,'lotId',body->'lotId','evidenceId',body->'evidenceId','quantity',body->'quantity','reservationId',body->'reservationId','effectiveAt',body->'effectiveAt'),as_of,context);
  ELSE
   IF body->>'lotId' IS NOT NULL OR body->>'reservationId' IS NOT NULL THEN RAISE EXCEPTION 'gas_park_loan_input';END IF;
   native=trading.apply_park_loan_native(catalog,md5(operation::text||':settle')::uuid,binding.claim_account_id,'operator_settle',jsonb_build_object(
    'positionId',advance.claim_id,'quantity',body->'quantity','ownedAccountId',binding.owned_account_id,'lotId',NULL,'reservationId',NULL,
    'evidenceId',body->'evidenceId','effectiveAt',body->'effectiveAt','availableAt',body->'effectiveAt','sourceObservationId',NULL),as_of,context);
  END IF;
  SELECT coalesce(max(publication_order),0)+1 INTO publication FROM trading.publications WHERE catalog_id=catalog;
  INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());id=gen_random_uuid();
  INSERT INTO trading.gas_park_loan_returns VALUES(catalog,id,trade,body->>'businessKey',CASE WHEN terms.principal_direction=1 THEN(native->>'id')::uuid END,
   CASE WHEN terms.principal_direction=-1 THEN(native->>'id')::uuid END,quantity,(body->>'evidenceId')::uuid,actor,publication,effective);
  outcome=jsonb_build_object('id',id,'quantity',trim_scale(quantity)::text,'outstandingPrincipal',trim_scale(binding.quantity-returned-quantity)::text);
 ELSE
  PERFORM trading.gas_park_loan_keys(body,ARRAY['expectedVersion','feeId','businessKey','expectedRevision','paidAt','amount','evidence'],ARRAY[]::text[]);
  IF advance.fee_id IS NULL OR(body->>'feeId')::uuid IS DISTINCT FROM advance.fee_id THEN RAISE EXCEPTION 'gas_park_loan_fee';END IF;
  native=trading.apply_park_loan_native(catalog,md5(operation::text||':payment')::uuid,
   CASE WHEN terms.principal_direction=1 THEN binding.owned_account_id ELSE binding.claim_account_id END,'fee_payment',body-'expectedVersion',as_of,context);
  IF jsonb_typeof(native->'changed') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'gas_park_loan_fee';END IF;
  outcome=native;
 END IF;
 outcome=outcome||jsonb_build_object('operationId',operation,'tradeId',trade,'action',action,'changed',CASE WHEN action='fee_payment' THEN(native->>'changed')::boolean ELSE true END);
 INSERT INTO trading.gas_park_loan_commands VALUES(catalog,operation,trade,actor,canonical,outcome,deadline);
 SET CONSTRAINTS ALL IMMEDIATE;
 PERFORM security.require_gas_owned_write(catalog,false,deadline);RETURN outcome;
END$$;

-- A service return cannot bypass its explicit native allocation. The same seal
-- protects both the guarded producer and an incomplete privileged write.
CREATE FUNCTION trading.check_gas_park_loan_integrity() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE catalog uuid=NEW.catalog_id;BEGIN
 IF EXISTS(SELECT 1 FROM trading.gas_park_loan_trades t JOIN trading.gas_park_loan_instruments i ON(i.catalog_id,i.instrument_id)=(t.catalog_id,t.instrument_id)
  JOIN trading.trades parent ON(parent.catalog_id,parent.id)=(t.catalog_id,t.trade_id)
  JOIN trading.gas_owned_accounts o ON(o.catalog_id,o.id)=(t.catalog_id,t.owned_account_id)
  LEFT JOIN trading.gas_owned_accounts c ON(c.catalog_id,c.id)=(t.catalog_id,t.claim_account_id)
  WHERE t.catalog_id=catalog AND((parent.book_id,parent.operation_id,parent.actor_id,parent.publication_order,parent.effective_at)
   IS DISTINCT FROM(t.book_id,t.operation_id,t.actor_id,t.publication_order,t.effective_at) OR o.kind<>'owned_inventory' OR(o.book_id,o.legal_entity_id,o.legal_entity_revision,o.definition_revision_id,o.reference_catalog_id,
    o.reference_revision_id,o.quantity_code,o.location_code,o.currency_code,o.mark_curve_code,o.mark_contract_id)
   IS DISTINCT FROM(t.book_id,t.legal_entity_id,t.legal_entity_revision,i.definition_revision_id,i.reference_catalog_id,i.reference_revision_id,i.quantity_code,i.location_code,i.currency_code,i.mark_curve_code,i.mark_contract_id)
   OR(i.principal_direction=1)<>(c.id IS NULL) OR i.principal_direction=-1 AND(c.kind<>'operator_balance' OR
    (c.book_id,c.legal_entity_id,c.legal_entity_revision,c.reference_catalog_id,c.reference_revision_id,c.quantity_code,c.location_code,c.currency_code,c.definition_revision_id,c.mark_curve_code,c.mark_contract_id,c.counterparty_id,c.counterparty_revision)
    IS DISTINCT FROM(o.book_id,o.legal_entity_id,o.legal_entity_revision,o.reference_catalog_id,o.reference_revision_id,o.quantity_code,o.location_code,o.currency_code,o.definition_revision_id,o.mark_curve_code,o.mark_contract_id,t.counterparty_id,t.counterparty_revision))))
 THEN RAISE EXCEPTION 'gas_park_loan_account';END IF;
 IF EXISTS(SELECT 1 FROM trading.gas_park_loan_advances a JOIN trading.gas_park_loan_trades t ON(t.catalog_id,t.trade_id)=(a.catalog_id,a.trade_id)
  JOIN trading.gas_park_loan_instruments i ON(i.catalog_id,i.instrument_id)=(t.catalog_id,t.instrument_id)
  LEFT JOIN trading.gas_owned_loans l ON(l.catalog_id,l.id)=(a.catalog_id,a.loan_id)
  LEFT JOIN trading.gas_owned_positions borrowed ON(borrowed.catalog_id,borrowed.id)=(a.catalog_id,a.stock_id)
  LEFT JOIN trading.gas_owned_positions debt ON(debt.catalog_id,debt.id)=(a.catalog_id,a.return_id)
  LEFT JOIN trading.gas_owned_positions c ON(c.catalog_id,c.id)=(a.catalog_id,a.claim_id)
  LEFT JOIN trading.gas_owned_consumptions d ON(d.catalog_id,d.id)=(a.catalog_id,a.dispatch_id)
  LEFT JOIN trading.gas_owned_positions stock ON(stock.catalog_id,stock.id)=(d.catalog_id,d.lot_id)
  LEFT JOIN trading.gas_owned_fees f ON(f.catalog_id,f.id)=(a.catalog_id,a.fee_id)
  WHERE a.catalog_id=catalog AND(a.effective_at<i.advance_at OR a.effective_at>=i.return_at OR
   i.principal_direction=1 AND(l.id IS NULL OR(l.account_id,l.received_lot_id,l.return_position_id,l.quantity,l.return_at,l.lender_id,l.lender_revision,borrowed.evidence_id,debt.evidence_id,borrowed.effective_at,debt.effective_at)
    IS DISTINCT FROM(t.owned_account_id,a.stock_id,a.return_id,t.quantity,i.return_at,t.counterparty_id,t.counterparty_revision,a.evidence_id,a.agreement_evidence_id,a.effective_at,a.effective_at)) OR
   i.principal_direction=-1 AND(c.id IS NULL OR c.kind<>'operator_claim' OR c.settlement_mode<>'return_quantity_v1'
    OR(c.account_id,c.quantity,c.effective_at,c.due_at,c.evidence_id,d.quantity,d.effective_at,d.evidence_id,stock.account_id)
    IS DISTINCT FROM(t.claim_account_id,t.quantity,a.effective_at,i.return_at,a.claim_evidence_id,t.quantity,a.effective_at,a.evidence_id,t.owned_account_id)) OR
   (i.fixed_fee_amount=0)<>(f.id IS NULL) OR f.id IS NOT NULL AND(f.position_id,f.loan_id,f.amount,f.reference_catalog_id,f.reference_revision_id,f.currency_code,f.due_at,f.effective_at)
    IS DISTINCT FROM(coalesce(a.return_id,a.claim_id),NULL::uuid,i.fixed_fee_amount,i.reference_catalog_id,i.reference_revision_id,i.currency_code,i.fee_due_at,a.effective_at)))
 THEN RAISE EXCEPTION 'gas_park_loan_counterpart';END IF;
 IF EXISTS(SELECT 1 FROM trading.gas_park_loan_returns r JOIN trading.gas_park_loan_advances a ON(a.catalog_id,a.trade_id)=(r.catalog_id,r.trade_id)
  LEFT JOIN trading.gas_owned_repayments p ON(p.catalog_id,p.id)=(r.catalog_id,r.repayment_id)
  LEFT JOIN trading.gas_owned_consumptions c ON(c.catalog_id,c.id)=(p.catalog_id,p.consumption_id)
  LEFT JOIN trading.gas_owned_claim_settlements s ON(s.catalog_id,s.id)=(r.catalog_id,r.settlement_id)
  WHERE r.catalog_id=catalog AND(r.effective_at<=a.effective_at OR r.repayment_id IS NOT NULL AND
    (p.loan_id,c.quantity,c.evidence_id,c.effective_at) IS DISTINCT FROM(a.loan_id,r.quantity,r.evidence_id,r.effective_at)
   OR r.settlement_id IS NOT NULL AND(s.position_id,s.quantity,s.evidence_id,s.effective_at) IS DISTINCT FROM(a.claim_id,r.quantity,r.evidence_id,r.effective_at)))
  OR EXISTS(SELECT 1 FROM trading.gas_owned_repayments p JOIN trading.gas_park_loan_advances a ON(a.catalog_id,a.loan_id)=(p.catalog_id,p.loan_id)
   WHERE p.catalog_id=catalog AND NOT EXISTS(SELECT 1 FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.repayment_id,r.trade_id)=(p.catalog_id,p.id,a.trade_id)))
  OR EXISTS(SELECT 1 FROM trading.gas_owned_claim_settlements s JOIN trading.gas_park_loan_advances a ON(a.catalog_id,a.claim_id)=(s.catalog_id,s.position_id)
   WHERE s.catalog_id=catalog AND NOT EXISTS(SELECT 1 FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.settlement_id,r.trade_id)=(s.catalog_id,s.id,a.trade_id)))
  OR EXISTS(SELECT 1 FROM trading.gas_park_loan_trades t JOIN trading.gas_park_loan_returns r ON(r.catalog_id,r.trade_id)=(t.catalog_id,t.trade_id)
   WHERE t.catalog_id=catalog GROUP BY t.trade_id,t.quantity HAVING sum(r.quantity)>t.quantity)
 THEN RAISE EXCEPTION 'gas_park_loan_counterpart';END IF;
 IF TG_TABLE_NAME='gas_park_loan_commands' THEN PERFORM security.require_gas_owned_write(catalog,false,NEW.authority_until);END IF;
 RETURN NULL;
END$$;

CREATE FUNCTION trading.guard_gas_park_loan_correction() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE linked boolean=false;BEGIN
 IF NEW.revision=1 THEN RETURN NEW;END IF;
 CASE TG_TABLE_NAME
 WHEN 'gas_owned_loan_quantities','gas_loan_fee_terms' THEN
  SELECT EXISTS(SELECT 1 FROM trading.gas_park_loan_advances a WHERE(a.catalog_id,a.loan_id)=(NEW.catalog_id,NEW.loan_id)) INTO linked;
 WHEN 'gas_owned_position_quantities' THEN
  SELECT EXISTS(SELECT 1 FROM trading.gas_park_loan_advances a WHERE a.catalog_id=NEW.catalog_id AND NEW.position_id IN(a.stock_id,a.return_id,a.claim_id))
   OR EXISTS(SELECT 1 FROM trading.gas_park_loan_returns r JOIN trading.gas_owned_claim_settlements s ON(s.catalog_id,s.id)=(r.catalog_id,r.settlement_id)
    WHERE r.catalog_id=NEW.catalog_id AND s.receipt_lot_id=NEW.position_id) INTO linked;
 WHEN 'gas_owned_consumption_quantities' THEN
  SELECT EXISTS(SELECT 1 FROM trading.gas_park_loan_advances a WHERE(a.catalog_id,a.dispatch_id)=(NEW.catalog_id,NEW.consumption_id))
   OR EXISTS(SELECT 1 FROM trading.gas_park_loan_returns r JOIN trading.gas_owned_repayments p ON(p.catalog_id,p.id)=(r.catalog_id,r.repayment_id)
    WHERE(r.catalog_id,p.consumption_id)=(NEW.catalog_id,NEW.consumption_id)) INTO linked;
 WHEN 'gas_operator_settlement_quantities' THEN
  SELECT EXISTS(SELECT 1 FROM trading.gas_park_loan_returns r WHERE(r.catalog_id,r.settlement_id)=(NEW.catalog_id,NEW.settlement_id)) INTO linked;
 END CASE;
 IF linked THEN RAISE EXCEPTION 'gas_park_loan_correction_required';END IF;RETURN NEW;
END$$;

DO $$DECLARE name text;BEGIN
 FOREACH name IN ARRAY ARRAY['gas_park_loan_trades','gas_park_loan_advances','gas_park_loan_returns','gas_park_loan_commands','gas_owned_repayments','gas_owned_claim_settlements'] LOOP
  EXECUTE format('CREATE CONSTRAINT TRIGGER gas_park_loan_integrity AFTER INSERT ON trading.%I DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trading.check_gas_park_loan_integrity()',name);
 END LOOP;
 FOREACH name IN ARRAY ARRAY['gas_owned_loan_quantities','gas_loan_fee_terms','gas_owned_position_quantities','gas_owned_consumption_quantities','gas_operator_settlement_quantities'] LOOP
  EXECUTE format('CREATE TRIGGER gas_park_loan_correction BEFORE INSERT ON trading.%I FOR EACH ROW EXECUTE FUNCTION trading.guard_gas_park_loan_correction()',name);
 END LOOP;
END$$;

CREATE FUNCTION security.gas_park_loan_booking_status(catalog uuid,operation uuid) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;actor uuid;binding trading.gas_park_loan_trades;terms trading.gas_park_loan_instruments;BEGIN
 deadline=security.gas_park_loan_authority(catalog,false);
 SELECT actor_id INTO STRICT actor FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 SELECT * INTO binding FROM trading.gas_park_loan_trades t WHERE(t.catalog_id,t.operation_id,t.actor_id)=(catalog,operation,actor);
 IF binding.trade_id IS NULL THEN RETURN jsonb_build_object('found',false);END IF;
 SELECT * INTO STRICT terms FROM trading.gas_park_loan_instruments i WHERE(i.catalog_id,i.instrument_id)=(catalog,binding.instrument_id);
 IF security.reference_version_visible(terms.reference_catalog_id,terms.reference_revision_id) IS NOT TRUE OR security.market_fact_visible(catalog,terms.definition_revision_id,NULL) IS NOT TRUE
 THEN RAISE EXCEPTION 'gas_owned_denied' USING ERRCODE='42501';END IF;
 PERFORM security.require_gas_owned_preview(catalog,deadline);
 RETURN jsonb_build_object('found',true,'request',(SELECT request FROM trading.trades WHERE(catalog_id,id)=(catalog,binding.trade_id)),
  'outcome',jsonb_build_object('tradeId',binding.trade_id,'instrumentId',binding.instrument_id,'revision',1,'operationId',operation));
END$$;

CREATE FUNCTION security.gas_park_loan_directory(catalog uuid,context uuid,as_of timestamptz,books uuid[],portfolios uuid[],trades uuid[]) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;result jsonb;BEGIN
 deadline=security.gas_park_loan_authority(catalog,false);
 PERFORM security.require_gas_park_loan_worker_scope(catalog,context,as_of,books,trades,NULL);
 IF pg_has_role(session_user,'openetrm_risk_worker','MEMBER') AND cardinality(portfolios)<>0 THEN RAISE EXCEPTION 'risk_job_scope' USING ERRCODE='42501';END IF;
 PERFORM security.require_gas_owned_read(catalog,context,as_of,deadline);
 IF books IS NULL OR portfolios IS NULL OR trades IS NULL OR cardinality(books)>128 OR cardinality(portfolios)>128 OR cardinality(trades)>4096
  OR EXISTS(SELECT 1 FROM unnest(books)b WHERE b IS NULL) OR EXISTS(SELECT 1 FROM unnest(portfolios)p WHERE p IS NULL)
  OR EXISTS(SELECT 1 FROM unnest(trades)t WHERE t IS NULL)
 THEN RAISE EXCEPTION 'gas_park_loan_scope';END IF;
 IF(SELECT count(*) FROM trading.gas_park_loan_trades t JOIN trading.books b ON(b.catalog_id,b.id)=(t.catalog_id,t.book_id)
  WHERE t.catalog_id=catalog AND(cardinality(books)=0 OR t.book_id=ANY(books)) AND(cardinality(portfolios)=0 OR b.portfolio_id=ANY(portfolios))
   AND(cardinality(trades)=0 OR t.trade_id=ANY(trades))
   AND trading.gas_owned_visible(catalog,t.publication_order,t.effective_at,context,as_of))>256
 THEN RAISE EXCEPTION 'gas_park_loan_scope';END IF;
 SELECT coalesce(jsonb_agg(security.read_gas_park_loan(catalog,t.trade_id,context,as_of) ORDER BY t.trade_id),'[]') INTO result
  FROM trading.gas_park_loan_trades t JOIN trading.books b ON(b.catalog_id,b.id)=(t.catalog_id,t.book_id)
  WHERE t.catalog_id=catalog AND(cardinality(books)=0 OR t.book_id=ANY(books)) AND(cardinality(portfolios)=0 OR b.portfolio_id=ANY(portfolios))
   AND(cardinality(trades)=0 OR t.trade_id=ANY(trades))
   AND trading.gas_owned_visible(catalog,t.publication_order,t.effective_at,context,as_of);
 PERFORM security.require_gas_owned_read(catalog,context,as_of,deadline);RETURN result;
END$$;

CREATE FUNCTION security.gas_park_loan_directory(catalog uuid,context uuid,as_of timestamptz,books uuid[],portfolios uuid[]) RETURNS jsonb
 LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.gas_park_loan_directory(catalog,context,as_of,books,portfolios,ARRAY[]::uuid[]);
$$;

CREATE FUNCTION security.gas_park_loan_directory(catalog uuid,context uuid,as_of timestamptz) RETURNS jsonb
 LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.gas_park_loan_directory(catalog,context,as_of,ARRAY[]::uuid[],ARRAY[]::uuid[]);
$$;

-- An immutable existence read keeps its original current authority without
-- claiming the command's single admitted source or retaining a temporary bind.
CREATE FUNCTION security.require_gas_park_loan_presence(catalog uuid,context uuid,as_of timestamptz,books uuid[],trades uuid[],until_at timestamptz) RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM settlement_data.require_futures_margin_preview(catalog,until_at);
 PERFORM security.require_trading_history(catalog,context);
 PERFORM security.require_gas_park_loan_worker_scope(catalog,context,as_of,books,trades,NULL);
 IF books IS NULL OR cardinality(books) NOT BETWEEN 1 AND 128 OR trades IS NULL OR cardinality(trades)>4096
  OR EXISTS(SELECT 1 FROM unnest(trades)t WHERE t IS NULL)
  OR '00000000-0000-0000-0000-000000000000'::uuid=ANY(books)
  OR '00000000-0000-0000-0000-000000000000'::uuid=ANY(trades)
  OR(SELECT count(DISTINCT b) FROM unnest(books)b)<>cardinality(books)
  OR(SELECT count(DISTINCT t) FROM unnest(trades)t)<>cardinality(trades)
  OR security.trading_context_day_matches(catalog,context,as_of) IS NOT TRUE
  OR NOT EXISTS(SELECT 1 FROM market_data.temporal_contexts t JOIN trading.contexts x ON(x.catalog_id,x.context_id)=(t.catalog_id,t.id)
   WHERE(t.catalog_id,t.id)=(catalog,context))
  OR EXISTS(SELECT 1 FROM unnest(books)b WHERE b IS NULL OR NOT EXISTS(SELECT 1 FROM trading.books k WHERE(k.catalog_id,k.id)=(catalog,b)
   AND trading.gas_owned_visible(catalog,k.publication_order,k.effective_at,context,as_of)))
 THEN RAISE EXCEPTION 'gas_park_loan_scope';END IF;
 PERFORM settlement_data.require_futures_margin_preview(catalog,until_at);
END$$;

CREATE FUNCTION security.require_gas_park_loan_scope(catalog uuid,context uuid,as_of timestamptz,books uuid[],trades uuid[]) RETURNS boolean
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;present boolean;BEGIN
 deadline=least(security.authority_until('ReadMarketData'),security.authority_until('ReadTrades'));
 PERFORM security.require_gas_park_loan_worker_scope(catalog,context,as_of,books,trades,NULL);
 PERFORM settlement_data.require_futures_margin_read(catalog,context,as_of,deadline);
 IF books IS NULL OR trades IS NULL OR cardinality(books)>128 OR cardinality(trades)>4096
  OR EXISTS(SELECT 1 FROM unnest(books)b WHERE b IS NULL OR NOT EXISTS(SELECT 1 FROM trading.books k WHERE(k.catalog_id,k.id)=(catalog,b)
   AND trading.gas_owned_visible(catalog,k.publication_order,k.effective_at,context,as_of)))
  OR EXISTS(SELECT 1 FROM unnest(trades)t WHERE t IS NULL)
 THEN RAISE EXCEPTION 'gas_park_loan_scope';END IF;
 SELECT EXISTS(SELECT 1 FROM trading.gas_park_loan_trades t WHERE t.catalog_id=catalog AND(cardinality(books)=0 OR t.book_id=ANY(books))
  AND(cardinality(trades)=0 OR t.trade_id=ANY(trades)) AND trading.gas_owned_visible(catalog,t.publication_order,t.effective_at,context,as_of)) INTO present;
 PERFORM settlement_data.require_futures_margin_read(catalog,context,as_of,deadline);RETURN present;
END$$;

CREATE FUNCTION security.gas_park_loan_trade_head(catalog uuid,trade uuid) RETURNS boolean
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;present boolean;job risk.jobs;BEGIN
 IF pg_has_role(session_user,'openetrm_risk_worker','MEMBER') THEN
  job=risk.bound_lifecycle_reader();
  PERFORM security.require_gas_park_loan_worker_scope(catalog,job.context_id,job.valuation_at,NULL,NULL,trade);
 END IF;
 deadline=least(security.authority_until('ReadMarketData'),security.authority_until('ReadTrades'));
 IF security.trading_access(catalog,'ReadTrades') IS NOT TRUE OR deadline IS NULL OR clock_timestamp()>=deadline
 THEN RAISE EXCEPTION 'gas_park_loan_denied' USING ERRCODE='42501';END IF;
 SELECT EXISTS(SELECT 1 FROM trading.gas_park_loan_trades t WHERE(t.catalog_id,t.trade_id)=(catalog,trade)
  AND security.trading_visible(catalog,t.publication_order,t.effective_at)) INTO present;
 IF security.trading_access(catalog,'ReadTrades') IS NOT TRUE OR clock_timestamp()>=deadline
 THEN RAISE EXCEPTION 'gas_park_loan_denied' USING ERRCODE='42501';END IF;RETURN present;
END$$;

-- Risk selection needs only the certified product identity, never service terms
-- or native balances. The worker remains bound to its original exact selector.
CREATE FUNCTION security.risk_gas_park_loan_trade_heads(catalog uuid,books uuid[],trades uuid[]) RETURNS SETOF jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE context uuid;as_of timestamptz;deadline timestamptz;result jsonb;BEGIN
 PERFORM risk.require_worker_attempt();
 deadline=least(security.authority_until('ReadMarketData'),security.authority_until('ReadTrades'));
 IF security.trading_access(catalog,'ReadTrades') IS NOT TRUE OR security.market_access(catalog,'ReadMarketData') IS NOT TRUE
  OR deadline IS NULL OR clock_timestamp()>=deadline
 THEN RAISE EXCEPTION 'gas_park_loan_denied' USING ERRCODE='42501';END IF;
 IF books IS NULL OR cardinality(books) NOT BETWEEN 1 AND 128 OR array_position(books,NULL) IS NOT NULL
  OR(SELECT count(DISTINCT b) FROM unnest(books)b)<>cardinality(books)
  OR trades IS NOT NULL AND(cardinality(trades) NOT BETWEEN 1 AND 256 OR array_position(trades,NULL) IS NOT NULL
   OR '00000000-0000-0000-0000-000000000000'::uuid=ANY(trades) OR(SELECT count(DISTINCT t) FROM unnest(trades)t)<>cardinality(trades))
 THEN RAISE EXCEPTION 'risk_trade_scope';END IF;
 SELECT c.market_context_id,c.trading_as_of INTO context,as_of FROM security.request_contexts c
  WHERE c.market_catalog_id=catalog AND c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned()
   AND c.runtime_login=session_user;
 IF context IS NULL OR as_of IS NULL THEN RAISE EXCEPTION 'knowledge_coverage';END IF;
 PERFORM security.require_gas_park_loan_worker_scope(catalog,context,as_of,books,coalesce(trades,ARRAY[]::uuid[]),NULL);
 PERFORM settlement_data.require_futures_margin_read(catalog,context,as_of,deadline);
 SELECT coalesce(jsonb_agg(jsonb_build_object('trade_id',t.trade_id,'book_id',t.book_id,'revision',t.revision) ORDER BY t.trade_id),'[]'::jsonb)
  INTO result FROM trading.gas_park_loan_trades t JOIN trading.books b ON(b.catalog_id,b.id)=(t.catalog_id,t.book_id)
  JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id)
  WHERE t.catalog_id=catalog AND t.book_id=ANY(books) AND(trades IS NULL OR t.trade_id=ANY(trades))
   AND trading.gas_owned_visible(catalog,t.publication_order,t.effective_at,context,as_of)
   AND trading.gas_owned_visible(catalog,b.publication_order,b.effective_at,context,as_of)
   AND trading.gas_owned_visible(catalog,p.publication_order,p.effective_at,context,as_of);
 PERFORM settlement_data.require_futures_margin_read(catalog,context,as_of,deadline);
 PERFORM risk.require_worker_attempt();RETURN QUERY SELECT value FROM jsonb_array_elements(result);
END$$;

-- An actual opening read cannot prove the absence of a source-known future
-- service birth. Event projection uses this separate knowledge-only fence.
CREATE FUNCTION security.gas_park_loan_projection_fence(catalog uuid,context uuid,opening_at timestamptz,horizon_at timestamptz,books uuid[],trades uuid[]) RETURNS boolean
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;present boolean;BEGIN
 deadline=least(security.authority_until('ReadMarketData'),security.authority_until('ReadTrades'));
 PERFORM security.require_gas_park_loan_worker_scope(catalog,context,opening_at,books,trades,NULL);
 PERFORM settlement_data.require_futures_margin_read(catalog,context,opening_at,deadline);
 IF horizon_at IS NULL OR NOT isfinite(horizon_at) OR horizon_at<opening_at OR books IS NULL OR trades IS NULL OR cardinality(books)>128 OR cardinality(trades)>4096
  OR EXISTS(SELECT 1 FROM unnest(trades)t WHERE t IS NULL)
  OR EXISTS(SELECT 1 FROM unnest(books)b WHERE b IS NULL OR NOT EXISTS(SELECT 1 FROM trading.books k WHERE(k.catalog_id,k.id)=(catalog,b)
   AND trading.gas_owned_visible(catalog,k.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00Z',context,opening_at)))
 THEN RAISE EXCEPTION 'gas_park_loan_scope';END IF;
 SELECT EXISTS(SELECT 1 FROM trading.gas_park_loan_trades t WHERE t.catalog_id=catalog AND(cardinality(books)=0 OR t.book_id=ANY(books))
  AND(cardinality(trades)=0 OR t.trade_id=ANY(trades))
  AND t.effective_at<=horizon_at AND trading.gas_owned_visible(catalog,t.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00Z',context,opening_at)
  AND NOT EXISTS(SELECT 1 FROM trading.gas_park_loan_advances a WHERE(a.catalog_id,a.trade_id)=(t.catalog_id,t.trade_id) AND a.effective_at<=opening_at
   AND trading.gas_owned_visible(catalog,a.publication_order,TIMESTAMPTZ '0001-01-01 00:00:00Z',context,opening_at))) INTO present;
 PERFORM settlement_data.require_futures_margin_read(catalog,context,opening_at,deadline);RETURN present;
END$$;

CREATE FUNCTION security.gas_park_loan_projection_fence(catalog uuid,context uuid,opening_at timestamptz,horizon_at timestamptz,books uuid[]) RETURNS boolean
 LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.gas_park_loan_projection_fence(catalog,context,opening_at,horizon_at,books,ARRAY[]::uuid[]);
$$;

DO $guard$DECLARE p pg_proc;BEGIN
 SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure('risk.needs_gas(risk.jobs)');
 IF NOT FOUND OR md5(p.prosrc)<>'742f6b564803ed5b5d20fba7464b510b' OR p.proowner<>'openetrm_security_owner'::regrole
  OR p.prorettype<>'boolean'::regtype OR p.proretset OR p.prokind<>'f' OR p.proisstrict OR p.proleakproof
  OR NOT p.prosecdef OR p.provolatile<>'v' OR p.proparallel<>'u' OR p.provariadic<>0
  OR p.proargnames IS DISTINCT FROM ARRAY['job'] OR p.proargmodes IS NOT NULL OR p.proallargtypes IS NOT NULL
  OR p.pronargdefaults<>0 OR p.proargdefaults IS NOT NULL OR(SELECT lanname FROM pg_language WHERE oid=p.prolang)<>'plpgsql'
  OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
  OR p.proacl::text IS DISTINCT FROM '{openetrm_security_owner=X/openetrm_security_owner}'
  OR to_regprocedure('risk.needs_gas_pre_park_loan(risk.jobs)') IS NOT NULL
 THEN RAISE EXCEPTION 'gas_park_loan_upgrade: unexpected gas worker classifier';END IF;
 EXECUTE replace(pg_get_functiondef(p.oid),'FUNCTION risk.needs_gas(','FUNCTION risk.needs_gas_pre_park_loan(');
END$guard$;
ALTER FUNCTION risk.needs_gas_pre_park_loan(risk.jobs) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION risk.needs_gas_pre_park_loan(risk.jobs) FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;
CREATE OR REPLACE FUNCTION risk.needs_gas(job risk.jobs) RETURNS boolean
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF risk.needs_gas_pre_park_loan(job) THEN RETURN true;END IF;
 RETURN EXISTS(WITH cut AS(SELECT x.known_through,t.known_at FROM market_data.temporal_contexts t
  JOIN trading.contexts x ON(x.catalog_id,x.context_id)=(t.catalog_id,t.id) WHERE(t.catalog_id,t.id)=(job.catalog_id,job.context_id))
  SELECT 1 FROM trading.gas_park_loan_trades s JOIN trading.knowledge_receipts k ON(k.catalog_id,k.publication_order)=(s.catalog_id,s.publication_order)
  CROSS JOIN cut WHERE s.catalog_id=job.catalog_id AND s.publication_order<=cut.known_through AND k.known_from<=cut.known_at
   AND s.effective_at<=job.valuation_at AND job.request->'bookIds' @> jsonb_build_array(s.book_id)
   AND(NULLIF(job.request->'tradeIds','null'::jsonb) IS NULL OR job.request->'tradeIds' @> jsonb_build_array(s.trade_id)));
END$$;
ALTER FUNCTION risk.needs_gas(risk.jobs) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION risk.needs_gas(risk.jobs) FROM PUBLIC,openetrm_runtime,openetrm_risk_worker;

DO $$DECLARE signature regprocedure;BEGIN
 FOR signature IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE(n.nspname='security' AND p.proname IN('gas_park_loan_authority','book_gas_park_loan','read_gas_park_loan','record_gas_park_loan','gas_park_loan_directory','gas_park_loan_booking_status','require_gas_park_loan_scope','require_gas_park_loan_presence','gas_park_loan_command_receipt','gas_park_loan_trade_head','gas_park_loan_projection_fence','require_gas_park_loan_worker_scope','risk_gas_park_loan_trade_heads'))
   OR(n.nspname='trading' AND p.proname IN('apply_park_loan_native','gas_park_loan_keys','gas_park_loan_fact','check_gas_park_loan_integrity','guard_gas_park_loan_correction')) LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',signature);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION security.book_gas_park_loan(uuid,jsonb,timestamptz),security.read_gas_park_loan(uuid,uuid,uuid,timestamptz),
 security.record_gas_park_loan(uuid,uuid,uuid,text,jsonb,timestamptz,uuid,boolean),security.gas_park_loan_directory(uuid,uuid,timestamptz),
 security.gas_park_loan_directory(uuid,uuid,timestamptz,uuid[],uuid[]),security.gas_park_loan_booking_status(uuid,uuid),
 security.gas_park_loan_directory(uuid,uuid,timestamptz,uuid[],uuid[],uuid[]),
 security.require_gas_park_loan_scope(uuid,uuid,timestamptz,uuid[],uuid[]),
 security.gas_park_loan_command_receipt(uuid,uuid,uuid,text,jsonb,timestamptz,uuid),security.gas_park_loan_authority(uuid,boolean),
 security.gas_park_loan_trade_head(uuid,uuid),security.gas_park_loan_projection_fence(uuid,uuid,timestamptz,timestamptz,uuid[]),
 security.gas_park_loan_projection_fence(uuid,uuid,timestamptz,timestamptz,uuid[],uuid[]) TO openetrm_runtime;
-- These probes are part of the common retained portfolio boundary even when
-- the selected books contain no service. They disclose no gas terms or balances.
GRANT EXECUTE ON FUNCTION security.require_gas_park_loan_scope(uuid,uuid,timestamptz,uuid[],uuid[]),
 security.gas_park_loan_trade_head(uuid,uuid),security.gas_park_loan_projection_fence(uuid,uuid,timestamptz,timestamptz,uuid[]),
 security.gas_park_loan_projection_fence(uuid,uuid,timestamptz,timestamptz,uuid[],uuid[]) TO openetrm_risk_worker;
GRANT EXECUTE ON FUNCTION security.read_gas_park_loan(uuid,uuid,uuid,timestamptz),
 security.gas_park_loan_directory(uuid,uuid,timestamptz),security.gas_park_loan_directory(uuid,uuid,timestamptz,uuid[],uuid[]),
 security.gas_park_loan_directory(uuid,uuid,timestamptz,uuid[],uuid[],uuid[]),security.gas_park_loan_authority(uuid,boolean) TO openetrm_risk_worker;
GRANT EXECUTE ON FUNCTION security.risk_gas_park_loan_trade_heads(uuid,uuid[],uuid[]) TO openetrm_runtime,openetrm_risk_worker;
GRANT EXECUTE ON FUNCTION security.require_gas_park_loan_presence(uuid,uuid,timestamptz,uuid[],uuid[],timestamptz) TO openetrm_runtime,openetrm_risk_worker;
-- The installed entry page shares the ordinary immutable prompt contract.
DO $prompt_page$
DECLARE definition text;before text='''blotter_new_gas''';BEGIN
 SELECT pg_get_functiondef(p.oid) INTO STRICT definition FROM pg_proc p
 WHERE p.oid='assistant.is_prompt_page(text)'::regprocedure
  AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='23f84ecb327ed0d2c0fe02c7c5dd76d7c90c9a06d742747fc533a0ad3a882a59'
  AND pg_get_userbyid(p.proowner)='openetrm_security_owner' AND NOT p.prosecdef AND p.provolatile='i'
  AND p.prokind='f' AND p.proparallel='u' AND NOT p.proisstrict AND NOT p.proleakproof AND p.provariadic=0
  AND p.proargmodes IS NULL AND p.proargnames=ARRAY['page'] AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='sql')
  AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.prorettype='boolean'::regtype
  AND p.proacl='{openetrm_security_owner=X/openetrm_security_owner}'::aclitem[];
 IF(length(definition)-length(replace(definition,before,'')))/length(before)<>1 THEN RAISE EXCEPTION 'gas_park_loan_prompt_predecessor';END IF;
 EXECUTE replace(definition,before,before||',''blotter_new_park_loan''');
EXCEPTION WHEN no_data_found THEN RAISE EXCEPTION 'gas_park_loan_prompt_predecessor';
END $prompt_page$;
COMMIT;
