-- The retained operating family serves complete supplied operating rights and
-- certificate forwards. Original contracts own exact membership and admission;
-- shared storage retains immutable programs and ordinary scenario execution.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Fail closed on an altered predecessor body, owner, privilege or execution mode.
DO $upgrade$DECLARE expected jsonb;p pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($contracts$
[{"signature":"trading.side_program_document(uuid,uuid)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner"],"config":["search_path=pg_catalog","enable_nestloop=off","jit=off"],"definer":false,"volatility":"s","strict":false,"parallel":"u","leakproof":false,"hash":"d727695c26e39749aceb13a3fd8b6a4f3cfbfe9354034bca2a7937e660e2d1d6"},{"signature":"trading.side_schedule_parameters(text,jsonb)","owner":"@migration_owner","acl":["=X/@migration_owner","@migration_owner=X/@migration_owner"],"config":["search_path=pg_catalog"],"definer":false,"volatility":"i","strict":false,"parallel":"s","leakproof":false,"hash":"ffa0d6885c7c3d718fec8742d65b20093e9d2d671fb2807f43c39d285ddcdf1b"},{"signature":"security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner"],"config":["search_path=pg_catalog","jit=off"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"bf1847a2ac16b1bba6fcb8f69f78b6dc3a21566b608fb8c44c9ecb702ac5b214"},{"signature":"security.side_schedule_visible(uuid,uuid)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_risk_worker=X/openetrm_security_owner"],"config":["search_path=pg_catalog"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"49c46db8014721fb1695cf59ded78b0b9171533eb0a099329eb3d58f13c5b337"},{"signature":"security.seal_side_schedule(uuid,uuid,uuid,text)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner"],"config":["search_path=pg_catalog","enable_nestloop=off","jit=off"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"6c76a44b1deb1e1126406d8d477cba048acd1c790f642a5117d73713825f0908"},{"signature":"security.publish_admitted_side_schedules(uuid,uuid,uuid)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner"],"config":["search_path=pg_catalog","jit=off"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"23ef3157e856d5ec6c5318df6db83f88ff6acb15acf38fa82525425e66b42fca"},{"signature":"security.require_side_schedule_read(uuid,uuid,uuid,uuid,timestamp with time zone)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner"],"config":["search_path=pg_catalog","jit=off"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"e40515e38ccc033785663dedbfc2bc57025b5cf8a43667a27c9c70b127b784dc"},{"signature":"trading.require_instrument_side_schedules()","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner"],"config":["search_path=pg_catalog","jit=off"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"fe91b7f2f041cc84e21a9b3fda6f1a09fa1f5493551cbb9c1446dc55c2fe1323"},{"signature":"trading.require_side_program_structure(uuid,uuid,jsonb)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner"],"config":["search_path=pg_catalog","enable_nestloop=off","jit=off"],"definer":false,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"c438707fe9643fb749382f347ec8a808122dbe55d158377b2ad31f0cc77b354a"},{"signature":"security.read_instrument_side_schedule_headers(uuid,uuid,uuid,timestamp with time zone)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_risk_worker=X/openetrm_security_owner"],"config":["search_path=pg_catalog","jit=off"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"b03eaef278cf1bae07e94cdb97961b3bbfd51bff4b9e1cca6fe6a587d3d4c5b5"},{"signature":"security.publish_operation_side_schedules(uuid,uuid)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner"],"config":["search_path=pg_catalog"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"9a737f86c1786258315b99af3203cd8a85649d8b916424c301a05a483dcadd98"},{"signature":"security.visible_side_schedules()","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_risk_worker=X/openetrm_security_owner"],"config":["search_path=pg_catalog"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"a9fccbb6dd27e4a81a9fa620f81d5a8d8b1dbc1c7568797adc4580f36e884e57"},{"signature":"security.publish_side_schedules(uuid,uuid,uuid)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner"],"config":["search_path=pg_catalog"],"definer":true,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"916d13e3203293f03270b4a741aeb0921c822f8fdbfad8879031a0e31196d1a3"},{"signature":"trading.require_side_program_content(uuid,uuid,bytea)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner"],"config":["search_path=pg_catalog","jit=off"],"definer":false,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"732ba5ab834c5b1ea02b8c1893c75daf93989c40e0b5563273512bad2f25dabf"},{"signature":"trading.retain_side_calendar_policy(uuid,uuid,jsonb,integer)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner"],"config":["search_path=pg_catalog"],"definer":false,"volatility":"v","strict":false,"parallel":"u","leakproof":false,"hash":"9ca4a73a22903aaf1da6cb017aa456900b16d1bff1569a99d46c2563f1ac7c63"},{"signature":"trading.request_side_calendar_policy(jsonb,integer)","owner":"openetrm_security_owner","acl":["openetrm_security_owner=X/openetrm_security_owner"],"config":["search_path=pg_catalog"],"definer":false,"volatility":"i","strict":false,"parallel":"u","leakproof":false,"hash":"c2f04ecf84bb955ec798635a2094dcda340e2d656f299d6b3d36c992f9462655"}]
$contracts$::jsonb) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(expected->>'signature');
  SELECT jsonb_agg(x::text ORDER BY x::text) INTO actual_acl FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x;
  SELECT jsonb_agg(value ORDER BY value) INTO expected_acl FROM(SELECT replace(value,'@migration_owner',quote_ident(current_user))::aclitem::text value FROM jsonb_array_elements_text(expected->'acl')) a;
  IF p.oid IS NULL OR encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex') IS DISTINCT FROM expected->>'hash' OR
   pg_get_userbyid(p.proowner) IS DISTINCT FROM(CASE expected->>'owner' WHEN '@migration_owner' THEN current_user ELSE expected->>'owner' END) OR p.prosecdef IS DISTINCT FROM(expected->>'definer')::boolean OR
   p.provolatile IS DISTINCT FROM(expected->>'volatility')::"char" OR p.proisstrict IS DISTINCT FROM(expected->>'strict')::boolean OR
   p.proleakproof IS DISTINCT FROM(expected->>'leakproof')::boolean OR p.proparallel IS DISTINCT FROM(expected->>'parallel')::"char" OR
   coalesce(to_jsonb(p.proconfig),'null'::jsonb) IS DISTINCT FROM expected->'config' OR actual_acl IS DISTINCT FROM expected_acl
  THEN RAISE EXCEPTION 'operating_program_upgrade: unexpected helper %',expected->>'signature';END IF;
 END LOOP;
END$upgrade$;

CREATE FUNCTION pg_temp.extend_operating_helper(signature text,marker text,replacement text) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $patch$
DECLARE source text=pg_get_functiondef(signature::regprocedure);
BEGIN
 IF (length(source)-length(replace(source,marker,'')))/length(marker)<>1 THEN
  RAISE EXCEPTION 'operating_program_upgrade: unexpected patch coordinate %',signature;END IF;
 EXECUTE replace(source,marker,replacement);
END$patch$;

ALTER TABLE trading.instrument_side_schedules
 ADD COLUMN operating_side_id uuid,
 ADD COLUMN rec_forward_side_id uuid,
 ADD FOREIGN KEY(catalog_id,instrument_id,slot,operating_side_id)
  REFERENCES trading.operating_memberships(catalog_id,instrument_id,slot,side_id),
 ADD FOREIGN KEY(catalog_id,instrument_id,slot,rec_forward_side_id)
  REFERENCES trading.rec_forward_memberships(catalog_id,instrument_id,slot,side_id),
 DROP CONSTRAINT instrument_side_schedules_check,
 DROP CONSTRAINT instrument_side_schedules_check1,
 ADD CONSTRAINT instrument_side_schedules_check CHECK(num_nonnulls(swap_fixed_side_id,swap_floating_side_id,swap_whole_term_side_id,ppa_side_id,gas_side_id,crude_side_id,lng_side_id,operating_side_id,rec_forward_side_id)=1),
 ADD CONSTRAINT instrument_side_schedules_check1 CHECK(side_id=coalesce(swap_fixed_side_id,swap_floating_side_id,swap_whole_term_side_id,ppa_side_id,gas_side_id,crude_side_id,lng_side_id,operating_side_id,rec_forward_side_id));
ALTER TABLE trading.side_schedule_rows DROP CONSTRAINT side_schedule_source_output_kind;
ALTER TABLE trading.side_schedule_rows ADD CONSTRAINT side_schedule_source_output_kind CHECK(output_kind=CASE
 WHEN operation IN('constant_price','price_lookup','curve_price_lookup','contract_observation_price','operating_contract_price','price_scale','price_add','weighted_price','price_application') THEN 'price'
 WHEN operation IN('quantity_input','quantity_literal','profile_quantity','asset_capacity','quantity_normalize','quantity_add','quantity_scale','quantity_transform','quantity_sum_cells') THEN 'quantity'
 WHEN operation='discount' THEN 'factor'
 WHEN operation IN('amount','pv','sum','sum_cells','output_guard') THEN 'money' ELSE NULL END);

SELECT pg_temp.extend_operating_helper('security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)',$before$'fixed','floating','power','certificate','capacity','gas','crude','lng'$before$,$after$'fixed','floating','power','certificate','capacity','gas','crude','lng','operating'$after$);

SELECT pg_temp.extend_operating_helper('trading.side_schedule_parameters(text,jsonb)',$before$WHEN 'constant_price' THEN ARRAY['denominator','numerator']$before$,$after$WHEN 'operating_contract_price' THEN ARRAY['selection']
  WHEN 'constant_price' THEN ARRAY['denominator','numerator']$after$);

SELECT pg_temp.extend_operating_helper('trading.side_schedule_parameters(text,jsonb)',$before$ IF operation='contract_observation_price' THEN$before$,$after$ IF operation='operating_contract_price' AND parameters->>'selection' IS DISTINCT FROM 'selected_contract_flat_v1' THEN RETURN false;END IF;
 IF operation='contract_observation_price' THEN$after$);

SELECT pg_temp.extend_operating_helper('trading.request_side_calendar_policy(jsonb,integer)',$before$ IF command->>'schema'='scheduled_financial_swap_booking_v1' THEN$before$,$after$ IF command->>'convention'='supplied_operating_right_trade_v1' THEN
  IF jsonb_typeof(command->'plan'->'valuation') IS DISTINCT FROM 'object' OR
   command#>>'{plan,valuation,paymentRule,frequency}' IS DISTINCT FROM 'monthly' OR
   command#>>'{plan,valuation,paymentRule,rule}' IS DISTINCT FROM 'days_after_period_end' OR
   command#>>'{plan,valuation,paymentRule,dayBasis}' IS DISTINCT FROM 'calendar_days' OR
   command#>>'{plan,valuation,paymentRule,adjustment}' IS DISTINCT FROM 'unadjusted' OR
   command#>'{plan,valuation,paymentRule,calendar}' IS DISTINCT FROM 'null'::jsonb
  THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
  RETURN jsonb_build_object('implementation','side_calendar_policy_v1',
   'delivery',jsonb_build_object('applicable',false,'calendar',NULL),
   'observation',jsonb_build_object('applicable',false,'calendar',NULL),
   'payment',jsonb_build_object('applicable',false,'calendar',NULL));
 END IF;
 IF command->'terms' ? 'assignmentCode' AND command->'terms' ? 'vintageFrom' THEN
  RETURN command->'terms'->'calendarPolicy';
 END IF;
 IF command->>'schema'='scheduled_financial_swap_booking_v1' THEN$after$);

SELECT pg_temp.extend_operating_helper('trading.retain_side_calendar_policy(uuid,uuid,jsonb,integer)',$before$to_jsonb(NOT linked)$before$,$after$to_jsonb(NOT linked AND family<>'operating')$after$);

SELECT pg_temp.extend_operating_helper('trading.retain_side_calendar_policy(uuid,uuid,jsonb,integer)',$before$family NOT IN('gas','crude','lng')$before$,$after$family NOT IN('gas','crude','lng','operating')$after$);

SELECT pg_temp.extend_operating_helper('security.seal_side_schedule(uuid,uuid,uuid,text)',$before$'constant_price','price_lookup','curve_price_lookup','contract_observation_price','quantity_input'$before$,$after$'constant_price','price_lookup','curve_price_lookup','contract_observation_price','operating_contract_price','quantity_input'$after$);

SELECT pg_temp.extend_operating_helper('security.seal_side_schedule(uuid,uuid,uuid,text)',$before$   WHEN 'contract_observation_price' THEN NOT$before$,$after$   WHEN 'operating_contract_price' THEN NOT(coalesce(s.n,0)=2 AND s.market_port AND s.quote_port AND s.dated_ports)
   WHEN 'contract_observation_price' THEN NOT$after$);

SELECT pg_temp.extend_operating_helper('security.seal_side_schedule(uuid,uuid,uuid,text)',$before$ INSERT INTO trading.side_schedule_seals(catalog_id,schedule_id,content_hash)$before$,$after$ -- The direct contract source and native delivery lifecycle belong only to
 -- the bounded operating family; an unrelated native product cannot opt in.
 IF EXISTS(SELECT 1 FROM trading.side_schedule_rows r JOIN trading.side_schedules operating_header
   ON(operating_header.catalog_id,operating_header.id)=(r.catalog_id,r.schedule_id) JOIN trading.sides s ON(s.catalog_id,s.id)=(operating_header.catalog_id,operating_header.side_id)
   WHERE(r.catalog_id,r.schedule_id)=(catalog,schedule) AND
    (r.operation='operating_contract_price' OR r.parameters->>'lifecycle'='future_operating_delivery_v1') AND s.family<>'operating')
 THEN RAISE EXCEPTION 'side_schedule_family';END IF;
 IF EXISTS(SELECT 1 FROM trading.side_schedule_rows r
   JOIN trading.side_schedule_bindings b ON(b.catalog_id,b.schedule_id,b.row_ordinal,b.port,b.kind)=(r.catalog_id,r.schedule_id,r.ordinal,'market','contract_price')
   JOIN trading.side_schedule_bindings q ON(q.catalog_id,q.schedule_id,q.row_ordinal,q.port,q.kind)=(r.catalog_id,r.schedule_id,r.ordinal,'quote','quote')
   JOIN market_data.curves c ON(c.catalog_id,c.revision_id,c.code)=(b.source_catalog_id,b.definition_revision_id,b.curve_code)
   JOIN ref_data.quote_specifications quote ON(quote.catalog_id,quote.revision_id,quote.code)=(q.reference_catalog_id,q.reference_revision_id,q.quote_code)
   WHERE(r.catalog_id,r.schedule_id,r.operation)=(catalog,schedule,'operating_contract_price') AND
    ((c.reference_catalog_id,c.reference_revision_id,c.quote_code) IS DISTINCT FROM(q.reference_catalog_id,q.reference_revision_id,q.quote_code) OR quote.kind<>'outright' OR
     (r.unit_catalog_id,r.unit_revision_id,r.unit_code,r.currency_catalog_id,r.currency_revision_id,r.currency_code,r.quote_multiplier) IS DISTINCT FROM
     (q.reference_catalog_id,q.reference_revision_id,quote.quantity_code,q.reference_catalog_id,q.reference_revision_id,quote.currency_code,quote.multiplier)))
 THEN RAISE EXCEPTION 'side_schedule_sources';END IF;
 INSERT INTO trading.side_schedule_seals(catalog_id,schedule_id,content_hash)$after$);

SELECT pg_temp.extend_operating_helper('trading.side_program_document(uuid,uuid)',$before$'price_lookup','curve_price_lookup','contract_observation_price','quantity_input'$before$,$after$'price_lookup','curve_price_lookup','contract_observation_price','operating_contract_price','quantity_input'$after$);

SELECT pg_temp.extend_operating_helper('trading.require_side_program_structure(uuid,uuid,jsonb)',$before$'price_lookup','curve_price_lookup','contract_observation_price','quantity_input'$before$,$after$'price_lookup','curve_price_lookup','contract_observation_price','operating_contract_price','quantity_input'$after$);

SELECT pg_temp.extend_operating_helper('trading.require_side_program_content(uuid,uuid,bytea)',$before$'whole_gas_day_delivery_v1','accrued_payment_v1'$before$,$after$'whole_gas_day_delivery_v1','accrued_payment_v1','future_operating_delivery_v1'$after$);

SELECT pg_temp.extend_operating_helper('trading.require_side_program_content(uuid,uuid,bytea)',$before$IN('undue_payment_v1','accrued_payment_v1')$before$,$after$IN('undue_payment_v1','accrued_payment_v1','future_operating_delivery_v1')$after$);

SELECT pg_temp.extend_operating_helper('trading.require_side_program_content(uuid,uuid,bytea)',$before$ IF document IS DISTINCT FROM trading.side_program_document$before$,$after$ IF document->>'family' IS DISTINCT FROM 'operating' AND EXISTS(SELECT 1 FROM trading.side_schedule_rows r WHERE(r.catalog_id,r.schedule_id)=(catalog,schedule) AND(r.operation='operating_contract_price' OR r.parameters->>'lifecycle'='future_operating_delivery_v1')) THEN RAISE EXCEPTION 'side_schedule_program';END IF;
 IF document IS DISTINCT FROM trading.side_program_document$after$);

SELECT pg_temp.extend_operating_helper('security.publish_admitted_side_schedules(uuid,uuid,uuid)',$before$ ) published;$before$,$after$  UNION ALL SELECT r.publication_order,r.effective_at FROM trading.operating_trade_revisions r WHERE(r.catalog_id,r.operation_id,r.instrument_id,r.actor_id)=(catalog,operation,instrument,actor)
  UNION ALL SELECT r.publication_order,r.effective_at FROM trading.rec_forward_trade_revisions r WHERE(r.catalog_id,r.operation_id,r.instrument_id,r.actor_id)=(catalog,operation,instrument,actor)
 ) published;$after$);

SELECT pg_temp.extend_operating_helper('security.publish_admitted_side_schedules(uuid,uuid,uuid)',$before$candidate.lng_side_id=NULL;$before$,$after$candidate.lng_side_id=NULL;candidate.operating_side_id=NULL;candidate.rec_forward_side_id=NULL;
  SELECT side_id INTO candidate.operating_side_id FROM trading.operating_memberships WHERE(catalog_id,instrument_id,slot)=(catalog,instrument,item.slot);
  SELECT side_id INTO candidate.rec_forward_side_id FROM trading.rec_forward_memberships WHERE(catalog_id,instrument_id,slot)=(catalog,instrument,item.slot);$after$);

SELECT pg_temp.extend_operating_helper('security.publish_admitted_side_schedules(uuid,uuid,uuid)',$before$AND candidate.lng_side_id IS NULL THEN$before$,$after$AND candidate.lng_side_id IS NULL AND candidate.operating_side_id IS NULL AND candidate.rec_forward_side_id IS NULL THEN$after$);

SELECT pg_temp.extend_operating_helper('security.publish_admitted_side_schedules(uuid,uuid,uuid)',$before$candidate.gas_side_id,candidate.crude_side_id,candidate.lng_side_id);$before$,$after$candidate.gas_side_id,candidate.crude_side_id,candidate.lng_side_id,candidate.operating_side_id,candidate.rec_forward_side_id);$after$);

SELECT pg_temp.extend_operating_helper('security.publish_admitted_side_schedules(uuid,uuid,uuid)',$before$    WHEN candidate.lng_side_id IS NOT NULL THEN$before$,$after$    WHEN candidate.operating_side_id IS NOT NULL OR candidate.rec_forward_side_id IS NOT NULL THEN 'operating'
    WHEN candidate.lng_side_id IS NOT NULL THEN$after$);

SELECT pg_temp.extend_operating_helper('security.publish_admitted_side_schedules(uuid,uuid,uuid)',$before$  SELECT * INTO prior FROM trading.instrument_side_schedules$before$,$after$  IF candidate.operating_side_id IS NOT NULL THEN
   IF NOT security.has_permission('ReadPhysical') THEN RAISE EXCEPTION 'No current physical authority' USING ERRCODE='42501';END IF;
   PERFORM trading.require_operating_program_shape(catalog,item.schedule_id,item.slot,instrument);
  ELSIF candidate.rec_forward_side_id IS NOT NULL THEN
   PERFORM trading.require_rec_forward_program_shape(catalog,item.schedule_id,item.slot,instrument);
  ELSIF EXISTS(SELECT 1 FROM trading.side_schedule_rows r WHERE(r.catalog_id,r.schedule_id)=(catalog,item.schedule_id)
   AND(r.operation='operating_contract_price' OR r.parameters->>'lifecycle'='future_operating_delivery_v1')) THEN
   RAISE EXCEPTION 'side_schedule_family';
  END IF;
  SELECT * INTO prior FROM trading.instrument_side_schedules$after$);

SELECT pg_temp.extend_operating_helper('security.publish_side_schedules(uuid,uuid,uuid)',$before$ ) booking;$before$,$after$  UNION ALL SELECT t.request FROM trading.operating_trade_revisions r JOIN trading.trades t ON(t.catalog_id,t.id)=(r.catalog_id,r.trade_id)
   WHERE(r.catalog_id,r.operation_id,r.actor_id,r.instrument_id)=(catalog,operation,staged.actor_id,instrument)
  UNION ALL SELECT t.request FROM trading.rec_forward_trade_revisions r JOIN trading.trades t ON(t.catalog_id,t.id)=(r.catalog_id,r.trade_id)
   WHERE(r.catalog_id,r.operation_id,r.actor_id,r.instrument_id)=(catalog,operation,staged.actor_id,instrument)
 ) booking;$after$);

SELECT pg_temp.extend_operating_helper('security.publish_operation_side_schedules(uuid,uuid)',$before$ ) replacements;$before$,$after$  UNION ALL SELECT instrument_id FROM trading.operating_trade_revisions WHERE(catalog_id,operation_id)=(catalog,operation)
  UNION ALL SELECT instrument_id FROM trading.rec_forward_trade_revisions WHERE(catalog_id,operation_id)=(catalog,operation)
 ) replacements;$after$);

SELECT pg_temp.extend_operating_helper('security.read_instrument_side_schedule_headers(uuid,uuid,uuid,timestamp with time zone)',$before$ IF expected=0 AND EXISTS$before$,$after$ IF expected=0 THEN SELECT count(*) INTO expected FROM trading.operating_memberships WHERE(catalog_id,instrument_id)=(catalog,instrument);END IF;
 IF expected=0 THEN SELECT count(*) INTO expected FROM trading.rec_forward_memberships WHERE(catalog_id,instrument_id)=(catalog,instrument);END IF;
 IF expected=0 AND EXISTS$after$);

SELECT pg_temp.extend_operating_helper('security.require_side_schedule_read(uuid,uuid,uuid,uuid,timestamp with time zone)',$before$   EXISTS(SELECT 1 FROM trading.lng_trade_revisions r WHERE(r.catalog_id,r.instrument_id)=(catalog,instrument) AND security.trading_visible(catalog,r.publication_order,r.effective_at)) OR$before$,$after$   EXISTS(SELECT 1 FROM trading.lng_trade_revisions r WHERE(r.catalog_id,r.instrument_id)=(catalog,instrument) AND security.trading_visible(catalog,r.publication_order,r.effective_at)) OR
   EXISTS(SELECT 1 FROM trading.operating_trade_revisions r WHERE(r.catalog_id,r.instrument_id)=(catalog,instrument) AND security.trading_visible(catalog,r.publication_order,r.effective_at)) OR
   EXISTS(SELECT 1 FROM trading.rec_forward_trade_revisions r WHERE(r.catalog_id,r.instrument_id)=(catalog,instrument) AND security.trading_visible(catalog,r.publication_order,r.effective_at)) OR$after$);

SELECT pg_temp.extend_operating_helper('security.require_side_schedule_read(uuid,uuid,uuid,uuid,timestamp with time zone)',$before$   EXISTS(SELECT 1 FROM trading.lng_trade_revisions r WHERE(r.catalog_id,r.instrument_id)=(catalog,instrument) AND security.ppa_visible_at(catalog,r.publication_order,r.effective_at,context,as_of)) OR$before$,$after$   EXISTS(SELECT 1 FROM trading.lng_trade_revisions r WHERE(r.catalog_id,r.instrument_id)=(catalog,instrument) AND security.ppa_visible_at(catalog,r.publication_order,r.effective_at,context,as_of)) OR
   EXISTS(SELECT 1 FROM trading.operating_trade_revisions r WHERE(r.catalog_id,r.instrument_id)=(catalog,instrument) AND security.ppa_visible_at(catalog,r.publication_order,r.effective_at,context,as_of)) OR
   EXISTS(SELECT 1 FROM trading.rec_forward_trade_revisions r WHERE(r.catalog_id,r.instrument_id)=(catalog,instrument) AND security.ppa_visible_at(catalog,r.publication_order,r.effective_at,context,as_of)) OR$after$);

SELECT pg_temp.extend_operating_helper('security.require_side_schedule_read(uuid,uuid,uuid,uuid,timestamp with time zone)',$before$ IF allowed IS NOT TRUE OR$before$,$after$ IF EXISTS(SELECT 1 FROM trading.instrument_side_schedules WHERE(catalog_id,instrument_id)=(catalog,instrument) AND operating_side_id IS NOT NULL) AND NOT security.has_permission('ReadPhysical')
 THEN RAISE EXCEPTION 'No current physical authority' USING ERRCODE='42501';END IF;
 IF allowed IS NOT TRUE OR$after$);

SELECT pg_temp.extend_operating_helper('trading.require_instrument_side_schedules()',$before$ IF TG_TABLE_NAME='lng_trade_revisions' THEN$before$,$after$ IF TG_TABLE_NAME='operating_trade_revisions' THEN
  SELECT count(*) INTO expected FROM trading.operating_memberships WHERE(catalog_id,instrument_id)=(NEW.catalog_id,NEW.instrument_id);
 ELSIF TG_TABLE_NAME='rec_forward_trade_revisions' THEN
  SELECT count(*) INTO expected FROM trading.rec_forward_memberships WHERE(catalog_id,instrument_id)=(NEW.catalog_id,NEW.instrument_id);
 ELSIF TG_TABLE_NAME='lng_trade_revisions' THEN$after$);

SELECT pg_temp.extend_operating_helper('security.side_schedule_visible(uuid,uuid)',$before$   AND security.reference_version_visible$before$,$after$   AND(security.has_permission('ReadPhysical') OR NOT EXISTS(SELECT 1 FROM trading.instrument_side_schedules m
    WHERE(m.catalog_id,m.schedule_id)=(p.catalog_id,p.schedule_id) AND m.operating_side_id IS NOT NULL))
   AND security.reference_version_visible$after$);

SELECT pg_temp.extend_operating_helper('security.visible_side_schedules()',$before$   AND EXISTS(SELECT 1 FROM revs r$before$,$after$   AND(security.has_permission('ReadPhysical') OR NOT EXISTS(SELECT 1 FROM trading.instrument_side_schedules m
    WHERE(m.catalog_id,m.schedule_id)=(p.catalog_id,p.schedule_id) AND m.operating_side_id IS NOT NULL))
   AND EXISTS(SELECT 1 FROM revs r$after$);

-- The original native transaction cannot commit a partial Side directory.
CREATE CONSTRAINT TRIGGER retained_operating_schedules AFTER INSERT ON trading.operating_trade_revisions
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trading.require_instrument_side_schedules();
CREATE CONSTRAINT TRIGGER retained_rec_forward_schedules AFTER INSERT ON trading.rec_forward_trade_revisions
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trading.require_instrument_side_schedules();
COMMIT;
