-- Unrelated scopes retain their own time laws; source-visible Transport
-- agreements still require the supported current-clock financial context.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(730849102);

DO $upgrade$DECLARE expected jsonb;p pg_proc;actual_acl jsonb;expected_acl jsonb;BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($contracts$
[{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"hash":"b27321f1042d99e302ed18367ae4808acdddae8d64dc1e6e11b0fe8bb8f2ec4c","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.gas_transport_financial_projection_fence(uuid,uuid,timestamp with time zone,timestamp with time zone,uuid[],uuid[])","volatility":"v"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"hash":"96978e79a232e0e46c13d1439aeda4c3a70d7593a32ce197cbb22f5e6db03864","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.require_gas_transport_financial_presence(uuid,uuid,timestamp with time zone,uuid[],uuid[],timestamp with time zone)","volatility":"v"},{"acl":["openetrm_risk_worker=X/openetrm_security_owner","openetrm_runtime=X/openetrm_security_owner","openetrm_security_owner=X/openetrm_security_owner"],"hash":"98d0f44629e0ab6d4fe068265f942a932eea82ed9d810f6e3578d71d1c92aeac","owner":"openetrm_security_owner","config":["search_path=pg_catalog"],"strict":false,"definer":true,"parallel":"u","leakproof":false,"signature":"security.require_gas_transport_financial_scope(uuid,uuid,timestamp with time zone,uuid[],uuid[])","volatility":"v"}]
$contracts$::jsonb) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(expected->>'signature');
  SELECT jsonb_agg(x::text ORDER BY x::text) INTO actual_acl FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x;
  SELECT jsonb_agg(value ORDER BY value) INTO expected_acl FROM(SELECT replace(value,'@migration_owner',quote_ident(current_user))::aclitem::text value FROM jsonb_array_elements_text(expected->'acl')) a;
  IF p.oid IS NULL OR encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex') IS DISTINCT FROM expected->>'hash' OR
   pg_get_userbyid(p.proowner) IS DISTINCT FROM(CASE expected->>'owner' WHEN '@migration_owner' THEN current_user ELSE expected->>'owner' END) OR p.prosecdef IS DISTINCT FROM(expected->>'definer')::boolean OR
   p.provolatile IS DISTINCT FROM(expected->>'volatility')::"char" OR p.proisstrict IS DISTINCT FROM(expected->>'strict')::boolean OR
   p.proleakproof IS DISTINCT FROM(expected->>'leakproof')::boolean OR p.proparallel IS DISTINCT FROM(expected->>'parallel')::"char" OR
   coalesce(to_jsonb(p.proconfig),'null'::jsonb) IS DISTINCT FROM expected->'config' OR actual_acl IS DISTINCT FROM expected_acl
  THEN RAISE EXCEPTION 'transport_financial_presence_upgrade: unexpected helper %',expected->>'signature';END IF;
 END LOOP;
END$upgrade$;

CREATE OR REPLACE FUNCTION security.require_gas_transport_financial_presence(catalog uuid,context uuid,as_of timestamptz,books uuid[],trades uuid[],until_at timestamptz) RETURNS void
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM trading.gas_transport_financial_selectors(books,trades);
 PERFORM security.gas_transport_financial_authority(catalog,NULL);
 PERFORM settlement_data.require_futures_margin_preview(catalog,until_at);
 PERFORM security.require_trading_history(catalog,context);
 PERFORM security.require_gas_park_loan_worker_scope(catalog,context,as_of,books,coalesce(trades,ARRAY[]::uuid[]),NULL);
 IF NOT security.trading_context_day_matches(catalog,context,as_of) OR NOT EXISTS(SELECT 1 FROM market_data.temporal_contexts t
  JOIN trading.contexts x ON(x.catalog_id,x.context_id)=(t.catalog_id,t.id) JOIN market_data.market_contexts m ON(m.catalog_id,m.context_id)=(t.catalog_id,t.id)
  WHERE(t.catalog_id,t.id)=(catalog,context) AND(t.known_at>=as_of OR NOT EXISTS(
   SELECT 1 FROM trading.gas_transport_financial_trades a WHERE a.catalog_id=catalog AND a.book_id=ANY(books)
    AND(coalesce(cardinality(trades),0)=0 OR a.trade_id=ANY(trades))
    AND trading.gas_owned_visible(catalog,a.publication_order,a.effective_at,context,as_of))))
 THEN RAISE EXCEPTION 'gas_transport_financial_context';END IF;
 IF until_at IS NULL OR clock_timestamp()>=until_at THEN RAISE EXCEPTION 'gas_transport_financial_denied' USING ERRCODE='42501';END IF;
END$$;
COMMIT;
