-- Ordinary point market facts. Publication does not adopt or value a trade.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
SELECT 1 FROM security.epoch WHERE id=true FOR UPDATE;
SELECT pg_advisory_xact_lock(730849102);

DO $$BEGIN
 IF EXISTS(SELECT 1 FROM market_data.observations WHERE starts_with(source_revision_id,'manual_point_revision_v1:'))
 THEN RAISE EXCEPTION 'point_trader_mark_upgrade: unexplained reserved revision namespace';END IF;
END$$;

-- The publisher reuses these immutable observation/domain and publication
-- primitives. Refuse drift in their executable source or privilege boundary.
DO $predecessor$DECLARE item record;p pg_proc;BEGIN
 FOR item IN SELECT * FROM(VALUES('market_data.guard_observation()','1dd679437d1f70c294353ef736220f19',false),
  ('security.record_market_event()','c3aabe403cf035b07207d039ba91461e',true))v(signature,digest,definer) LOOP
  SELECT * INTO STRICT p FROM pg_proc WHERE oid=to_regprocedure(item.signature);
  IF md5(p.prosrc)<>item.digest OR p.prosecdef<>item.definer OR p.provolatile<>'v' OR p.prokind<>'f' OR p.proparallel<>'u'
   OR p.proisstrict OR p.proleakproof OR p.provariadic<>0 OR p.pronargs<>0 OR p.proargmodes IS NOT NULL OR p.proargnames IS NOT NULL
   OR p.prorettype<>'trigger'::regtype OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
   OR p.prolang<>(SELECT oid FROM pg_language WHERE lanname='plpgsql')
   OR item.definer AND pg_get_userbyid(p.proowner)<>'openetrm_security_owner'
   OR NOT item.definer AND p.proowner<>(SELECT relowner FROM pg_class WHERE oid='market_data.observations'::regclass)
   OR(SELECT count(*) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))))<>1
   OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a WHERE a.grantee<>p.proowner OR a.privilege_type<>'EXECUTE')
  THEN RAISE EXCEPTION 'point_trader_mark_upgrade: unexpected helper %',item.signature;END IF;
 END LOOP;
EXCEPTION WHEN no_data_found THEN RAISE EXCEPTION 'point_trader_mark_upgrade: missing observation primitive';END$predecessor$;

CREATE TABLE market_data.point_trader_mark_commands(
 catalog_id uuid NOT NULL,operation_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),
 observation_id uuid NOT NULL,definition_revision_id uuid NOT NULL,reference_catalog_id uuid NOT NULL,reference_revision_id uuid NOT NULL,
 curve_code ref_data.code NOT NULL,contract_id uuid NOT NULL,series_id uuid NOT NULL,source_code ref_data.code NOT NULL,quote_code ref_data.code NOT NULL,
 request jsonb NOT NULL,fact jsonb NOT NULL,outcome jsonb NOT NULL,source_context_id uuid,source_as_of ref_data.instant NOT NULL,authority_until ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,operation_id),
 FOREIGN KEY(catalog_id,observation_id,definition_revision_id) REFERENCES market_data.observations(catalog_id,id,definition_revision_id),
 FOREIGN KEY(catalog_id,definition_revision_id,reference_catalog_id,reference_revision_id) REFERENCES market_data.revisions(catalog_id,id,reference_catalog_id,reference_revision_id),
 FOREIGN KEY(catalog_id,definition_revision_id,curve_code,contract_id) REFERENCES market_data.curve_members(catalog_id,revision_id,curve_code,contract_id),
 FOREIGN KEY(catalog_id,definition_revision_id,series_id) REFERENCES market_data.series(catalog_id,revision_id,id),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,source_code) REFERENCES ref_data.sources(catalog_id,revision_id,code),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,quote_code) REFERENCES ref_data.quote_specifications(catalog_id,revision_id,code),
 FOREIGN KEY(catalog_id,source_context_id) REFERENCES market_data.temporal_contexts(catalog_id,id)
);
CREATE UNIQUE INDEX point_trader_mark_one_changed_receipt ON market_data.point_trader_mark_commands(catalog_id,observation_id)
 WHERE outcome->'changed'='true'::jsonb;
ALTER TABLE market_data.point_trader_mark_commands OWNER TO openetrm_security_owner;
ALTER TABLE market_data.point_trader_mark_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_data.point_trader_mark_commands FORCE ROW LEVEL SECURITY;
CREATE POLICY owner_all ON market_data.point_trader_mark_commands TO openetrm_security_owner USING(true) WITH CHECK(true);
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON market_data.point_trader_mark_commands
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
GRANT INSERT ON market_data.observations TO openetrm_security_owner;

CREATE FUNCTION market_data.point_trader_mark_keys(body jsonb,keys text[]) RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
 IF jsonb_typeof(body) IS DISTINCT FROM 'object' OR(SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(body)k)
  IS DISTINCT FROM(SELECT array_agg(k ORDER BY k) FROM unnest(keys)k) THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
END$$;
CREATE FUNCTION market_data.point_trader_mark_instant(value timestamptz) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT to_char(value AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
$$;
CREATE FUNCTION market_data.point_trader_mark_at(value text) RETURNS timestamptz LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE result timestamptz;BEGIN
 IF value IS NULL OR value!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,6}|[.][0-9]{6}0)?(Z|[+]00:00)$'
 THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 result=value::timestamptz;
 IF result<TIMESTAMPTZ '0001-01-01Z' OR result>=TIMESTAMPTZ '9999-12-31Z' THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 RETURN result;
EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RAISE EXCEPTION 'point_trader_mark_input';END$$;
CREATE FUNCTION market_data.point_trader_mark_number(value text) RETURNS numeric LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
 IF value IS NULL OR length(value)>45 OR value!~'^-?(0|[1-9][0-9]*)([.][0-9]{1,18})?$' OR abs(value::numeric)>=1e24
 THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 RETURN trim_scale(value::numeric);
END$$;
CREATE FUNCTION market_data.point_trader_mark_identity(domain text,fields text[]) RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE field text;payload text='';BEGIN
 FOREACH field IN ARRAY ARRAY[domain]||fields LOOP
  IF field IS NULL THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
  payload=payload||octet_length(convert_to(field,'UTF8'))::text||':'||field;
 END LOOP;
 RETURN domain||':'||encode(sha256(convert_to(payload,'UTF8')),'hex');
END$$;
CREATE FUNCTION market_data.point_trader_mark_token(catalog uuid,target jsonb,revision boolean) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT market_data.point_trader_mark_identity(CASE WHEN revision THEN 'manual_point_revision_v1' ELSE 'manual_point_event_v1' END,
  ARRAY[catalog::text,target->>'definitionRevisionId',target->>'seriesId',target->>'source','trader_mark',target->>'observedAt']||
   CASE WHEN revision THEN ARRAY[target->>'sourceEventId',coalesce(target->>'expectedPreviousObservationId','')] ELSE ARRAY[]::text[] END)
$$;
CREATE FUNCTION market_data.point_trader_mark_body(body jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE target jsonb=body->'target';original jsonb=body->'originalInputs';key text;value text;evidence text;BEGIN
 PERFORM market_data.point_trader_mark_keys(body,ARRAY['policy','target','value','evidence','originalInputs']);
 PERFORM market_data.point_trader_mark_keys(target,ARRAY['definitionRevisionId','referenceCatalogId','referenceRevisionId','curveCode','contractId','seriesId','source','quote','observedAt','sourceEventId','sourceRevisionToken','expectedPreviousObservationId']);
 IF body->'policy' IS DISTINCT FROM '"manual_final_direct_point_trader_mark_v1"'::jsonb
  OR jsonb_typeof(body->'value') IS DISTINCT FROM 'string' OR jsonb_typeof(body->'evidence') IS DISTINCT FROM 'string'
 THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 FOR key,value IN SELECT k,v#>>'{}' FROM jsonb_each(target)e(k,v) LOOP
  IF key='expectedPreviousObservationId' AND target->key='null'::jsonb THEN CONTINUE;END IF;
  IF jsonb_typeof(target->key) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
  IF key IN('definitionRevisionId','referenceCatalogId','referenceRevisionId','contractId','seriesId','expectedPreviousObservationId') THEN
   IF value::uuid='00000000-0000-0000-0000-000000000000'::uuid THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
   target=jsonb_set(target,ARRAY[key],to_jsonb(value::uuid));
  ELSIF key='observedAt' THEN target=jsonb_set(target,ARRAY[key],to_jsonb(market_data.point_trader_mark_instant(market_data.point_trader_mark_at(value))));
  ELSIF key IN('curveCode','source','quote') THEN PERFORM value::ref_data.code;
  ELSIF value='' THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 END LOOP;
 IF original IS DISTINCT FROM 'null'::jsonb THEN
  PERFORM market_data.point_trader_mark_keys(original,ARRAY['snapshotId','fingerprint']);
  IF jsonb_typeof(original->'snapshotId') IS DISTINCT FROM 'string' OR jsonb_typeof(original->'fingerprint') IS DISTINCT FROM 'string'
   OR(original->>'snapshotId')::uuid='00000000-0000-0000-0000-000000000000'::uuid OR(original->>'fingerprint')!~'^[0-9a-f]{64}$'
  THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
  original=jsonb_set(original,'{snapshotId}',to_jsonb((original->>'snapshotId')::uuid));
 END IF;
 evidence=btrim(body->>'evidence',' ');
 IF length(evidence) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 RETURN jsonb_build_object('policy',body->'policy','target',target,'value',market_data.point_trader_mark_number(body->>'value')::text,'evidence',evidence,'originalInputs',original);
EXCEPTION WHEN invalid_text_representation OR check_violation OR numeric_value_out_of_range THEN RAISE EXCEPTION 'point_trader_mark_input';END$$;
CREATE FUNCTION market_data.point_trader_mark_fact(body jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('policy',body->'policy','target',(body->'target')-'curveCode','value',body->'value')
$$;

CREATE FUNCTION security.point_trader_mark_authority(catalog uuid,writing boolean) RETURNS timestamptz LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE candidate timestamptz;deadline timestamptz;permission text;BEGIN
 IF writing IS NULL OR pg_has_role(session_user,'openetrm_risk_worker','MEMBER') THEN RAISE EXCEPTION 'point_trader_mark_denied' USING ERRCODE='42501';END IF;
 FOREACH permission IN ARRAY CASE WHEN writing THEN ARRAY['ReadMarketData','ImportObservations'] ELSE ARRAY['ReadMarketData'] END LOOP
  candidate=security.authority_until(permission);
  IF candidate IS NULL OR NOT isfinite(candidate) OR clock_timestamp()>=candidate THEN RAISE EXCEPTION 'point_trader_mark_denied' USING ERRCODE='42501';END IF;
  deadline=least(deadline,candidate);
 END LOOP;
 IF security.market_access(catalog,'ReadMarketData') IS NOT TRUE OR writing AND security.market_access(catalog,'ImportObservations') IS NOT TRUE
  OR clock_timestamp()>=deadline THEN RAISE EXCEPTION 'point_trader_mark_denied' USING ERRCODE='42501';END IF;
 RETURN deadline;
END$$;
CREATE FUNCTION security.require_point_trader_mark_commit(catalog uuid,definition uuid,reference_catalog uuid,reference_revision uuid,writing boolean,until_at timestamptz)
 RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF until_at IS NULL OR NOT isfinite(until_at) OR clock_timestamp()>=until_at THEN RAISE EXCEPTION 'point_trader_mark_denied' USING ERRCODE='42501';END IF;
 PERFORM security.point_trader_mark_authority(catalog,writing);
 IF num_nonnulls(definition,reference_catalog,reference_revision) NOT IN(0,3) THEN RAISE EXCEPTION 'point_trader_mark_source';END IF;
 IF definition IS NOT NULL THEN
  IF security.reference_access(reference_catalog,'ReadMarketData') IS NOT TRUE OR security.reference_version_visible(reference_catalog,reference_revision) IS NOT TRUE
  THEN RAISE EXCEPTION 'point_trader_mark_denied' USING ERRCODE='42501';END IF;
  IF NOT EXISTS(SELECT 1 FROM market_data.revisions r WHERE(r.catalog_id,r.id,r.reference_catalog_id,r.reference_revision_id)=(catalog,definition,reference_catalog,reference_revision) AND r.state='sealed')
  THEN RAISE EXCEPTION 'point_trader_mark_source';END IF;
 END IF;
 IF clock_timestamp()>=until_at THEN RAISE EXCEPTION 'point_trader_mark_denied' USING ERRCODE='42501';END IF;
END$$;
CREATE FUNCTION market_data.point_trader_mark_known(catalog uuid,definition uuid,observation uuid,context uuid) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM market_data.temporal_contexts t JOIN market_data.market_contexts m ON(m.catalog_id,m.context_id)=(t.catalog_id,t.id)
  JOIN market_data.knowledge_events e ON e.catalog_id=t.catalog_id AND e.revision_id=definition AND e.observation_id IS NOT DISTINCT FROM observation
  JOIN market_data.market_knowledge_receipts k ON(k.catalog_id,k.event_order,k.publication_xid)=(e.catalog_id,e.event_order,e.publication_xid)
  JOIN market_data.revision_periods p ON(p.catalog_id,p.revision_id)=(e.catalog_id,e.revision_id)
  WHERE(t.catalog_id,t.id)=(catalog,context) AND e.event_order<=m.known_through AND k.known_from<=t.known_at
   AND p.effective_from<=t.effective_on AND t.effective_on<p.effective_to)
$$;
CREATE FUNCTION security.require_point_trader_mark_read(catalog uuid,context uuid,as_of timestamptz,definition uuid,reference_catalog uuid,reference_revision uuid,until_at timestamptz)
 RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE q security.request_contexts;BEGIN
 PERFORM security.require_point_trader_mark_commit(catalog,definition,reference_catalog,reference_revision,false,until_at);
 SELECT * INTO STRICT q FROM security.request_contexts c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user;
 IF context IS NULL OR as_of IS NULL OR NOT isfinite(as_of) OR as_of<TIMESTAMPTZ '0001-01-01Z' OR as_of>=TIMESTAMPTZ '9999-12-31Z'
  OR q.market_context_id IS NOT NULL AND(q.market_catalog_id,q.market_context_id) IS DISTINCT FROM(catalog,context)
  OR NOT EXISTS(SELECT 1 FROM market_data.temporal_contexts t JOIN market_data.market_contexts m ON(m.catalog_id,m.context_id)=(t.catalog_id,t.id)
   WHERE(t.catalog_id,t.id)=(catalog,context) AND as_of<=t.known_at)
  OR NOT market_data.point_trader_mark_known(catalog,definition,NULL,context)
 THEN RAISE EXCEPTION 'point_trader_mark_context';END IF;
 PERFORM security.require_point_trader_mark_commit(catalog,definition,reference_catalog,reference_revision,false,until_at);
END$$;
CREATE FUNCTION market_data.require_point_trader_mark_target(catalog uuid,target jsonb) RETURNS void LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE c market_data.curves;s market_data.series;previous market_data.observations;BEGIN
 SELECT * INTO c FROM market_data.curves x WHERE(x.catalog_id,x.revision_id,x.code)=(catalog,(target->>'definitionRevisionId')::uuid,target->>'curveCode');
 SELECT * INTO s FROM market_data.series x WHERE(x.catalog_id,x.revision_id,x.id)=(catalog,(target->>'definitionRevisionId')::uuid,(target->>'seriesId')::uuid);
 IF c.code IS NULL OR s.id IS NULL OR(c.reference_catalog_id,c.reference_revision_id,c.rule,c.direct_role,c.direct_source_code,c.quote_code)
  IS DISTINCT FROM((target->>'referenceCatalogId')::uuid,(target->>'referenceRevisionId')::uuid,'direct','trader_mark',target->>'source',target->>'quote')
  OR(s.reference_catalog_id,s.reference_revision_id,s.contract_id,s.quote_code) IS DISTINCT FROM(c.reference_catalog_id,c.reference_revision_id,(target->>'contractId')::uuid,c.quote_code)
  OR NOT EXISTS(SELECT 1 FROM market_data.curve_members m WHERE(m.catalog_id,m.revision_id,m.curve_code,m.contract_id)=(catalog,c.revision_id,c.code,s.contract_id))
  OR NOT EXISTS(SELECT 1 FROM ref_data.quote_specifications q WHERE(q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code) AND q.kind='outright')
 THEN RAISE EXCEPTION 'point_trader_mark_source';END IF;
 IF target->>'expectedPreviousObservationId' IS NULL THEN
  IF target->>'sourceEventId' IS DISTINCT FROM market_data.point_trader_mark_token(catalog,target,false) THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 ELSE
  SELECT * INTO previous FROM market_data.observations o WHERE(o.catalog_id,o.id)=(catalog,(target->>'expectedPreviousObservationId')::uuid);
  IF previous.id IS NULL OR(previous.definition_revision_id,previous.series_id,previous.reference_catalog_id,previous.reference_revision_id,previous.source_code,previous.source_event_id,previous.role,previous.publication_state,previous.observed_at)
   IS DISTINCT FROM(c.revision_id,s.id,c.reference_catalog_id,c.reference_revision_id,target->>'source',target->>'sourceEventId','trader_mark','final',market_data.point_trader_mark_at(target->>'observedAt'))
  THEN RAISE EXCEPTION 'point_trader_mark_source';END IF;
 END IF;
 IF target->>'sourceRevisionToken' IS DISTINCT FROM market_data.point_trader_mark_token(catalog,target,true) THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
END$$;
CREATE FUNCTION market_data.require_point_trader_mark_source(catalog uuid,body jsonb,context uuid,as_of timestamptz,until_at timestamptz,excluding uuid DEFAULT NULL)
 RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE target jsonb=body->'target';heads integer;streams integer;current_id uuid;count integer;BEGIN
 PERFORM security.require_point_trader_mark_read(catalog,context,as_of,(target->>'definitionRevisionId')::uuid,(target->>'referenceCatalogId')::uuid,(target->>'referenceRevisionId')::uuid,until_at);
 PERFORM market_data.require_point_trader_mark_target(catalog,target);
 IF market_data.point_trader_mark_at(target->>'observedAt') IS DISTINCT FROM as_of THEN RAISE EXCEPTION 'point_trader_mark_context';END IF;
 SELECT count(*),count(DISTINCT o.source_event_id) INTO count,streams FROM market_data.observations o
  WHERE(o.catalog_id,o.definition_revision_id,o.series_id,o.source_code,o.role,o.observed_at)=(catalog,(target->>'definitionRevisionId')::uuid,(target->>'seriesId')::uuid,target->>'source','trader_mark',as_of)
   AND o.id IS DISTINCT FROM excluding;
 IF target->>'expectedPreviousObservationId' IS NULL THEN
  IF count<>0 THEN RAISE EXCEPTION 'point_trader_mark_stale';END IF;
 ELSE
  SELECT count(*),(array_agg(o.id))[1] INTO heads,current_id FROM market_data.observations o
   WHERE(o.catalog_id,o.definition_revision_id,o.series_id,o.source_code,o.role,o.observed_at)=(catalog,(target->>'definitionRevisionId')::uuid,(target->>'seriesId')::uuid,target->>'source','trader_mark',as_of)
    AND o.id IS DISTINCT FROM excluding AND NOT EXISTS(SELECT 1 FROM market_data.observations next WHERE(next.catalog_id,next.corrects_id)=(catalog,o.id) AND next.id IS DISTINCT FROM excluding);
  IF streams<>1 OR heads<>1 OR current_id IS DISTINCT FROM(target->>'expectedPreviousObservationId')::uuid
   OR NOT market_data.point_trader_mark_known(catalog,(target->>'definitionRevisionId')::uuid,current_id,context)
  THEN RAISE EXCEPTION 'point_trader_mark_stale';END IF;
 END IF;
END$$;

CREATE FUNCTION market_data.point_trader_mark_outcome(catalog uuid,operation uuid,observation uuid,changed boolean) RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('operationId',operation,'observationId',o.id,'changed',changed,'definitionRevisionId',o.definition_revision_id,
  'referenceCatalogId',o.reference_catalog_id,'referenceRevisionId',o.reference_revision_id,'contractId',s.contract_id,'seriesId',o.series_id,
  'source',o.source_code,'quote',s.quote_code,'observedAt',market_data.point_trader_mark_instant(o.observed_at),
  'sourceEventId',o.source_event_id,'sourceRevisionId',o.source_revision_id,'previousObservationId',o.corrects_id,'value',trim_scale(o.value)::text,
  'knowledgeEventOrder',e.event_order,'publicationXid',e.publication_xid::text)
 FROM market_data.observations o JOIN market_data.series s ON(s.catalog_id,s.revision_id,s.id)=(o.catalog_id,o.definition_revision_id,o.series_id)
 JOIN market_data.knowledge_events e ON(e.catalog_id,e.observation_id)=(o.catalog_id,o.id) WHERE(o.catalog_id,o.id)=(catalog,observation)
$$;
CREATE FUNCTION security.point_trader_mark_owner(catalog uuid) RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM security.point_trader_mark_authority(catalog,false);
 RETURN presentation.preference_owner(security.presentation_actor(),'point_trader_mark:'||catalog::text);
END$$;
CREATE FUNCTION security.point_trader_mark_status(catalog uuid,operation uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;actor uuid;prior market_data.point_trader_mark_commands;BEGIN
 deadline=security.point_trader_mark_authority(catalog,false);
 SELECT actor_id INTO STRICT actor FROM security.request_contexts c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT * INTO prior FROM market_data.point_trader_mark_commands c WHERE(c.catalog_id,c.operation_id)=(catalog,operation);
 IF prior.operation_id IS NULL THEN
  PERFORM security.require_point_trader_mark_commit(catalog,NULL,NULL,NULL,false,deadline);
  RETURN jsonb_build_object('found',false,'authorityUntil',deadline);
 END IF;
 IF prior.actor_id<>actor THEN RAISE EXCEPTION 'point_trader_mark_conflict';END IF;
 PERFORM security.require_point_trader_mark_commit(catalog,prior.definition_revision_id,prior.reference_catalog_id,prior.reference_revision_id,false,deadline);
 RETURN jsonb_build_object('found',true,'authorityUntil',deadline,'definitionRevisionId',prior.definition_revision_id,
  'referenceCatalogId',prior.reference_catalog_id,'referenceRevisionId',prior.reference_revision_id,'request',prior.request,'outcome',prior.outcome);
END$$;

CREATE FUNCTION security.record_point_trader_mark(catalog uuid,operation uuid,body jsonb,source_context uuid,as_of timestamptz) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;actor uuid;target jsonb;request jsonb;prior market_data.point_trader_mark_commands;
 previous market_data.observations;selected market_data.observations;outcome jsonb;observation uuid;changed boolean=false;BEGIN
 deadline=security.point_trader_mark_authority(catalog,true);body=market_data.point_trader_mark_body(body);target=body->'target';
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR as_of IS DISTINCT FROM market_data.point_trader_mark_at(target->>'observedAt')
 THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 request=jsonb_build_object('body',body,'sourceContextId',source_context,'asOf',market_data.point_trader_mark_instant(as_of));
 SELECT actor_id INTO STRICT actor FROM security.request_contexts c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user;
 PERFORM pg_advisory_xact_lock(730849102);
 SELECT * INTO prior FROM market_data.point_trader_mark_commands c WHERE(c.catalog_id,c.operation_id)=(catalog,operation);
 IF prior.operation_id IS NOT NULL THEN
  IF(prior.actor_id,prior.request) IS DISTINCT FROM(actor,request) THEN RAISE EXCEPTION 'point_trader_mark_conflict';END IF;
  PERFORM security.require_point_trader_mark_commit(catalog,prior.definition_revision_id,prior.reference_catalog_id,prior.reference_revision_id,true,deadline);
  RETURN prior.outcome;
 END IF;
 PERFORM security.require_point_trader_mark_commit(catalog,(target->>'definitionRevisionId')::uuid,(target->>'referenceCatalogId')::uuid,(target->>'referenceRevisionId')::uuid,true,deadline);
 PERFORM market_data.require_point_trader_mark_target(catalog,target);
 -- A prospective revision does not become a business fact or reserve its token
 -- when the explicitly selected genuine predecessor already has that value.
 IF target->>'expectedPreviousObservationId' IS NOT NULL THEN
  SELECT * INTO STRICT previous FROM market_data.observations o WHERE(o.catalog_id,o.id)=(catalog,(target->>'expectedPreviousObservationId')::uuid);
  IF previous.value=(body->>'value')::numeric THEN observation=previous.id;END IF;
 END IF;
 IF observation IS NULL THEN
  -- Only real observations own revision identities. No-op command journals
  -- cannot occupy a prospective token or block a later changed value.
  SELECT * INTO selected FROM market_data.observations o WHERE(o.catalog_id,o.source_code,o.source_event_id,o.source_revision_id)=
   (catalog,target->>'source',target->>'sourceEventId',target->>'sourceRevisionToken');
  IF selected.id IS NOT NULL THEN
   IF(selected.definition_revision_id,selected.series_id,selected.reference_catalog_id,selected.reference_revision_id,selected.observed_at,selected.role,selected.publication_state,selected.corrects_id,selected.value)
    IS DISTINCT FROM((target->>'definitionRevisionId')::uuid,(target->>'seriesId')::uuid,(target->>'referenceCatalogId')::uuid,(target->>'referenceRevisionId')::uuid,as_of,'trader_mark','final',(target->>'expectedPreviousObservationId')::uuid,(body->>'value')::numeric)
   THEN RAISE EXCEPTION 'point_trader_mark_conflict';END IF;
   observation=selected.id;
  END IF;
 END IF;
 IF observation IS NULL THEN
  PERFORM market_data.require_point_trader_mark_source(catalog,body,source_context,as_of,deadline);
  observation=gen_random_uuid();changed=true;
  INSERT INTO market_data.observations(catalog_id,id,definition_revision_id,series_id,reference_catalog_id,reference_revision_id,source_code,
   source_event_id,source_revision_id,role,publication_state,observed_at,received_at,value,corrects_id)
  VALUES(catalog,observation,(target->>'definitionRevisionId')::uuid,(target->>'seriesId')::uuid,(target->>'referenceCatalogId')::uuid,(target->>'referenceRevisionId')::uuid,
   target->>'source',target->>'sourceEventId',target->>'sourceRevisionToken','trader_mark','final',as_of,clock_timestamp(),(body->>'value')::numeric,(target->>'expectedPreviousObservationId')::uuid);
 END IF;
 outcome=market_data.point_trader_mark_outcome(catalog,operation,observation,changed);
 INSERT INTO market_data.point_trader_mark_commands(catalog_id,operation_id,actor_id,observation_id,definition_revision_id,reference_catalog_id,reference_revision_id,
  curve_code,contract_id,series_id,source_code,quote_code,request,fact,outcome,source_context_id,source_as_of,authority_until)
 VALUES(catalog,operation,actor,observation,(target->>'definitionRevisionId')::uuid,(target->>'referenceCatalogId')::uuid,(target->>'referenceRevisionId')::uuid,
  target->>'curveCode',(target->>'contractId')::uuid,(target->>'seriesId')::uuid,target->>'source',target->>'quote',request,market_data.point_trader_mark_fact(body),outcome,source_context,as_of,deadline);
 SET CONSTRAINTS market_data.point_trader_mark_receipt,market_data.point_trader_mark_observation IMMEDIATE;
 SET CONSTRAINTS market_data.point_trader_mark_receipt,market_data.point_trader_mark_observation DEFERRED;
 PERFORM security.require_point_trader_mark_commit(catalog,(target->>'definitionRevisionId')::uuid,(target->>'referenceCatalogId')::uuid,(target->>'referenceRevisionId')::uuid,true,deadline);
 RETURN outcome;
EXCEPTION WHEN check_violation THEN RAISE EXCEPTION 'point_trader_mark_input';
 WHEN foreign_key_violation THEN RAISE EXCEPTION 'point_trader_mark_source';
 WHEN unique_violation THEN RAISE EXCEPTION 'point_trader_mark_conflict';END$$;

CREATE FUNCTION market_data.require_point_trader_mark_receipt(catalog uuid,operation uuid) RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
DECLARE c market_data.point_trader_mark_commands;o market_data.observations;previous market_data.observations;e market_data.knowledge_events;
 body jsonb;target jsonb;actor uuid;changed boolean;BEGIN
 SELECT * INTO STRICT c FROM market_data.point_trader_mark_commands x WHERE(x.catalog_id,x.operation_id)=(catalog,operation);
 PERFORM security.require_point_trader_mark_commit(catalog,c.definition_revision_id,c.reference_catalog_id,c.reference_revision_id,true,c.authority_until);
 SELECT actor_id INTO STRICT actor FROM security.request_contexts q WHERE q.backend_pid=pg_backend_pid() AND q.transaction_id=pg_current_xact_id_if_assigned() AND q.runtime_login=session_user;
 body=market_data.point_trader_mark_body(c.request->'body');target=body->'target';
 PERFORM market_data.require_point_trader_mark_target(catalog,target);
 IF c.actor_id<>actor OR c.request IS DISTINCT FROM jsonb_build_object('body',body,'sourceContextId',c.source_context_id,'asOf',market_data.point_trader_mark_instant(c.source_as_of))
  OR c.source_as_of IS DISTINCT FROM market_data.point_trader_mark_at(target->>'observedAt') OR c.fact IS DISTINCT FROM market_data.point_trader_mark_fact(body)
  OR(c.definition_revision_id,c.reference_catalog_id,c.reference_revision_id,c.curve_code,c.contract_id,c.series_id,c.source_code,c.quote_code)
   IS DISTINCT FROM((target->>'definitionRevisionId')::uuid,(target->>'referenceCatalogId')::uuid,(target->>'referenceRevisionId')::uuid,target->>'curveCode',(target->>'contractId')::uuid,(target->>'seriesId')::uuid,target->>'source',target->>'quote')
 THEN RAISE EXCEPTION 'point_trader_mark_receipt';END IF;
 SELECT * INTO STRICT o FROM market_data.observations x WHERE(x.catalog_id,x.id)=(catalog,c.observation_id);
 SELECT * INTO STRICT e FROM market_data.knowledge_events x WHERE(x.catalog_id,x.observation_id)=(catalog,o.id);
 IF(o.definition_revision_id,o.series_id,o.reference_catalog_id,o.reference_revision_id,o.source_code,o.source_event_id,o.role,o.publication_state,o.observed_at,o.value)
  IS DISTINCT FROM(c.definition_revision_id,c.series_id,c.reference_catalog_id,c.reference_revision_id,c.source_code,target->>'sourceEventId','trader_mark','final',c.source_as_of,(body->>'value')::numeric)
  OR c.outcome->'changed' NOT IN('true'::jsonb,'false'::jsonb) OR c.outcome->'changed' IS NULL
 THEN RAISE EXCEPTION 'point_trader_mark_receipt';END IF;
 changed=(c.outcome->>'changed')::boolean;
 IF c.outcome IS DISTINCT FROM market_data.point_trader_mark_outcome(catalog,operation,o.id,changed) THEN RAISE EXCEPTION 'point_trader_mark_receipt';END IF;
 IF NOT changed THEN
  IF NOT(o.source_revision_id=target->>'sourceRevisionToken' AND o.corrects_id IS NOT DISTINCT FROM(target->>'expectedPreviousObservationId')::uuid
   OR o.id IS NOT DISTINCT FROM(target->>'expectedPreviousObservationId')::uuid)
  THEN RAISE EXCEPTION 'point_trader_mark_receipt';END IF;
  RETURN;
 END IF;
 IF o.source_revision_id IS DISTINCT FROM target->>'sourceRevisionToken' OR o.corrects_id IS DISTINCT FROM(target->>'expectedPreviousObservationId')::uuid
  OR e.publication_xid<>pg_current_xact_id() OR o.received_at<transaction_timestamp() OR o.received_at>clock_timestamp()
 THEN RAISE EXCEPTION 'point_trader_mark_receipt';END IF;
 IF o.corrects_id IS NOT NULL THEN
  SELECT * INTO STRICT previous FROM market_data.observations p WHERE(p.catalog_id,p.id)=(catalog,o.corrects_id);
  IF previous.value=o.value OR NOT EXISTS(SELECT 1 FROM market_data.knowledge_events p WHERE(p.catalog_id,p.observation_id)=(catalog,previous.id) AND p.event_order<e.event_order)
  THEN RAISE EXCEPTION 'point_trader_mark_receipt';END IF;
 END IF;
 PERFORM market_data.require_point_trader_mark_source(catalog,body,c.source_context_id,c.source_as_of,c.authority_until,o.id);
END$$;
CREATE FUNCTION market_data.guard_point_trader_mark_receipt() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN PERFORM market_data.require_point_trader_mark_receipt(NEW.catalog_id,NEW.operation_id);RETURN NEW;END$$;
CREATE CONSTRAINT TRIGGER point_trader_mark_receipt AFTER INSERT ON market_data.point_trader_mark_commands DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_point_trader_mark_receipt();
CREATE FUNCTION market_data.guard_point_trader_mark_observation() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE operation uuid;BEGIN
 IF NOT starts_with(NEW.source_revision_id,'manual_point_revision_v1:') THEN RETURN NEW;END IF;
 SELECT c.operation_id INTO operation FROM market_data.point_trader_mark_commands c WHERE(c.catalog_id,c.observation_id)=(NEW.catalog_id,NEW.id) AND c.outcome->'changed'='true'::jsonb;
 IF operation IS NULL THEN RAISE EXCEPTION 'point_trader_mark_receipt';END IF;
 PERFORM market_data.require_point_trader_mark_receipt(NEW.catalog_id,operation);RETURN NEW;
END$$;
CREATE CONSTRAINT TRIGGER point_trader_mark_observation AFTER INSERT ON market_data.observations DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_point_trader_mark_observation();
-- Kept outside the producer's eager named validation: recheck the original
-- source and original authority through final admission, excluding only self.
CREATE CONSTRAINT TRIGGER point_trader_mark_deadline AFTER INSERT ON market_data.point_trader_mark_commands DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_point_trader_mark_receipt();

CREATE FUNCTION security.point_trader_mark_setup(catalog uuid,context uuid,as_of timestamptz,definition uuid,reference_catalog uuid,reference_revision uuid,filters jsonb)
 RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE deadline timestamptz;import_until timestamptz;candidate record;previous market_data.observations;target jsonb;comparison jsonb;
 choices jsonb='[]';unavailable jsonb='[]';reason text;label text;seen integer=0;skip_count integer;page_limit integer;has_more boolean=false;
 point_count integer;streams integer;heads integer;head uuid;quote_filter jsonb=filters->'quoteFilter';search text;BEGIN
 -- Even the optional publication flag keeps its original absence. Setup itself
 -- is a read and never acquires observation-import authority by waiting.
 import_until=security.authority_until('ImportObservations');deadline=security.point_trader_mark_authority(catalog,false);
 PERFORM market_data.point_trader_mark_keys(filters,ARRAY['curveCode','contractId','search','offset','limit','quoteFilter','eligibility']);
 IF filters->'curveCode' IS DISTINCT FROM 'null'::jsonb AND jsonb_typeof(filters->'curveCode') IS DISTINCT FROM 'string'
  OR filters->'contractId' IS DISTINCT FROM 'null'::jsonb AND jsonb_typeof(filters->'contractId') IS DISTINCT FROM 'string'
  OR filters->'search' IS DISTINCT FROM 'null'::jsonb AND jsonb_typeof(filters->'search') IS DISTINCT FROM 'string'
  OR jsonb_typeof(filters->'offset') IS DISTINCT FROM 'number' OR(filters->>'offset')!~'^(0|[1-9][0-9]*)$'
  OR jsonb_typeof(filters->'limit') IS DISTINCT FROM 'number' OR(filters->>'limit')!~'^[1-9][0-9]*$'
  OR filters->'eligibility' NOT IN('null'::jsonb,'"live_at_value_time_v1"'::jsonb)
 THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 skip_count=(filters->>'offset')::integer;page_limit=(filters->>'limit')::integer;search=coalesce(filters->>'search','');
 IF skip_count>100000 OR page_limit>100 OR length(search)>256 THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 IF filters->>'curveCode' IS NOT NULL THEN PERFORM(filters->>'curveCode')::ref_data.code;END IF;
 IF filters->>'contractId' IS NOT NULL AND(filters->>'contractId')::uuid='00000000-0000-0000-0000-000000000000'::uuid THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 IF quote_filter IS DISTINCT FROM 'null'::jsonb THEN
  PERFORM market_data.point_trader_mark_keys(quote_filter,ARRAY['quantityCode','currencyCode','multiplier']);
  IF jsonb_typeof(quote_filter->'quantityCode') IS DISTINCT FROM 'string' OR jsonb_typeof(quote_filter->'currencyCode') IS DISTINCT FROM 'string'
   OR jsonb_typeof(quote_filter->'multiplier') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
  PERFORM(quote_filter->>'quantityCode')::ref_data.code;PERFORM(quote_filter->>'currencyCode')::ref_data.code;
  IF market_data.point_trader_mark_number(quote_filter->>'multiplier')<=0 THEN RAISE EXCEPTION 'point_trader_mark_input';END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 PERFORM security.require_point_trader_mark_read(catalog,context,as_of,definition,reference_catalog,reference_revision,deadline);
 FOR candidate IN SELECT c.code,c.name,c.direct_source_code,s.id series_id,s.contract_id,s.quote_code,k.delivery_from,k.delivery_to,k.expiry_at,
   u.symbol||' · quote multiplier '||trim_scale(q.multiplier)::text value_unit,money.display_code currency,
   c.name||' · '||k.delivery_from::text||' → '||k.delivery_to::text||' · '||c.direct_source_code base_label
  FROM market_data.curves c JOIN market_data.curve_members m ON(m.catalog_id,m.revision_id,m.curve_code)=(c.catalog_id,c.revision_id,c.code)
  JOIN market_data.series s ON(s.catalog_id,s.revision_id,s.contract_id,s.quote_code)=(c.catalog_id,c.revision_id,m.contract_id,c.quote_code)
  JOIN market_data.contracts k ON(k.catalog_id,k.revision_id,k.id)=(s.catalog_id,s.revision_id,s.contract_id)
  JOIN ref_data.quote_specifications q ON(q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code)
  JOIN ref_data.quantity_specifications quantity ON(quantity.catalog_id,quantity.revision_id,quantity.code)=(q.catalog_id,q.revision_id,q.quantity_code)
  JOIN ref_data.units u ON(u.catalog_id,u.revision_id,u.code)=(quantity.catalog_id,quantity.revision_id,quantity.unit_code)
  JOIN ref_data.currencies money ON(money.catalog_id,money.revision_id,money.code)=(q.catalog_id,q.revision_id,q.currency_code)
  WHERE(c.catalog_id,c.revision_id,c.reference_catalog_id,c.reference_revision_id)=(catalog,definition,reference_catalog,reference_revision)
   AND c.rule='direct' AND c.direct_role='trader_mark' AND q.kind='outright'
   AND(filters->>'curveCode' IS NULL OR c.code=filters->>'curveCode') AND(filters->>'contractId' IS NULL OR k.id=(filters->>'contractId')::uuid)
   AND(quote_filter='null'::jsonb OR(q.quantity_code,q.currency_code,q.multiplier)=(quote_filter->>'quantityCode',quote_filter->>'currencyCode',market_data.point_trader_mark_number(quote_filter->>'multiplier')))
   AND strpos(lower(c.name||' '||c.code||' '||k.delivery_from::text||' '||k.delivery_to::text||' '||c.direct_source_code),lower(search))>0
  ORDER BY c.code,m.ordinal,k.id,s.id OFFSET skip_count LIMIT page_limit+1 LOOP
  seen=seen+1;IF seen>page_limit THEN has_more=true;EXIT;END IF;
  reason=NULL;comparison=NULL;previous=NULL;head=NULL;
  label=candidate.base_label||CASE WHEN candidate.expiry_at<=as_of THEN ' · expired at value time' ELSE '' END;
  IF filters->>'eligibility'='live_at_value_time_v1' AND candidate.expiry_at<=as_of THEN reason='source_expired';END IF;
  SELECT count(*),count(DISTINCT o.source_event_id) INTO point_count,streams FROM market_data.observations o
   WHERE(o.catalog_id,o.definition_revision_id,o.series_id,o.source_code,o.role,o.observed_at)=(catalog,definition,candidate.series_id,candidate.direct_source_code,'trader_mark',as_of);
  IF point_count>0 THEN
   SELECT count(*),(array_agg(o.id))[1] INTO heads,head FROM market_data.observations o
    WHERE(o.catalog_id,o.definition_revision_id,o.series_id,o.source_code,o.role,o.observed_at)=(catalog,definition,candidate.series_id,candidate.direct_source_code,'trader_mark',as_of)
     AND NOT EXISTS(SELECT 1 FROM market_data.observations next WHERE(next.catalog_id,next.corrects_id)=(catalog,o.id));
   IF streams<>1 OR heads<>1 THEN reason=coalesce(reason,'ambiguous_point');
   ELSE
    SELECT * INTO STRICT previous FROM market_data.observations o WHERE(o.catalog_id,o.id)=(catalog,head);
    IF previous.publication_state<>'final' THEN reason=coalesce(reason,'final_predecessor_required');
    ELSIF NOT market_data.point_trader_mark_known(catalog,definition,previous.id,context) THEN reason=coalesce(reason,'point_source_stale');END IF;
   END IF;
  END IF;
  IF reason IS NOT NULL THEN unavailable=unavailable||jsonb_build_array(jsonb_build_object('label',label,'reason',reason));CONTINUE;END IF;
  target=jsonb_build_object('definitionRevisionId',definition,'referenceCatalogId',reference_catalog,'referenceRevisionId',reference_revision,
   'curveCode',candidate.code,'contractId',candidate.contract_id,'seriesId',candidate.series_id,'source',candidate.direct_source_code,'quote',candidate.quote_code,
   'observedAt',market_data.point_trader_mark_instant(as_of),'expectedPreviousObservationId',previous.id,'sourceEventId',previous.source_event_id);
  IF previous.id IS NULL THEN target=jsonb_set(target,'{sourceEventId}',to_jsonb(market_data.point_trader_mark_token(catalog,target,false)));
  ELSE comparison=jsonb_build_object('observationId',previous.id,'value',trim_scale(previous.value)::text,'sourceRevisionId',previous.source_revision_id);END IF;
  target=target||jsonb_build_object('sourceRevisionToken',market_data.point_trader_mark_token(catalog,target,true));
  choices=choices||jsonb_build_array(jsonb_build_object('label',label,'target',target,'valueUnit',candidate.value_unit,'currency',candidate.currency,'previous',comparison));
 END LOOP;
 PERFORM security.require_point_trader_mark_read(catalog,context,as_of,definition,reference_catalog,reference_revision,deadline);
 RETURN jsonb_build_object('contextId',context,'asOf',market_data.point_trader_mark_instant(as_of),
  'effectiveOn',(SELECT effective_on FROM market_data.temporal_contexts WHERE(catalog_id,id)=(catalog,context)),
  'knownAt',(SELECT known_at FROM market_data.temporal_contexts WHERE(catalog_id,id)=(catalog,context)),
  'source',jsonb_build_object('definitionRevisionId',definition,'referenceCatalogId',reference_catalog,'referenceRevisionId',reference_revision),
  'authorityUntil',deadline,'choices',choices,'unavailable',unavailable,
  'canPublish',import_until IS NOT NULL AND isfinite(import_until) AND clock_timestamp()<import_until AND security.has_permission('ImportObservations'),
  'page',jsonb_build_object('offset',skip_count,'limit',page_limit,'hasMore',has_more,'search',search));
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation THEN RAISE EXCEPTION 'point_trader_mark_input';END$$;

DO $$DECLARE signature regprocedure;BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'market_data.point_trader_mark_keys(jsonb,text[])'::regprocedure,
  'market_data.point_trader_mark_instant(timestamptz)'::regprocedure,
  'market_data.point_trader_mark_at(text)'::regprocedure,
  'market_data.point_trader_mark_number(text)'::regprocedure,
  'market_data.point_trader_mark_identity(text,text[])'::regprocedure,
  'market_data.point_trader_mark_token(uuid,jsonb,boolean)'::regprocedure,
  'market_data.point_trader_mark_body(jsonb)'::regprocedure,
  'market_data.point_trader_mark_fact(jsonb)'::regprocedure,
  'security.point_trader_mark_authority(uuid,boolean)'::regprocedure,
  'security.require_point_trader_mark_commit(uuid,uuid,uuid,uuid,boolean,timestamptz)'::regprocedure,
  'market_data.point_trader_mark_known(uuid,uuid,uuid,uuid)'::regprocedure,
  'security.require_point_trader_mark_read(uuid,uuid,timestamptz,uuid,uuid,uuid,timestamptz)'::regprocedure,
  'market_data.require_point_trader_mark_target(uuid,jsonb)'::regprocedure,
  'market_data.require_point_trader_mark_source(uuid,jsonb,uuid,timestamptz,timestamptz,uuid)'::regprocedure,
  'market_data.point_trader_mark_outcome(uuid,uuid,uuid,boolean)'::regprocedure,
  'security.point_trader_mark_owner(uuid)'::regprocedure,
  'security.point_trader_mark_status(uuid,uuid)'::regprocedure,
  'security.record_point_trader_mark(uuid,uuid,jsonb,uuid,timestamptz)'::regprocedure,
  'market_data.require_point_trader_mark_receipt(uuid,uuid)'::regprocedure,
  'market_data.guard_point_trader_mark_receipt()'::regprocedure,
  'market_data.guard_point_trader_mark_observation()'::regprocedure,
  'security.point_trader_mark_setup(uuid,uuid,timestamptz,uuid,uuid,uuid,jsonb)'::regprocedure] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,openetrm_runtime,openetrm_risk_worker',signature);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION security.point_trader_mark_authority(uuid,boolean),
 security.require_point_trader_mark_commit(uuid,uuid,uuid,uuid,boolean,timestamptz),
 security.require_point_trader_mark_read(uuid,uuid,timestamptz,uuid,uuid,uuid,timestamptz),
 security.point_trader_mark_owner(uuid),security.point_trader_mark_status(uuid,uuid),
 security.point_trader_mark_setup(uuid,uuid,timestamptz,uuid,uuid,uuid,jsonb),
 security.record_point_trader_mark(uuid,uuid,jsonb,uuid,timestamptz) TO openetrm_runtime;
COMMIT;
