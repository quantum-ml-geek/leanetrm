-- Native producer and certified metadata for the bounded certificate forward.
-- Inventory ownership and fulfillment evidence remain separate operations.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT 1 FROM security.epoch WHERE id=true FOR UPDATE;
SELECT pg_advisory_xact_lock(730849102);

DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['rec_forward_instruments','rec_forward_memberships','rec_forward_trade_revisions','rec_deliveries'] LOOP
  EXECUTE format('CREATE POLICY forward_internal_content ON trading.%I TO openetrm_security_owner USING(true) WITH CHECK(true)',t);
 END LOOP;
END$$;

CREATE TABLE trading.rec_forward_booking_requests(
 catalog_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),operation_id uuid NOT NULL,
 command jsonb NOT NULL,outcome jsonb NOT NULL,
 PRIMARY KEY(catalog_id,actor_id,operation_id),FOREIGN KEY(catalog_id) REFERENCES market_data.catalogs(id)
);
ALTER TABLE trading.rec_forward_booking_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading.rec_forward_booking_requests FORCE ROW LEVEL SECURITY;
CREATE POLICY internal_content ON trading.rec_forward_booking_requests TO openetrm_security_owner USING(true) WITH CHECK(true);
GRANT SELECT,INSERT ON trading.rec_forward_booking_requests TO openetrm_security_owner;
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.rec_forward_booking_requests FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();

CREATE FUNCTION security.rec_forward_scope(catalog uuid,writing boolean) RETURNS uuid
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;BEGIN
 PERFORM 1 FROM security.epoch WHERE id=true FOR SHARE;
 IF security.trading_access(catalog,'ReadTrades') IS NOT TRUE OR security.market_access(catalog,'ReadMarketData') IS NOT TRUE
  OR(writing AND(security.trading_access(catalog,'BookTrade') IS NOT TRUE OR security.current_write_context() IS NOT TRUE))
  OR(pg_has_role(session_user,'openetrm_risk_worker','MEMBER') AND risk.worker_read() IS NOT TRUE)
 THEN RAISE EXCEPTION 'rec_forward_denied' USING ERRCODE='42501';END IF;
 SELECT q.actor_id INTO actor FROM security.request_contexts q WHERE q.backend_pid=pg_backend_pid()
  AND q.transaction_id=pg_current_xact_id_if_assigned() AND q.runtime_login=session_user AND q.expires_at>clock_timestamp();
 IF actor IS NULL THEN RAISE EXCEPTION 'rec_forward_denied' USING ERRCODE='42501';END IF;
 RETURN actor;
END$$;
CREATE FUNCTION security.rec_forward_booking_status(catalog uuid,operation uuid) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;result jsonb;BEGIN
 actor=security.rec_forward_scope(catalog,false);
 SELECT r.outcome INTO result FROM trading.rec_forward_booking_requests r WHERE(r.catalog_id,r.actor_id,r.operation_id)=(catalog,actor,operation);
 PERFORM security.rec_forward_scope(catalog,false);RETURN result;
END$$;
CREATE FUNCTION security.rec_forward_booking_replay(catalog uuid,body jsonb) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;r trading.rec_forward_booking_requests;BEGIN
 actor=security.rec_forward_scope(catalog,false);
 IF body->>'ownerId' IS DISTINCT FROM security.rec_trade_owner(catalog) THEN RAISE EXCEPTION 'rec_owner_changed';END IF;
 SELECT * INTO r FROM trading.rec_forward_booking_requests WHERE(catalog_id,actor_id,operation_id)=(catalog,actor,(body->>'operationId')::uuid);
 IF NOT FOUND THEN RETURN NULL;END IF;
 IF r.command IS DISTINCT FROM body THEN RAISE EXCEPTION 'rec_forward_request_conflict';END IF;
 PERFORM security.rec_forward_scope(catalog,false);RETURN r.outcome;
END$$;

CREATE FUNCTION security.book_rec_forward(catalog uuid,request jsonb,prepared jsonb,at_time timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;operation uuid;trade uuid;instrument uuid;book uuid;t jsonb;price jsonb;policy jsonb;payment jsonb;canonical jsonb;
 prior trading.rec_forward_booking_requests;existing trading.rec_forward_trade_revisions;assignment market_data.rec_valuation_assignments;
 mark ref_data.quote_specifications;quote ref_data.quote_specifications;staged trading.side_schedule_requests;member record;
 from_at timestamptz;to_at timestamptz;vintage_first date;vintage_last date;count_value numeric;fixed numeric;physical integer;cash integer;
 publication integer;outcome jsonb;trade_number integer;instrument_number integer;booking jsonb;
BEGIN
 actor=security.rec_forward_scope(catalog,true);
 IF trading.rec_keys(request,ARRAY['context','operationId','tradeId','ownerId','bookId','tradeDate','legalEntityId','legalEntityRevision','counterpartyId','counterpartyRevision','terms']) IS NOT TRUE
  OR EXISTS(SELECT 1 FROM jsonb_each(request)e WHERE jsonb_typeof(e.value) IS DISTINCT FROM CASE
   WHEN e.key IN('context','terms') THEN 'object' WHEN e.key IN('legalEntityRevision','counterpartyRevision') THEN 'number' ELSE 'string' END)
  OR jsonb_typeof(request->'context') IS DISTINCT FROM 'object' OR request#>>'{context,convention}' IS DISTINCT FROM 'rec_forward_v1'
  OR (request->'context')-ARRAY['snapshotId','convention','knowledgeMode','contextId']<>'{}'::jsonb
  OR NOT(request->'context' ?& ARRAY['snapshotId','convention','knowledgeMode'])
  OR EXISTS(SELECT 1 FROM jsonb_each(request->'context')e WHERE jsonb_typeof(e.value) IS DISTINCT FROM CASE WHEN e.key='contextId' THEN 'null' ELSE 'string' END)
  OR request#>>'{context,knowledgeMode}' IS DISTINCT FROM 'current' OR nullif(request#>>'{context,contextId}','') IS NOT NULL
  OR request->>'legalEntityRevision' !~ '^[1-9][0-9]{0,9}$' OR request->>'counterpartyRevision' !~ '^[1-9][0-9]{0,9}$'
  OR at_time IS NULL OR NOT isfinite(at_time) OR at_time>clock_timestamp()
  OR request->>'tradeDate' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  OR request->>'ownerId' IS DISTINCT FROM security.rec_trade_owner(catalog) OR pg_column_size(request)>32768
 THEN RAISE EXCEPTION 'rec_forward_input';END IF;
 IF(request#>>'{context,snapshotId}')::uuid='00000000-0000-0000-0000-000000000000' THEN RAISE EXCEPTION 'rec_forward_input';END IF;
 operation=(request->>'operationId')::uuid;trade=(request->>'tradeId')::uuid;book=(request->>'bookId')::uuid;
 IF operation IS NULL OR trade IS NULL OR book IS NULL OR operation='00000000-0000-0000-0000-000000000000' OR trade='00000000-0000-0000-0000-000000000000' OR book='00000000-0000-0000-0000-000000000000'
 THEN RAISE EXCEPTION 'rec_forward_input';END IF;
 PERFORM pg_advisory_xact_lock(730849102);PERFORM security.rec_forward_scope(catalog,true);
 SELECT * INTO prior FROM trading.rec_forward_booking_requests WHERE(catalog_id,actor_id,operation_id)=(catalog,actor,operation);
 IF FOUND THEN IF prior.command IS DISTINCT FROM request THEN RAISE EXCEPTION 'rec_forward_request_conflict';END IF;RETURN prior.outcome;END IF;
 IF EXISTS(SELECT 1 FROM trading.trades WHERE(catalog_id,operation_id)=(catalog,operation)) THEN RAISE EXCEPTION 'rec_forward_request_conflict';END IF;
 t=request->'terms';
 IF trading.rec_keys(t,ARRAY['definitionRevisionId','assignmentCode','productCode','vintageFrom','vintageTo','deliveryFrom','deliveryTo','quantity','physicalDirection','considerationDirection','consideration','paymentRule','calendarPolicy','discounting']) IS NOT TRUE
  OR EXISTS(SELECT 1 FROM jsonb_each(t)e WHERE jsonb_typeof(e.value) IS DISTINCT FROM CASE
   WHEN e.key IN('consideration','paymentRule','calendarPolicy') THEN 'object' WHEN e.key='discounting' THEN 'boolean' ELSE 'string' END)
  OR t->'discounting' IS DISTINCT FROM 'false'::jsonb OR t->>'quantity' !~ '^[0-9]+(\.0+)?$' OR length(t->>'quantity')>32
 THEN RAISE EXCEPTION 'rec_forward_input';END IF;
 count_value=(t->>'quantity')::numeric;
 IF count_value IS NULL OR count_value<=0 OR count_value>9223372036854775807 OR count_value<>trunc(count_value) THEN RAISE EXCEPTION 'rec_forward_quantity';END IF;
 IF t->>'deliveryFrom' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00(\.0{1,7})?(Z|\+00:00)$'
  OR t->>'deliveryTo' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00(\.0{1,7})?(Z|\+00:00)$'
  OR t->>'vintageFrom' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR t->>'vintageTo' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
 THEN RAISE EXCEPTION 'rec_forward_input';END IF;
 from_at=(t->>'deliveryFrom')::timestamptz;to_at=(t->>'deliveryTo')::timestamptz;
 vintage_first=(t->>'vintageFrom')::date;vintage_last=(t->>'vintageTo')::date;
 IF from_at<=at_time OR to_at-from_at<>interval '1 day' OR NOT isfinite(from_at) OR NOT isfinite(to_at)
  OR vintage_first>=vintage_last THEN RAISE EXCEPTION 'rec_delivery_lifecycle';END IF;
 physical=CASE t->>'physicalDirection' WHEN 'receive' THEN 1 WHEN 'deliver' THEN -1 END;
 cash=CASE t->>'considerationDirection' WHEN 'receive' THEN 1 WHEN 'pay' THEN -1 END;
 IF physical IS NULL OR cash IS NULL OR cash<>-physical THEN RAISE EXCEPTION 'rec_forward_direction';END IF;
 payment=t->'paymentRule';policy=t->'calendarPolicy';price=t->'consideration';
 IF trading.rec_keys(payment,ARRAY['frequency','rule','days','dayOfMonth','dayBasis','shortMonth','adjustment','calendar','implementation']) IS NOT TRUE
  OR payment->>'frequency' IS DISTINCT FROM 'monthly' OR payment->>'rule' IS DISTINCT FROM 'days_after_period_end'
  OR payment->>'dayBasis' IS DISTINCT FROM 'calendar_days' OR payment->>'adjustment' IS DISTINCT FROM 'unadjusted'
  OR payment->>'implementation' IS DISTINCT FROM 'monthly_payment_date_rules_v1' OR jsonb_typeof(payment->'days') IS DISTINCT FROM 'number'
  OR payment->>'days' !~ '^(0|[1-9][0-9]{0,2})$' OR(payment->>'days')::integer NOT BETWEEN 0 AND 366
  OR payment->'dayOfMonth' IS DISTINCT FROM 'null'::jsonb OR payment->'shortMonth' IS DISTINCT FROM 'null'::jsonb OR payment->'calendar' IS DISTINCT FROM 'null'::jsonb
  OR policy IS DISTINCT FROM '{"implementation":"side_calendar_policy_v1","delivery":{"applicable":false,"calendar":null},"observation":{"applicable":false,"calendar":null},"payment":{"applicable":false,"calendar":null}}'::jsonb
  OR trading.rec_keys(price,ARRAY['mode','quoteCode','fixedPrice','curveCode','contractId']) IS NOT TRUE
  OR jsonb_typeof(price->'mode') IS DISTINCT FROM 'string' OR jsonb_typeof(price->'quoteCode') IS DISTINCT FROM 'string'
 THEN RAISE EXCEPTION 'rec_forward_policy';END IF;
 IF(date_trunc('month',from_at AT TIME ZONE 'UTC')+interval '1 month'-interval '1 day'+make_interval(days=>(payment->>'days')::integer)) AT TIME ZONE 'UTC'<to_at
 THEN RAISE EXCEPTION 'rec_forward_policy';END IF;
 SELECT * INTO assignment FROM market_data.rec_valuation_assignments a
  WHERE(a.catalog_id,a.revision_id,a.code,a.product_code,a.vintage_from,a.vintage_to)=
   (catalog,(t->>'definitionRevisionId')::uuid,t->>'assignmentCode',t->>'productCode',vintage_first,vintage_last);
 IF NOT FOUND OR security.market_fact_visible(catalog,assignment.revision_id,NULL) IS NOT TRUE
  OR security.reference_access(assignment.reference_catalog_id,'ReadMarketData') IS NOT TRUE
  OR security.reference_version_visible(assignment.reference_catalog_id,assignment.reference_revision_id) IS NOT TRUE
 THEN RAISE EXCEPTION 'rec_forward_source' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM market_data.contracts k
  WHERE(k.catalog_id,k.revision_id,k.id)=(catalog,assignment.revision_id,assignment.contract_id)
   AND k.delivery_from<=(from_at AT TIME ZONE 'UTC')::date AND k.delivery_to>=(to_at AT TIME ZONE 'UTC')::date)
 THEN RAISE EXCEPTION 'rec_forward_price';END IF;
 SELECT q.* INTO STRICT mark FROM market_data.curves c JOIN ref_data.quote_specifications q
  ON(q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code)
  WHERE(c.catalog_id,c.revision_id,c.code)=(catalog,assignment.revision_id,assignment.curve_code);
 SELECT q.* INTO quote FROM ref_data.quote_specifications q WHERE(q.catalog_id,q.revision_id,q.code,q.kind,q.quantity_code,q.currency_code)=
  (assignment.reference_catalog_id,assignment.reference_revision_id,price->>'quoteCode','outright',mark.quantity_code,mark.currency_code);
 IF NOT FOUND THEN RAISE EXCEPTION 'rec_forward_price';END IF;
 IF price->>'mode'='fixed' THEN
  IF jsonb_typeof(price->'fixedPrice') IS DISTINCT FROM 'string' OR price->>'fixedPrice' !~ '^-?[0-9]+(\.[0-9]+)?$' OR length(price->>'fixedPrice')>80 OR price->'curveCode' IS DISTINCT FROM 'null'::jsonb OR price->'contractId' IS DISTINCT FROM 'null'::jsonb
  THEN RAISE EXCEPTION 'rec_forward_price';END IF;
  fixed=(price->>'fixedPrice')::numeric;
  IF fixed IS NULL OR abs(fixed)>=1e12 THEN RAISE EXCEPTION 'rec_forward_price';END IF;
 ELSIF price->>'mode'='selected_contract_flat_v1' THEN
  IF jsonb_typeof(price->'curveCode') IS DISTINCT FROM 'string' OR jsonb_typeof(price->'contractId') IS DISTINCT FROM 'string'
  THEN RAISE EXCEPTION 'rec_forward_price';END IF;
  IF price->'fixedPrice' IS DISTINCT FROM 'null'::jsonb OR NOT EXISTS(
   SELECT 1 FROM market_data.curves c JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.curve_code)=(c.catalog_id,c.revision_id,c.code)
   JOIN market_data.contracts k ON(k.catalog_id,k.revision_id,k.id)=(m.catalog_id,m.revision_id,m.contract_id)
   WHERE(c.catalog_id,c.revision_id,c.code,c.quote_code,k.id)=(catalog,assignment.revision_id,price->>'curveCode',quote.code,(price->>'contractId')::uuid)
    AND k.delivery_from<=(from_at AT TIME ZONE 'UTC')::date AND k.delivery_to>=(to_at AT TIME ZONE 'UTC')::date)
  THEN RAISE EXCEPTION 'rec_forward_price';END IF;
 ELSE RAISE EXCEPTION 'rec_forward_price';END IF;
 -- Canonical business value excludes calculation coordinates, retries and owner
 -- presentation tokens. Stable trade identity prevents accidental second trades.
 canonical=jsonb_build_object('bookId',book,'tradeDate',(request->>'tradeDate')::date,'legalEntityId',(request->>'legalEntityId')::uuid,
  'legalEntityRevision',(request->>'legalEntityRevision')::integer,'counterpartyId',(request->>'counterpartyId')::uuid,
  'counterpartyRevision',(request->>'counterpartyRevision')::integer,'terms',trading.operating_canonical_value(t));
 SELECT * INTO existing FROM trading.rec_forward_trade_revisions WHERE(catalog_id,trade_id)=(catalog,trade);
 IF FOUND THEN
  IF existing.actor_id<>actor OR canonical IS DISTINCT FROM(
   SELECT h.terms FROM trading.rec_forward_instruments h WHERE(h.catalog_id,h.instrument_id)=(catalog,existing.instrument_id)) THEN RAISE EXCEPTION 'rec_forward_revision_conflict';END IF;
  SELECT tr.reference_number,ir.reference_number INTO STRICT trade_number,instrument_number FROM trading.trade_references tr
   JOIN trading.instrument_references ir ON(ir.catalog_id,ir.instrument_id)=(tr.catalog_id,existing.instrument_id) WHERE(tr.catalog_id,tr.trade_id)=(catalog,trade);
  outcome=jsonb_build_object('operationId',operation,'tradeId',trade,'revision',1,'instrumentId',existing.instrument_id,
   'tradeReference','TR-'||lpad(trade_number::text,greatest(6,length(trade_number::text)),'0'),'instrumentReference','IN-'||lpad(instrument_number::text,greatest(6,length(instrument_number::text)),'0'),'changed',false);
  INSERT INTO trading.rec_forward_booking_requests VALUES(catalog,actor,operation,request,outcome);
  PERFORM security.rec_forward_scope(catalog,true);RETURN outcome;
 END IF;
 IF EXISTS(SELECT 1 FROM trading.trades WHERE(catalog_id,id)=(catalog,trade)) THEN RAISE EXCEPTION 'rec_forward_revision_conflict';END IF;
 booking=request-ARRAY['context','operationId','tradeId','ownerId','bookId','terms'];
 PERFORM security.require_trade_parties(catalog,booking,at_time);
 IF NOT EXISTS(SELECT 1 FROM trading.books b JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id)
  WHERE(b.catalog_id,b.id)=(catalog,book) AND b.effective_at<=at_time AND p.effective_at<=at_time)
 THEN RAISE EXCEPTION 'rec_forward_book';END IF;
 SELECT * INTO staged FROM trading.side_schedule_requests WHERE(catalog_id,request_id)=(catalog,operation);
 IF NOT FOUND OR staged.actor_id<>actor OR staged.command_hash<>sha256(convert_to(request::text,'UTF8')) OR staged.permission<>'BookTrade'
  OR staged.trade_id IS NOT NULL OR staged.expected_revision IS NOT NULL THEN RAISE EXCEPTION 'rec_forward_schedule';END IF;
 PERFORM security.lock_side_schedule_request(catalog,operation);
 IF trading.rec_keys(prepared,ARRAY['instrumentId','members']) IS NOT TRUE OR prepared->'members' IS DISTINCT FROM
  '[{"slot":0,"name":"physical_delivery"},{"slot":1,"name":"consideration"}]'::jsonb
  OR(SELECT count(*) FROM trading.side_schedule_request_items WHERE(catalog_id,request_id)=(catalog,operation))<>2
 THEN RAISE EXCEPTION 'rec_forward_schedule';END IF;
 instrument=(prepared->>'instrumentId')::uuid;
 IF instrument IS NULL OR instrument='00000000-0000-0000-0000-000000000000' THEN RAISE EXCEPTION 'rec_forward_input';END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO publication FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());
 INSERT INTO trading.instruments VALUES(catalog,instrument,publication,at_time);
 INSERT INTO trading.rec_forward_instruments VALUES(catalog,instrument,assignment.revision_id,assignment.reference_catalog_id,assignment.reference_revision_id,
  assignment.code,assignment.product_code,vintage_first,vintage_last,from_at,to_at,quote.code,price->>'mode',fixed,price->>'curveCode',(price->>'contractId')::uuid,
  payment,policy,false,canonical);
 FOR member IN SELECT i.slot,i.schedule_id,h.side_id FROM trading.side_schedule_request_items i JOIN trading.side_schedules h
  ON(h.catalog_id,h.id)=(i.catalog_id,i.schedule_id) WHERE(i.catalog_id,i.request_id)=(catalog,operation) ORDER BY i.slot LOOP
  INSERT INTO trading.rec_forward_memberships VALUES(catalog,instrument,member.slot,member.side_id,CASE member.slot WHEN 0 THEN physical ELSE cash END);
  PERFORM trading.require_rec_forward_program_shape(catalog,member.schedule_id,member.slot,instrument);
 END LOOP;
 PERFORM security.stamp_trade_booking(catalog);
 INSERT INTO trading.trades VALUES(catalog,trade,book,operation,actor,request,publication,at_time);
 INSERT INTO trading.rec_forward_trade_revisions VALUES(catalog,trade,1,instrument,book,operation,actor,count_value,physical,cash,
  (request->>'tradeDate')::date,(request->>'legalEntityId')::uuid,(request->>'legalEntityRevision')::integer,
  (request->>'counterpartyId')::uuid,(request->>'counterpartyRevision')::integer,publication,at_time);
 INSERT INTO trading.rec_deliveries SELECT catalog,gen_random_uuid(),trade,1,instrument,0,h.side_id,i.schedule_id,
  assignment.reference_catalog_id,assignment.reference_revision_id,assignment.product_code,vintage_first,vintage_last,count_value,from_at,to_at,physical
  FROM trading.side_schedule_request_items i JOIN trading.side_schedules h ON(h.catalog_id,h.id)=(i.catalog_id,i.schedule_id)
  WHERE(i.catalog_id,i.request_id,i.slot)=(catalog,operation,0);
 SELECT tr.reference_number,ir.reference_number INTO STRICT trade_number,instrument_number FROM trading.trade_references tr
  JOIN trading.instrument_references ir ON(ir.catalog_id,ir.instrument_id)=(tr.catalog_id,instrument) WHERE(tr.catalog_id,tr.trade_id)=(catalog,trade);
 outcome=jsonb_build_object('operationId',operation,'tradeId',trade,'revision',1,'instrumentId',instrument,
  'tradeReference','TR-'||lpad(trade_number::text,greatest(6,length(trade_number::text)),'0'),'instrumentReference','IN-'||lpad(instrument_number::text,greatest(6,length(instrument_number::text)),'0'),'changed',true);
 INSERT INTO trading.rec_forward_booking_requests VALUES(catalog,actor,operation,request,outcome);
 PERFORM security.rec_forward_scope(catalog,true);RETURN outcome;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow OR numeric_value_out_of_range OR null_value_not_allowed
 THEN RAISE EXCEPTION 'rec_forward_input';
END$$;

CREATE FUNCTION security.rec_forward_position_scope(catalog uuid,books uuid[],portfolios uuid[],trades uuid[]) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE context uuid;result jsonb;complete boolean;BEGIN
 PERFORM security.rec_forward_scope(catalog,false);
 IF books IS NULL OR portfolios IS NULL OR cardinality(books)>128 OR cardinality(portfolios)>128
  OR array_position(books,NULL) IS NOT NULL OR array_position(portfolios,NULL) IS NOT NULL
  OR(trades IS NOT NULL AND(cardinality(trades) NOT BETWEEN 1 AND 256 OR array_position(trades,NULL) IS NOT NULL OR(SELECT count(DISTINCT x) FROM unnest(trades)x)<>cardinality(trades)))
 THEN RAISE EXCEPTION 'rec_forward_scope';END IF;
 SELECT c.market_context_id INTO context FROM security.request_contexts c JOIN trading.contexts t ON(t.catalog_id,t.context_id)=(c.market_catalog_id,c.market_context_id)
  WHERE c.market_catalog_id=catalog AND c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned()
   AND c.runtime_login=session_user AND c.trading_as_of IS NOT NULL;
 IF context IS NULL THEN RAISE EXCEPTION 'knowledge_coverage';END IF;
 PERFORM security.require_trading_history(catalog,context);
 WITH held AS(SELECT r.* FROM trading.rec_forward_trade_revisions r JOIN trading.books b ON(b.catalog_id,b.id)=(r.catalog_id,r.book_id)
  JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id)
  WHERE r.catalog_id=catalog AND security.trading_visible(r.catalog_id,r.publication_order,r.effective_at)
   AND security.trading_visible(b.catalog_id,b.publication_order,b.effective_at) AND security.trading_visible(p.catalog_id,p.publication_order,p.effective_at)
   AND(cardinality(books)=0 OR r.book_id=ANY(books)) AND(cardinality(portfolios)=0 OR b.portfolio_id=ANY(portfolios))
   AND(trades IS NULL OR r.trade_id=ANY(trades)))
 SELECT coalesce(jsonb_agg(jsonb_build_object('trade_id',r.trade_id,'binding_id',r.instrument_id,'instrument_id',r.instrument_id,
   'definition_revision_id',h.definition_revision_id,'book_id',r.book_id,'revision',r.revision,'trade_reference',tr.reference_number) ORDER BY tr.reference_number),'[]'),
  coalesce(bool_and(h.instrument_id IS NOT NULL AND tr.reference_number IS NOT NULL AND a.code IS NOT NULL
   AND security.market_fact_visible(h.catalog_id,h.definition_revision_id,NULL) AND security.reference_access(h.reference_catalog_id,'ReadMarketData')
   AND security.reference_version_visible(h.reference_catalog_id,h.reference_revision_id)),true)
 INTO result,complete FROM held r LEFT JOIN trading.rec_forward_instruments h USING(catalog_id,instrument_id)
 LEFT JOIN market_data.rec_valuation_assignments a ON(a.catalog_id,a.revision_id,a.code)=(h.catalog_id,h.definition_revision_id,h.assignment_code)
 LEFT JOIN trading.trade_references tr ON(tr.catalog_id,tr.trade_id)=(r.catalog_id,r.trade_id);
 IF complete IS NOT TRUE THEN RAISE EXCEPTION 'rec_forward_unavailable' USING ERRCODE='42501';END IF;
 PERFORM security.rec_forward_scope(catalog,false);RETURN result;
END$$;
CREATE FUNCTION security.read_rec_forward_positions(catalog uuid,books uuid[],portfolios uuid[],trades uuid[]) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE inventory jsonb;result jsonb;BEGIN
 inventory=security.rec_forward_position_scope(catalog,books,portfolios,trades);
 SELECT coalesce(jsonb_agg(jsonb_build_object('head',to_jsonb(x),'product',jsonb_build_object(
  'code',p.code,'name',p.name,'reference_catalog_id',h.reference_catalog_id,'reference_revision_id',h.reference_revision_id,
  'registry_code',program.registry_code,'program_code',p.program_code,'class_code',p.class_code,'technology_code',p.technology_code,'geography_code',p.geography_code,
  'quantity_code',p.quantity_code,'unit',u.symbol,'commodity_code',q.commodity_code,'commodity_name',commodity.name,
  'currency_code',quote.currency_code,'currency',currency.display_code,'curve_code',assignment.curve_code,'quote_code',mark_curve.quote_code,
  'projection_curves',CASE WHEN h.consideration_curve_code IS NULL THEN jsonb_build_array(assignment.curve_code)
   ELSE(SELECT jsonb_agg(v ORDER BY v) FROM(SELECT DISTINCT v FROM unnest(ARRAY[assignment.curve_code,h.consideration_curve_code])v) z) END)) ORDER BY x.trade_reference),'[]')
 INTO result FROM(
  SELECT r.*,r.instrument_id binding_id,h.definition_revision_id,h.reference_catalog_id,h.reference_revision_id,h.product_code,
   h.vintage_from,h.vintage_to,h.delivery_from,h.delivery_to,t.request,tr.reference_number trade_reference,ir.reference_number instrument_reference,
   b.booker_id,b.booker_name,b.booker_login,b.executed_at,b.implementation booking_implementation,b.label_captured_at,
   le.name legal_entity,cp.name counterparty,
   (SELECT jsonb_agg(jsonb_build_object('slot',m.slot,'sideId',m.side_id,'name',CASE m.slot WHEN 0 THEN 'physical_delivery' ELSE 'consideration' END,
     'coefficient',m.coefficient::text) ORDER BY m.slot) FROM trading.rec_forward_memberships m WHERE(m.catalog_id,m.instrument_id)=(r.catalog_id,r.instrument_id)) members
  FROM trading.rec_forward_trade_revisions r JOIN trading.rec_forward_instruments h USING(catalog_id,instrument_id)
  JOIN trading.trades t ON(t.catalog_id,t.id)=(r.catalog_id,r.trade_id)
  JOIN trading.trade_references tr ON(tr.catalog_id,tr.trade_id)=(r.catalog_id,r.trade_id)
  JOIN trading.instrument_references ir ON(ir.catalog_id,ir.instrument_id)=(r.catalog_id,r.instrument_id)
  JOIN trading.booking_facts b ON(b.catalog_id,b.trade_id)=(r.catalog_id,r.trade_id)
  JOIN trading.legal_entities le ON(le.catalog_id,le.id,le.revision)=(r.catalog_id,r.legal_entity_id,r.legal_entity_revision)
  JOIN trading.counterparties cp ON(cp.catalog_id,cp.id,cp.revision)=(r.catalog_id,r.counterparty_id,r.counterparty_revision)
  WHERE r.catalog_id=catalog AND r.trade_id IN(SELECT(value->>'trade_id')::uuid FROM jsonb_array_elements(inventory)))x
 JOIN trading.rec_forward_instruments h ON(h.catalog_id,h.instrument_id)=(x.catalog_id,x.instrument_id)
 JOIN market_data.rec_valuation_assignments assignment ON(assignment.catalog_id,assignment.revision_id,assignment.code)=(h.catalog_id,h.definition_revision_id,h.assignment_code)
 JOIN market_data.curves mark_curve ON(mark_curve.catalog_id,mark_curve.revision_id,mark_curve.code)=(assignment.catalog_id,assignment.revision_id,assignment.curve_code)
 JOIN ref_data.rec_products p ON(p.catalog_id,p.revision_id,p.code)=(h.reference_catalog_id,h.reference_revision_id,h.product_code)
 JOIN ref_data.rec_programs program ON(program.catalog_id,program.revision_id,program.code)=(p.catalog_id,p.revision_id,p.program_code)
 JOIN ref_data.quantity_specifications q ON(q.catalog_id,q.revision_id,q.code)=(p.catalog_id,p.revision_id,p.quantity_code)
 JOIN ref_data.units u ON(u.catalog_id,u.revision_id,u.code)=(q.catalog_id,q.revision_id,q.unit_code)
 JOIN ref_data.commodities commodity ON(commodity.catalog_id,commodity.revision_id,commodity.code)=(q.catalog_id,q.revision_id,q.commodity_code)
 JOIN ref_data.quote_specifications quote ON(quote.catalog_id,quote.revision_id,quote.code)=(h.reference_catalog_id,h.reference_revision_id,h.consideration_quote_code)
 JOIN ref_data.currencies currency ON(currency.catalog_id,currency.revision_id,currency.code)=(quote.catalog_id,quote.revision_id,quote.currency_code);
 IF jsonb_array_length(result)<>jsonb_array_length(inventory) OR EXISTS(SELECT 1 FROM jsonb_array_elements(result)r WHERE jsonb_array_length(r#>'{head,members}')<>2)
 THEN RAISE EXCEPTION 'rec_forward_metadata';END IF;
 PERFORM security.rec_forward_position_scope(catalog,books,portfolios,trades);RETURN result;
END$$;
DO $$DECLARE f regprocedure;BEGIN
 FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='security' AND p.proname IN('rec_forward_scope','rec_forward_booking_status','rec_forward_booking_replay','book_rec_forward','rec_forward_position_scope','read_rec_forward_positions') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION security.rec_forward_booking_status(uuid,uuid),security.rec_forward_booking_replay(uuid,jsonb),security.book_rec_forward(uuid,jsonb,jsonb,timestamptz) TO openetrm_runtime;
GRANT EXECUTE ON FUNCTION security.rec_forward_position_scope(uuid,uuid[],uuid[],uuid[]),security.read_rec_forward_positions(uuid,uuid[],uuid[],uuid[]) TO openetrm_runtime,openetrm_risk_worker;
COMMIT;
