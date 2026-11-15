-- Exact calendar ownership is retained with each Side. Existing Side identities
-- and executable bytes are not rewritten or supplied with inferred bindings.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["@migration_owner=X/@migration_owner"],"owner":"@migration_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"market_data.guard_knowledge_receipt()","definition":"a376e86bfb72c2f4fd49e1659c29ae0df0503c2f98c7b096a92fb11cbac5122d","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)","definition":"5fa6f967fe2b50ce087218c8da0cf92d1dc71ab008945bdcef1dc0ef0965d726","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.market_access(uuid,text)","definition":"804fc62e6057b1b2d528e3493d761aa52d613a766a9087c90fcd6313b5832383","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.reference_access(uuid,text)","definition":"697d1e75ddba8a9a7fbdfa948951d3c6760e445f6f681ba307c1c937568c0828","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","plan_cache_mode=force_generic_plan"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.reference_version_visible(uuid,uuid)","definition":"1618ae8b3f399f0489e6cee8b496228ab327e17333526c6bea9ba61c3f0486bc","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.request_market_cut()","definition":"69192885dee01df92e831c46fe1d24a816146e7306cb1d69187d834a524a7e56","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.require_side_schedule_read(uuid,uuid,uuid,uuid,timestamp with time zone)","definition":"132b5860c6641016f7c506bb49fd66e21260a1920dc78688b575b53bec6bb284","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","enable_nestloop=off","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.seal_side_schedule(uuid,uuid,uuid,text)","definition":"9bc017eef4e83c057f21d949ad24a9300a6a905cad08b59591727901399fb9e9","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_schedule_visible(uuid,uuid)","definition":"612bc9056c528377aefab89fbef92d305d61c3ebb5ebd14bfb8a8be65a33f194","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.trading_access(uuid,text)","definition":"422b9a2343e622a55ea85cdc707c17762b3be087228d5a653a895875639bb5cb","volatility":"v"}
,{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.visible_side_schedules()","definition":"9a084689dda8d90e1030ff42874d002d4a1d87f790cc812eb4888101c01d08a5","volatility":"v"}]
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






CREATE TABLE trading.side_calendar_bindings (
 catalog_id uuid NOT NULL,
 side_id uuid NOT NULL,
 purpose text NOT NULL CHECK(purpose IN('Delivery','Observation','Payment')),
 policy_version text NOT NULL CHECK(policy_version='side_calendar_policy_v1'),
 applicable boolean NOT NULL,
 reference_catalog_id uuid,
 reference_revision_id uuid,
 calendar_code ref_data.code,
 definition_digest bytea,
 payment_timing text,
 source_catalog_id uuid,
 source_event_order integer,
 PRIMARY KEY(catalog_id,side_id,purpose),
 FOREIGN KEY(catalog_id,side_id) REFERENCES trading.sides(catalog_id,id),
 FOREIGN KEY(reference_catalog_id,reference_revision_id,calendar_code)
  REFERENCES ref_data.calendars(catalog_id,revision_id,code) MATCH FULL,
 FOREIGN KEY(source_catalog_id,source_event_order)
  REFERENCES market_data.market_knowledge_receipts(catalog_id,event_order) MATCH FULL,
 CHECK((applicable AND reference_catalog_id IS NOT NULL AND reference_revision_id IS NOT NULL
   AND calendar_code IS NOT NULL AND definition_digest IS NOT NULL AND octet_length(definition_digest)=32
   AND source_catalog_id IS NOT NULL AND source_event_order IS NOT NULL)
  OR(NOT applicable AND reference_catalog_id IS NULL AND reference_revision_id IS NULL
   AND calendar_code IS NULL AND definition_digest IS NULL AND source_catalog_id IS NULL AND source_event_order IS NULL)),
 CHECK(CASE WHEN purpose='Payment' AND applicable THEN payment_timing IS NOT DISTINCT FROM 'utc_payment_day_v1'
  ELSE payment_timing IS NULL END)
);
ALTER TABLE trading.side_calendar_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading.side_calendar_bindings FORCE ROW LEVEL SECURITY;
GRANT SELECT,INSERT ON trading.side_calendar_bindings TO openetrm_security_owner;
GRANT SELECT ON trading.side_calendar_bindings TO openetrm_runtime,openetrm_risk_worker;
CREATE POLICY internal_content ON trading.side_calendar_bindings TO openetrm_security_owner USING(true) WITH CHECK(true);
CREATE POLICY scoped_read ON trading.side_calendar_bindings FOR SELECT TO openetrm_runtime,openetrm_risk_worker USING(true);
CREATE FUNCTION security.side_calendar_visible(catalog uuid,canonical_side uuid) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.trading_access(catalog,'ReadTrades') AND
  (NOT pg_has_role(session_user,'openetrm_risk_worker','MEMBER') OR risk.worker_read()) AND
  EXISTS(SELECT 1 FROM trading.side_schedules h WHERE(h.catalog_id,h.side_id)=(catalog,canonical_side)
  AND security.side_schedule_visible(h.catalog_id,h.id));
$$;
ALTER FUNCTION security.side_calendar_visible(uuid,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.side_calendar_visible(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.side_calendar_visible(uuid,uuid) TO openetrm_runtime,openetrm_risk_worker;
CREATE POLICY temporal_read ON trading.side_calendar_bindings AS RESTRICTIVE FOR SELECT TO openetrm_runtime,openetrm_risk_worker
 USING(security.side_calendar_visible(catalog_id,side_id));
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.side_calendar_bindings
 FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();

CREATE FUNCTION security.side_calendar_cutoff(context_catalog uuid,context uuid) RETURNS timestamptz
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT CASE WHEN context IS NOT NULL THEN
  (SELECT t.known_at FROM market_data.temporal_contexts t WHERE(t.catalog_id,t.id)=(context_catalog,context)
   AND security.market_access(t.catalog_id,'ReadMarketData'))
 ELSE coalesce((SELECT c.known_at FROM security.request_market_cut() c),statement_timestamp()) END;
$$;

-- Publication establishes availability, not the pricing bundle's applicability
-- interval. Only this exact calendar reader uses this narrower source contract.
-- New capture selects the earliest qualified receipt, with a complete stable
-- tie-break. A supplied proof is verified exactly and is never substituted.
CREATE FUNCTION security.resolve_side_calendar(catalog uuid,revision uuid,calendar_name text,pinned jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE source record;proof jsonb;document jsonb;cutoff timestamptz=security.side_calendar_cutoff(NULL,NULL);
BEGIN
 IF NOT security.reference_access(catalog,'ReadMarketData')
  OR(pg_has_role(session_user,'openetrm_risk_worker','MEMBER') AND NOT risk.worker_read())
  OR NOT EXISTS(SELECT 1 FROM ref_data.revisions r WHERE(r.catalog_id,r.id,r.state)=(catalog,revision,'sealed'))
 THEN RAISE EXCEPTION 'calendar_reference';END IF;
 SELECT e.catalog_id,e.event_order,k.known_from INTO source FROM market_data.revisions r
 JOIN market_data.knowledge_events e ON(e.catalog_id,e.revision_id)=(r.catalog_id,r.id) AND e.observation_id IS NULL
 JOIN market_data.market_knowledge_receipts k ON(k.catalog_id,k.event_order,k.publication_xid)=(e.catalog_id,e.event_order,e.publication_xid)
 WHERE(r.reference_catalog_id,r.reference_revision_id,r.state)=(catalog,revision,'sealed')
  AND k.known_from<=cutoff AND security.market_access(r.catalog_id,'ReadMarketData')
  AND(pinned IS NULL OR(e.catalog_id,e.event_order)=((pinned->>'CatalogId')::uuid,(pinned->>'EventOrder')::integer))
 ORDER BY k.known_from,e.catalog_id,e.event_order LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'calendar_reference';END IF;
 proof=jsonb_build_object('contract','calendar_publication_proof_v1','CatalogId',source.catalog_id,'EventOrder',source.event_order,
  'KnownFrom',to_char(source.known_from AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')||'0+00:00');
 IF pinned IS NOT NULL AND pinned IS DISTINCT FROM proof THEN RAISE EXCEPTION 'calendar_reference';END IF;
 SELECT jsonb_build_object('coverageFrom',c.coverage_from,'coverageTo',c.coverage_to,'weekendMask',c.weekend_mask,
  'exceptions',coalesce((SELECT jsonb_agg(jsonb_build_object('date',d.business_date,'open',d.is_business_day) ORDER BY d.business_date)
   FROM ref_data.calendar_days d WHERE(d.catalog_id,d.revision_id,d.calendar_code)=(catalog,revision,calendar_name)),'[]'::jsonb),
  'publication',proof,'reference',jsonb_build_object('catalogId',catalog,'revisionId',revision,'code',calendar_name)) INTO document
 FROM ref_data.calendars c WHERE(c.catalog_id,c.revision_id,c.code)=(catalog,revision,calendar_name);
 IF NOT FOUND THEN RAISE EXCEPTION 'calendar_reference';END IF;
 IF(document->>'coverageTo')::date-(document->>'coverageFrom')::date>36600 OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(document->'exceptions') d
   WHERE(d->>'date')::date<(document->>'coverageFrom')::date OR(d->>'date')::date>=(document->>'coverageTo')::date)
 THEN RAISE EXCEPTION 'calendar_definition';END IF;
 IF NOT security.reference_access(catalog,'ReadMarketData') OR NOT security.market_access(source.catalog_id,'ReadMarketData')
  OR(pg_has_role(session_user,'openetrm_risk_worker','MEMBER') AND NOT risk.worker_read())
 THEN RAISE EXCEPTION 'calendar_reference';END IF;
 RETURN document;
END$$;
CREATE FUNCTION security.read_side_calendar(catalog uuid,revision uuid,calendar_name text) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.resolve_side_calendar(catalog,revision,calendar_name,NULL);
$$;

-- Only the fixed, versioned calendar encoding is reproduced here. No general
-- financial canonicalizer or schedule generator is implemented in the database.
CREATE FUNCTION trading.captured_calendar_identity(document jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE exceptions text;
BEGIN
 SELECT coalesce(string_agg(format('{"contract":"calendar_exception_v1","Date":"%s","Open":%s}',
  d->>'date',d->>'open'),',' ORDER BY d->>'date'),'') INTO exceptions FROM jsonb_array_elements(document->'exceptions') d;
 RETURN format('{"contract":"captured_calendar_definition_v1","Exceptions":[%s],"From":"%s","Key":["reference",["reference_revision","%s","%s"],%s],"To":"%s","WeekendMask":%s}',
  exceptions,document->>'coverageFrom',document->'reference'->>'catalogId',document->'reference'->>'revisionId',
  (document->'reference'->'code')::text,document->>'coverageTo',document->>'weekendMask');
END$$;

CREATE FUNCTION trading.request_side_calendar_policy(command jsonb,slot_number integer) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE selected jsonb;
BEGIN
 IF command->>'schema'='scheduled_financial_swap_booking_v1' THEN
  IF jsonb_typeof(command->'body') IS DISTINCT FROM 'object' OR NOT command ?& ARRAY['schema','body','valuation','booking']
   OR command-ARRAY['schema','body','valuation','booking']<>'{}'::jsonb THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
  command=command->'body';
 END IF;
 IF (CASE WHEN jsonb_typeof(command->'terms'->'memberships')='array' THEN 1 ELSE 0 END
  +CASE WHEN jsonb_typeof(command->'physicalSides')='array' THEN 1 ELSE 0 END
  +CASE WHEN jsonb_typeof(command->'scheduled')='object' THEN 1 ELSE 0 END
  +CASE WHEN jsonb_typeof(command->'deliveryCalendarPolicy')='object' THEN 1 ELSE 0 END
  +CASE WHEN jsonb_typeof(command->'fixed')='object' OR jsonb_typeof(command->'firstFloating')='object'
    OR jsonb_typeof(command->'floating')='object' THEN 1 ELSE 0 END)<>1
  OR(jsonb_typeof(command->'fixed')='object' AND jsonb_typeof(command->'firstFloating')='object')
 THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
 IF jsonb_typeof(command->'terms'->'memberships')='array' THEN
  selected=command->'terms'->'memberships'->slot_number->'side'->'calendarPolicy';
 ELSIF jsonb_typeof(command->'physicalSides')='array' THEN
  IF slot_number<jsonb_array_length(command->'physicalSides') THEN
   selected=command->'physicalSides'->slot_number->'calendarPolicy';
  ELSE selected=command->'cashSides'->(slot_number-jsonb_array_length(command->'physicalSides'))->'calendarPolicy';END IF;
 ELSIF jsonb_typeof(command->'scheduled')='object' THEN
  selected=command->'scheduled'->(CASE slot_number WHEN 0 THEN 'first' WHEN 1 THEN 'second' END)->'calendarPolicy';
 ELSIF jsonb_typeof(command->'deliveryCalendarPolicy')='object' THEN
  selected=command->(CASE slot_number WHEN 0 THEN 'deliveryCalendarPolicy' WHEN 1 THEN 'considerationCalendarPolicy' WHEN 2 THEN 'feeCalendarPolicy' END);
 ELSE
  selected=CASE slot_number WHEN 0 THEN coalesce(nullif(command->'firstFloating','null'::jsonb),command->'fixed')->'calendarPolicy'
   WHEN 1 THEN command->'floating'->'calendarPolicy' END;
 END IF;
 IF jsonb_typeof(selected) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
 RETURN selected;
END$$;

CREATE FUNCTION trading.require_side_calendar_schedule(catalog uuid,schedule uuid) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE selected_side uuid;
BEGIN
 SELECT side_id INTO STRICT selected_side FROM trading.side_schedules WHERE(catalog_id,id)=(catalog,schedule);
 IF(SELECT count(*) FROM trading.side_calendar_bindings WHERE(catalog_id,side_id)=(catalog,selected_side))<>3
 THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
 IF EXISTS(SELECT 1 FROM trading.side_calendar_bindings b
  JOIN ref_data.calendars c ON(c.catalog_id,c.revision_id,c.code)=(b.reference_catalog_id,b.reference_revision_id,b.calendar_code)
  JOIN trading.side_schedule_rows r ON(r.catalog_id,r.schedule_id)=(catalog,schedule)
  WHERE(b.catalog_id,b.side_id)=(catalog,selected_side) AND b.applicable AND CASE b.purpose
   WHEN 'Delivery' THEN r.delivery_from<c.coverage_from OR r.delivery_to>c.coverage_to
   WHEN 'Observation' THEN r.observation_from<c.coverage_from OR r.observation_to>c.coverage_to
   WHEN 'Payment' THEN r.operation IN('discount','output_guard') AND
    ((r.value_at AT TIME ZONE 'UTC')::date<c.coverage_from OR(r.value_at AT TIME ZONE 'UTC')::date>=c.coverage_to)
   END)
 THEN RAISE EXCEPTION 'calendar_coverage';END IF;
 IF EXISTS(SELECT 1 FROM trading.side_calendar_bindings b
  JOIN ref_data.calendars c ON(c.catalog_id,c.revision_id,c.code)=(b.reference_catalog_id,b.reference_revision_id,b.calendar_code)
  JOIN trading.side_schedule_grids g ON(g.catalog_id,g.schedule_id)=(catalog,schedule)
  CROSS JOIN LATERAL unnest(g.operating_days) day_number
  WHERE(b.catalog_id,b.side_id)=(catalog,selected_side) AND b.applicable AND b.purpose IN('Delivery','Observation')
   AND(DATE '0001-01-01'+day_number<c.coverage_from OR DATE '0001-01-01'+day_number>=c.coverage_to))
 THEN RAISE EXCEPTION 'calendar_coverage';END IF;
END$$;

CREATE FUNCTION trading.retain_side_calendar_policy(catalog uuid,schedule uuid,command jsonb,slot_number integer) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE side uuid;policy jsonb;requested jsonb;selected_purpose text;binding jsonb;selected jsonb;captured text;family text;identity jsonb;linked boolean;
 binding_applicable boolean;ref_catalog uuid;ref_revision uuid;code text;digest bytea;timing text;expected jsonb;document jsonb;
 source_catalog uuid;source_event integer;
BEGIN
 SELECT h.side_id,s.economic_identity::jsonb->'CalendarPolicy',s.family,s.economic_identity::jsonb INTO side,policy,family,identity FROM trading.side_schedules h
 JOIN trading.sides s ON(s.catalog_id,s.id)=(h.catalog_id,h.side_id) WHERE(h.catalog_id,h.id)=(catalog,schedule);
 IF jsonb_typeof(policy) IS DISTINCT FROM 'object' OR policy->>'contract' IS DISTINCT FROM 'side_calendar_policy_v1'
  OR policy-ARRAY['contract','Delivery','Observation','Payment','PaymentTiming']<>'{}'::jsonb
  OR NOT(policy ?& ARRAY['Delivery','Observation','Payment','PaymentTiming'])
 THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
 linked=coalesce(identity->'IntervalDefinition'->'Quantity'->>'contract'='ppa_slot_quantity_v1',false);
 IF policy->'Delivery'->'Applicable' IS DISTINCT FROM to_jsonb(NOT linked)
  OR policy->'Observation'->'Applicable' IS DISTINCT FROM to_jsonb(family='floating')
  OR policy->'Payment'->'Applicable' IS DISTINCT FROM to_jsonb(family NOT IN('gas','crude','lng'))
 THEN RAISE EXCEPTION 'side_calendar_applicability';END IF;
 requested=trading.request_side_calendar_policy(command,slot_number);
 IF requested->>'implementation' IS DISTINCT FROM 'side_calendar_policy_v1'
  OR requested-ARRAY['implementation','delivery','observation','payment']<>'{}'::jsonb
 THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
 FOREACH selected_purpose IN ARRAY ARRAY['Delivery','Observation','Payment'] LOOP
  binding=policy->selected_purpose;selected=requested->lower(selected_purpose);
  IF jsonb_typeof(binding) IS DISTINCT FROM 'object' OR binding->>'contract' IS DISTINCT FROM 'side_calendar_binding_v1'
   OR jsonb_typeof(binding->'Applicable') IS DISTINCT FROM 'boolean'
   OR binding-ARRAY['contract','Applicable','Calendar','DefinitionDigest','Publication']<>'{}'::jsonb
   OR NOT(binding ?& ARRAY['Calendar','DefinitionDigest','Publication'])
   OR jsonb_typeof(selected) IS DISTINCT FROM 'object' OR selected-ARRAY['applicable','calendar']<>'{}'::jsonb
   OR jsonb_typeof(selected->'applicable') IS DISTINCT FROM 'boolean' OR NOT(selected ? 'calendar')
  THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
  binding_applicable=(binding->>'Applicable')::boolean;
  ref_catalog=NULL;ref_revision=NULL;code=NULL;digest=NULL;timing=NULL;source_catalog=NULL;source_event=NULL;
  IF binding_applicable THEN
   IF jsonb_typeof(binding->'Calendar') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
   ref_catalog=(binding->'Calendar'->'Key'->1->>1)::uuid;
   ref_revision=(binding->'Calendar'->'Key'->1->>2)::uuid;
   code=binding->'Calendar'->'Key'->>2;
   IF ref_catalog IS NULL OR ref_revision IS NULL OR code IS NULL THEN RAISE EXCEPTION 'calendar_reference';END IF;
   IF jsonb_typeof(binding->'Publication') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'calendar_reference';END IF;
   document=security.resolve_side_calendar(ref_catalog,ref_revision,code,binding->'Publication');
   source_catalog=(document->'publication'->>'CatalogId')::uuid;source_event=(document->'publication'->>'EventOrder')::integer;
   captured=trading.captured_calendar_identity(document);
   digest=sha256(convert_to(captured,'UTF8'));
   IF binding->'Calendar' IS DISTINCT FROM captured::jsonb OR binding->>'DefinitionDigest' IS DISTINCT FROM encode(digest,'hex')
   THEN RAISE EXCEPTION 'calendar_definition_mismatch';END IF;
   expected=jsonb_build_object('applicable',true,'calendar',jsonb_build_object('revision',jsonb_build_object('catalogId',ref_catalog,'revisionId',ref_revision),'code',code));
   IF selected_purpose='Payment' THEN timing='utc_payment_day_v1';END IF;
  ELSE
   IF binding->'Calendar' IS DISTINCT FROM 'null'::jsonb OR binding->'DefinitionDigest' IS DISTINCT FROM 'null'::jsonb OR binding->'Publication' IS DISTINCT FROM 'null'::jsonb
   THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
   expected=jsonb_build_object('applicable',false,'calendar',NULL);
  END IF;
  IF selected IS DISTINCT FROM expected THEN RAISE EXCEPTION 'side_calendar_conflict';END IF;
  IF selected_purpose='Payment' AND policy->'PaymentTiming' IS DISTINCT FROM coalesce(to_jsonb(timing),'null'::jsonb)
  THEN RAISE EXCEPTION 'side_calendar_policy';END IF;
  INSERT INTO trading.side_calendar_bindings VALUES(catalog,side,selected_purpose,'side_calendar_policy_v1',binding_applicable,ref_catalog,ref_revision,code,digest,timing,source_catalog,source_event)
   ON CONFLICT DO NOTHING;
  IF NOT EXISTS(SELECT 1 FROM trading.side_calendar_bindings b WHERE(b.catalog_id,b.side_id,b.purpose)=(catalog,side,selected_purpose)
   AND(b.policy_version,b.applicable,b.reference_catalog_id,b.reference_revision_id,b.calendar_code,b.definition_digest,b.payment_timing,b.source_catalog_id,b.source_event_order)
    IS NOT DISTINCT FROM('side_calendar_policy_v1',binding_applicable,ref_catalog,ref_revision,code,digest,timing,source_catalog,source_event))
  THEN RAISE EXCEPTION 'side_calendar_conflict';END IF;
  IF binding_applicable AND NOT EXISTS(SELECT 1 FROM trading.side_schedule_authorities a
   WHERE(a.catalog_id,a.schedule_id,a.kind,a.authority_catalog_id)=(catalog,schedule,'reference',ref_catalog)) THEN
   INSERT INTO trading.side_schedule_authorities VALUES(catalog,schedule,'reference',ref_catalog,NULL,ref_catalog);
  END IF;
  IF binding_applicable AND NOT EXISTS(SELECT 1 FROM trading.side_schedule_authorities a
   WHERE(a.catalog_id,a.schedule_id,a.kind,a.authority_catalog_id)=(catalog,schedule,'market',source_catalog)) THEN
   INSERT INTO trading.side_schedule_authorities VALUES(catalog,schedule,'market',source_catalog,source_catalog,NULL);
  END IF;
 END LOOP;
END$$;
ALTER FUNCTION trading.captured_calendar_identity(jsonb) OWNER TO openetrm_security_owner;
ALTER FUNCTION security.side_calendar_cutoff(uuid,uuid) OWNER TO openetrm_security_owner;
ALTER FUNCTION security.resolve_side_calendar(uuid,uuid,text,jsonb) OWNER TO openetrm_security_owner;
ALTER FUNCTION security.read_side_calendar(uuid,uuid,text) OWNER TO openetrm_security_owner;
ALTER FUNCTION trading.request_side_calendar_policy(jsonb,integer) OWNER TO openetrm_security_owner;
ALTER FUNCTION trading.retain_side_calendar_policy(uuid,uuid,jsonb,integer) OWNER TO openetrm_security_owner;
ALTER FUNCTION trading.require_side_calendar_schedule(uuid,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.side_calendar_cutoff(uuid,uuid),security.resolve_side_calendar(uuid,uuid,text,jsonb),security.read_side_calendar(uuid,uuid,text),
 trading.captured_calendar_identity(jsonb),trading.request_side_calendar_policy(jsonb,integer),
 trading.retain_side_calendar_policy(uuid,uuid,jsonb,integer),trading.require_side_calendar_schedule(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.read_side_calendar(uuid,uuid,text) TO openetrm_runtime,openetrm_risk_worker;

CREATE FUNCTION security.side_calendar_proofs_visible(catalog uuid,schedule uuid,context uuid) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT NOT EXISTS(SELECT 1 FROM trading.side_schedules h JOIN trading.side_calendar_bindings b
  ON(b.catalog_id,b.side_id)=(h.catalog_id,h.side_id)
  WHERE(h.catalog_id,h.id)=(catalog,schedule) AND b.applicable AND NOT EXISTS(
   SELECT 1 FROM market_data.knowledge_events e
   JOIN market_data.market_knowledge_receipts k ON(k.catalog_id,k.event_order,k.publication_xid)=(e.catalog_id,e.event_order,e.publication_xid)
   JOIN market_data.revisions r ON(r.catalog_id,r.id)=(e.catalog_id,e.revision_id)
   JOIN ref_data.revisions rr ON(rr.catalog_id,rr.id)=(r.reference_catalog_id,r.reference_revision_id)
   WHERE(e.catalog_id,e.event_order)=(b.source_catalog_id,b.source_event_order) AND e.observation_id IS NULL
    AND(r.reference_catalog_id,r.reference_revision_id,r.state,rr.state)=(b.reference_catalog_id,b.reference_revision_id,'sealed','sealed')
    AND k.known_from<=security.side_calendar_cutoff(catalog,context)
    AND security.reference_access(b.reference_catalog_id,'ReadMarketData') AND security.market_access(b.source_catalog_id,'ReadMarketData')));
$$;
ALTER FUNCTION security.side_calendar_proofs_visible(uuid,uuid,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.side_calendar_proofs_visible(uuid,uuid,uuid) FROM PUBLIC;

DO $$DECLARE body text;marker text=' RETURN found_schedule;';BEGIN
 body=pg_get_functiondef('security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)'::regprocedure);
 IF (length(body)-length(replace(body,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'side_calendar_predecessor';END IF;
 EXECUTE replace(body,marker,E' PERFORM trading.retain_side_calendar_policy(catalog,found_schedule,command,slot_number);\n'||marker);
END$$;
DO $$DECLARE body text;marker text=' SELECT * INTO STRICT h FROM trading.side_schedules WHERE(catalog_id,id)=(catalog,schedule) FOR UPDATE;';BEGIN
 body=pg_get_functiondef('security.seal_side_schedule(uuid,uuid,uuid,text)'::regprocedure);
 IF (length(body)-length(replace(body,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'side_calendar_seal_predecessor';END IF;
 EXECUTE replace(body,marker,marker||E'\n PERFORM trading.require_side_calendar_schedule(catalog,schedule);');
END$$;
DO $$DECLARE body text;marker text='AND security.reference_version_visible(s.reference_catalog_id,s.reference_revision_id)';BEGIN
 body=pg_get_functiondef('security.side_schedule_visible(uuid,uuid)'::regprocedure);
 IF (length(body)-length(replace(body,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'side_calendar_visibility_predecessor';END IF;
 EXECUTE replace(body,marker,marker||E'\n   AND security.side_calendar_proofs_visible(catalog,schedule,NULL)');
END$$;
DO $$DECLARE body text;marker text='AND EXISTS(SELECT 1 FROM revs r WHERE(r.catalog,r.revision)=(s.reference_catalog_id,s.reference_revision_id))';BEGIN
 body=pg_get_functiondef('security.visible_side_schedules()'::regprocedure);
 IF (length(body)-length(replace(body,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'side_calendar_set_visibility_predecessor';END IF;
 EXECUTE replace(body,marker,marker||E'\n   AND security.side_calendar_proofs_visible(p.catalog_id,p.schedule_id,NULL)');
END$$;
DO $$DECLARE body text;marker text='IF allowed IS NOT TRUE OR NOT security.reference_access(reference_catalog,''ReadMarketData'')';BEGIN
 body=pg_get_functiondef('security.require_side_schedule_read(uuid,uuid,uuid,uuid,timestamptz)'::regprocedure);
 IF (length(body)-length(replace(body,marker,'')))/length(marker)<>1 THEN RAISE EXCEPTION 'side_calendar_read_predecessor';END IF;
 EXECUTE replace(body,marker,marker||E'\n  OR NOT security.side_calendar_proofs_visible(catalog,schedule,context)');
END$$;
COMMIT;
