-- Complete future supplied-plan operating rights use ordinary trading identities.
BEGIN;
SELECT 1 FROM security.epoch FOR UPDATE;
SELECT pg_advisory_xact_lock(730849102);
CREATE TABLE trading.power_operating_instruments(
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,definition_revision_id uuid NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,facility_id uuid NOT NULL,facility_version integer NOT NULL,
 delivery_from ref_data.instant NOT NULL,delivery_to ref_data.instant NOT NULL,
 quantity_code ref_data.code NOT NULL,currency_code ref_data.code NOT NULL,terms jsonb NOT NULL,
 publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,instrument_id),CHECK(delivery_from<delivery_to),CHECK(jsonb_typeof(terms)='object'),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.instruments(catalog_id,id),
 FOREIGN KEY(catalog_id,facility_id,facility_version) REFERENCES physical.power_operating_facility_versions(catalog_id,facility_id,version),
 FOREIGN KEY(catalog_id,definition_revision_id,reference_catalog_id,reference_revision_id) REFERENCES market_data.revisions(catalog_id,id,reference_catalog_id,reference_revision_id),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,quantity_code) REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,currency_code) REFERENCES ref_data.currencies(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.operating_memberships(
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,slot integer NOT NULL CHECK(slot BETWEEN 0 AND 7),side_id uuid NOT NULL,
 name text NOT NULL CHECK(name IN('discharging_energy','energy_output','payment_energy','charging_energy','fuel_input','variable_fee','access_fee')),
 coefficient integer NOT NULL CHECK(coefficient IN(-1,1)),
 PRIMARY KEY(catalog_id,instrument_id,slot),UNIQUE(catalog_id,instrument_id,slot,side_id),UNIQUE(catalog_id,instrument_id,name),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.power_operating_instruments(catalog_id,instrument_id),
 FOREIGN KEY(catalog_id,side_id) REFERENCES trading.sides(catalog_id,id)
);
CREATE TABLE trading.operating_trade_revisions(
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,revision integer NOT NULL CHECK(revision=1),instrument_id uuid NOT NULL,book_id uuid NOT NULL,
 operation_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 legal_entity_id uuid NOT NULL,legal_entity_revision integer NOT NULL,counterparty_id uuid NOT NULL,counterparty_revision integer NOT NULL,
 PRIMARY KEY(catalog_id,trade_id,revision),UNIQUE(catalog_id,operation_id),UNIQUE(catalog_id,instrument_id),
 FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.trades(catalog_id,id),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.power_operating_instruments(catalog_id,instrument_id),
 FOREIGN KEY(catalog_id,book_id) REFERENCES trading.books(catalog_id,id),
 FOREIGN KEY(catalog_id,legal_entity_id,legal_entity_revision) REFERENCES trading.legal_entities(catalog_id,id,revision),
 FOREIGN KEY(catalog_id,counterparty_id,counterparty_revision) REFERENCES trading.counterparties(catalog_id,id,revision),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.operating_plan_quantities(
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,ordinal integer NOT NULL CHECK(ordinal>=0),name text NOT NULL,
 interval_from ref_data.instant NOT NULL,interval_to ref_data.instant NOT NULL,quantity_code ref_data.code NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,numerator numeric NOT NULL,denominator numeric NOT NULL,
 PRIMARY KEY(catalog_id,instrument_id,ordinal,name),CHECK(interval_from<interval_to),
 CHECK(numerator>=0 AND trunc(numerator)=numerator AND denominator>0 AND trunc(denominator)=denominator AND length(numerator::text)<=1234 AND length(denominator::text)<=1234),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.power_operating_instruments(catalog_id,instrument_id),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,quantity_code) REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code)
);
CREATE TABLE trading.operating_side_prices(
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,slot integer NOT NULL,quote_code ref_data.code NOT NULL,
 reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,mode text NOT NULL CHECK(mode IN('fixed','selected_contract_flat_v1')),
 fixed_price ref_data.exact_number,curve_code ref_data.code,contract_id uuid,definition_revision_id uuid NOT NULL,
 PRIMARY KEY(catalog_id,instrument_id,slot),CHECK((mode='fixed')=(fixed_price IS NOT NULL)),CHECK((mode='fixed')=(curve_code IS NULL AND contract_id IS NULL)),
 FOREIGN KEY(catalog_id,instrument_id,slot) REFERENCES trading.operating_memberships(catalog_id,instrument_id,slot),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,quote_code) REFERENCES ref_data.quote_specifications(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,definition_revision_id,curve_code) REFERENCES market_data.curves(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,definition_revision_id,contract_id) REFERENCES market_data.contracts(catalog_id,revision_id,id),
 FOREIGN KEY(catalog_id,definition_revision_id,curve_code,contract_id) REFERENCES market_data.curve_members(catalog_id,revision_id,curve_code,contract_id)
);
CREATE TABLE trading.operating_booking_requests(
 catalog_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),operation_id uuid NOT NULL,
 command jsonb NOT NULL,outcome jsonb NOT NULL,PRIMARY KEY(catalog_id,actor_id,operation_id),
 FOREIGN KEY(catalog_id) REFERENCES market_data.catalogs(id)
);
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['power_operating_instruments','operating_memberships','operating_trade_revisions','operating_plan_quantities','operating_side_prices','operating_booking_requests'] LOOP
  EXECUTE format('ALTER TABLE trading.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE trading.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.%I FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt()',t);
  EXECUTE format('CREATE POLICY owner_access ON trading.%I TO openetrm_security_owner USING(true) WITH CHECK(true)',t);
  EXECUTE format('GRANT SELECT,INSERT ON trading.%I TO openetrm_security_owner',t);
 END LOOP;
END$$;

CREATE FUNCTION security.operating_booking_scope(catalog uuid,writing boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;BEGIN
 PERFORM 1 FROM security.epoch WHERE id FOR SHARE;
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.market_access(catalog,'ReadMarketData')
  OR(writing AND(NOT security.trading_access(catalog,'BookTrade') OR NOT security.current_write_context()))
  OR(pg_has_role(session_user,'openetrm_risk_worker','MEMBER') AND NOT risk.worker_read())
 THEN RAISE EXCEPTION 'operating_booking_denied' USING ERRCODE='42501';END IF;
 SELECT q.actor_id INTO actor FROM security.request_contexts q WHERE q.backend_pid=pg_backend_pid()
 AND q.transaction_id=pg_current_xact_id_if_assigned() AND q.runtime_login=session_user AND q.expires_at>clock_timestamp();
 IF actor IS NULL THEN RAISE EXCEPTION 'operating_booking_denied' USING ERRCODE='42501';END IF;
 RETURN actor;
END$$;
CREATE FUNCTION security.operating_booking_status(catalog uuid,operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;result jsonb;BEGIN
 actor=security.operating_booking_scope(catalog,false);
 SELECT r.outcome INTO result FROM trading.operating_booking_requests r WHERE(r.catalog_id,r.actor_id,r.operation_id)=(catalog,actor,operation);
 PERFORM security.operating_booking_scope(catalog,false);RETURN result;
END$$;

-- Exact rational arithmetic is admission only; market valuation stays managed.
CREATE FUNCTION trading.operating_ratio(n numeric,d numeric) RETURNS numeric[] LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE a numeric=abs(n);b numeric=d;t numeric;BEGIN
 IF d<=0 OR trunc(n)<>n OR trunc(d)<>d THEN RAISE EXCEPTION 'operating_quantity';END IF;
 WHILE b<>0 LOOP t=mod(a,b);a=b;b=t;END LOOP;
 RETURN ARRAY[trim_scale(n/a),trim_scale(d/a)];
END$$;
CREATE FUNCTION trading.operating_decimal(v text) RETURNS numeric[] LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE n numeric;d numeric;BEGIN
 IF v IS NULL OR length(v)>80 OR v !~ '^-?[0-9]+(\.[0-9]{1,18})?$' THEN RAISE EXCEPTION 'operating_booking_number';END IF;
 n=v::numeric;IF abs(n)>=1e24 THEN RAISE EXCEPTION 'operating_booking_number';END IF;
 d=power(10,scale(n));RETURN trading.operating_ratio(n*d,d);
END$$;
CREATE FUNCTION trading.operating_add(a numeric[],b numeric[]) RETURNS numeric[] LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$SELECT trading.operating_ratio(a[1]*b[2]+b[1]*a[2],a[2]*b[2])$$;
CREATE FUNCTION trading.operating_multiply(a numeric[],b numeric[]) RETURNS numeric[] LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$SELECT trading.operating_ratio(a[1]*b[1],a[2]*b[2])$$;
CREATE FUNCTION trading.operating_require_decimals(v jsonb,names text[]) RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE n text;BEGIN
 FOREACH n IN ARRAY names LOOP
  IF jsonb_typeof(v->n) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'operating_booking_number';END IF;
  PERFORM trading.operating_decimal(v->>n);
 END LOOP;
END$$;
CREATE FUNCTION trading.operating_instant(v text) RETURNS timestamptz LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
 IF v IS NULL OR v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6}|\.[0-9]{6}0)?(Z|\+00:00)$' THEN RAISE EXCEPTION 'operating_booking_grid';END IF;
 RETURN v::timestamptz;
END$$;
CREATE FUNCTION trading.operating_plan_admission(f physical.power_operating_facility_versions,p jsonb,valuation timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE kind text=f.kind;params jsonb=f.parameters;s jsonb;v jsonb=p->'valuation';items jsonb;item jsonb;result jsonb='[]';
 start_at timestamptz;at_from timestamptz;at_to timestamptz;step interval;hours numeric[];i integer=0;counted integer;
 energy numeric[];charge numeric[];discharge numeric[];stored numeric[];throughput numeric[];amount numeric[];fuel numeric[];
 output numeric;available numeric;previous numeric;state text;next_state text;state_from timestamptz;issued timestamptz;starts integer;
 n numeric;d numeric;zero numeric[]=ARRAY[0::numeric,1::numeric];online boolean;started boolean;stopped boolean;basis text;
BEGIN
 IF NOT physical.power_operating_keys(p,ARRAY['snapshotId','facilityId','facilityVersion','grid','batteryState','batteryDispatch','thermalState','thermalDispatch','solarRight','solarDispatch','valuation'])
 OR jsonb_typeof(p->'snapshotId') IS DISTINCT FROM 'string' OR(p->>'snapshotId')::uuid='00000000-0000-0000-0000-000000000000'
 OR jsonb_typeof(p->'facilityId') IS DISTINCT FROM 'string' OR jsonb_typeof(p->'facilityVersion') IS DISTINCT FROM 'number' OR(p->>'facilityId')::uuid<>f.facility_id OR(p->>'facilityVersion')::integer<>f.version
 OR NOT physical.power_operating_keys(p->'grid',ARRAY['operatingDate','firstInterval'])
 OR jsonb_typeof(p->'batteryDispatch') IS DISTINCT FROM 'array' OR jsonb_typeof(p->'thermalDispatch') IS DISTINCT FROM 'array'
 OR jsonb_typeof(p->'solarDispatch') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'operating_booking_input';END IF;
 IF NOT EXISTS(SELECT 1 FROM ref_data.clock_rules clock WHERE(clock.catalog_id,clock.revision_id,clock.code,clock.kind,clock.fixed_offset_seconds)=
 (f.reference_catalog_id,f.reference_revision_id,f.clock_code,'fixed_offset',0)) THEN RAISE EXCEPTION 'operating_booking_clock';END IF;
 IF p->'grid'->>'operatingDate' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR jsonb_typeof(p->'grid'->'firstInterval') IS DISTINCT FROM 'number'
 OR(p->'grid'->>'firstInterval')::integer NOT BETWEEN 1 AND 1440/f.interval_minutes THEN RAISE EXCEPTION 'operating_booking_grid';END IF;
 step=make_interval(mins=>f.interval_minutes);hours=trading.operating_ratio(f.interval_minutes,60);
 start_at=(p->'grid'->>'operatingDate')::date::timestamp AT TIME ZONE 'UTC'+((p->'grid'->>'firstInterval')::integer-1)*step;
 items=p->(kind||'Dispatch');counted=jsonb_array_length(items);
 IF counted NOT BETWEEN 1 AND 1024 OR start_at<=valuation OR start_at<f.effective_from OR start_at+counted*step>f.effective_to
 THEN RAISE EXCEPTION 'operating_delivery_lifecycle';END IF;
 IF kind='battery' THEN
  IF NOT physical.power_operating_keys(p->'batteryState',ARRAY['at','storedMwh','cumulativeGridThroughputMwh','terminalMinimumMwh','terminalMaximumMwh'])
  OR p->'thermalState'<>'null'::jsonb OR p->'solarRight'<>'null'::jsonb OR jsonb_array_length(p->'thermalDispatch')<>0 OR jsonb_array_length(p->'solarDispatch')<>0
  THEN RAISE EXCEPTION 'operating_booking_union';END IF;
  s=p->'batteryState';PERFORM trading.operating_require_decimals(s,ARRAY['storedMwh','cumulativeGridThroughputMwh','terminalMinimumMwh','terminalMaximumMwh']);stored=trading.operating_decimal(s->>'storedMwh');throughput=trading.operating_decimal(s->>'cumulativeGridThroughputMwh');
  IF trading.operating_instant(s->>'at')<>start_at OR stored[1]<0 OR throughput[1]<0 OR
   stored[1]<(params->>'minimumStoredMwh')::numeric*stored[2] OR stored[1]>(params->>'maximumStoredMwh')::numeric*stored[2]
   OR(s->>'terminalMinimumMwh')::numeric<(params->>'minimumStoredMwh')::numeric OR(s->>'terminalMaximumMwh')::numeric>(params->>'maximumStoredMwh')::numeric
   OR(s->>'terminalMinimumMwh')::numeric>(s->>'terminalMaximumMwh')::numeric THEN RAISE EXCEPTION 'operating_booking_state';END IF;
 ELSIF kind='thermal' THEN
  IF NOT physical.power_operating_keys(p->'thermalState',ARRAY['at','commitment','elapsedMinutes','previousOutputMw','startsUsed','guaranteedHeatRate','guaranteedNoLoadFuelPerHour','guaranteedStartupFuel','terminalPolicy','numericalPolicy'])
  OR p->'batteryState'<>'null'::jsonb OR p->'solarRight'<>'null'::jsonb OR jsonb_array_length(p->'batteryDispatch')<>0 OR jsonb_array_length(p->'solarDispatch')<>0 THEN RAISE EXCEPTION 'operating_booking_union';END IF;
  s=p->'thermalState';PERFORM trading.operating_require_decimals(s,ARRAY['previousOutputMw','guaranteedHeatRate','guaranteedNoLoadFuelPerHour','guaranteedStartupFuel']);state=s->>'commitment';previous=(s->>'previousOutputMw')::numeric;starts=(s->>'startsUsed')::integer;
  IF trading.operating_instant(s->>'at')<>start_at OR state NOT IN('online','offline') OR starts<0 OR starts>(params->>'maximumStarts')::integer
   OR jsonb_typeof(s->'elapsedMinutes') IS DISTINCT FROM 'number' OR jsonb_typeof(s->'startsUsed') IS DISTINCT FROM 'number' OR(s->>'elapsedMinutes')::integer NOT BETWEEN 0 AND 525600 OR previous<0 OR previous>(params->>'maximumOutputMw')::numeric
   OR(state='offline' AND previous<>0) OR(state='online' AND previous<(params->>'minimumOutputMw')::numeric)
   OR s->>'terminalPolicy' IS DISTINCT FROM 'require_minimum_times_satisfied' OR s->>'numericalPolicy' IS DISTINCT FROM 'thermal_exact_elapsed_quantity_v1'
   OR(trading.operating_decimal(s->>'guaranteedHeatRate'))[1]<=0 OR(trading.operating_decimal(s->>'guaranteedNoLoadFuelPerHour'))[1]<0 OR(trading.operating_decimal(s->>'guaranteedStartupFuel'))[1]<0
  THEN RAISE EXCEPTION 'operating_booking_state';END IF;
  state_from=start_at-make_interval(mins=>(s->>'elapsedMinutes')::integer);
  basis=v->>'fuelQuantityBasis';IF basis NOT IN('guaranteed','consumption') OR basis IS NULL THEN RAISE EXCEPTION 'operating_booking_policy';END IF;
 ELSE
  IF NOT physical.power_operating_keys(p->'solarRight',ARRAY['forecastAssumption','entitlementNumerator','entitlementDenominator','deliveryBasis','paymentBasis'])
  OR p->'batteryState'<>'null'::jsonb OR p->'thermalState'<>'null'::jsonb OR jsonb_array_length(p->'batteryDispatch')<>0 OR jsonb_array_length(p->'thermalDispatch')<>0 THEN RAISE EXCEPTION 'operating_booking_union';END IF;
  s=p->'solarRight';IF jsonb_typeof(s->'entitlementNumerator') IS DISTINCT FROM 'string' OR jsonb_typeof(s->'entitlementDenominator') IS DISTINCT FROM 'string' OR s->>'entitlementNumerator' !~ '^[0-9]+$' OR s->>'entitlementDenominator' !~ '^[0-9]+$' THEN RAISE EXCEPTION 'operating_booking_number';END IF;n=(s->>'entitlementNumerator')::numeric;d=(s->>'entitlementDenominator')::numeric;
  IF n<=0 OR d<=0 OR n>d OR trunc(n)<>n OR trunc(d)<>d OR length(n::text)>80 OR length(d::text)>80
  OR s->>'forecastAssumption' IS DISTINCT FROM 'hypothetical_supplied_forecast_v1' OR s->>'deliveryBasis' IS DISTINCT FROM 'as_produced'
  OR s->>'paymentBasis' NOT IN('produced_only','delivery_obligation') THEN RAISE EXCEPTION 'operating_booking_policy';END IF;
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
  at_from=start_at+i*step;at_to=at_from+step;
  IF kind='battery' THEN
   IF NOT physical.power_operating_keys(item,ARRAY['chargeMw','dischargeMw','availablePowerFraction']) THEN RAISE EXCEPTION 'operating_booking_input';END IF;
   PERFORM trading.operating_require_decimals(item,ARRAY['chargeMw','dischargeMw','availablePowerFraction']);
   charge=trading.operating_multiply(trading.operating_decimal(item->>'chargeMw'),hours);discharge=trading.operating_multiply(trading.operating_decimal(item->>'dischargeMw'),hours);
   available=(item->>'availablePowerFraction')::numeric;
   IF charge[1]<0 OR discharge[1]<0 OR(charge[1]>0 AND discharge[1]>0) OR available<0 OR available>1
   OR(item->>'chargeMw')::numeric>(params->>'maximumChargeMw')::numeric*available OR(item->>'dischargeMw')::numeric>(params->>'maximumDischargeMw')::numeric*available THEN RAISE EXCEPTION 'operating_battery_limit';END IF;
   amount=trading.operating_multiply(charge,trading.operating_decimal(params->>'chargeEfficiency'));
   stored=trading.operating_add(stored,amount);
   amount=trading.operating_decimal(params->>'dischargeEfficiency');amount=trading.operating_multiply(discharge,ARRAY[-amount[2],amount[1]]);
   stored=trading.operating_add(stored,amount);throughput=trading.operating_add(throughput,trading.operating_add(charge,discharge));
   IF stored[1]<(params->>'minimumStoredMwh')::numeric*stored[2] OR stored[1]>(params->>'maximumStoredMwh')::numeric*stored[2]
   OR(params->>'throughputPolicy'='grid_charge_plus_discharge' AND throughput[1]>(params->>'maximumThroughputMwh')::numeric*throughput[2]) THEN RAISE EXCEPTION 'operating_battery_state';END IF;
   energy=discharge;fuel=NULL;
   result=result||jsonb_build_array(jsonb_build_object('ordinal',i,'name','charge','from',at_from,'to',at_to,'quantity',f.energy_quantity_code,'numerator',charge[1]::text,'denominator',charge[2]::text),
    jsonb_build_object('ordinal',i,'name','variable','from',at_from,'to',at_to,'quantity',f.energy_quantity_code,'numerator',(trading.operating_add(charge,discharge))[1]::text,'denominator',(trading.operating_add(charge,discharge))[2]::text));
  ELSIF kind='thermal' THEN
   IF NOT physical.power_operating_keys(item,ARRAY['commitment','outputMw','availableMw','startupInstructionAt']) THEN RAISE EXCEPTION 'operating_booking_input';END IF;
   PERFORM trading.operating_require_decimals(item,ARRAY['outputMw','availableMw']);
   output=(trading.operating_decimal(item->>'outputMw'))[1]/(trading.operating_decimal(item->>'outputMw'))[2];available=(item->>'availableMw')::numeric;
   next_state=item->>'commitment';online=next_state='online';started=online AND state='offline';stopped=next_state='offline' AND state='online';
   IF next_state IS NULL OR next_state NOT IN('online','offline') OR available<0 OR available>(params->>'maximumOutputMw')::numeric OR output<0
   OR(online AND(output<(params->>'minimumOutputMw')::numeric OR output>available)) OR(NOT online AND output<>0) THEN RAISE EXCEPTION 'operating_thermal_output';END IF;
   IF started THEN
    issued=CASE WHEN item->'startupInstructionAt'='null'::jsonb THEN NULL ELSE trading.operating_instant(item->>'startupInstructionAt') END;
    IF issued IS NULL OR issued>at_from OR issued<state_from OR at_from-issued<make_interval(mins=>(params->>'startupLeadMinutes')::integer)
    OR issued-state_from<make_interval(mins=>(params->>'minimumDownMinutes')::integer) OR starts>=(params->>'maximumStarts')::integer
    OR output>(params->>'startupMaximumOutputMw')::numeric THEN RAISE EXCEPTION 'operating_thermal_start';END IF;starts=starts+1;
   ELSIF item->'startupInstructionAt'<>'null'::jsonb THEN RAISE EXCEPTION 'operating_thermal_start';END IF;
   IF stopped AND(at_from-state_from<make_interval(mins=>(params->>'minimumUpMinutes')::integer) OR previous>(params->>'shutdownMaximumOutputMw')::numeric) THEN RAISE EXCEPTION 'operating_thermal_stop';END IF;
   IF online AND NOT started AND abs(output-previous)*60>(CASE WHEN output>=previous THEN(params->>'rampUpMwPerHour')::numeric ELSE(params->>'rampDownMwPerHour')::numeric END)*f.interval_minutes THEN RAISE EXCEPTION 'operating_thermal_ramp';END IF;
   IF started OR stopped THEN state_from=at_from;END IF;
   energy=trading.operating_multiply(trading.operating_decimal(item->>'outputMw'),hours);fuel=zero;
   IF online THEN
    fuel=trading.operating_add(trading.operating_multiply(energy,trading.operating_decimal(CASE basis WHEN 'guaranteed' THEN s->>'guaranteedHeatRate' ELSE params->>'consumptionHeatRate' END)),
     trading.operating_multiply(hours,trading.operating_decimal(CASE basis WHEN 'guaranteed' THEN s->>'guaranteedNoLoadFuelPerHour' ELSE params->>'consumptionNoLoadFuelPerHour' END)));
    IF started THEN fuel=trading.operating_add(fuel,trading.operating_decimal(CASE basis WHEN 'guaranteed' THEN s->>'guaranteedStartupFuel' ELSE params->>'consumptionStartupFuel' END));END IF;
   END IF;
   result=result||jsonb_build_array(jsonb_build_object('ordinal',i,'name','fuel','from',at_from,'to',at_to,'quantity',f.fuel_quantity_code,'numerator',fuel[1]::text,'denominator',fuel[2]::text));
   state=next_state;previous=output;
  ELSE
   IF NOT physical.power_operating_keys(item,ARRAY['productionMwh','requiredDeliveryMwh']) OR item->'requiredDeliveryMwh'<>'null'::jsonb THEN RAISE EXCEPTION 'operating_booking_input';END IF;
   PERFORM trading.operating_require_decimals(item,ARRAY['productionMwh']);
   energy=trading.operating_multiply(trading.operating_decimal(item->>'productionMwh'),trading.operating_ratio(n,d));
   IF energy[1]<0 THEN RAISE EXCEPTION 'operating_solar_output';END IF;
   result=result||jsonb_build_array(jsonb_build_object('ordinal',i,'name','payment','from',at_from,'to',at_to,'quantity',f.energy_quantity_code,'numerator',energy[1]::text,'denominator',energy[2]::text));
  END IF;
  result=result||jsonb_build_array(jsonb_build_object('ordinal',i,'name','energy','from',at_from,'to',at_to,'quantity',f.energy_quantity_code,'numerator',energy[1]::text,'denominator',energy[2]::text));
  i=i+1;
 END LOOP;
 IF kind='battery' AND(stored[1]<(s->>'terminalMinimumMwh')::numeric*stored[2] OR stored[1]>(s->>'terminalMaximumMwh')::numeric*stored[2]) THEN RAISE EXCEPTION 'operating_battery_terminal';END IF;
 IF kind='thermal' AND at_to-state_from<make_interval(mins=>(CASE state WHEN 'online' THEN params->>'minimumUpMinutes' ELSE params->>'minimumDownMinutes' END)::integer) THEN RAISE EXCEPTION 'operating_thermal_terminal';END IF;
 RETURN result;
END$$;
CREATE FUNCTION trading.operating_payment_at(interval_from timestamptz,days integer) RETURNS timestamptz LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT(date_trunc('month',interval_from AT TIME ZONE 'UTC')+interval '1 month'-interval '1 day'+make_interval(days=>days)) AT TIME ZONE 'UTC'
$$;
CREATE FUNCTION trading.require_operating_program_shape(catalog uuid,schedule uuid,member_slot integer,instrument uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE h trading.power_operating_instruments;m trading.operating_memberships;p trading.operating_side_prices;q ref_data.quote_specifications;
 cell record;guard trading.side_schedule_rows;amount trading.side_schedule_rows;quantity trading.side_schedule_rows;price trading.side_schedule_rows;
 pv trading.side_schedule_rows;discount trading.side_schedule_rows;port_name text;expected integer;payment timestamptz;cash integer;root integer;
BEGIN
 SELECT * INTO STRICT h FROM trading.power_operating_instruments WHERE(catalog_id,instrument_id)=(catalog,instrument);
 SELECT * INTO STRICT m FROM trading.operating_memberships WHERE(catalog_id,instrument_id,slot)=(catalog,instrument,member_slot);
 SELECT * INTO STRICT p FROM trading.operating_side_prices WHERE(catalog_id,instrument_id,slot)=(catalog,instrument,member_slot);
 SELECT * INTO STRICT q FROM ref_data.quote_specifications WHERE(catalog_id,revision_id,code)=(p.reference_catalog_id,p.reference_revision_id,p.quote_code);
 IF NOT EXISTS(SELECT 1 FROM trading.side_schedules s JOIN trading.sides d ON(d.catalog_id,d.id)=(s.catalog_id,s.side_id)
 WHERE(s.catalog_id,s.id,s.side_id,d.family,d.definition_revision_id,d.reference_catalog_id,d.reference_revision_id)=
 (catalog,schedule,m.side_id,'operating',h.definition_revision_id,h.reference_catalog_id,h.reference_revision_id))
 OR EXISTS(SELECT 1 FROM trading.side_schedule_grids WHERE(catalog_id,schedule_id)=(catalog,schedule))
 OR EXISTS(SELECT 1 FROM trading.side_schedule_ports WHERE(catalog_id,schedule_id)=(catalog,schedule))
 OR EXISTS(SELECT 1 FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id)=(catalog,schedule) AND operation NOT IN('quantity_literal','constant_price','operating_contract_price','amount','discount','pv','output_guard','sum'))
 THEN RAISE EXCEPTION 'operating_schedule_shape';END IF;
 port_name=CASE m.name WHEN 'charging_energy' THEN 'charge' WHEN 'fuel_input' THEN 'fuel' WHEN 'payment_energy' THEN 'payment'
 WHEN 'variable_fee' THEN CASE WHEN h.terms->>'kind'='battery' THEN 'variable' WHEN h.terms->>'kind'='solar' THEN 'payment' ELSE 'energy' END ELSE 'energy' END;
 expected=CASE WHEN m.name='access_fee' THEN 1 ELSE(SELECT count(*) FROM trading.operating_plan_quantities WHERE(catalog_id,instrument_id,name)=(catalog,instrument,port_name))END;
 IF expected<1 OR(SELECT count(*) FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id)=(catalog,schedule))<>5*expected+(CASE WHEN p.mode='fixed' THEN 1 ELSE expected END)+1
 OR(SELECT count(*) FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id,operation)=(catalog,schedule,'sum'))<>1
 OR(SELECT count(*) FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id,operation)=(catalog,schedule,CASE WHEN p.mode='fixed' THEN 'constant_price' ELSE 'operating_contract_price' END))<>(CASE WHEN p.mode='fixed' THEN 1 ELSE expected END)
 OR(SELECT count(*) FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id)=(catalog,schedule))<>(CASE WHEN p.mode='fixed' THEN 0 ELSE 2*expected END)
 OR(SELECT count(*) FROM trading.side_schedule_roots WHERE(catalog_id,schedule_id)=(catalog,schedule))<>3*expected+1
 OR(SELECT count(*) FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id,operation)=(catalog,schedule,'output_guard'))<>expected
 OR(SELECT count(*) FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id,operation)=(catalog,schedule,'quantity_literal'))<>expected
 OR(SELECT count(*) FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id,operation)=(catalog,schedule,'amount'))<>expected
 OR(SELECT count(*) FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id,operation)=(catalog,schedule,'pv'))<>expected
 OR(SELECT count(*) FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id,operation)=(catalog,schedule,'discount'))<>expected
 THEN RAISE EXCEPTION 'operating_schedule_shape';END IF;
 FOR cell IN SELECT * FROM trading.operating_plan_quantities WHERE(catalog_id,instrument_id,name)=(catalog,instrument,port_name) ORDER BY ordinal LIMIT expected LOOP
  payment=trading.operating_payment_at(cell.interval_from,(h.terms->'plan'->'valuation'->'paymentRule'->>'days')::integer);
  SELECT * INTO STRICT guard FROM trading.side_schedule_rows WHERE(catalog_id,schedule_id,operation,payment_ordinal)=(catalog,schedule,'output_guard',cell.ordinal);
  IF(guard.interval_from,guard.interval_to,guard.value_at,guard.parameters->>'measure',guard.parameters->>'lifecycle',guard.parameters->>'pricePolicy')
   IS DISTINCT FROM(cell.interval_from,cell.interval_to,payment,'present_value_v1','undue_payment_v1','selected_context_v1')
   OR(guard.operating_date,guard.hour_beginning,guard.minute,guard.occurrence) IS DISTINCT FROM((cell.interval_from AT TIME ZONE 'UTC')::date,extract(hour FROM cell.interval_from AT TIME ZONE 'UTC')::smallint,extract(minute FROM cell.interval_from AT TIME ZONE 'UTC')::smallint,1::smallint) THEN RAISE EXCEPTION 'operating_schedule_time';END IF;
  SELECT r.* INTO STRICT amount FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r
   ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
   WHERE(e.catalog_id,e.schedule_id,e.target,e.port)=(catalog,schedule,guard.ordinal,'amount');
  SELECT r.* INTO STRICT pv FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
   WHERE(e.catalog_id,e.schedule_id,e.target,e.port)=(catalog,schedule,guard.ordinal,'discounted');
  SELECT r.* INTO STRICT quantity FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
   WHERE(e.catalog_id,e.schedule_id,e.target,e.port)=(catalog,schedule,amount.ordinal,'quantity');
  SELECT r.* INTO STRICT price FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
   WHERE(e.catalog_id,e.schedule_id,e.target,e.port)=(catalog,schedule,amount.ordinal,'price');
  SELECT r.* INTO STRICT discount FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
   WHERE(e.catalog_id,e.schedule_id,e.target,e.port)=(catalog,schedule,pv.ordinal,'discount');
  IF NOT EXISTS(SELECT 1 FROM trading.side_schedule_roots WHERE(catalog_id,schedule_id,name,measure,row_ordinal)=(catalog,schedule,'operating/'||cell.ordinal||'/quantity','schedule_quantity',quantity.ordinal))
   OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_roots WHERE(catalog_id,schedule_id,name,measure,row_ordinal)=(catalog,schedule,'operating/'||cell.ordinal||'/cash','contractual_amount',amount.ordinal))
   OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_roots WHERE(catalog_id,schedule_id,name,measure,row_ordinal)=(catalog,schedule,'operating/'||cell.ordinal||'/pv','contribution_pv',guard.ordinal))
   THEN RAISE EXCEPTION 'operating_schedule_root';END IF;
  IF amount.operation<>'amount' OR pv.operation<>'pv' OR discount.operation<>'discount' OR discount.value_at<>payment
   OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_edges WHERE(catalog_id,schedule_id,target,port,source)=(catalog,schedule,pv.ordinal,'amount',amount.ordinal))
   OR quantity.operation<>'quantity_literal' OR(quantity.unit_catalog_id,quantity.unit_revision_id,quantity.unit_code) IS DISTINCT FROM(h.reference_catalog_id,h.reference_revision_id,q.quantity_code)
   OR(quantity.parameters->>'numerator')::numeric*(CASE WHEN m.name='access_fee' THEN 1 ELSE cell.denominator END)<>
     (CASE WHEN m.name='access_fee' THEN 1 ELSE cell.numerator END)*(quantity.parameters->>'denominator')::numeric
   OR(price.unit_catalog_id,price.unit_revision_id,price.unit_code,price.currency_code,price.quote_multiplier) IS DISTINCT FROM(h.reference_catalog_id,h.reference_revision_id,q.quantity_code,q.currency_code,q.multiplier)
  THEN RAISE EXCEPTION 'operating_schedule_quantity';END IF;
  IF p.mode='fixed' THEN
   IF price.operation<>'constant_price' OR(price.parameters->>'numerator')::numeric<>p.fixed_price*(price.parameters->>'denominator')::numeric THEN RAISE EXCEPTION 'operating_schedule_price';END IF;
  ELSE
   IF price.operation<>'operating_contract_price' OR price.parameters->>'selection'<>'selected_contract_flat_v1'
    OR(SELECT count(*) FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal)=(catalog,schedule,price.ordinal))<>2
    OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal,port,kind,source_catalog_id,definition_revision_id,curve_code,contract_id)=
     (catalog,schedule,price.ordinal,'market','contract_price',catalog,h.definition_revision_id,p.curve_code,p.contract_id))
    OR NOT EXISTS(SELECT 1 FROM trading.side_schedule_bindings WHERE(catalog_id,schedule_id,row_ordinal,port,kind,reference_catalog_id,reference_revision_id,quote_code)=
     (catalog,schedule,price.ordinal,'quote','quote',h.reference_catalog_id,h.reference_revision_id,p.quote_code)) THEN RAISE EXCEPTION 'operating_schedule_price';END IF;
  END IF;
 END LOOP;
 SELECT r.ordinal INTO STRICT root FROM trading.side_schedule_roots x JOIN trading.side_schedule_rows r ON(r.catalog_id,r.schedule_id,r.ordinal)=(x.catalog_id,x.schedule_id,x.row_ordinal)
 WHERE(x.catalog_id,x.schedule_id,x.name,x.measure,r.operation)=(catalog,schedule,'pv','pv','sum');
 IF(SELECT count(*) FROM trading.side_schedule_edges WHERE(catalog_id,schedule_id,target,port)=(catalog,schedule,root,'input'))<>expected
 OR EXISTS(SELECT 1 FROM trading.side_schedule_edges e JOIN trading.side_schedule_rows r ON(r.catalog_id,r.schedule_id,r.ordinal)=(e.catalog_id,e.schedule_id,e.source)
 WHERE(e.catalog_id,e.schedule_id,e.target)=(catalog,schedule,root) AND r.operation<>'output_guard') OR(SELECT count(DISTINCT source) FROM trading.side_schedule_edges WHERE(catalog_id,schedule_id,target,port)=(catalog,schedule,root,'input'))<>expected THEN RAISE EXCEPTION 'operating_schedule_root';END IF;
EXCEPTION WHEN no_data_found OR too_many_rows THEN RAISE EXCEPTION 'operating_schedule_shape';
END$$;
CREATE FUNCTION trading.operating_canonical_value(v jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE result jsonb;item record;t text;BEGIN
 IF jsonb_typeof(v)='object' THEN
  result='{}';FOR item IN SELECT * FROM jsonb_each(v) LOOP result=result||jsonb_build_object(item.key,trading.operating_canonical_value(item.value));END LOOP;RETURN result;
 ELSIF jsonb_typeof(v)='array' THEN
  result='[]';FOR item IN SELECT value FROM jsonb_array_elements(v) LOOP result=result||jsonb_build_array(trading.operating_canonical_value(item.value));END LOOP;RETURN result;
 ELSIF jsonb_typeof(v)='string' THEN
  t=v#>>'{}';IF t~'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN RETURN to_jsonb((t::uuid)::text);END IF;IF t~'^-?[0-9]+(\.[0-9]+)?$' AND length(t)<=80 THEN RETURN to_jsonb(trim_scale(t::numeric)::text);END IF;
  IF t~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,7})?(Z|\+00:00)$' THEN RETURN to_jsonb(to_char(t::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'Z');END IF;
 END IF;RETURN v;
END$$;
CREATE FUNCTION security.book_operating_right(catalog uuid,body jsonb,prepared jsonb,valuation timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;operation uuid;prior trading.operating_booking_requests;f physical.power_operating_facility_versions;
 staged trading.side_schedule_requests;plan jsonb;canonical jsonb;facts jsonb;rows jsonb;row jsonb;v jsonb;price jsonb;
 publication integer;trade uuid;instrument uuid;outcome jsonb;book uuid;member record;name text;expected_names text[];slot integer=0;quote ref_data.quote_specifications;
 start_at timestamptz;end_at timestamptz;kind text;quantity ref_data.quantity_specifications;expected_quantity text;rc uuid;rr uuid;
BEGIN
 actor=security.operating_booking_scope(catalog,true);
 IF length(body::text)>1048576 OR NOT physical.power_operating_keys(prepared,ARRAY['instrumentId','members']) OR NOT physical.power_operating_keys(body,ARRAY['operationId','tradeId','expectedRevision','bookId','legalEntityId','legalEntityRevision','counterpartyId','counterpartyRevision','reason','convention','plan'])
 OR body->>'convention' IS DISTINCT FROM 'supplied_operating_right_trade_v1' OR body->'tradeId' IS DISTINCT FROM 'null'::jsonb OR body->'expectedRevision' IS DISTINCT FROM '0'::jsonb
 OR jsonb_typeof(body->'operationId') IS DISTINCT FROM 'string' OR jsonb_typeof(body->'bookId') IS DISTINCT FROM 'string'
 OR jsonb_typeof(body->'legalEntityId') IS DISTINCT FROM 'string' OR jsonb_typeof(body->'counterpartyId') IS DISTINCT FROM 'string'
 OR jsonb_typeof(body->'legalEntityRevision') IS DISTINCT FROM 'number' OR jsonb_typeof(body->'counterpartyRevision') IS DISTINCT FROM 'number'
 OR jsonb_typeof(body->'reason') IS DISTINCT FROM 'string' OR nullif(btrim(body->>'reason'),'') IS NULL OR length(body->>'reason')>500 OR valuation IS NULL OR NOT isfinite(valuation)
 THEN RAISE EXCEPTION 'operating_booking_input';END IF;
 operation=(body->>'operationId')::uuid;book=(body->>'bookId')::uuid;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000' OR book IS NULL THEN RAISE EXCEPTION 'operating_booking_input';END IF;
 PERFORM pg_advisory_xact_lock(730849102);PERFORM security.operating_booking_scope(catalog,true);
 SELECT * INTO prior FROM trading.operating_booking_requests WHERE(catalog_id,actor_id,operation_id)=(catalog,actor,operation);
 IF FOUND THEN IF prior.command IS DISTINCT FROM body THEN RAISE EXCEPTION 'operating_request_conflict';END IF;RETURN prior.outcome;END IF;
 IF EXISTS(SELECT 1 FROM trading.trades WHERE(catalog_id,operation_id)=(catalog,operation)) THEN RAISE EXCEPTION 'operating_request_conflict';END IF;
 plan=body->'plan';v=plan->'valuation';
 SELECT * INTO f FROM physical.power_operating_facility_versions WHERE(catalog_id,facility_id,version)=(catalog,(plan->>'facilityId')::uuid,(plan->>'facilityVersion')::integer);
 IF NOT FOUND OR NOT security.has_permission('ReadPhysical') OR NOT security.reference_access(f.reference_catalog_id,'ReadMarketData')
 OR NOT security.reference_version_visible(f.reference_catalog_id,f.reference_revision_id) OR NOT security.market_fact_visible(catalog,f.definition_revision_id,NULL)
 THEN RAISE EXCEPTION 'operating_facility_unavailable' USING ERRCODE='42501';END IF;
 rc=f.reference_catalog_id;rr=f.reference_revision_id;kind=f.kind;
 IF NOT physical.power_operating_keys(v,ARRAY['perspective','measure','currencyCode','rightQuantityCode','discounting','paymentRule','energyPrice','chargingPrice','fuelPrice','fuelQuantityBasis','accessQuoteCode','accessPrice','accessFeeBasis','variablePrice','variableQuantityBasis','startupQuoteCode','startupPrice','startupFeeBasis'])
 OR v->>'perspective' IS DISTINCT FROM 'resource_right_holder_v1' OR v->>'measure' IS DISTINCT FROM 'remaining_operating_value_v1' OR v->'discounting' IS DISTINCT FROM 'false'::jsonb
 OR v->'startupQuoteCode' IS DISTINCT FROM 'null'::jsonb OR v->'startupPrice' IS DISTINCT FROM 'null'::jsonb OR v->'startupFeeBasis' IS DISTINCT FROM 'null'::jsonb
 OR NOT physical.power_operating_keys(v->'paymentRule',ARRAY['frequency','rule','days','dayOfMonth','dayBasis','shortMonth','adjustment','calendar','implementation'])
 OR v->'paymentRule'->>'frequency' IS DISTINCT FROM 'monthly' OR v->'paymentRule'->>'rule' IS DISTINCT FROM 'days_after_period_end'
 OR v->'paymentRule'->>'dayBasis' IS DISTINCT FROM 'calendar_days' OR v->'paymentRule'->>'adjustment' IS DISTINCT FROM 'unadjusted'
 OR jsonb_typeof(v->'paymentRule'->'days') IS DISTINCT FROM 'number' OR v->'paymentRule'->>'implementation' IS DISTINCT FROM 'monthly_payment_date_rules_v1' OR(v->'paymentRule'->>'days')::integer NOT BETWEEN 0 AND 366
 OR v->'paymentRule'->'dayOfMonth' IS DISTINCT FROM 'null'::jsonb OR v->'paymentRule'->'shortMonth' IS DISTINCT FROM 'null'::jsonb OR v->'paymentRule'->'calendar' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'operating_booking_policy';END IF;
 -- Native callers use the same closed scalar shapes as the managed command.
 -- Validate before staging or semantic reuse can conceal malformed prices.
 IF jsonb_typeof(v->'currencyCode') IS DISTINCT FROM 'string' OR jsonb_typeof(v->'rightQuantityCode') IS DISTINCT FROM 'string'
 OR jsonb_typeof(v->'energyPrice') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'operating_booking_price';END IF;
 FOREACH name IN ARRAY ARRAY['accessQuoteCode','startupQuoteCode','fuelQuantityBasis','accessFeeBasis','variableQuantityBasis'] LOOP
  IF jsonb_typeof(v->name) NOT IN('string','null') THEN RAISE EXCEPTION 'operating_booking_price';END IF;
 END LOOP;
 FOREACH name IN ARRAY ARRAY['accessPrice','variablePrice','startupPrice'] LOOP
  IF jsonb_typeof(v->name) NOT IN('string','null') THEN RAISE EXCEPTION 'operating_booking_price';END IF;
  IF jsonb_typeof(v->name)='string' THEN PERFORM trading.operating_decimal(v->>name);END IF;
 END LOOP;
 FOR price IN SELECT value FROM jsonb_array_elements(jsonb_build_array(v->'energyPrice',v->'chargingPrice',v->'fuelPrice')) LOOP
  IF price='null'::jsonb THEN CONTINUE;END IF;
  IF NOT physical.power_operating_keys(price,ARRAY['mode','quoteCode','fixedPrice','curveCode','contractId'])
   OR jsonb_typeof(price->'mode') IS DISTINCT FROM 'string' OR jsonb_typeof(price->'quoteCode') IS DISTINCT FROM 'string'
  THEN RAISE EXCEPTION 'operating_booking_price';END IF;
  IF price->>'mode'='fixed' THEN
   IF jsonb_typeof(price->'fixedPrice') IS DISTINCT FROM 'string' OR price->'curveCode' IS DISTINCT FROM 'null'::jsonb
    OR price->'contractId' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'operating_booking_price';END IF;
   PERFORM trading.operating_decimal(price->>'fixedPrice');
  ELSIF price->>'mode'='selected_contract_flat_v1' THEN
   IF price->'fixedPrice' IS DISTINCT FROM 'null'::jsonb OR jsonb_typeof(price->'curveCode') IS DISTINCT FROM 'string'
    OR jsonb_typeof(price->'contractId') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'operating_booking_price';END IF;
  ELSE RAISE EXCEPTION 'operating_booking_price';END IF;
 END LOOP;
 IF(kind='battery' AND(v->'chargingPrice'='null'::jsonb OR v->'fuelPrice'<>'null'::jsonb OR v->'fuelQuantityBasis'<>'null'::jsonb))
 OR(kind<>'battery' AND v->'chargingPrice'<>'null'::jsonb) OR(kind<>'thermal' AND(v->'fuelPrice'<>'null'::jsonb OR v->'fuelQuantityBasis'<>'null'::jsonb))
 OR(v->'variablePrice'='null'::jsonb AND v->'variableQuantityBasis'<>'null'::jsonb)
 OR(v->'variablePrice'<>'null'::jsonb AND v->>'variableQuantityBasis' IS DISTINCT FROM CASE kind WHEN 'battery' THEN 'grid_charge_plus_discharge' WHEN 'thermal' THEN 'energy_output' ELSE 'payment_energy' END)
 OR(v->'accessPrice'='null'::jsonb AND(v->'accessQuoteCode'<>'null'::jsonb OR v->'accessFeeBasis'<>'null'::jsonb))
 OR(v->'accessPrice'<>'null'::jsonb AND(v->>'accessFeeBasis' IS DISTINCT FROM 'preview_horizon_once_v1' OR v->'accessQuoteCode'='null'::jsonb))
 THEN RAISE EXCEPTION 'operating_booking_policy';END IF;
 SELECT * INTO quantity FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code)=(rc,rr,v->>'rightQuantityCode');
 IF NOT FOUND OR quantity.unit_code<>'resource_right' OR NOT EXISTS(SELECT 1 FROM ref_data.dimensions d
 WHERE(d.catalog_id,d.revision_id,d.code,d.mass_power,d.length_power,d.time_power,d.temperature_power,d.amount_power,d.current_power,d.luminous_power)=
 (rc,rr,quantity.dimension_code,0,0,0,0,0,0,0)) OR quantity.commodity_code<>(SELECT commodity_code FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code)=(rc,rr,f.energy_quantity_code)) THEN RAISE EXCEPTION 'operating_right_quantity';END IF;
 rows=trading.operating_plan_admission(f,plan,valuation);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE trading.operating_payment_at((x->>'from')::timestamptz,(v->'paymentRule'->>'days')::integer)<(x->>'to')::timestamptz) THEN RAISE EXCEPTION 'operating_booking_policy';END IF;
 SELECT min((value->>'from')::timestamptz),max((value->>'to')::timestamptz) INTO start_at,end_at FROM jsonb_array_elements(rows);
 canonical=trading.operating_canonical_value(plan-'snapshotId');
 IF kind='solar' THEN
  price=canonical->'solarRight';
  DECLARE fraction numeric[];BEGIN fraction=trading.operating_ratio((price->>'entitlementNumerator')::numeric,(price->>'entitlementDenominator')::numeric);
   canonical=jsonb_set(canonical,'{solarRight,entitlementNumerator}',to_jsonb(fraction[1]::text));
   canonical=jsonb_set(canonical,'{solarRight,entitlementDenominator}',to_jsonb(fraction[2]::text));END;
 END IF;
 PERFORM security.require_trade_parties(catalog,jsonb_build_object('tradeDate',(security.stamp_trade_booking(catalog) AT TIME ZONE 'UTC')::date,'legalEntityId',body->'legalEntityId','legalEntityRevision',body->'legalEntityRevision',
 'counterpartyId',body->'counterpartyId','counterpartyRevision',body->'counterpartyRevision'),valuation);
 facts=jsonb_build_object('plan',canonical,'kind',kind,'bookId',book,'legalEntityId',(body->>'legalEntityId')::uuid,'legalEntityRevision',(body->>'legalEntityRevision')::integer,
  'counterpartyId',(body->>'counterpartyId')::uuid,'counterpartyRevision',(body->>'counterpartyRevision')::integer);
 SELECT jsonb_build_object('operationId',operation,'tradeId',r.trade_id,'revision',r.revision,'instrumentId',r.instrument_id,'bindingId',r.instrument_id,'changed',false)
 INTO outcome FROM trading.operating_trade_revisions r JOIN trading.power_operating_instruments h USING(catalog_id,instrument_id)
 WHERE r.catalog_id=catalog AND h.terms=facts;
 IF FOUND THEN INSERT INTO trading.operating_booking_requests VALUES(catalog,actor,operation,body,outcome);RETURN outcome;END IF;
 IF EXISTS(SELECT 1 FROM trading.power_operating_instruments h JOIN physical.power_operating_facility_versions old ON(old.catalog_id,old.facility_id,old.version)=(h.catalog_id,h.facility_id,h.facility_version)
 WHERE h.catalog_id=catalog AND old.reference_catalog_id=rc AND old.facility_code=f.facility_code AND h.delivery_from<end_at AND start_at<h.delivery_to)
 THEN RAISE EXCEPTION 'operating_right_overlap';END IF;

 IF NOT EXISTS(SELECT 1 FROM trading.books b JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id)
 WHERE(b.catalog_id,b.id)=(catalog,book) AND b.effective_at<=valuation AND p.effective_at<=valuation) THEN RAISE EXCEPTION 'operating_booking_book';END IF;
 SELECT * INTO staged FROM trading.side_schedule_requests WHERE(catalog_id,request_id)=(catalog,operation);
 IF NOT FOUND OR staged.actor_id<>actor OR staged.command_hash<>sha256(convert_to(body::text,'UTF8')) OR staged.permission<>'BookTrade' THEN RAISE EXCEPTION 'operating_schedule';END IF;
 PERFORM security.lock_side_schedule_request(catalog,operation);
 expected_names=ARRAY[CASE kind WHEN 'battery' THEN 'discharging_energy' WHEN 'thermal' THEN 'energy_output' ELSE 'payment_energy' END];
 IF kind='battery' THEN expected_names=array_append(expected_names,'charging_energy');ELSIF kind='thermal' THEN expected_names=array_append(expected_names,'fuel_input');END IF;
 IF v->'variablePrice'<>'null'::jsonb THEN expected_names=array_append(expected_names,'variable_fee');END IF;
 IF v->'accessPrice'<>'null'::jsonb THEN expected_names=array_append(expected_names,'access_fee');END IF;
 IF(SELECT count(*) FROM trading.side_schedule_request_items WHERE(catalog_id,request_id)=(catalog,operation))<>cardinality(expected_names)
 OR jsonb_array_length(prepared->'members')<>cardinality(expected_names) THEN RAISE EXCEPTION 'operating_schedule';END IF;
 instrument=(prepared->>'instrumentId')::uuid;IF instrument IS NULL OR instrument='00000000-0000-0000-0000-000000000000' THEN RAISE EXCEPTION 'operating_booking_input';END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO publication FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,publication,pg_current_xact_id());trade=gen_random_uuid();
 INSERT INTO trading.instruments(catalog_id,id,publication_order,effective_at) VALUES(catalog,instrument,publication,valuation);
 INSERT INTO trading.power_operating_instruments VALUES(catalog,instrument,f.definition_revision_id,rc,rr,f.facility_id,f.version,start_at,end_at,v->>'rightQuantityCode',v->>'currencyCode',facts,publication,valuation);
 INSERT INTO trading.operating_plan_quantities SELECT catalog,instrument,(x->>'ordinal')::integer,x->>'name',(x->>'from')::timestamptz,(x->>'to')::timestamptz,x->>'quantity',rc,rr,(x->>'numerator')::numeric,(x->>'denominator')::numeric FROM jsonb_array_elements(rows)x;
 FOR member IN SELECT i.slot,i.schedule_id,h.side_id FROM trading.side_schedule_request_items i JOIN trading.side_schedules h ON(h.catalog_id,h.id)=(i.catalog_id,i.schedule_id)
 WHERE(i.catalog_id,i.request_id)=(catalog,operation) ORDER BY i.slot LOOP
  name=expected_names[member.slot+1];
  IF(prepared->'members'->member.slot->>'name') IS DISTINCT FROM name THEN RAISE EXCEPTION 'operating_schedule';END IF;
  price=CASE name WHEN 'charging_energy' THEN v->'chargingPrice' WHEN 'fuel_input' THEN v->'fuelPrice'
   WHEN 'variable_fee' THEN jsonb_build_object('mode','fixed','quoteCode',v->'energyPrice'->>'quoteCode','fixedPrice',v->'variablePrice','curveCode',NULL,'contractId',NULL)
   WHEN 'access_fee' THEN jsonb_build_object('mode','fixed','quoteCode',v->>'accessQuoteCode','fixedPrice',v->'accessPrice','curveCode',NULL,'contractId',NULL) ELSE v->'energyPrice' END;
  IF NOT physical.power_operating_keys(price,ARRAY['mode','quoteCode','fixedPrice','curveCode','contractId']) THEN RAISE EXCEPTION 'operating_booking_price';END IF;
  expected_quantity=CASE name WHEN 'fuel_input' THEN f.fuel_quantity_code WHEN 'access_fee' THEN v->>'rightQuantityCode' ELSE f.energy_quantity_code END;
  SELECT q.* INTO quote FROM ref_data.quote_specifications q WHERE(q.catalog_id,q.revision_id,q.code,q.kind,q.quantity_code,q.currency_code)=(rc,rr,price->>'quoteCode','outright',expected_quantity,v->>'currencyCode');
  IF NOT FOUND THEN RAISE EXCEPTION 'operating_booking_price';END IF;
  IF price->>'mode'='fixed' THEN
   PERFORM trading.operating_decimal(price->>'fixedPrice');IF price->'curveCode'<>'null'::jsonb OR price->'contractId'<>'null'::jsonb THEN RAISE EXCEPTION 'operating_booking_price';END IF;
  ELSIF price->>'mode'='selected_contract_flat_v1' THEN
   IF price->'fixedPrice'<>'null'::jsonb OR NOT EXISTS(SELECT 1 FROM market_data.curves c JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.curve_code)=(c.catalog_id,c.revision_id,c.code)
    JOIN market_data.contracts k ON(k.catalog_id,k.revision_id,k.id)=(m.catalog_id,m.revision_id,m.contract_id)
    WHERE(c.catalog_id,c.revision_id,c.code,c.quote_code,k.id)=(catalog,f.definition_revision_id,price->>'curveCode',quote.code,(price->>'contractId')::uuid)
    AND k.delivery_from<=(start_at AT TIME ZONE 'UTC')::date AND k.delivery_to>((end_at-interval '1 microsecond') AT TIME ZONE 'UTC')::date) THEN RAISE EXCEPTION 'operating_booking_price';END IF;
  ELSE RAISE EXCEPTION 'operating_booking_price';END IF;
  INSERT INTO trading.operating_memberships VALUES(catalog,instrument,member.slot,member.side_id,name,CASE WHEN member.slot=0 THEN 1 ELSE -1 END);
  INSERT INTO trading.operating_side_prices VALUES(catalog,instrument,member.slot,quote.code,rc,rr,price->>'mode',(price->>'fixedPrice')::numeric,price->>'curveCode',(price->>'contractId')::uuid,f.definition_revision_id);
  PERFORM trading.require_operating_program_shape(catalog,member.schedule_id,member.slot,instrument);
 END LOOP;
 INSERT INTO trading.trades(catalog_id,id,book_id,operation_id,actor_id,request,publication_order,effective_at) VALUES(catalog,trade,book,operation,actor,body,publication,valuation);
 INSERT INTO trading.operating_trade_revisions VALUES(catalog,trade,1,instrument,book,operation,actor,publication,valuation,(body->>'legalEntityId')::uuid,(body->>'legalEntityRevision')::integer,(body->>'counterpartyId')::uuid,(body->>'counterpartyRevision')::integer);
 outcome=jsonb_build_object('operationId',operation,'tradeId',trade,'revision',1,'instrumentId',instrument,'bindingId',instrument,'changed',true);
 INSERT INTO trading.operating_booking_requests VALUES(catalog,actor,operation,body,outcome);
 PERFORM security.operating_booking_scope(catalog,true);
 IF NOT security.has_permission('ReadPhysical') OR NOT security.reference_access(rc,'ReadMarketData') OR NOT security.reference_version_visible(rc,rr) OR NOT security.market_fact_visible(catalog,f.definition_revision_id,NULL) THEN RAISE EXCEPTION 'operating_booking_denied' USING ERRCODE='42501';END IF;RETURN outcome;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR invalid_datetime_format OR datetime_field_overflow OR null_value_not_allowed THEN RAISE EXCEPTION 'operating_booking_input';
END$$;
CREATE FUNCTION security.operating_position_scope(catalog uuid,books uuid[],portfolios uuid[],trades uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE context uuid;result jsonb;complete boolean;BEGIN
 PERFORM security.operating_booking_scope(catalog,false);
 IF books IS NULL OR portfolios IS NULL OR cardinality(books)>128 OR cardinality(portfolios)>128
 OR array_position(books,NULL) IS NOT NULL OR array_position(portfolios,NULL) IS NOT NULL
 OR(trades IS NOT NULL AND(cardinality(trades) NOT BETWEEN 1 AND 256 OR array_position(trades,NULL) IS NOT NULL OR(SELECT count(DISTINCT x) FROM unnest(trades)x)<>cardinality(trades)))
 THEN RAISE EXCEPTION 'operating_position_scope';END IF;
 SELECT c.market_context_id INTO context FROM security.request_contexts c JOIN trading.contexts t ON(t.catalog_id,t.context_id)=(c.market_catalog_id,c.market_context_id)
 WHERE c.market_catalog_id=catalog AND c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user AND c.trading_as_of IS NOT NULL;
 IF context IS NULL THEN RAISE EXCEPTION 'knowledge_coverage';END IF;
 PERFORM security.require_trading_history(catalog,context);
 WITH held AS(SELECT r.* FROM trading.operating_trade_revisions r JOIN trading.books b ON(b.catalog_id,b.id)=(r.catalog_id,r.book_id)
  JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id)
  WHERE r.catalog_id=catalog AND security.trading_visible(r.catalog_id,r.publication_order,r.effective_at)
  AND security.trading_visible(b.catalog_id,b.publication_order,b.effective_at) AND security.trading_visible(p.catalog_id,p.publication_order,p.effective_at)
  AND(cardinality(books)=0 OR r.book_id=ANY(books)) AND(cardinality(portfolios)=0 OR b.portfolio_id=ANY(portfolios)) AND(trades IS NULL OR r.trade_id=ANY(trades)))
 SELECT coalesce(jsonb_agg(jsonb_build_object('trade_id',r.trade_id,'binding_id',r.instrument_id,'instrument_id',r.instrument_id,
  'definition_revision_id',h.definition_revision_id,'book_id',r.book_id,'revision',r.revision,'trade_reference',tr.reference_number) ORDER BY tr.reference_number),'[]'),
  coalesce(bool_and(h.instrument_id IS NOT NULL AND tr.reference_number IS NOT NULL AND f.facility_id IS NOT NULL
   AND security.trading_visible(h.catalog_id,h.publication_order,h.effective_at) AND security.has_permission('ReadPhysical')
   AND security.market_fact_visible(h.catalog_id,h.definition_revision_id,NULL) AND security.reference_access(h.reference_catalog_id,'ReadMarketData')
   AND security.reference_version_visible(h.reference_catalog_id,h.reference_revision_id)),true)
 INTO result,complete FROM held r LEFT JOIN trading.power_operating_instruments h USING(catalog_id,instrument_id)
 LEFT JOIN physical.power_operating_facility_versions f ON(f.catalog_id,f.facility_id,f.version)=(h.catalog_id,h.facility_id,h.facility_version)
 LEFT JOIN trading.trade_references tr ON(tr.catalog_id,tr.trade_id)=(r.catalog_id,r.trade_id);
 IF complete IS NOT TRUE THEN RAISE EXCEPTION 'operating_position_unavailable' USING ERRCODE='42501';END IF;
 PERFORM security.operating_booking_scope(catalog,false);RETURN result;
END$$;
CREATE FUNCTION security.read_operating_positions(catalog uuid,books uuid[],portfolios uuid[],trades uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE inventory jsonb;result jsonb;BEGIN
 inventory=security.operating_position_scope(catalog,books,portfolios,trades);
 SELECT coalesce(jsonb_agg(jsonb_build_object('head',to_jsonb(x),'physical',jsonb_build_object(
 'reference_catalog_id',h.reference_catalog_id,'reference_revision_id',h.reference_revision_id,'facility_code',f.facility_code,'facility_name',l.name,
 'kind',f.kind,'quantity_code',h.quantity_code,'currency_code',h.currency_code,'unit',u.symbol,'currency',c.display_code,
 'commodity_code',q.commodity_code,'commodity_name',co.name,
 'projection_curves',(SELECT coalesce(jsonb_agg(DISTINCT curve_code),'[]') FROM trading.operating_side_prices z WHERE(z.catalog_id,z.instrument_id)=(h.catalog_id,h.instrument_id) AND z.curve_code IS NOT NULL))) ORDER BY x.trade_reference),'[]')
 INTO result FROM(
  SELECT r.*,r.instrument_id binding_id,h.definition_revision_id,h.facility_id,h.facility_version,h.delivery_from,h.delivery_to,t.request,
   tr.reference_number trade_reference,ir.reference_number instrument_reference,
   b.trade_date,b.booker_id,b.booker_name,b.booker_login,b.executed_at,b.implementation booking_implementation,b.label_captured_at,
   le.name legal_entity,cp.name counterparty,
   (SELECT jsonb_agg(jsonb_build_object('slot',m.slot,'sideId',m.side_id,'name',m.name,'coefficient',m.coefficient::text) ORDER BY slot)
    FROM trading.operating_memberships m WHERE(m.catalog_id,m.instrument_id)=(r.catalog_id,r.instrument_id)) members
  FROM trading.operating_trade_revisions r JOIN trading.power_operating_instruments h USING(catalog_id,instrument_id)
  JOIN trading.trades t ON(t.catalog_id,t.id)=(r.catalog_id,r.trade_id)
  JOIN trading.trade_references tr ON(tr.catalog_id,tr.trade_id)=(r.catalog_id,r.trade_id)
  JOIN trading.instrument_references ir ON(ir.catalog_id,ir.instrument_id)=(r.catalog_id,r.instrument_id)
  JOIN trading.booking_facts b ON(b.catalog_id,b.trade_id)=(r.catalog_id,r.trade_id)
  JOIN trading.legal_entities le ON(le.catalog_id,le.id,le.revision)=(r.catalog_id,r.legal_entity_id,r.legal_entity_revision)
  JOIN trading.counterparties cp ON(cp.catalog_id,cp.id,cp.revision)=(r.catalog_id,r.counterparty_id,r.counterparty_revision)
  WHERE r.catalog_id=catalog AND r.trade_id IN(SELECT(value->>'trade_id')::uuid FROM jsonb_array_elements(inventory)))x
 JOIN trading.power_operating_instruments h ON(h.catalog_id,h.instrument_id)=(x.catalog_id,x.instrument_id)
 JOIN physical.power_operating_facility_versions f ON(f.catalog_id,f.facility_id,f.version)=(h.catalog_id,h.facility_id,h.facility_version)
 JOIN ref_data.locations l ON(l.catalog_id,l.revision_id,l.code)=(h.reference_catalog_id,h.reference_revision_id,f.facility_code)
 JOIN ref_data.quantity_specifications q ON(q.catalog_id,q.revision_id,q.code)=(h.reference_catalog_id,h.reference_revision_id,h.quantity_code)
 JOIN ref_data.units u ON(u.catalog_id,u.revision_id,u.code)=(q.catalog_id,q.revision_id,q.unit_code)
 JOIN ref_data.commodities co ON(co.catalog_id,co.revision_id,co.code)=(q.catalog_id,q.revision_id,q.commodity_code)
 JOIN ref_data.currencies c ON(c.catalog_id,c.revision_id,c.code)=(h.reference_catalog_id,h.reference_revision_id,h.currency_code);
 IF jsonb_array_length(result)<>jsonb_array_length(inventory) THEN RAISE EXCEPTION 'operating_position_metadata';END IF;
 PERFORM security.operating_position_scope(catalog,books,portfolios,trades);RETURN result;
END$$;
CREATE FUNCTION security.operating_booking_replay(catalog uuid,body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;r trading.operating_booking_requests;BEGIN
 actor=security.operating_booking_scope(catalog,false);
 SELECT * INTO r FROM trading.operating_booking_requests WHERE(catalog_id,actor_id,operation_id)=(catalog,actor,(body->>'operationId')::uuid);
 IF NOT FOUND THEN RETURN NULL;END IF;
 IF r.command IS DISTINCT FROM body THEN RAISE EXCEPTION 'operating_request_conflict';END IF;
 PERFORM security.operating_booking_scope(catalog,false);RETURN r.outcome;
END$$;
DO $$DECLARE f regprocedure;BEGIN
 FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='trading' AND(p.proname LIKE 'operating_%' OR p.proname='require_operating_program_shape'))
 OR(n.nspname='security' AND p.proname IN('operating_booking_scope','operating_booking_status','operating_booking_replay','book_operating_right','operating_position_scope','read_operating_positions')) LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f);EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION security.book_operating_right(uuid,jsonb,jsonb,timestamptz),security.operating_booking_status(uuid,uuid),security.operating_booking_replay(uuid,jsonb) TO openetrm_runtime;
GRANT EXECUTE ON FUNCTION security.operating_position_scope(uuid,uuid[],uuid[],uuid[]),security.read_operating_positions(uuid,uuid[],uuid[],uuid[]) TO openetrm_runtime,openetrm_risk_worker;
COMMIT;
