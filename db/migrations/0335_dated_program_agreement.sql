-- Admit dated financial cash against its request, canonical terms and executable
-- expression. An internally consistent manifest is not economic agreement.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"ref_data.clock_boundary(uuid,uuid,text,date)","definition":"2a3764f58d6de30d1fe354896e72b664d78672a82d4498190b04c58e5bc0715e","volatility":"s"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"ref_data.clock_local(uuid,uuid,text,timestamp with time zone)","definition":"3d4933c9d6322cc77e6ba07f4ce71471dd9d07b64254caeab30026f4e3703055","volatility":"s"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)","definition":"636596f7ab54b2ac92704f0bc830061f1930587c5a61cd28d7c5bff7e7510dcd","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])","definition":"ad168fea2a58d339949a87d6596aea4c16442050c237441ca843ea26d67cab7c","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid)","definition":"be3e478b53c750e4e826722f5c04cb10b6df812b44cb304ae70cef5734eeeb92","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[],uuid)","definition":"be7704fb6cb0e1f8c5df5272d0cebbb3bbdc551d4b8f5d6e7d32eb192ff29c79","volatility":"v"},{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamp with time zone,timestamp with time zone,text,text,text,jsonb,uuid[])","definition":"ee35c7f3a4f293233b079a4a79e05ca044b3e6003cc93b80e09a7b6a7800ba27","volatility":"v"},{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamp with time zone,jsonb,uuid[])","definition":"df0c44559c82a9dd21b44382ddf0252e6898ed6323a529c86c8ba2c4fd94d656","volatility":"v"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.side_calendar_policy_document(uuid,uuid)","definition":"468af4999ed99cbedec32957bcf2e029dda5f6a09698778a6be666049e02f993","volatility":"s"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_payment_provenance(uuid,uuid,uuid,date,date)","definition":"961893312b71300cc4142a35a7520090e88a95aa8796d4a495cb773ac0dc001d","volatility":"v"},{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.staged_economic_side(uuid,uuid,integer)","definition":"d03028c519f675fa5b8b60df30f6c39c5722e63aa1b3ef1a0babda8ebf26d02c","volatility":"v"}]
$calendar_helpers$::jsonb) LOOP
  SELECT * INTO helper FROM pg_proc WHERE oid=to_regprocedure(expected->>'signature');
  SELECT jsonb_agg(x::text ORDER BY x::text) INTO actual_acl FROM unnest(coalesce(helper.proacl,acldefault('f',helper.proowner))) x;
  SELECT jsonb_agg(value ORDER BY value) INTO expected_acl FROM(
   SELECT replace(value,'@migration_owner',quote_ident(current_user))::aclitem::text value FROM jsonb_array_elements_text(expected->'acl')) a;
  IF helper.oid IS NULL OR encode(sha256(convert_to(pg_get_functiondef(helper.oid),'UTF8')),'hex') IS DISTINCT FROM expected->>'definition' OR
   pg_get_userbyid(helper.proowner) IS DISTINCT FROM(CASE expected->>'owner' WHEN '@migration_owner' THEN current_user ELSE expected->>'owner' END) OR
   helper.prosecdef IS DISTINCT FROM(expected->>'definer')::boolean OR helper.provolatile IS DISTINCT FROM(expected->>'volatility')::"char" OR
   helper.proisstrict IS DISTINCT FROM(expected->>'strict')::boolean OR helper.proleakproof IS DISTINCT FROM(expected->>'leakproof')::boolean OR
   helper.proparallel IS DISTINCT FROM(expected->>'parallel')::"char" OR coalesce(to_jsonb(helper.proconfig),'null'::jsonb) IS DISTINCT FROM expected->'config' OR
   actual_acl IS DISTINCT FROM expected_acl THEN RAISE EXCEPTION 'calendar_contract_upgrade: unexpected helper %',expected->>'signature';END IF;
 END LOOP;
END$calendar_upgrade$;

CREATE FUNCTION security.require_dated_price_source(catalog uuid,schedule uuid,leaf trading.side_schedule_rows,terms jsonb,identity jsonb,period jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET jit=off AS $$
DECLARE market trading.side_schedule_bindings;source trading.side_schedule_bindings;custom trading.custom_curve_projection_bindings;
 contract market_data.contracts;fixing market_data.index_fixing_observations;captured jsonb;selection jsonb;expected jsonb;
 reference_revision jsonb=jsonb_build_array('reference_revision',leaf.unit_catalog_id,leaf.unit_revision_id);
BEGIN
 SELECT * INTO STRICT market FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal,port)=(catalog,schedule,leaf.ordinal,'market');
 SELECT * INTO STRICT contract FROM market_data.contracts WHERE(catalog_id,revision_id,id)=(market.source_catalog_id,market.definition_revision_id,market.contract_id);
 IF NOT EXISTS(SELECT 1 FROM trading.side_schedule_bindings b WHERE(b.catalog_id,b.schedule_id,b.row_ordinal,b.port,b.kind,b.reference_catalog_id,b.reference_revision_id,b.quote_code)=
  (catalog,schedule,leaf.ordinal,'quote','quote',leaf.unit_catalog_id,leaf.unit_revision_id,terms->>'quote'))
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF terms->>'implementation'='contract_observation_average_v1' THEN
  IF leaf.operation<>'contract_observation_price' THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  SELECT x INTO captured FROM jsonb_array_elements(period->'ContractObservations') x WHERE(x->>'Ordinal')::integer=(leaf.parameters->>'observationOrdinal')::integer;
  SELECT x INTO expected FROM jsonb_array_elements(terms->'contractObservations') x WHERE(x->>'ordinal')::integer=(leaf.parameters->>'observationOrdinal')::integer;
  SELECT * INTO STRICT source FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal,port)=(catalog,schedule,leaf.ordinal,'settlement');
  IF captured IS NULL OR expected IS NULL OR(source.source_catalog_id,source.definition_revision_id,source.series_id,source.source_code,source.coordinate)
   IS DISTINCT FROM(catalog,(terms->>'definitionRevision')::uuid,(expected->>'seriesId')::uuid,expected->>'sourceCode',
    CASE terms#>>'{contractObservationTerms,role}' WHEN 'daily_settlement' THEN 'DailySettlement' WHEN 'trader_mark' THEN 'TraderMark' END)
   OR (market.contract_id,leaf.observation_from,leaf.observation_to,(leaf.parameters->>'sampleAt')::timestamptz,(leaf.parameters->>'selectionAt')::timestamptz)
    IS DISTINCT FROM((expected->>'contractId')::uuid,(expected->>'observationFrom')::date,(expected->>'observationTo')::date,(expected->>'fixingAt')::timestamptz,(expected->>'selectionAt')::timestamptz)
   OR(leaf.observation_from,leaf.observation_to,(leaf.parameters->>'sampleAt')::timestamptz,(leaf.parameters->>'selectionAt')::timestamptz)
    IS DISTINCT FROM((captured->>'From')::date,(captured->>'To')::date,(captured->>'FixingAt')::timestamptz,(captured->>'SelectionAt')::timestamptz)
   OR captured#>'{Market,2}' IS DISTINCT FROM jsonb_build_array('contract',jsonb_build_array('definition_revision',catalog,market.definition_revision_id),market.contract_id)
   OR captured#>'{Market,1}' IS DISTINCT FROM jsonb_build_array('curve',jsonb_build_array('definition_revision',catalog,market.definition_revision_id),market.curve_code)
   OR captured->'Quote' IS DISTINCT FROM identity->'DateQuote'
   OR captured#>'{Contract,1}' IS DISTINCT FROM captured#>'{Market,2}'
   OR(captured#>>'{Contract,2}')::integer IS DISTINCT FROM(CASE contract.kind WHEN 'future' THEN 1 WHEN 'forward' THEN 2 WHEN 'future_option' THEN 3 END)
   OR((captured#>>'{Contract,3}')::date,(captured#>>'{Contract,4}')::date,(captured#>>'{Contract,5}')::timestamptz)
    IS DISTINCT FROM(contract.delivery_from,contract.delivery_to,contract.expiry_at)
   OR captured->'Source' IS DISTINCT FROM jsonb_build_array('reference',reference_revision,source.source_code)
   OR captured->'Series' IS DISTINCT FROM jsonb_build_array('series',jsonb_build_array('definition_revision',catalog,source.definition_revision_id),source.series_id)
   OR captured->>'Implementation' IS DISTINCT FROM leaf.parameters->>'implementation'
   OR leaf.parameters->>'expiryPolicy' IS DISTINCT FROM(CASE terms#>>'{contractObservationTerms,expiryPolicy}' WHEN 'require_live' THEN 'RequireLive' WHEN 'carry_final_settlement' THEN 'CarryFinalSettlement' END)
   OR(captured->>'ExpiryPolicy')::integer IS DISTINCT FROM(CASE leaf.parameters->>'expiryPolicy' WHEN 'RequireLive' THEN 1 WHEN 'CarryFinalSettlement' THEN 2 END)
   OR(captured->>'Role')::integer IS DISTINCT FROM(CASE source.coordinate WHEN 'TraderMark' THEN 1 WHEN 'DailySettlement' THEN 2 END)
   OR(SELECT count(*) FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal)=(catalog,schedule,leaf.ordinal))<>3
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 ELSE
  selection=jsonb_build_object('contract','price_settlement_selection_v1','CurveTargetIndex',jsonb_build_array('reference',reference_revision,terms->>'index'),
   'Mode',CASE terms->>'settlementMode' WHEN 'curve_target' THEN 1 WHEN 'override' THEN 2 END,
   'ProjectionPolicy',terms->'settlementProjectionPolicy','SelectedIndex',jsonb_build_array('reference',reference_revision,terms->>'settlementIndex'));
  IF identity->'DateSettlement' IS DISTINCT FROM selection OR(leaf.parameters->>'selection')::jsonb IS DISTINCT FROM selection
   OR(leaf.observation_from,leaf.observation_to) IS DISTINCT FROM(contract.delivery_from,contract.delivery_to)
   OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_bindings b WHERE(b.catalog_id,b.schedule_id,b.row_ordinal,b.port,b.kind,b.reference_catalog_id,b.reference_revision_id,b.index_code)=
    (catalog,schedule,leaf.ordinal,'index','index',leaf.unit_catalog_id,leaf.unit_revision_id,terms->>'settlementIndex'))
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  SELECT * INTO STRICT source FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal,port)=(catalog,schedule,leaf.ordinal,'fixing');
  SELECT * INTO STRICT fixing FROM market_data.index_fixing_observations WHERE(catalog_id,revision_id,index_code,observation_from,observation_to)=
   (catalog,(terms->>'definitionRevision')::uuid,terms->>'settlementIndex',contract.delivery_from,contract.delivery_to);
  SELECT x INTO captured FROM jsonb_array_elements(period->'Fixings') x WHERE(x->>'From')::date=contract.delivery_from AND(x->>'To')::date=contract.delivery_to;
  IF(source.source_catalog_id,source.definition_revision_id,source.fixing_index_code,source.fixing_from,source.fixing_to,source.series_id,source.source_code,source.coordinate)
   IS DISTINCT FROM(fixing.catalog_id,fixing.revision_id,fixing.index_code,fixing.observation_from,fixing.observation_to,fixing.series_id,fixing.source_code,fixing.implementation)
   OR captured IS NULL OR(captured->>'FixingAt')::timestamptz IS DISTINCT FROM fixing.fixing_at
   OR captured->'Index' IS DISTINCT FROM jsonb_build_array('reference',reference_revision,fixing.index_code)
   OR captured->'Quote' IS DISTINCT FROM jsonb_build_array('reference',reference_revision,fixing.quote_code)
   OR captured->'Source' IS DISTINCT FROM jsonb_build_array('reference',reference_revision,fixing.source_code)
   OR captured->'Series' IS DISTINCT FROM jsonb_build_array('series',jsonb_build_array('definition_revision',catalog,fixing.revision_id),fixing.series_id)
   OR captured->>'Implementation' IS DISTINCT FROM fixing.implementation
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  IF terms->>'customProjection' IS NULL THEN
   IF leaf.operation<>'price_lookup' OR nullif(period->'CustomProjection','null'::jsonb) IS NOT NULL
    OR(SELECT count(*) FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal)=(catalog,schedule,leaf.ordinal))<>4
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  ELSE
   SELECT * INTO STRICT custom FROM trading.custom_curve_projection_bindings WHERE(catalog_id,id)=(catalog,(terms->>'customProjection')::uuid);
   IF period->'CustomProjection' IS DISTINCT FROM jsonb_build_array('custom_projection',custom.catalog_id,custom.curve_id,custom.version,custom.output_node,custom.position,custom.selection,custom.implementation)
    OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_bindings b WHERE(b.catalog_id,b.schedule_id,b.row_ordinal,b.port,b.kind,b.custom_catalog_id,b.custom_curve_id,b.custom_version,b.output_node,b.position)
     IS NOT DISTINCT FROM(catalog,schedule,leaf.ordinal,'projection','custom_output',custom.catalog_id,custom.curve_id,custom.version,custom.output_node,custom.position))
    OR(SELECT count(*) FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal)=(catalog,schedule,leaf.ordinal))<>5
    OR leaf.operation IS DISTINCT FROM(CASE custom.selection WHEN 'containing_delivery_interval_v1' THEN 'curve_price_lookup' ELSE 'price_lookup' END)
    OR custom.selection='containing_delivery_interval_v1' AND((leaf.parameters->>'from')::date,(leaf.parameters->>'to')::date,leaf.parameters->>'policy')
      IS DISTINCT FROM(contract.delivery_from,contract.delivery_to,custom.selection)
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  END IF;
 END IF;
END$$;
ALTER FUNCTION security.require_dated_price_source(uuid,uuid,trading.side_schedule_rows,jsonb,jsonb,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.require_dated_price_source(uuid,uuid,trading.side_schedule_rows,jsonb,jsonb,jsonb) FROM PUBLIC;

-- Reconstruct the canonical parameter/source contract from prepared native terms.
-- Graph rows are checked separately; equal cash alone is not identity agreement.
CREATE FUNCTION security.require_dated_period_identity(catalog uuid,side uuid,period_number integer,terms jsonb,identity jsonb,price_unit jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET jit=off AS $$
DECLARE period jsonb=identity->'Periods'->period_number;expected jsonb;payment jsonb;pricing text;binding jsonb;
 reference jsonb=identity#>'{QuantityBasis,1}';definition jsonb=jsonb_build_array('definition_revision',catalog,(terms->>'definitionRevision')::uuid);
 curve jsonb;calendar_identity jsonb='null';business_dates jsonb;observations jsonb='[]';fixings jsonb='[]';projections jsonb='[]';lookups jsonb='[]';
 row jsonb;contract market_data.contracts;fixing market_data.index_fixing_observations;custom trading.custom_curve_projection_bindings;
 calendar ref_data.calendars;calendar_binding trading.side_calendar_bindings;contract_key jsonb;contract_identity jsonb;market jsonb;quantity jsonb;lookup jsonb;
 averaging integer;sampled boolean=terms->>'implementation'='contract_observation_average_v1';offset_count integer;custom_identity jsonb='null';
BEGIN
 SELECT pricing_binding_identity INTO STRICT pricing FROM trading.sides WHERE(catalog_id,id)=(catalog,side);
 payment=CASE WHEN terms->>'paymentRule' IS NULL THEN 'null'::jsonb ELSE security.side_payment_provenance(catalog,side,(terms->>'paymentRule')::uuid,
  (terms->>'deliveryFrom')::date,(terms->>'deliveryTo')::date)->'paymentRule' END;
 expected=jsonb_build_object('contract',CASE WHEN terms->>'kind'='fixed' THEN 'fixed_side_period_v2' WHEN sampled THEN 'floating_side_period_v4' ELSE 'floating_side_period_v3' END,
  'DeliveryFrom',(terms->>'deliveryFrom')::date,'DeliveryTo',(terms->>'deliveryTo')::date,
  'PaymentAt',to_char((terms->>'paymentAt')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00',
  'DeliveryCompletionAt',CASE WHEN period->>'DeliveryCompletionAt' IS NOT NULL THEN to_jsonb(to_char((period->>'DeliveryCompletionAt')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00') ELSE 'null'::jsonb END,
  'Allocation',period->'Allocation','PaymentSchedule',payment);
 IF terms->>'kind'='fixed' THEN
  IF pricing<>'' OR period IS DISTINCT FROM expected THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  RETURN;
 END IF;
 averaging=CASE terms->>'averaging' WHEN 'monthly_index_price' THEN 1 WHEN 'calendar_day_arithmetic' THEN 2 WHEN 'observation_arithmetic' THEN 3
  WHEN 'calendar_days_previous' THEN 4 WHEN 'calendar_days_next' THEN 5 WHEN 'quantity_weighted' THEN 6 END;
 curve=jsonb_build_array('curve',definition,terms->>'curve');
 IF averaging IN(3,4,5) THEN
  SELECT * INTO STRICT calendar_binding FROM trading.side_calendar_bindings WHERE(catalog_id,side_id,purpose)=(catalog,side,'Observation');
  SELECT * INTO STRICT calendar FROM ref_data.calendars WHERE(catalog_id,revision_id,code)=
   (calendar_binding.reference_catalog_id,calendar_binding.reference_revision_id,calendar_binding.calendar_code);
  SELECT coalesce(jsonb_agg(day::date ORDER BY day),'[]'::jsonb) INTO business_dates
   FROM generate_series(calendar.coverage_from::timestamp,calendar.coverage_to::timestamp-interval '1 day',interval '1 day') d(day)
   LEFT JOIN ref_data.calendar_days e ON(e.catalog_id,e.revision_id,e.calendar_code,e.business_date)=(calendar.catalog_id,calendar.revision_id,calendar.code,day::date)
   WHERE coalesce(e.is_business_day,(calendar.weekend_mask&(1<<(extract(isodow FROM day)::integer-1)))=0);
  calendar_identity=jsonb_build_array('observation_calendar',jsonb_build_array('reference',jsonb_build_array('reference_revision',calendar.catalog_id,calendar.revision_id),calendar.code),
   jsonb_build_array('date_set',calendar.coverage_from,calendar.coverage_to,business_dates));
 END IF;
 FOR row IN SELECT value FROM jsonb_array_elements(CASE WHEN sampled THEN terms->'contractObservations' ELSE terms->'projections' END) ORDER BY(value->>'ordinal')::integer LOOP
  SELECT * INTO STRICT contract FROM market_data.contracts WHERE(catalog_id,revision_id,id)=(catalog,(terms->>'definitionRevision')::uuid,(row->>'contractId')::uuid);
  contract_key=jsonb_build_array('contract',definition,contract.id);market=jsonb_build_array('request',curve,contract_key);
  contract_identity=jsonb_build_array('market_contract',contract_key,CASE contract.kind WHEN 'future' THEN 1 WHEN 'forward' THEN 2 WHEN 'future_option' THEN 3 END,
   contract.delivery_from,contract.delivery_to,to_char(contract.expiry_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00',
   CASE WHEN contract.futures_series_code IS NOT NULL THEN jsonb_build_array('reference',jsonb_build_array('reference_revision',contract.reference_catalog_id,contract.reference_revision_id),contract.futures_series_code) ELSE 'null'::jsonb END);
  IF sampled THEN
   lookup=jsonb_build_object('contract','contract_observation_source_v1','Market',market,'Contract',contract_identity,'Quote',identity->'DateQuote',
    'Ordinal',(row->>'ordinal')::integer,'From',(row->>'observationFrom')::date,'To',(row->>'observationTo')::date,
    'FixingAt',to_char((row->>'fixingAt')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00',
    'SelectionAt',to_char((row->>'selectionAt')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00',
    'Source',jsonb_build_array('reference',reference,row->>'sourceCode'),'Series',jsonb_build_array('series',definition,(row->>'seriesId')::uuid),
    'Role',CASE terms#>>'{contractObservationTerms,role}' WHEN 'trader_mark' THEN 1 WHEN 'daily_settlement' THEN 2 END,
    'ExpiryPolicy',CASE terms#>>'{contractObservationTerms,expiryPolicy}' WHEN 'require_live' THEN 1 WHEN 'carry_final_settlement' THEN 2 END,'Implementation','contract_observation_source_v1');
   lookups=lookups||jsonb_build_array(lookup);
   observations=observations||jsonb_build_array(jsonb_build_array('observation',(row->>'observationFrom')::date,(row->>'observationTo')::date,NULL));
  ELSE
   quantity=CASE WHEN row->>'quantity' IS NOT NULL THEN jsonb_build_array('quantity',trim_scale((row->>'quantity')::numeric)::text,identity->'QuantityBasis') ELSE 'null'::jsonb END;
   projections=projections||jsonb_build_array(jsonb_build_array('projection',market,contract_identity,quantity));
   observations=observations||jsonb_build_array(jsonb_build_array('observation',contract.delivery_from,contract.delivery_to,quantity));
   SELECT * INTO STRICT fixing FROM market_data.index_fixing_observations WHERE(catalog_id,revision_id,index_code,observation_from,observation_to)=
    (catalog,(terms->>'definitionRevision')::uuid,terms->>'settlementIndex',contract.delivery_from,contract.delivery_to);
   fixings=fixings||jsonb_build_array(jsonb_build_object('contract','IndexFixing_v1','Index',jsonb_build_array('reference',reference,fixing.index_code),
    'Quote',jsonb_build_array('reference',reference,fixing.quote_code),'From',fixing.observation_from,'To',fixing.observation_to,
    'FixingAt',to_char(fixing.fixing_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00',
    'Series',jsonb_build_array('series',definition,fixing.series_id),'Source',jsonb_build_array('reference',reference,fixing.source_code),'Implementation',fixing.implementation));
  END IF;
 END LOOP;
 IF NOT sampled AND terms->>'customProjection' IS NOT NULL THEN
  SELECT * INTO STRICT custom FROM trading.custom_curve_projection_bindings WHERE(catalog_id,id)=(catalog,(terms->>'customProjection')::uuid);
  custom_identity=jsonb_build_array('custom_projection',custom.catalog_id,custom.curve_id,custom.version,custom.output_node,custom.position,custom.selection,custom.implementation);
 END IF;
 expected=expected||jsonb_build_object('FirstFixingAt',to_char((terms->>'firstFixingAt')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00',
  'Averaging',averaging,'ObservationImplementation',terms->'implementation','Calendar',calendar_identity,'ObservationSchedule',observations,'Fixings',fixings,
  'Spread',CASE WHEN(terms->>'spread')::numeric=0 THEN 'null'::jsonb ELSE jsonb_build_array('price',trim_scale((terms->>'spread')::numeric)::text,price_unit) END,
  'ProjectionCurve',curve,'CustomProjection',custom_identity);
 IF sampled THEN expected=expected||jsonb_build_object('ContractObservations',lookups);END IF;
 IF period IS DISTINCT FROM expected OR sampled AND identity->'DateSettlement' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 binding=pricing::jsonb;
 IF sampled THEN
  SELECT coalesce(sum(jsonb_array_length(value->'ContractObservations')),0)::integer INTO offset_count FROM jsonb_array_elements(identity->'Periods') WITH ORDINALITY p(value,n) WHERE n<=period_number;
  IF binding-'Observations' IS DISTINCT FROM '{"contract":"contract_observation_bindings_v1"}'::jsonb OR
   jsonb_array_length(binding->'Observations') IS DISTINCT FROM(SELECT sum(jsonb_array_length(value->'ContractObservations'))::integer FROM jsonb_array_elements(identity->'Periods')) OR
   (SELECT jsonb_agg(value ORDER BY n) FROM jsonb_array_elements(binding->'Observations') WITH ORDINALITY p(value,n) WHERE n>offset_count AND n<=offset_count+jsonb_array_length(lookups)) IS DISTINCT FROM lookups
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 ELSE
  IF binding-'Periods' IS DISTINCT FROM '{"contract":"whole_term_projection_bindings_v1"}'::jsonb OR
   jsonb_array_length(binding->'Periods') IS DISTINCT FROM jsonb_array_length(identity->'Periods') OR
   binding->'Periods'->period_number IS DISTINCT FROM jsonb_build_object('contract','floating_projection_binding_v1','Projections',projections)
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 END IF;
END$$;
ALTER FUNCTION security.require_dated_period_identity(uuid,uuid,integer,jsonb,jsonb,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.require_dated_period_identity(uuid,uuid,integer,jsonb,jsonb,jsonb) FROM PUBLIC;

CREATE FUNCTION security.require_dated_swap_period(catalog uuid,side uuid,period_number integer,terms jsonb,numerator numeric,denominator numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET jit=off AS $$
DECLARE identity jsonb;period jsonb;price jsonb;quote_reference jsonb;quantity_reference jsonb;price_unit jsonb;
 quote ref_data.quote_specifications;schedule uuid;
 guard trading.side_schedule_rows;amount trading.side_schedule_rows;quantity trading.side_schedule_rows;
 discounted trading.side_schedule_rows;discount trading.side_schedule_rows;side_sum trading.side_schedule_rows;
 average trading.side_schedule_rows;application trading.side_schedule_rows;leaf trading.side_schedule_rows;adder trading.side_schedule_rows;
 market trading.side_schedule_bindings;expected jsonb;coefficients jsonb='{}';entry jsonb;key text;
 count_apps integer=0;expected_count integer;pn numeric;pd numeric;an numeric;ad numeric;common numeric;total numeric;
BEGIN
 SELECT s.economic_identity::jsonb,h.id INTO STRICT identity,schedule FROM trading.sides s
  JOIN trading.side_schedules h ON(h.catalog_id,h.side_id)=(s.catalog_id,s.id)
  JOIN trading.side_schedule_seals z ON(z.catalog_id,z.schedule_id)=(h.catalog_id,h.id)
  WHERE(s.catalog_id,s.id)=(catalog,side) AND h.generator_version='whole_term_side_blocks_v3';
 period=identity->'Periods'->period_number;
 IF identity-'contract'-'CalendarPolicy'-'GasDeliveryClock'-'IntervalDefinition'-'Periods'-'PowerQuantity'-'QuantityBasis'-
  (CASE WHEN terms->>'kind'='fixed' THEN 'DateQuoteKey' ELSE 'DateQuote' END)-
  (CASE WHEN terms->>'kind'='fixed' THEN 'Price' ELSE 'DateSettlement' END)-
  (CASE WHEN terms->>'kind'='fixed' THEN 'contract' ELSE 'IntervalPriceDefinition' END) IS DISTINCT FROM '{}'::jsonb OR
  (SELECT count(*) FROM jsonb_object_keys(identity))<>(CASE WHEN terms->>'kind'='fixed' THEN 9 ELSE 10 END) OR
  identity->'GasDeliveryClock' IS DISTINCT FROM 'null'::jsonb OR identity->'IntervalDefinition' IS DISTINCT FROM 'null'::jsonb OR
  terms->>'kind'='floating' AND identity->'IntervalPriceDefinition' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF jsonb_typeof(period->'Allocation') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF jsonb_array_length(period->'Allocation')<>3 OR period#>>'{Allocation,0}' IS DISTINCT FROM 'exact_ratio' OR
  coalesce(period#>>'{Allocation,1}','')!~'^[1-9][0-9]*$' OR coalesce(period#>>'{Allocation,2}','')!~'^[1-9][0-9]*$' OR
  (period#>>'{Allocation,1}')::numeric>=power(2::numeric,4096) OR(period#>>'{Allocation,2}')::numeric>=power(2::numeric,4096) OR
  gcd((period#>>'{Allocation,1}')::numeric,(period#>>'{Allocation,2}')::numeric)<>1
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;

 SELECT * INTO STRICT quote FROM ref_data.quote_specifications WHERE(catalog_id,revision_id,code)=
  ((identity#>>'{QuantityBasis,1,1}')::uuid,(identity#>>'{QuantityBasis,1,2}')::uuid,terms->>'quote');
 quote_reference=jsonb_build_array('reference',jsonb_build_array('reference_revision',quote.catalog_id,quote.revision_id),quote.code);
 quantity_reference=jsonb_build_array('reference',jsonb_build_array('reference_revision',quote.catalog_id,quote.revision_id),quote.quantity_code);
 price_unit=jsonb_build_array('price_unit',jsonb_build_array('reference',jsonb_build_array('reference_revision',quote.catalog_id,quote.revision_id),quote.currency_code),quantity_reference,trim_scale(quote.multiplier)::text);
 IF identity->'QuantityBasis' IS DISTINCT FROM quantity_reference OR
  (CASE WHEN terms->>'kind'='fixed' THEN identity->'DateQuoteKey' ELSE identity#>'{DateQuote,1}' END) IS DISTINCT FROM quote_reference
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF terms->>'kind'='floating' AND identity->'DateQuote' IS DISTINCT FROM jsonb_build_array('quote',quote_reference,
  CASE quote.kind WHEN 'outright' THEN 1 WHEN 'basis' THEN 2 END,price_unit->1,quantity_reference,trim_scale(quote.multiplier)::text,
  trim_scale(quote.trading_tick)::text,trim_scale(quote.clearing_increment)::text,trim_scale(quote.minimum)::text,trim_scale(quote.maximum)::text)
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF period IS NULL OR (period->>'DeliveryFrom')::date IS DISTINCT FROM(terms->>'deliveryFrom')::date
  OR (period->>'DeliveryTo')::date IS DISTINCT FROM(terms->>'deliveryTo')::date
  OR (period->>'PaymentAt')::timestamptz IS DISTINCT FROM(terms->>'paymentAt')::timestamptz
  OR (period#>>'{Allocation,1}')::numeric*denominator IS DISTINCT FROM numerator*(period#>>'{Allocation,2}')::numeric
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 PERFORM security.require_dated_period_identity(catalog,side,period_number,terms,identity,price_unit);
 IF terms->>'kind'='fixed' THEN
  price=jsonb_build_array('price',trim_scale((terms->>'price')::numeric)::text,price_unit);
  IF identity->>'contract' IS DISTINCT FROM 'FixedSide_v5' THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  IF identity#>>'{Price,contract}'='ppa_stepped_price_v1' THEN
   IF (identity->'Price')-'Steps' IS DISTINCT FROM '{"contract":"ppa_stepped_price_v1"}'::jsonb OR
    jsonb_array_length(identity#>'{Price,Steps}') IS DISTINCT FROM jsonb_array_length(identity->'Periods') OR
    (SELECT count(DISTINCT x->'Price') FROM jsonb_array_elements(identity#>'{Price,Steps}') x)<=1 OR
    identity#>ARRAY['Price','Steps',period_number::text] IS DISTINCT FROM jsonb_build_object('contract','ppa_price_step_v1','From',(terms->>'deliveryFrom')::date,'Price',price)
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  ELSIF identity->'Price' IS DISTINCT FROM jsonb_build_object('contract','ppa_flat_price_v1','Price',price)
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 ELSE
  IF identity->>'contract' IS DISTINCT FROM 'FloatingSide_v9' OR coalesce((period#>>'{Spread,1}')::numeric,0) IS DISTINCT FROM(terms->>'spread')::numeric
   OR nullif(period->'Spread','null'::jsonb) IS NOT NULL AND period#>'{Spread,2}' IS DISTINCT FROM price_unit
   OR (period#>>'{ProjectionCurve,1,1}')::uuid IS DISTINCT FROM catalog
   OR (period#>>'{ProjectionCurve,1,2}')::uuid IS DISTINCT FROM(terms->>'definitionRevision')::uuid
   OR period#>>'{ProjectionCurve,2}' IS DISTINCT FROM terms->>'curve'
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 END IF;
 SELECT r.* INTO STRICT guard FROM trading.side_schedule_roots root JOIN trading.side_schedule_rows r
  ON(r.catalog_id,r.schedule_id,r.ordinal)=(root.catalog_id,root.schedule_id,root.row_ordinal)
  WHERE(root.catalog_id,root.schedule_id,root.name,root.measure)=(catalog,schedule,'payment/'||period_number||'/pv','contribution_pv');
 SELECT r.* INTO STRICT amount FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
  ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
  WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal)=(catalog,schedule,guard.ordinal,'amount',0);
 SELECT r.* INTO STRICT discounted FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
  ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
  WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal)=(catalog,schedule,guard.ordinal,'discounted',0);
 SELECT r.* INTO STRICT discount FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
  ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
  WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal)=(catalog,schedule,discounted.ordinal,'discount',0);
 SELECT r.* INTO STRICT side_sum FROM trading.side_schedule_roots root JOIN trading.side_schedule_rows r
  ON(r.catalog_id,r.schedule_id,r.ordinal)=(root.catalog_id,root.schedule_id,root.row_ordinal)
  WHERE(root.catalog_id,root.schedule_id,root.name,root.measure)=(catalog,schedule,'pv','pv');
 IF discounted.operation<>'pv' OR discount.operation<>'discount' OR side_sum.operation<>'sum'
  OR discount.parameters IS DISTINCT FROM '{"policy":"context_required_v1"}'::jsonb
  OR(guard.parameters->>'lifecycle',guard.parameters->>'measure',guard.parameters->>'pricePolicy',guard.parameters->>'firstFixingAt')
   IS DISTINCT FROM('undue_payment_v1','present_value_v1','selected_context_v1','none')
  OR EXISTS(SELECT 1 FROM trading.side_schedule_rows r WHERE(r.catalog_id,r.schedule_id)=(catalog,schedule)
   AND r.ordinal IN(guard.ordinal,amount.ordinal,discounted.ordinal,discount.ordinal)
   AND(r.delivery_from,r.delivery_to,r.value_at,r.payment_ordinal) IS DISTINCT FROM
    ((terms->>'deliveryFrom')::date,(terms->>'deliveryTo')::date,(terms->>'paymentAt')::timestamptz,period_number))
  OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_edges e WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal,e.source)
   =(catalog,schedule,discounted.ordinal,'amount',0,amount.ordinal))
  OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_edges e WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal,e.source)
   =(catalog,schedule,side_sum.ordinal,'input',period_number,guard.ordinal))
  OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_roots r WHERE(r.catalog_id,r.schedule_id,r.name,r.measure,r.row_ordinal)
   =(catalog,schedule,'payment/'||period_number||'/cash','contractual_amount',amount.ordinal))
  OR(SELECT count(*) FROM trading.side_schedule_edges WHERE(catalog_id,schedule_id,target)=(catalog,schedule,side_sum.ordinal))<>jsonb_array_length(identity->'Periods')
  OR(SELECT count(*) FROM trading.side_schedule_roots WHERE(catalog_id,schedule_id)=(catalog,schedule))<>2*jsonb_array_length(identity->'Periods')+1
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF period_number=0 AND(EXISTS(SELECT 1 FROM trading.side_schedule_grids WHERE(catalog_id,schedule_id)=(catalog,schedule))
  OR EXISTS(SELECT 1 FROM trading.side_schedule_ports WHERE(catalog_id,schedule_id)=(catalog,schedule))
  OR EXISTS(SELECT 1 FROM trading.side_schedule_bindings b JOIN trading.side_schedule_rows r ON(r.catalog_id,r.schedule_id,r.ordinal)=(b.catalog_id,b.schedule_id,b.row_ordinal)
   WHERE(b.catalog_id,b.schedule_id)=(catalog,schedule) AND r.operation NOT IN('price_lookup','curve_price_lookup','contract_observation_price'))
  OR EXISTS(WITH RECURSIVE reached(ordinal) AS(SELECT side_sum.ordinal UNION SELECT e.source FROM reached r
    JOIN trading.side_schedule_edges e ON(e.catalog_id,e.schedule_id,e.target)=(catalog,schedule,r.ordinal))
   SELECT 1 FROM trading.side_schedule_rows r WHERE(r.catalog_id,r.schedule_id)=(catalog,schedule) AND NOT EXISTS(SELECT 1 FROM reached WHERE ordinal=r.ordinal)))
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 SELECT r.* INTO STRICT quantity FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
  ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
  WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal)=(catalog,schedule,amount.ordinal,'quantity',0);
 SELECT r.* INTO STRICT average FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
  ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
  WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal)=(catalog,schedule,amount.ordinal,'price',0);
 IF guard.operation<>'output_guard' OR amount.operation<>'amount' OR quantity.operation<>'quantity_literal' OR average.operation<>'weighted_price'
  OR(quantity.parameters->>'numerator')::numeric*denominator IS DISTINCT FROM numerator*(quantity.parameters->>'denominator')::numeric
  OR(quantity.unit_catalog_id,quantity.unit_revision_id,quantity.unit_code) IS DISTINCT FROM(quote.catalog_id,quote.revision_id,quote.quantity_code)
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 FOR application IN SELECT r.* FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
  ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
  WHERE(e.catalog_id,e.schedule_id,e.target,e.port)=(catalog,schedule,average.ordinal,'input') ORDER BY e.ordinal LOOP
  count_apps=count_apps+1;
  IF application.operation<>'price_application' OR application.parameters->>'mapping' IS DISTINCT FROM
   (CASE WHEN terms->>'kind'='fixed' THEN 'fixed_total_payment_v1' WHEN terms->>'implementation'='contract_observation_average_v1' THEN 'contract_observation_average_v1'
    ELSE CASE terms->>'averaging' WHEN 'monthly_index_price' THEN 'monthly_index_price_v1' WHEN 'calendar_day_arithmetic' THEN 'calendar_day_arithmetic_v1'
     WHEN 'observation_arithmetic' THEN 'observation_arithmetic_v1' WHEN 'calendar_days_previous' THEN 'calendar_days_previous_v1'
     WHEN 'calendar_days_next' THEN 'calendar_days_next_v1' WHEN 'quantity_weighted' THEN 'positive_quantity_weighted_v1' END END) THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  an=(application.parameters->>'numerator')::numeric;ad=(application.parameters->>'denominator')::numeric;
  IF an IS NULL OR ad IS NULL OR an<=0 OR ad<=0 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  SELECT r.* INTO STRICT leaf FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
   ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
   WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal)=(catalog,schedule,application.ordinal,'input',0);
  IF terms->>'kind'='fixed' THEN
   IF leaf.operation<>'constant_price' OR(leaf.parameters->>'numerator')::numeric IS DISTINCT FROM(terms->>'price')::numeric*(leaf.parameters->>'denominator')::numeric
    OR an<>ad OR count_apps<>1 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   key='fixed';
  ELSE
   IF (terms->>'spread')::numeric<>0 THEN
   IF leaf.operation<>'price_add' THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   IF(SELECT count(*) FROM trading.side_schedule_edges WHERE(catalog_id,schedule_id,target)=(catalog,schedule,leaf.ordinal))<>2
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   SELECT r.* INTO STRICT adder FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
    ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
    WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal)=(catalog,schedule,leaf.ordinal,'input',1);
   IF adder.operation<>'constant_price' OR(adder.parameters->>'numerator')::numeric IS DISTINCT FROM(terms->>'spread')::numeric*(adder.parameters->>'denominator')::numeric
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   SELECT r.* INTO STRICT leaf FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
    ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
    WHERE(e.catalog_id,e.schedule_id,e.target,e.port,e.ordinal)=(catalog,schedule,leaf.ordinal,'input',0);
   END IF;
   SELECT * INTO STRICT market FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal,port)=(catalog,schedule,leaf.ordinal,'market');
   IF leaf.operation NOT IN('price_lookup','curve_price_lookup','contract_observation_price') OR
    (market.source_catalog_id,market.definition_revision_id,market.curve_code) IS DISTINCT FROM(catalog,(terms->>'definitionRevision')::uuid,terms->>'curve')
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   PERFORM security.require_dated_price_source(catalog,schedule,leaf,terms,identity,period);
   key=CASE WHEN terms->>'implementation'='contract_observation_average_v1' THEN leaf.observation_from::text ELSE market.contract_id::text END;
   IF key IS NULL THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  END IF;
  IF(leaf.unit_catalog_id,leaf.unit_revision_id,leaf.unit_code,leaf.currency_catalog_id,leaf.currency_revision_id,leaf.currency_code,leaf.quote_multiplier)
   IS DISTINCT FROM(quote.catalog_id,quote.revision_id,quote.quantity_code,quote.catalog_id,quote.revision_id,quote.currency_code,quote.multiplier)
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  entry=coefficients->key;pn=coalesce((entry->>0)::numeric,0);pd=coalesce((entry->>1)::numeric,1);
  pn=pn*ad+an*pd;pd=pd*ad;common=gcd(pn,pd);
  coefficients=jsonb_set(coefficients,ARRAY[key],jsonb_build_array(trim_scale(pn/common)::text,trim_scale(pd/common)::text));
 END LOOP;
 IF count_apps=0 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF terms->>'kind'='floating' THEN
  IF terms->>'implementation'='contract_observation_average_v1' THEN
   expected=terms->'contractObservations';total=jsonb_array_length(expected);
  ELSE expected=terms->'projections';SELECT sum((x->>'weight')::numeric) INTO total FROM jsonb_array_elements(expected) x;END IF;
  expected_count=jsonb_array_length(expected);
  IF expected_count IS DISTINCT FROM(SELECT count(*) FROM jsonb_object_keys(coefficients)) THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  FOR entry IN SELECT value FROM jsonb_array_elements(expected) LOOP
   key=CASE WHEN terms->>'implementation'='contract_observation_average_v1' THEN entry->>'observationFrom' ELSE entry->>'contractId' END;
   pn=(coefficients#>>ARRAY[key,'0'])::numeric;pd=(coefficients#>>ARRAY[key,'1'])::numeric;
   IF pn IS NULL OR pd IS NULL OR pn*total IS DISTINCT FROM pd*(CASE WHEN terms->>'implementation'='contract_observation_average_v1' THEN 1 ELSE(entry->>'weight')::numeric END)
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  END LOOP;
 END IF;
END$$;
ALTER FUNCTION security.require_dated_swap_period(uuid,uuid,integer,jsonb,numeric,numeric) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.require_dated_swap_period(uuid,uuid,integer,jsonb,numeric,numeric) FROM PUBLIC;
-- Native agreement checks do not author schedules. They independently verify the
-- caller's normalized quantities against the exact declared units and inputs.
CREATE FUNCTION security.dated_quantity_ratio(rc uuid,rr uuid,source_code text,target_code text) RETURNS numeric[]
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET jit=off AS $$
DECLARE source ref_data.quantity_specifications;target ref_data.quantity_specifications;scales jsonb='{}';pending text[];at integer=1;unit text;edge record;
 prior jsonb;n numeric;d numeric;k numeric;shift numeric;
BEGIN
 SELECT * INTO STRICT source FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code)=(rc,rr,source_code);
 SELECT * INTO STRICT target FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code)=(rc,rr,target_code);
 IF(source.commodity_code,source.basis_code,source.dimension_code) IS DISTINCT FROM(target.commodity_code,target.basis_code,target.dimension_code)
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF(SELECT count(*) FROM ref_data.units WHERE(catalog_id,revision_id)=(rc,rr))>256 OR
  (SELECT count(*) FROM ref_data.unit_conversions WHERE(catalog_id,revision_id)=(rc,rr))>1024
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 -- Traverse each connected component once and reject inconsistent alternate paths.
 FOR unit IN SELECT code FROM ref_data.units WHERE(catalog_id,revision_id)=(rc,rr) ORDER BY code COLLATE "C" LOOP
  IF scales?unit THEN CONTINUE;END IF;
  scales=jsonb_set(scales,ARRAY[unit],jsonb_build_array(1,1,unit));pending=ARRAY[unit];at=1;
  WHILE at<=cardinality(pending) LOOP
   FOR edge IN SELECT to_unit_code destination,factor_numerator num,factor_denominator den FROM ref_data.unit_conversions
     WHERE(catalog_id,revision_id,from_unit_code)=(rc,rr,pending[at])
    UNION ALL SELECT from_unit_code,factor_denominator,factor_numerator FROM ref_data.unit_conversions
     WHERE(catalog_id,revision_id,to_unit_code)=(rc,rr,pending[at]) LOOP
    n=(scales#>>ARRAY[pending[at],'0'])::numeric*edge.num;d=(scales#>>ARRAY[pending[at],'1'])::numeric*edge.den;
    shift=power(10::numeric,greatest(scale(n),scale(d)));n=n*shift;d=d*shift;k=gcd(n,d);n=div(n,k);d=div(d,k);
    IF n>=power(2::numeric,4096) OR d>=power(2::numeric,4096) THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
    prior=scales->edge.destination;
    IF prior IS NOT NULL THEN
     IF(prior->>0)::numeric*d<>(prior->>1)::numeric*n THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
    ELSE scales=jsonb_set(scales,ARRAY[edge.destination],jsonb_build_array(n,d,unit));pending=array_append(pending,edge.destination);END IF;
   END LOOP;at=at+1;
  END LOOP;
 END LOOP;
 IF scales#>>ARRAY[source.unit_code,'2'] IS DISTINCT FROM scales#>>ARRAY[target.unit_code,'2'] THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 n=(scales#>>ARRAY[target.unit_code,'0'])::numeric*(scales#>>ARRAY[source.unit_code,'1'])::numeric;
 d=(scales#>>ARRAY[target.unit_code,'1'])::numeric*(scales#>>ARRAY[source.unit_code,'0'])::numeric;k=gcd(n,d);n=div(n,k);d=div(d,k);
 IF n>=power(2::numeric,4096) OR d>=power(2::numeric,4096) THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 RETURN ARRAY[n,d];
END$$;

CREATE FUNCTION security.dated_power_quantity(identity jsonb,body jsonb,prepared jsonb,period_number integer) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET jit=off AS $$
DECLARE power jsonb=identity->'PowerQuantity';period jsonb=identity->'Periods'->period_number;authored jsonb=body->'periods'->period_number;
 part jsonb;cell jsonb;ref jsonb;rc uuid;rr uuid;clock_name text;starts timestamptz;ends timestamptz;instant timestamptz;local_at timestamp;
 requested_mask text;holiday_mask text;selected boolean;closed boolean;position integer=0;hours integer=0;rate numeric=(authored->>'amount')::numeric;
 q ref_data.quantity_specifications;expected jsonb;selected_quantity text;capture jsonb;
BEGIN
 rc=(identity#>>'{QuantityBasis,1,1}')::uuid;rr=(identity#>>'{QuantityBasis,1,2}')::uuid;clock_name=body#>>'{power,clock,code}';
 IF power IS NULL OR power='null'::jsonb OR power->>'contract' IS DISTINCT FROM 'scheduled_power_quantity_parameters_v1' OR
  (power->>'IntervalMinutes')::integer IS DISTINCT FROM 60 OR(power->>'MaskMinutes')::integer IS DISTINCT FROM 60
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 FOR position IN 0..1 LOOP
  selected_quantity=CASE position WHEN 0 THEN body#>>'{quantity,code}' ELSE identity#>>'{QuantityBasis,2}' END;
  SELECT * INTO STRICT q FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code)=(rc,rr,selected_quantity);
  ref=jsonb_build_array('reference_revision',rc,rr);
  expected=jsonb_build_array('quantity_specification_v1',jsonb_build_array('reference',ref,q.code),jsonb_build_array('reference',ref,q.commodity_code),
   jsonb_build_array('reference',ref,q.basis_code),jsonb_build_array('reference',ref,q.unit_code),jsonb_build_array('reference',ref,q.dimension_code));
  IF power->(CASE position WHEN 0 THEN 'Power' ELSE 'Energy' END) IS DISTINCT FROM expected OR
   (q.unit_code,q.dimension_code) IS DISTINCT FROM(CASE position WHEN 0 THEN 'megawatt' ELSE 'megawatt_hour' END,CASE position WHEN 0 THEN 'power' ELSE 'energy' END)
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 END LOOP;
 IF power#>'{Power,2}' IS DISTINCT FROM power#>'{Energy,2}' THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 IF body#>>'{power,product}'='all_hours' THEN requested_mask=repeat('1',168);holiday_mask=requested_mask;
 ELSIF body#>>'{power,product}'='weekday_block' THEN
  IF(body#>>'{power,startHour}')::integer NOT BETWEEN 0 AND 23 OR(body#>>'{power,endHour}')::integer NOT BETWEEN 1 AND 24 OR
   (body#>>'{power,startHour}')::integer>=(body#>>'{power,endHour}')::integer OR body#>>'{power,saturday}' IS NULL
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  SELECT string_agg(CASE WHEN i/24<(CASE WHEN(body#>>'{power,saturday}')::boolean THEN 6 ELSE 5 END) AND
   i%24>=(body#>>'{power,startHour}')::integer AND i%24<(body#>>'{power,endHour}')::integer THEN '1' ELSE '0' END,'' ORDER BY i)
   INTO requested_mask FROM generate_series(0,167) i;holiday_mask=repeat('0',168);
 ELSE RAISE EXCEPTION 'side_schedule_definition';END IF;
 SELECT payload::jsonb,jsonb_build_object('contract','scheduled_power_quantity_parameters_v1',
  'Clock',jsonb_build_array('reference',jsonb_build_array('reference_revision',rc,rr),clock_name),
  'ClockRules',payload,'ClockFingerprint',encode(definition_digest,'hex'),'Power',power->'Power','Energy',power->'Energy',
  'MaskMinutes',60,'WeeklyMask',requested_mask,'HolidayMask',holiday_mask,'IntervalMinutes',60,'Periods',power->'Periods')
  INTO STRICT capture,expected FROM ref_data.clock_captures WHERE(catalog_id,revision_id,clock_code)=(rc,rr,clock_name);
 IF power IS DISTINCT FROM expected OR
  jsonb_array_length(power->'Periods') IS DISTINCT FROM jsonb_array_length(body->'periods') OR
  power->'Periods'->period_number IS DISTINCT FROM jsonb_build_object('contract','scheduled_power_quantity_period_v1',
   'From',(period->>'DeliveryFrom')::date,'To',(period->>'DeliveryTo')::date,'Rate',trim_scale(rate)::text)
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 part=prepared->'periods'->period_number->'power';position=0;
 starts=ref_data.clock_boundary(rc,rr,clock_name,(period->>'DeliveryFrom')::date);ends=ref_data.clock_boundary(rc,rr,clock_name,(period->>'DeliveryTo')::date);
 FOR instant IN SELECT generate_series(starts,ends-interval '1 hour',interval '1 hour') LOOP
  local_at=ref_data.clock_local(rc,rr,clock_name,instant);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(capture->'Runs') r WHERE(r->>'From')::timestamptz>instant AND(r->>'From')::timestamptz<instant+interval '1 hour') OR
   date_trunc('hour',local_at)<>local_at OR ref_data.clock_local(rc,rr,clock_name,instant+interval '1 hour'-interval '1 microsecond')<>local_at+interval '1 hour'-interval '1 microsecond'
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  closed=EXISTS(SELECT 1 FROM jsonb_array_elements(identity#>'{CalendarPolicy,Delivery,Calendar,Exceptions}') x WHERE(x->>'Date')::date=local_at::date AND NOT(x->>'Open')::boolean);
  selected=substr(CASE WHEN closed THEN holiday_mask ELSE requested_mask END,(extract(isodow FROM local_at)::integer-1)*24+extract(hour FROM local_at)::integer+1,1)='1';
  IF NOT selected THEN CONTINUE;END IF;
  cell=part->'intervals'->position;
  IF cell IS NULL OR((cell#>>'{interval,start}')::timestamptz,(cell#>>'{interval,end}')::timestamptz,(cell#>>'{interval,operatingDate}')::date)
   IS DISTINCT FROM(instant,instant+interval '1 hour',local_at::date) OR
   (cell#>>'{energy,numerator}')::numeric IS DISTINCT FROM rate*(cell#>>'{energy,denominator}')::numeric
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  position=position+1;hours=hours+1;
 END LOOP;
 IF hours=0 OR starts+make_interval(hours=>extract(epoch FROM ends-starts)::integer/3600)<>ends OR
  jsonb_array_length(part->'intervals') IS DISTINCT FROM position OR(part->>'durationTicks')::numeric IS DISTINCT FROM hours::numeric*36000000000 OR
  part->>'energyQuantity' IS DISTINCT FROM identity#>>'{QuantityBasis,2}' OR
  (part#>>'{total,numerator}')::numeric IS DISTINCT FROM rate*hours*(part#>>'{total,denominator}')::numeric
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
 RETURN rate*hours;
END$$;

CREATE FUNCTION security.require_dated_quantities(catalog uuid,operation uuid,body jsonb,compiled jsonb,quantity numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET jit=off AS $$
DECLARE identities jsonb='[]';totals jsonb='[]';amounts jsonb;side jsonb;identity jsonb;period jsonb;shape jsonb;factor jsonb=body#>'{scheduled,factor}';
 currencies jsonb='[]';currency_code text;slot integer;n integer;rc uuid;rr uuid;native text;ratio numeric[];other numeric[];pn numeric;pd numeric;tn numeric;td numeric;k numeric;days integer;basis text;
BEGIN
 FOR slot IN 0..1 LOOP
  SELECT economic_identity::jsonb INTO STRICT identity FROM trading.sides WHERE(catalog_id,id)=(catalog,security.staged_economic_side(catalog,operation,slot));
  identities=identities||jsonb_build_array(identity);side=body->'scheduled'->(CASE slot WHEN 0 THEN 'first' ELSE 'second' END);shape=compiled->slot;
  rc=(identity#>>'{QuantityBasis,1,1}')::uuid;rr=(identity#>>'{QuantityBasis,1,2}')::uuid;native=identity#>>'{QuantityBasis,2}';basis=side->>'basis';
  IF(side#>>'{quantity,revision,catalogId}')::uuid IS DISTINCT FROM rc OR(side#>>'{quantity,revision,revisionId}')::uuid IS DISTINCT FROM rr OR
   jsonb_array_length(side->'periods') IS DISTINCT FROM jsonb_array_length(identity->'Periods') THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  SELECT q.currency_code INTO STRICT currency_code FROM ref_data.quote_specifications q WHERE(q.catalog_id,q.revision_id,q.code)=
   (rc,rr,coalesce(identity#>>'{DateQuoteKey,2}',identity#>>'{DateQuote,1,2}'));
  currencies=currencies||jsonb_build_array(jsonb_build_array('reference',identity#>'{QuantityBasis,1}',currency_code));
  IF slot=1 AND(currencies->0 IS DISTINCT FROM currencies->1 OR
   body#>>'{scheduled,implementation}'='whole_term_scheduled_financial_swap_v1' AND identities#>'{0,QuantityBasis}' IS DISTINCT FROM identity->'QuantityBasis')
  THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  IF basis='factor_of_first_side_v1' THEN
   IF slot<>1 OR factor IS NULL OR side#>>'{quantity,code}' IS DISTINCT FROM native OR
    EXISTS(SELECT 1 FROM ref_data.quantity_specifications a JOIN ref_data.quantity_specifications b
     ON(b.catalog_id,b.revision_id,b.code)=(rc,rr,native)
     WHERE(a.catalog_id,a.revision_id,a.code)=(rc,rr,identities#>>'{0,QuantityBasis,2}') AND a.commodity_code=b.commodity_code)
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   ratio=security.dated_quantity_ratio(rc,rr,identities#>>'{0,QuantityBasis,2}',factor#>>'{denominatorQuantity,code}');
   other=security.dated_quantity_ratio(rc,rr,factor#>>'{numeratorQuantity,code}',native);
   pn=(totals#>>'{0,0}')::numeric*ratio[1]*other[1]*(factor->>'value')::numeric;pd=(totals#>>'{0,1}')::numeric*ratio[2]*other[2];
   FOR n IN 0..jsonb_array_length(identity->'Periods')-1 LOOP
    IF identities#>ARRAY['0','Periods',n::text,'Allocation'] IS DISTINCT FROM identity#>ARRAY['Periods',n::text,'Allocation'] OR
     (identities#>>ARRAY['0','Periods',n::text,'DeliveryFrom'],identities#>>ARRAY['0','Periods',n::text,'DeliveryTo']) IS DISTINCT FROM
      (identity#>>ARRAY['Periods',n::text,'DeliveryFrom'],identity#>>ARRAY['Periods',n::text,'DeliveryTo'])
    THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   END LOOP;
   totals=totals||jsonb_build_array(jsonb_build_array(pn,pd));CONTINUE;
  END IF;
  ratio=CASE WHEN basis='selected_interval_power' THEN ARRAY[1::numeric,1::numeric] ELSE security.dated_quantity_ratio(rc,rr,side#>>'{quantity,code}',native) END;
  amounts='[]';tn=0;td=1;
  SELECT sum((x->>'DeliveryTo')::date-(x->>'DeliveryFrom')::date) INTO days FROM jsonb_array_elements(identity->'Periods') x;
  FOR n IN 0..jsonb_array_length(identity->'Periods')-1 LOOP
   period=identity->'Periods'->n;pd=1;
   IF basis<>'selected_interval_power' AND body#>>'{scheduled,implementation}'='whole_term_scheduled_financial_swap_v1' THEN
    pn=CASE WHEN basis='contract_total' THEN(side->>'amount')::numeric ELSE(side->'periods'->n->>'amount')::numeric END;
    IF mod(pn*ratio[1]*1000000000000000000,ratio[2])<>0 OR pn*ratio[1]>=1000000000000000000000000*ratio[2]
    THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   END IF;
   CASE basis
    WHEN 'period_total' THEN pn=(side->'periods'->n->>'amount')::numeric;
    WHEN 'calendar_day_rate' THEN pn=(side->'periods'->n->>'amount')::numeric*((period->>'DeliveryTo')::date-(period->>'DeliveryFrom')::date);
    WHEN 'contract_total' THEN
     IF side->>'allocation'='equal_periods' THEN pn=(side->>'amount')::numeric;pd=jsonb_array_length(identity->'Periods');
     ELSIF side->>'allocation'='calendar_days' THEN pn=(side->>'amount')::numeric*((period->>'DeliveryTo')::date-(period->>'DeliveryFrom')::date);pd=days;
     ELSE RAISE EXCEPTION 'side_schedule_definition';END IF;
    WHEN 'selected_interval_power' THEN pn=security.dated_power_quantity(identity,side,shape,n);
    ELSE RAISE EXCEPTION 'side_schedule_definition';
   END CASE;
   pn=pn*ratio[1];pd=pd*ratio[2];
   IF pn IS NULL OR pd IS NULL OR pn<=0 OR pd<=0 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   amounts=amounts||jsonb_build_array(jsonb_build_array(pn,pd));tn=tn*pd+pn*td;td=td*pd;
   k=power(10::numeric,greatest(scale(tn),scale(td)));tn=tn*k;td=td*k;k=gcd(tn,td);tn=div(tn,k);td=div(td,k);
  END LOOP;
  FOR n IN 0..jsonb_array_length(identity->'Periods')-1 LOOP
   IF(amounts#>>ARRAY[n::text,'0'])::numeric*td*(shape#>>ARRAY['periods',n::text,'denominator'])::numeric
    IS DISTINCT FROM(amounts#>>ARRAY[n::text,'1'])::numeric*tn*(shape#>>ARRAY['periods',n::text,'numerator'])::numeric
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
  END LOOP;
  totals=totals||jsonb_build_array(jsonb_build_array(tn,td));
 END LOOP;
 IF quantity*(totals#>>'{0,1}')::numeric IS DISTINCT FROM(totals#>>'{0,0}')::numeric OR
  (compiled#>>'{1,relativeNumerator}')::numeric*(totals#>>'{0,0}')::numeric*(totals#>>'{1,1}')::numeric IS DISTINCT FROM
  (compiled#>>'{1,relativeDenominator}')::numeric*(totals#>>'{1,0}')::numeric*(totals#>>'{0,1}')::numeric
 THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
END$$;

DO $$DECLARE signature regprocedure;BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'security.dated_quantity_ratio(uuid,uuid,text,text)'::regprocedure,
  'security.dated_power_quantity(jsonb,jsonb,jsonb,integer)'::regprocedure,
  'security.require_dated_quantities(uuid,uuid,jsonb,jsonb,numeric)'::regprocedure] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',signature);
 END LOOP;
END$$;
DO $$DECLARE source text;marker text;BEGIN
 source=pg_get_functiondef('security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamptz,jsonb,uuid[])'::regprocedure);
 marker='children=children||jsonb_build_array(jsonb_build_object(''terms'',parameters,''n'',num,''d'',den));';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_schedule_agreement_upgrade';END IF;
 source=replace(source,marker,'PERFORM security.require_dated_swap_period(catalog,security.staged_economic_side(catalog,operation,slot),n,parameters,num,den);'||marker);
 marker='kind=(side_body->''periods''->0->>''fixed'') IS NOT NULL;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_schedule_agreement_upgrade';END IF;
 source=replace(source,marker,marker||'IF security.side_calendar_policy_document(catalog,security.staged_economic_side(catalog,operation,slot)) IS DISTINCT FROM side_body->''calendarPolicy'' THEN RAISE EXCEPTION ''side_schedule_definition'';END IF;');
 marker='IF(compiled->0->>''relativeNumerator'')::numeric IS DISTINCT FROM 1';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_schedule_agreement_upgrade';END IF;
 source=replace(source,marker,'PERFORM security.require_dated_quantities(catalog,operation,body,compiled,quantity);'||marker);
 EXECUTE source;
END$$;
-- Single-period compositions use the same semantic check, before first insert
-- or reuse. The original committed-outcome branch remains ahead of generation.
DO $$DECLARE source text;marker text;guard text;signature regprocedure;BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid)'::regprocedure,
  'security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[],uuid)'::regprocedure] LOOP
  source=pg_get_functiondef(signature);
  guard=$guard$IF security.side_calendar_policy_document(catalog,canonical_side) IS DISTINCT FROM body->'calendarPolicy' OR
   NOT EXISTS(SELECT 1 FROM trading.sides WHERE(catalog_id,id,reference_catalog_id,reference_revision_id)=(catalog,canonical_side,ref_catalog,ref_revision)
    AND jsonb_array_length(economic_identity::jsonb->'Periods')=1 AND economic_identity::jsonb->'PowerQuantity'='null'::jsonb)
   THEN RAISE EXCEPTION 'side_schedule_definition';END IF;$guard$;
  IF strpos(source,'prepare_floating_swap_period')>0 THEN
   marker='SELECT s.id INTO side FROM trading.swap_floating_sides';
   guard=guard||'PERFORM security.require_dated_swap_period(catalog,canonical_side,0,p,1,1);';
  ELSE
   marker='SELECT id INTO side FROM trading.swap_fixed_sides';
   guard=guard||'PERFORM security.require_dated_swap_period(catalog,canonical_side,0,security.prepare_fixed_swap_period(catalog,ref_catalog,ref_revision,quote,body,valuation,publication_number,from_at),1,1);';
  END IF;
  IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_schedule_agreement_upgrade';END IF;
  EXECUTE replace(source,marker,guard||marker);
 END LOOP;
END$$;
COMMIT;
