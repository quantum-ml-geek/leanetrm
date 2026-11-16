-- Exact operating-parameter extensions of existing physical locations.
-- Operational state, dispatch, contractual guarantees and valuation policy are not setup.
BEGIN;
SELECT pg_advisory_xact_lock(730849102);
CREATE SCHEMA IF NOT EXISTS physical AUTHORIZATION openetrm_security_owner;
GRANT USAGE ON SCHEMA physical TO openetrm_runtime;
INSERT INTO security.permissions VALUES('ReadPhysical'),('ManagePhysicalSetup') ON CONFLICT DO NOTHING;

CREATE TABLE physical.power_operating_facility_versions (
 catalog_id uuid NOT NULL,facility_id uuid NOT NULL,version integer NOT NULL CHECK(version>0),
 actor_id uuid NOT NULL REFERENCES security.principals(id),
 definition_revision_id uuid NOT NULL,reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,
 facility_code ref_data.code NOT NULL,kind text NOT NULL CHECK(kind IN('thermal','battery','solar')),
 clock_code ref_data.code NOT NULL,interval_minutes integer NOT NULL CHECK(interval_minutes IN(5,15,30,60) AND(kind='battery' OR interval_minutes IN(15,60))),
 power_quantity_code ref_data.code,energy_quantity_code ref_data.code NOT NULL,
 fuel_quantity_code ref_data.code,
 effective_from ref_data.instant NOT NULL,effective_to ref_data.instant NOT NULL,
 implementation text NOT NULL CHECK(implementation='structured_power_facility_v1'),parameters jsonb NOT NULL,
 publication_order integer NOT NULL,
 PRIMARY KEY(catalog_id,facility_id,version),
 UNIQUE(catalog_id,reference_catalog_id,facility_code,kind,version),
 CHECK(effective_from<effective_to),CHECK((kind='thermal')=(fuel_quantity_code IS NOT NULL)),
 CHECK((kind='solar')=(power_quantity_code IS NULL)),
 CHECK(jsonb_typeof(parameters)='object'),
 FOREIGN KEY(catalog_id,definition_revision_id,reference_catalog_id,reference_revision_id)
  REFERENCES market_data.revisions(catalog_id,id,reference_catalog_id,reference_revision_id),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,facility_code) REFERENCES ref_data.locations(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,clock_code) REFERENCES ref_data.clock_rules(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,power_quantity_code) REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,energy_quantity_code) REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,fuel_quantity_code) REFERENCES ref_data.quantity_specifications(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE physical.power_operating_facility_requests (
 catalog_id uuid NOT NULL REFERENCES market_data.catalogs(id),actor_id uuid NOT NULL REFERENCES security.principals(id),
 request_id uuid NOT NULL,command jsonb NOT NULL,outcome jsonb NOT NULL,
 PRIMARY KEY(catalog_id,actor_id,request_id)
);
CREATE TRIGGER immutable_operating_parameters BEFORE UPDATE OR DELETE ON physical.power_operating_facility_versions
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
CREATE TRIGGER immutable_operating_request BEFORE UPDATE OR DELETE ON physical.power_operating_facility_requests
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
ALTER TABLE physical.power_operating_facility_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE physical.power_operating_facility_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE physical.power_operating_facility_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE physical.power_operating_facility_requests FORCE ROW LEVEL SECURITY;
REVOKE ALL ON physical.power_operating_facility_versions,physical.power_operating_facility_requests FROM PUBLIC,openetrm_runtime;
GRANT SELECT,INSERT ON physical.power_operating_facility_versions,physical.power_operating_facility_requests TO openetrm_security_owner;

CREATE FUNCTION physical.power_operating_scope(catalog uuid,writing boolean) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;BEGIN
 PERFORM 1 FROM security.epoch WHERE id FOR SHARE;
 IF NOT security.has_permission('ReadPhysical') OR NOT security.market_access(catalog,'ReadMarketData')
  OR (writing AND(NOT security.market_access(catalog,'ManagePhysicalSetup') OR NOT security.current_write_context()))
 THEN RAISE EXCEPTION 'power_facility_denied' USING ERRCODE='42501';END IF;
 SELECT q.actor_id INTO actor FROM security.request_contexts q WHERE q.backend_pid=pg_backend_pid()
  AND q.transaction_id=pg_current_xact_id_if_assigned() AND q.runtime_login=session_user AND q.expires_at>clock_timestamp();
 IF actor IS NULL THEN RAISE EXCEPTION 'power_facility_denied' USING ERRCODE='42501';END IF;
 RETURN actor;
END$$;

CREATE FUNCTION physical.power_operating_keys(value jsonb,keys text[]) RETURNS boolean
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
 IF jsonb_typeof(value) IS DISTINCT FROM 'object' THEN RETURN false;END IF;
 RETURN(SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(value)k)=
  (SELECT array_agg(k ORDER BY k) FROM unnest(keys)k);
END
$$;

-- Closed transport normalization. Managed admission applies the same selected
-- physical model's static validation before this durable operation is called.
CREATE FUNCTION physical.power_operating_command(body jsonb) RETURNS jsonb
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE t jsonb;p jsonb;variant text;n text;names text[];ints text[];v ref_data.exact_number;at_from ref_data.instant;at_to ref_data.instant;BEGIN
 IF body IS NULL OR length(body::text)>16384 OR NOT physical.power_operating_keys(body,ARRAY['id','version','effectiveFrom','effectiveTo','terms']) THEN
  RAISE EXCEPTION 'power_facility_shape';END IF;
 t=body->'terms';variant=t->>'kind';
 IF NOT physical.power_operating_keys(t,ARRAY['kind','definitionCatalogId','definitionRevisionId','referenceCatalogId','referenceRevisionId','facilityCode','clockCode','intervalMinutes',
  'powerQuantityCode','energyQuantityCode','fuelQuantityCode','battery','thermal','solar','implementation'])
  OR variant IS NULL OR variant NOT IN('thermal','battery','solar') OR t->>'implementation' IS DISTINCT FROM 'structured_power_facility_v1'
  OR jsonb_typeof(body->'id') IS DISTINCT FROM 'string'
  OR (body->>'id')::uuid='00000000-0000-0000-0000-000000000000' OR (body->>'version')::integer<1
  OR jsonb_typeof(body->'version') IS DISTINCT FROM 'number' OR jsonb_typeof(t->'intervalMinutes') IS DISTINCT FROM 'number'
  OR t->>'intervalMinutes' NOT IN('5','15','30','60') OR(variant<>'battery' AND t->>'intervalMinutes' NOT IN('15','60'))
 THEN RAISE EXCEPTION 'power_facility_shape';END IF;
 FOREACH n IN ARRAY ARRAY['definitionCatalogId','definitionRevisionId','referenceCatalogId','referenceRevisionId'] LOOP
  IF jsonb_typeof(t->n) IS DISTINCT FROM 'string' OR (t->>n)::uuid='00000000-0000-0000-0000-000000000000' THEN RAISE EXCEPTION 'power_facility_shape';END IF;
  t=jsonb_set(t,ARRAY[n],to_jsonb(((t->>n)::uuid)::text));
 END LOOP;
 FOREACH n IN ARRAY ARRAY['facilityCode','clockCode','energyQuantityCode'] LOOP
  IF jsonb_typeof(t->n) IS DISTINCT FROM 'string' OR t->>n !~ '^[a-z][a-z0-9_.-]{0,63}$' THEN RAISE EXCEPTION 'power_facility_shape';END IF;
 END LOOP;
 IF(variant='solar' AND t->'powerQuantityCode' IS DISTINCT FROM 'null'::jsonb)
  OR(variant<>'solar' AND(jsonb_typeof(t->'powerQuantityCode') IS DISTINCT FROM 'string' OR t->>'powerQuantityCode' !~ '^[a-z][a-z0-9_.-]{0,63}$'))
 THEN RAISE EXCEPTION 'power_facility_shape';END IF;
 IF (variant='thermal' AND(jsonb_typeof(t->'fuelQuantityCode') IS DISTINCT FROM 'string' OR t->>'fuelQuantityCode' !~ '^[a-z][a-z0-9_.-]{0,63}$'))
  OR (variant<>'thermal' AND t->'fuelQuantityCode' IS DISTINCT FROM 'null'::jsonb) THEN RAISE EXCEPTION 'power_facility_shape';END IF;
 FOREACH n IN ARRAY ARRAY['thermal','battery','solar'] LOOP
  IF n<>variant AND t->n IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'power_facility_shape';END IF;
 END LOOP;
 p=t->variant;
 IF variant='thermal' THEN
  names=ARRAY['minimumOutputMw','maximumOutputMw','rampUpMwPerHour','rampDownMwPerHour','startupMaximumOutputMw','shutdownMaximumOutputMw',
   'consumptionHeatRate','consumptionNoLoadFuelPerHour','consumptionStartupFuel'];
  ints=ARRAY['minimumUpMinutes','minimumDownMinutes','startupLeadMinutes','maximumStarts'];
  IF NOT physical.power_operating_keys(p,names||ints) THEN RAISE EXCEPTION 'power_facility_shape';END IF;
 ELSIF variant='battery' THEN
  names=ARRAY['maximumChargeMw','maximumDischargeMw','minimumStoredMwh','maximumStoredMwh','chargeEfficiency','dischargeEfficiency'];ints=ARRAY[]::text[];
  IF NOT physical.power_operating_keys(p,names||ARRAY['meterBoundary','lossPolicy','capacityPolicy','simultaneousPolicy','chargingOrigin','throughputPolicy','maximumThroughputMwh'])
   OR p->>'meterBoundary' IS DISTINCT FROM 'grid_side_ac' OR p->>'lossPolicy' IS DISTINCT FROM 'zero_auxiliary_and_self_discharge'
   OR p->>'capacityPolicy' IS DISTINCT FROM 'fixed' OR p->>'simultaneousPolicy' IS DISTINCT FROM 'prohibited' OR p->>'chargingOrigin' IS DISTINCT FROM 'grid'
  THEN RAISE EXCEPTION 'power_facility_shape';END IF;
  IF p->>'throughputPolicy'='grid_charge_plus_discharge' THEN names=names||'maximumThroughputMwh';
  ELSIF p->>'throughputPolicy' IS DISTINCT FROM 'uncapped' OR p->'maximumThroughputMwh' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'power_facility_shape';END IF;
 ELSE
  names=ARRAY[]::text[];ints=ARRAY[]::text[];
  IF NOT physical.power_operating_keys(p,ARRAY['stage']) OR p->>'stage' IS NULL OR p->>'stage' NOT IN('generated','delivered') THEN RAISE EXCEPTION 'power_facility_shape';END IF;
 END IF;
 FOREACH n IN ARRAY names LOOP
  IF jsonb_typeof(p->n) IS DISTINCT FROM 'string' OR length(p->>n)>80 OR p->>n !~ '^-?[0-9]+(\.[0-9]+)?$' THEN RAISE EXCEPTION 'power_facility_parameters';END IF;
  v=(p->>n)::ref_data.exact_number;
  IF v<0 THEN RAISE EXCEPTION 'power_facility_parameters';END IF;
  p=jsonb_set(p,ARRAY[n],to_jsonb(trim_scale(v)::text));
 END LOOP;
 FOREACH n IN ARRAY ints LOOP
  IF jsonb_typeof(p->n) IS DISTINCT FROM 'number' OR p->>n !~ '^[0-9]+$' OR
   (p->>n)::numeric>(CASE WHEN n='maximumStarts' THEN 2147483647 ELSE 525600 END) THEN RAISE EXCEPTION 'power_facility_parameters';END IF;
 END LOOP;
 IF variant='thermal' AND((p->>'consumptionHeatRate')::numeric<=0 OR (p->>'maximumOutputMw')::numeric<=0 OR (p->>'minimumOutputMw')::numeric>(p->>'maximumOutputMw')::numeric
  OR (p->>'startupMaximumOutputMw')::numeric>(p->>'maximumOutputMw')::numeric OR (p->>'shutdownMaximumOutputMw')::numeric>(p->>'maximumOutputMw')::numeric)
  OR variant='battery' AND((p->>'maximumChargeMw')::numeric=0 AND (p->>'maximumDischargeMw')::numeric=0
   OR (p->>'maximumStoredMwh')::numeric<=0 OR (p->>'minimumStoredMwh')::numeric>(p->>'maximumStoredMwh')::numeric
   OR (p->>'chargeEfficiency')::numeric<=0 OR (p->>'chargeEfficiency')::numeric>1 OR (p->>'dischargeEfficiency')::numeric<=0 OR (p->>'dischargeEfficiency')::numeric>1)
 THEN RAISE EXCEPTION 'power_facility_parameters';END IF;
 FOREACH n IN ARRAY ARRAY['effectiveFrom','effectiveTo'] LOOP
  IF jsonb_typeof(body->n) IS DISTINCT FROM 'string' OR body->>n !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|\+00:00)$' THEN RAISE EXCEPTION 'power_facility_time';END IF;
 END LOOP;
 at_from=(body->>'effectiveFrom')::ref_data.instant;at_to=(body->>'effectiveTo')::ref_data.instant;
 IF at_from>=at_to THEN RAISE EXCEPTION 'power_facility_time';END IF;
 body=jsonb_set(body,'{effectiveFrom}',to_jsonb(to_char(at_from AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
 body=jsonb_set(body,'{effectiveTo}',to_jsonb(to_char(at_to AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
 body=jsonb_set(body,'{id}',to_jsonb(((body->>'id')::uuid)::text));
 RETURN jsonb_set(body,'{terms}',jsonb_set(t,ARRAY[variant],p));
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation OR invalid_datetime_format OR datetime_field_overflow THEN
 RAISE EXCEPTION 'power_facility_parameters';
END$$;

CREATE FUNCTION physical.power_operating_envelope(v physical.power_operating_facility_versions) RETURNS jsonb
 LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('id',v.facility_id,'version',v.version,
  'effectiveFrom',to_char(v.effective_from AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'effectiveTo',to_char(v.effective_to AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'terms',jsonb_build_object('kind',v.kind,'definitionCatalogId',v.catalog_id,'definitionRevisionId',v.definition_revision_id,
   'referenceCatalogId',v.reference_catalog_id,'referenceRevisionId',v.reference_revision_id,'facilityCode',v.facility_code,'clockCode',v.clock_code,
   'intervalMinutes',v.interval_minutes,'powerQuantityCode',v.power_quantity_code,'energyQuantityCode',v.energy_quantity_code,
   'fuelQuantityCode',v.fuel_quantity_code,'implementation',v.implementation,
   'battery',CASE WHEN v.kind='battery' THEN v.parameters END,'thermal',CASE WHEN v.kind='thermal' THEN v.parameters END,'solar',CASE WHEN v.kind='solar' THEN v.parameters END))
$$;

CREATE FUNCTION physical.save_power_operating_facility(catalog uuid,request uuid,expected_version integer,candidate jsonb) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;body jsonb;t jsonb;saved physical.power_operating_facility_versions;prior physical.power_operating_facility_requests;
 command jsonb;result jsonb;head integer;logical_id uuid;ordinal integer;BEGIN
 actor=physical.power_operating_scope(catalog,true);
 IF request IS NULL OR request='00000000-0000-0000-0000-000000000000' OR expected_version IS NULL OR expected_version<0 OR expected_version=2147483647 THEN RAISE EXCEPTION 'power_facility_request';END IF;
 body=physical.power_operating_command(candidate);t=body->'terms';command=jsonb_build_object('expectedVersion',expected_version,'facility',body);
 IF (t->>'definitionCatalogId')::uuid IS DISTINCT FROM catalog THEN RAISE EXCEPTION 'power_facility_reference';END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 PERFORM physical.power_operating_scope(catalog,true);
 IF NOT security.reference_access((t->>'referenceCatalogId')::uuid,'ReadMarketData') THEN RAISE EXCEPTION 'power_facility_reference' USING ERRCODE='42501';END IF;
 SELECT * INTO prior FROM physical.power_operating_facility_requests r WHERE(r.catalog_id,r.actor_id,r.request_id)=(catalog,actor,request);
 IF FOUND THEN
  IF prior.command IS DISTINCT FROM command THEN RAISE EXCEPTION 'power_facility_request_conflict';END IF;
  PERFORM physical.power_operating_scope(catalog,true);
  RETURN prior.outcome;
 END IF;
 IF NOT security.reference_access((t->>'referenceCatalogId')::uuid,'ReadMarketData') OR NOT EXISTS(
  SELECT 1 FROM market_data.revisions r JOIN market_data.knowledge_events e ON(e.catalog_id,e.revision_id)=(r.catalog_id,r.id) AND e.observation_id IS NULL
  WHERE(r.catalog_id,r.id,r.reference_catalog_id,r.reference_revision_id)=(catalog,(t->>'definitionRevisionId')::uuid,(t->>'referenceCatalogId')::uuid,(t->>'referenceRevisionId')::uuid) AND r.state='sealed')
 THEN RAISE EXCEPTION 'power_facility_reference' USING ERRCODE='42501';END IF;
 -- Identity and unit semantics are resolved from the selected exact reference rows.
 IF NOT EXISTS(SELECT 1 FROM ref_data.locations l LEFT JOIN ref_data.quantity_specifications p ON(p.catalog_id,p.revision_id,p.code)=(l.catalog_id,l.revision_id,t->>'powerQuantityCode')
  JOIN ref_data.quantity_specifications e ON(e.catalog_id,e.revision_id,e.code)=(l.catalog_id,l.revision_id,t->>'energyQuantityCode')
  WHERE(l.catalog_id,l.revision_id,l.code)=((t->>'referenceCatalogId')::uuid,(t->>'referenceRevisionId')::uuid,t->>'facilityCode')
   AND(l.clock_code IS NULL OR l.clock_code=t->>'clockCode') AND e.unit_code='megawatt_hour' AND e.dimension_code='energy'
   AND(t->>'kind'='solar' OR(p.unit_code='megawatt' AND p.dimension_code='power' AND p.commodity_code=e.commodity_code))
   AND(t->>'kind'<>'thermal' OR EXISTS(SELECT 1 FROM ref_data.quantity_specifications f WHERE(f.catalog_id,f.revision_id,f.code)=(l.catalog_id,l.revision_id,t->>'fuelQuantityCode') AND f.dimension_code='energy' AND f.commodity_code<>e.commodity_code)))
 THEN RAISE EXCEPTION 'power_facility_reference';END IF;
 SELECT * INTO saved FROM physical.power_operating_facility_versions v WHERE v.catalog_id=catalog
  AND(v.reference_catalog_id,v.facility_code,v.kind)=((t->>'referenceCatalogId')::uuid,t->>'facilityCode',t->>'kind')
  AND physical.power_operating_envelope(v)-'id'-'version'=body-'id'-'version' ORDER BY v.version LIMIT 1;
 IF FOUND THEN result=jsonb_build_object('requestId',request,'changed',false,'facility',physical.power_operating_envelope(saved));
 ELSE
  SELECT max(v.version),min(v.facility_id::text)::uuid INTO head,logical_id FROM physical.power_operating_facility_versions v
   WHERE v.catalog_id=catalog AND(v.reference_catalog_id,v.facility_code,v.kind)=((t->>'referenceCatalogId')::uuid,t->>'facilityCode',t->>'kind');
  IF coalesce(head,0)<>expected_version OR (body->>'version')::integer<>expected_version+1
   OR(head IS NOT NULL AND logical_id IS DISTINCT FROM (body->>'id')::uuid)
   OR EXISTS(SELECT 1 FROM physical.power_operating_facility_versions v WHERE(v.catalog_id,v.facility_id)=(catalog,(body->>'id')::uuid)
     AND(v.reference_catalog_id,v.facility_code,v.kind) IS DISTINCT FROM((t->>'referenceCatalogId')::uuid,t->>'facilityCode',t->>'kind'))
  THEN RAISE EXCEPTION 'power_facility_revision_conflict';END IF;
  SELECT coalesce(max(p.publication_order),0)+1 INTO ordinal FROM trading.publications p WHERE p.catalog_id=catalog;
  INSERT INTO trading.publications VALUES(catalog,ordinal,pg_current_xact_id());
  INSERT INTO physical.power_operating_facility_versions VALUES(catalog,(body->>'id')::uuid,(body->>'version')::integer,actor,
   (t->>'definitionRevisionId')::uuid,(t->>'referenceCatalogId')::uuid,(t->>'referenceRevisionId')::uuid,t->>'facilityCode',t->>'kind',t->>'clockCode',(t->>'intervalMinutes')::integer,
   t->>'powerQuantityCode',t->>'energyQuantityCode',t->>'fuelQuantityCode',(body->>'effectiveFrom')::timestamptz,(body->>'effectiveTo')::timestamptz,
   t->>'implementation',t->(t->>'kind'),ordinal) RETURNING * INTO saved;
  result=jsonb_build_object('requestId',request,'changed',true,'facility',physical.power_operating_envelope(saved));
 END IF;
 PERFORM physical.power_operating_scope(catalog,true);
 INSERT INTO physical.power_operating_facility_requests VALUES(catalog,actor,request,command,result);
 RETURN result;
END$$;

CREATE FUNCTION physical.power_operating_context(catalog uuid,context uuid,as_of timestamptz,business_on date) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE bound uuid;BEGIN
 PERFORM physical.power_operating_scope(catalog,false);
 IF context IS NULL OR business_on IS NULL OR as_of IS NULL OR NOT isfinite(as_of) OR NOT EXISTS(SELECT 1 FROM market_data.temporal_contexts t
  JOIN trading.contexts c ON(c.catalog_id,c.context_id)=(t.catalog_id,t.id)
  WHERE(t.catalog_id,t.id)=(catalog,context) AND t.effective_on=business_on)
 THEN RAISE EXCEPTION 'power_facility_context';END IF;
 SELECT market_context_id INTO bound FROM security.request_contexts q WHERE q.backend_pid=pg_backend_pid()
  AND q.transaction_id=pg_current_xact_id_if_assigned() AND q.runtime_login=session_user;
 IF bound IS NULL THEN PERFORM security.use_market_context(catalog,context);
 ELSIF NOT EXISTS(SELECT 1 FROM security.request_contexts q WHERE q.backend_pid=pg_backend_pid() AND q.transaction_id=pg_current_xact_id_if_assigned()
  AND q.runtime_login=session_user AND(q.market_catalog_id,q.market_context_id)=(catalog,context)) THEN RAISE EXCEPTION 'power_facility_context';END IF;
END$$;

CREATE FUNCTION physical.power_operating_visible(v physical.power_operating_facility_versions,context uuid) RETURNS boolean
 LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.reference_access(v.reference_catalog_id,'ReadMarketData') AND security.market_fact_visible(v.catalog_id,v.definition_revision_id,NULL)
  AND EXISTS(SELECT 1 FROM trading.contexts c JOIN trading.knowledge_receipts k ON k.catalog_id=c.catalog_id
   JOIN market_data.temporal_contexts t ON(t.catalog_id,t.id)=(c.catalog_id,c.context_id)
   WHERE(c.catalog_id,c.context_id)=(v.catalog_id,context) AND k.publication_order=v.publication_order AND k.publication_order<=c.known_through AND k.known_from<=t.known_at)
$$;

CREATE FUNCTION physical.read_power_operating_facility(catalog uuid,facility uuid,selected_version integer,context uuid,as_of timestamptz,business_on date) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;BEGIN
 PERFORM physical.power_operating_context(catalog,context,as_of,business_on);
 SELECT physical.power_operating_envelope(v) INTO result FROM physical.power_operating_facility_versions v
  WHERE(v.catalog_id,v.facility_id,v.version)=(catalog,facility,selected_version) AND physical.power_operating_visible(v,context);
 IF result IS NULL THEN RAISE EXCEPTION 'power_facility_unavailable';END IF;
 PERFORM physical.power_operating_scope(catalog,false);RETURN result;
END$$;

CREATE FUNCTION physical.list_power_operating_facilities(catalog uuid,context uuid,as_of timestamptz,business_on date,selection_policy text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;BEGIN
 PERFORM physical.power_operating_context(catalog,context,as_of,business_on);
 IF selection_policy IS NULL OR selection_policy NOT IN('all_known_versions_v1','active_asof_latest_v1') THEN RAISE EXCEPTION 'power_facility_selection_policy';END IF;
 WITH eligible AS(SELECT v.* FROM physical.power_operating_facility_versions v WHERE v.catalog_id=catalog AND physical.power_operating_visible(v,context)
  AND(selection_policy='all_known_versions_v1' OR(v.effective_from<=as_of AND as_of<v.effective_to))),
 selected AS(SELECT e.* FROM eligible e WHERE selection_policy='all_known_versions_v1' OR e.version=(SELECT max(n.version) FROM eligible n WHERE n.facility_id=e.facility_id))
 SELECT coalesce(jsonb_agg(physical.power_operating_envelope(s) ORDER BY s.facility_code,s.kind,s.version),'[]') INTO result FROM selected s;
 PERFORM physical.power_operating_scope(catalog,false);RETURN result;
END$$;

CREATE FUNCTION physical.power_operating_facility_request_status(catalog uuid,request uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid;result jsonb;BEGIN
 actor=physical.power_operating_scope(catalog,false);
 IF NOT security.current_write_context() THEN RAISE EXCEPTION 'power_facility_context';END IF;
 SELECT r.outcome INTO result FROM physical.power_operating_facility_requests r WHERE(r.catalog_id,r.actor_id,r.request_id)=(catalog,actor,request);
 IF result IS NOT NULL AND NOT security.reference_access((result#>>'{facility,terms,referenceCatalogId}')::uuid,'ReadMarketData')
 THEN RAISE EXCEPTION 'power_facility_reference' USING ERRCODE='42501';END IF;
 PERFORM physical.power_operating_scope(catalog,false);RETURN result;
END$$;

-- No raw runtime table access or public helper execution. Capability operations
-- recheck the trusted current principal and scope even when replaying a receipt.
DO $$DECLARE f regprocedure;BEGIN
 FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='physical' AND p.proname IN(
  'power_operating_scope','power_operating_keys','power_operating_command','power_operating_envelope','save_power_operating_facility',
  'power_operating_context','power_operating_visible','read_power_operating_facility','list_power_operating_facilities','power_operating_facility_request_status') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION physical.save_power_operating_facility(uuid,uuid,integer,jsonb),
 physical.read_power_operating_facility(uuid,uuid,integer,uuid,timestamptz,date),
 physical.list_power_operating_facilities(uuid,uuid,timestamptz,date,text),
 physical.power_operating_facility_request_status(uuid,uuid) TO openetrm_runtime;
COMMIT;
