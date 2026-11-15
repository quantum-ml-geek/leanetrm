-- Publication compares executable payment coordinates with the dates admitted
-- from the original native terms. Content hashes alone do not prove agreement.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

-- Pin the complete helper contracts this upgrade consumes, including authority.
DO $calendar_upgrade$DECLARE expected jsonb;helper pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($calendar_helpers$
[{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":false,"parallel":"u","leakproof":false,"signature":"security.ppa_side_document(uuid,uuid)","definition":"235a3771bfffb28867ce6359813361a17cf456fa3e31784c1c028eb23cb109b7","volatility":"s"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog","jit=off"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.publish_admitted_side_schedules(uuid,uuid,uuid)","definition":"23ef3157e856d5ec6c5318df6db83f88ff6acb15acf38fa82525425e66b42fca","volatility":"v"}
,{"acl":["openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.publish_side_schedules(uuid,uuid,uuid)","definition":"ced26bf2313d275760cfad69ee70536563edc8b262c0ce6a5ebd9739ac642ab7","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.side_payment_date(jsonb,date,date,jsonb)","definition":"f892ff3657c180dffd957e875feb3d90b924afc7acbf82331877fe4ff893c67e","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.staged_economic_side(uuid,uuid,integer)","definition":"d03028c519f675fa5b8b60df30f6c39c5722e63aa1b3ef1a0babda8ebf26d02c","volatility":"v"}
,{"acl":["openetrm_security_owner=X/openetrm_security_owner"],"owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.swap_payment_date(uuid,uuid,date,date,jsonb)","definition":"d2f5a79c979acd5354fc5940fbc66717986744cbcdc36ac5737b135ad2092546","volatility":"v"}]
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




-- Reproduce only the exact payment-rule wire contract from admitted typed terms.
CREATE FUNCTION security.side_payment_provenance(catalog uuid,side uuid,rule_id uuid,starts date,ends date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE rule trading.swap_payment_rules;binding trading.side_calendar_bindings;calendar ref_data.calendars;
 calendar_identity jsonb;business_dates jsonb;rule_identity jsonb;anchor date;spec jsonb;
BEGIN
 IF rule_id IS NULL THEN RETURN jsonb_build_object('paymentRule','explicit_payment_date_v1','unadjustedPayment','none');END IF;
 SELECT * INTO STRICT rule FROM trading.swap_payment_rules WHERE(catalog_id,id)=(catalog,rule_id);
 SELECT * INTO STRICT binding FROM trading.side_calendar_bindings WHERE(catalog_id,side_id,purpose)=(catalog,side,'Payment');
 IF NOT binding.applicable OR(rule.reference_catalog_id,rule.reference_revision_id) IS DISTINCT FROM(binding.reference_catalog_id,binding.reference_revision_id)
  OR rule.calendar_code IS NOT NULL AND rule.calendar_code<>binding.calendar_code THEN RAISE EXCEPTION 'side_schedule_payment_provenance';END IF;
 SELECT * INTO STRICT calendar FROM ref_data.calendars WHERE(catalog_id,revision_id,code)=(binding.reference_catalog_id,binding.reference_revision_id,binding.calendar_code);
 IF rule.calendar_code IS NOT NULL THEN
  SELECT coalesce(jsonb_agg(day::date ORDER BY day),'[]'::jsonb) INTO business_dates
   FROM generate_series(calendar.coverage_from::timestamp,calendar.coverage_to::timestamp-INTERVAL '1 day',INTERVAL '1 day') d(day)
   LEFT JOIN ref_data.calendar_days e ON(e.catalog_id,e.revision_id,e.calendar_code,e.business_date)=
    (calendar.catalog_id,calendar.revision_id,calendar.code,day::date)
   WHERE coalesce(e.is_business_day,(calendar.weekend_mask&(1<<(extract(isodow FROM day)::integer-1)))=0);
  calendar_identity=jsonb_build_array('payment_calendar',
   jsonb_build_array('reference',jsonb_build_array('reference_revision',calendar.catalog_id,calendar.revision_id),calendar.code),
   jsonb_build_array('date_set',calendar.coverage_from,calendar.coverage_to,business_dates));
 END IF;
 rule_identity=jsonb_build_array('payment_rule',rule.implementation,1,
  CASE rule.rule WHEN 'days_after_period_end' THEN 1 WHEN 'day_of_following_month' THEN 2 END,rule.days,rule.day_of_month,
  CASE rule.day_basis WHEN 'calendar_days' THEN 1 WHEN 'business_days' THEN 2 END,
  CASE rule.short_month WHEN 'reject' THEN 1 WHEN 'clamp' THEN 2 END,
  CASE rule.adjustment WHEN 'following' THEN 1 WHEN 'preceding' THEN 2 WHEN 'modified_following' THEN 3 WHEN 'unadjusted' THEN 4 WHEN 'modified_preceding' THEN 5 END,calendar_identity);
 spec=jsonb_build_object('frequency',rule.frequency,'rule',rule.rule,'days',rule.days,'dayOfMonth',rule.day_of_month,
  'dayBasis',rule.day_basis,'shortMonth',rule.short_month,'adjustment','unadjusted',
  'calendar',CASE WHEN rule.day_basis='business_days' THEN rule.calendar_code END,'implementation',rule.implementation);
 anchor=security.swap_payment_date(calendar.catalog_id,calendar.revision_id,starts,ends,spec);
 RETURN jsonb_build_object('paymentRule',rule_identity,'unadjustedPayment',anchor);
END$$;
ALTER FUNCTION security.side_payment_provenance(uuid,uuid,uuid,date,date) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.side_payment_provenance(uuid,uuid,uuid,date,date) FROM PUBLIC;

CREATE FUNCTION trading.require_side_payment_dates(catalog uuid,schedule uuid,expected jsonb) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF jsonb_typeof(expected) IS DISTINCT FROM 'array' OR jsonb_array_length(expected)=0 THEN
  RAISE EXCEPTION 'side_schedule_payment_date';END IF;
 IF EXISTS(
  SELECT 1 FROM trading.side_schedule_rows r
  LEFT JOIN trading.side_schedule_grids g ON(g.catalog_id,g.schedule_id,g.ordinal)=(r.catalog_id,r.schedule_id,r.grid_ordinal)
  LEFT JOIN jsonb_to_recordset(expected) AS e(ordinal integer,"deliveryFrom" date,"deliveryTo" date,"paymentAt" timestamptz)
   ON CASE WHEN r.grid_ordinal IS NULL THEN (r.payment_ordinal,r.delivery_from,r.delivery_to)=(e.ordinal,e."deliveryFrom",e."deliveryTo")
    ELSE g.month=e."deliveryFrom" AND(e."deliveryFrom"+INTERVAL '1 month')::date=e."deliveryTo" END
  WHERE(r.catalog_id,r.schedule_id)=(catalog,schedule) AND r.operation IN('discount','output_guard')
   AND(e.ordinal IS NULL OR r.value_at IS DISTINCT FROM e."paymentAt")
 ) OR EXISTS(
  SELECT 1 FROM jsonb_to_recordset(expected) AS e(ordinal integer,"deliveryFrom" date,"deliveryTo" date,"paymentAt" timestamptz)
  WHERE NOT EXISTS(SELECT 1 FROM trading.side_schedule_rows r
   LEFT JOIN trading.side_schedule_grids g ON(g.catalog_id,g.schedule_id,g.ordinal)=(r.catalog_id,r.schedule_id,r.grid_ordinal)
   WHERE(r.catalog_id,r.schedule_id,r.operation)=(catalog,schedule,'output_guard') AND
    CASE WHEN r.grid_ordinal IS NULL THEN(r.payment_ordinal,r.delivery_from,r.delivery_to)=(e.ordinal,e."deliveryFrom",e."deliveryTo")
     ELSE g.month=e."deliveryFrom" END)
 ) THEN RAISE EXCEPTION 'side_schedule_payment_date';END IF;
 IF EXISTS(SELECT 1 FROM trading.side_schedule_rows r
  LEFT JOIN trading.side_schedule_grids g ON(g.catalog_id,g.schedule_id,g.ordinal)=(r.catalog_id,r.schedule_id,r.grid_ordinal)
  LEFT JOIN jsonb_to_recordset(expected) AS e(ordinal integer,"deliveryFrom" date,"paymentRule" jsonb,"unadjustedPayment" text)
   ON CASE WHEN r.grid_ordinal IS NULL THEN r.payment_ordinal=e.ordinal ELSE g.month=e."deliveryFrom" END
  WHERE(r.catalog_id,r.schedule_id,r.operation)=(catalog,schedule,'output_guard') AND
   (e."paymentRule" IS NULL OR CASE WHEN r.parameters->>'paymentRule'='explicit_payment_date_v1'
     THEN to_jsonb('explicit_payment_date_v1'::text) ELSE(r.parameters->>'paymentRule')::jsonb END IS DISTINCT FROM e."paymentRule"
    OR r.parameters->>'unadjustedPayment' IS DISTINCT FROM e."unadjustedPayment"))
 THEN RAISE EXCEPTION 'side_schedule_payment_provenance';END IF;
END$$;
ALTER FUNCTION trading.require_side_payment_dates(uuid,uuid,jsonb) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION trading.require_side_payment_dates(uuid,uuid,jsonb) FROM PUBLIC;

CREATE FUNCTION security.require_staged_payment_dates(catalog uuid,operation uuid,instrument uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE item record;expected jsonb;native_side trading.ppa_sides;document jsonb;selected_canonical uuid;
BEGIN
 FOR item IN SELECT i.slot,i.schedule_id FROM trading.side_schedule_request_items i
  WHERE(i.catalog_id,i.request_id)=(catalog,operation) ORDER BY i.slot LOOP
  selected_canonical=security.staged_economic_side(catalog,operation,item.slot);
  IF EXISTS(SELECT 1 FROM trading.swap_instruments i WHERE(i.catalog_id,i.instrument_id)=(catalog,instrument)) THEN
   SELECT jsonb_agg(jsonb_build_object('ordinal',p.ordinal,'deliveryFrom',p.starts,'deliveryTo',p.ends,'paymentAt',p.payment)||security.side_payment_provenance(catalog,p.canonical,p.rule,p.starts,p.ends) ORDER BY p.ordinal)
    INTO expected FROM(
    SELECT 0 ordinal,s.delivery_from starts,s.delivery_to ends,s.payment_at payment,s.id canonical,s.payment_rule_id rule
     FROM trading.swap_instruments i JOIN trading.swap_fixed_sides s ON(s.catalog_id,s.id)=(i.catalog_id,i.fixed_side_id)
     WHERE(i.catalog_id,i.instrument_id)=(catalog,instrument) AND item.slot=0
    UNION ALL SELECT 0,s.delivery_from,s.delivery_to,s.payment_at,s.id,s.payment_rule_id
     FROM trading.swap_instruments i JOIN trading.swap_floating_sides s
      ON(s.catalog_id,s.id)=(i.catalog_id,CASE item.slot WHEN 0 THEN i.first_floating_side_id WHEN 1 THEN i.floating_side_id END)
     WHERE(i.catalog_id,i.instrument_id)=(catalog,instrument)
    UNION ALL SELECT p.ordinal,p.delivery_from,p.delivery_to,p.payment_at,p.side_id,p.payment_rule_id
     FROM trading.swap_instruments i JOIN trading.swap_side_periods p
      ON(p.catalog_id,p.side_id)=(i.catalog_id,CASE item.slot WHEN 0 THEN i.scheduled_first_id WHEN 1 THEN i.scheduled_second_id END)
     WHERE(i.catalog_id,i.instrument_id)=(catalog,instrument)
   ) p WHERE p.canonical=selected_canonical;
   PERFORM trading.require_side_payment_dates(catalog,item.schedule_id,expected);
  ELSIF EXISTS(SELECT 1 FROM trading.ppa_instruments i WHERE(i.catalog_id,i.instrument_id)=(catalog,instrument)) THEN
   SELECT s.* INTO STRICT native_side FROM trading.ppa_memberships m JOIN trading.ppa_sides s ON(s.catalog_id,s.id)=(m.catalog_id,m.side_id)
    WHERE(m.catalog_id,m.instrument_id,m.position)=(catalog,instrument,item.slot);
   IF native_side.canonical_side_id IS DISTINCT FROM selected_canonical THEN RAISE EXCEPTION 'side_schedule_definition';END IF;
   document=security.ppa_side_document(catalog,native_side.id);
   SELECT jsonb_agg(jsonb_build_object('ordinal',n-1,'deliveryFrom',month::date,'deliveryTo',(month+INTERVAL '1 month')::date,
    'paymentAt',security.side_payment_date(document->'calendarPolicy',month::date,(month+INTERVAL '1 month')::date,document->'paymentRule')::timestamp AT TIME ZONE 'UTC')||security.side_payment_provenance(catalog,selected_canonical,native_side.payment_rule_id,month::date,(month+INTERVAL '1 month')::date)||jsonb_build_object('unadjustedPayment','none') ORDER BY n)
    INTO expected FROM generate_series(native_side.delivery_from::timestamp,native_side.delivery_to::timestamp-INTERVAL '1 month',INTERVAL '1 month') WITH ORDINALITY m(month,n);
   PERFORM trading.require_side_payment_dates(catalog,item.schedule_id,expected);
  END IF;
 END LOOP;
END$$;
ALTER FUNCTION security.require_staged_payment_dates(uuid,uuid,uuid) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.require_staged_payment_dates(uuid,uuid,uuid) FROM PUBLIC;

DO $$DECLARE source text;marker text=' PERFORM security.publish_admitted_side_schedules(catalog,operation,instrument);';BEGIN
 source=pg_get_functiondef('security.publish_side_schedules(uuid,uuid,uuid)'::regprocedure);
 IF strpos(source,marker)=0 THEN RAISE EXCEPTION 'side_schedule_payment_upgrade';END IF;
 EXECUTE replace(source,marker,' PERFORM security.require_staged_payment_dates(catalog,operation,instrument);'||E'\n'||marker);
END$$;
COMMIT;
