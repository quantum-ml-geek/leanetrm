-- Native admission uses the same UTC payment-day boundary as the managed
-- contract. Actual payment events and negotiated correction instants are unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.book_physical_crude(uuid,jsonb,timestamp with time zone)","definition":"b615785b489dca56c12adaf6502b79827a11e89420ec9ca3047686ec7c37ad17","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.book_physical_gas(uuid,jsonb,timestamp with time zone)","definition":"839b78c6204c33d07619834029d235be9930c69442304cb90e1e474eb70ba69a","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.book_physical_lng(uuid,jsonb,timestamp with time zone)","definition":"1f2df00f8f297df3533903d64f0e0922428d11e393177861aeff9ca7c3caf5c9","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,jsonb,uuid[])","definition":"ece8295b905b4fef1e4e2786f0e5f0aad2ade009de9475a59f75d8b19165b29e","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)","definition":"305d05fc804fc22857564f9bd056a89e37c2d8d5c7007eea77b175a2a06c071a","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])","definition":"f07e38b2b86ddd51f04afe239d47da744c8214ca9d699ec67123b097b20b2bf4","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid)","definition":"47db1367c7e7986a9d934a6bcf6fe6e0a2a2f06efc4c16770c831eb6eb962971","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamp with time zone,timestamp with time zone,text,text,text,jsonb,uuid[])","definition":"e529aee52b71dacae32d3f8802e1faeecbde2e3d1cccb8bf8ef382da34df367b","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamp with time zone,jsonb,uuid[])","definition":"41f76170d3f70e728d5c291fd889301b8bf41f17cc20cd2f6c48515e31ad15e3","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.swap_business_day(uuid,uuid,text,date)","definition":"2bba232e4c8c194e61c580af023499b87f83deb0c152425e9782343b5ac60d86","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.swap_fixing_evidence(uuid,uuid,uuid,uuid,text,text,date,date,text,timestamp with time zone,timestamp with time zone,uuid[])","definition":"b839707809efc1c350caea9bdf34e30ba2cf6120bcb2ca94ae5292e04120f7a4","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.swap_observation_fixing_evidence(uuid,uuid,uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid[],jsonb)","definition":"f35f271f632283559ebb4e7abd51240b2e5537fa87aca71c3672397860bec1c3","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.write_gas_composition(uuid,jsonb,timestamp with time zone,boolean)","definition":"dc0e5f6acbe2137480a4ec2672caca59a39c7ab830b97d6e0e4d7e14fe8fcca6","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"trading.require_crude_program_shape(uuid,uuid,integer,timestamp with time zone,timestamp with time zone,timestamp with time zone,numeric,market_data.crude_valuation_assignments)","definition":"ccfe47d383c29efffe3fb8c7711d2c1ccf4b5e7fc775081447168ac4ac201a5a","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"trading.require_gas_index_cash_shape(uuid,uuid,trading.gas_component_terms,market_data.gas_valuation_assignments,jsonb)","definition":"8a7d023d386c9e8c472a907cdd6cb9ff2825f19cc1a42d378c7bea61bc77ddb2","volatility":"v"}]
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




DO $$DECLARE source text;signature regprocedure;marker text;BEGIN
 source=pg_get_functiondef('security.swap_business_day(uuid,uuid,text,date)'::regprocedure);
 marker='IF NOT FOUND OR c.coverage_to-c.coverage_from>36600 OR day<c.coverage_from OR day>=c.coverage_to THEN RAISE EXCEPTION ''payment_calendar'' USING ERRCODE=''P0001'';END IF;';
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'payment_day_admission_predecessor';END IF;
 EXECUTE replace(source,marker,$patch$
 IF NOT FOUND THEN RAISE EXCEPTION 'calendar_reference';END IF;
 IF c.coverage_to-c.coverage_from>36600 OR day<c.coverage_from OR day>=c.coverage_to THEN RAISE EXCEPTION 'calendar_coverage';END IF;
 $patch$);
 FOREACH signature IN ARRAY ARRAY[
  'security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz)'::regprocedure,
  'security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid)'::regprocedure,
  'security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,uuid[])'::regprocedure,
  'security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamptz,integer,timestamptz,jsonb,uuid[])'::regprocedure] LOOP
  source=pg_get_functiondef(signature);
  marker='::timestamp AT TIME ZONE ''UTC'';';
  -- Only the generated payment assignment is changed, not fixing instants.
  source=regexp_replace(source,'(payment=security.side_payment_date[^;]+;)',
   E'\\1\n IF (payment AT TIME ZONE ''UTC'')::date<(body->>''deliveryTo'')::date THEN RAISE EXCEPTION ''payment_before_delivery'';END IF;');
  IF strpos(source,'payment_before_delivery')=0 THEN RAISE EXCEPTION 'payment_day_admission_predecessor';END IF;
  EXECUTE source;
 END LOOP;
 FOREACH signature IN ARRAY ARRAY[
  'security.swap_fixing_evidence(uuid,uuid,uuid,uuid,text,text,date,date,text,timestamptz,timestamptz,uuid[])'::regprocedure,
  'security.swap_observation_fixing_evidence(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,uuid[],jsonb)'::regprocedure] LOOP
  source=pg_get_functiondef(signature);
  IF strpos(source,'r.fixing_at>=payment')=0 THEN RAISE EXCEPTION 'payment_day_admission_predecessor';END IF;
  EXECUTE replace(source,'r.fixing_at>=payment','(r.fixing_at AT TIME ZONE ''UTC'')::date>(payment AT TIME ZONE ''UTC'')::date');
 END LOOP;
END$$;

DO $$DECLARE signature regprocedure;source text;changed text;item record;BEGIN
 FOR signature IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE(n.nspname,p.proname) IN(('security','save_composed_swap'),('security','save_scheduled_swap'),
   ('security','write_gas_composition'),('security','book_physical_gas'),('security','book_physical_crude'),('security','book_physical_lng'),
   ('trading','require_gas_index_cash_shape'),('trading','require_crude_program_shape')) LOOP
  source=pg_get_functiondef(signature);changed=source;
  changed=regexp_replace(changed,'valuation>=([sfap])\.payment_at',
   '(valuation AT TIME ZONE ''UTC'')::date>(\1.payment_at AT TIME ZONE ''UTC'')::date','g');
  changed=regexp_replace(changed,'payment<(day_end|end_at|discharge_end)',
   '(payment AT TIME ZONE ''UTC'')::date<(\1 AT TIME ZONE ''UTC'')::date','g');
  changed=replace(changed,'fixing.fixing_at>=payment','(fixing.fixing_at AT TIME ZONE ''UTC'')::date>(payment AT TIME ZONE ''UTC'')::date');
  IF changed=source THEN RAISE EXCEPTION 'payment_day_admission_predecessor: %',signature;END IF;
  EXECUTE changed;
 END LOOP;
 FOR item IN SELECT conrelid::regclass AS relation,conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint
  WHERE conrelid IN('trading.swap_floating_sides'::regclass,'trading.swap_side_periods'::regclass,
   'trading.crude_instruments'::regclass,'trading.lng_instruments'::regclass) AND contype='c'
  AND(pg_get_constraintdef(oid) LIKE '%first_fixing_at%<%payment_at%' OR
      pg_get_constraintdef(oid) LIKE '%payment_at%>=%') LOOP
  source=replace(item.definition,'(first_fixing_at)::timestamp with time zone < (payment_at)::timestamp with time zone',
   '(first_fixing_at AT TIME ZONE ''UTC'')::date <= (payment_at AT TIME ZONE ''UTC'')::date');
  source=replace(source,'(payment_at)::timestamp with time zone >= (delivery_to)::timestamp with time zone',
   '(payment_at AT TIME ZONE ''UTC'')::date >= (delivery_to AT TIME ZONE ''UTC'')::date');
  source=replace(source,'(payment_at)::timestamp with time zone >= (discharge_to)::timestamp with time zone',
   '(payment_at AT TIME ZONE ''UTC'')::date >= (discharge_to AT TIME ZONE ''UTC'')::date');
  IF source=item.definition THEN RAISE EXCEPTION 'payment_day_admission_predecessor: %',item.conname;END IF;
  EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',item.relation,item.conname);
  EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s NOT VALID',item.relation,item.conname,source);
 END LOOP;
END$$;
COMMIT;
