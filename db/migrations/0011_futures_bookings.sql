-- Immutable synthetic fixed-lot futures bookings. No daily/final settlement or PV.
BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM market_data.temporal_contexts) THEN
  RAISE EXCEPTION 'Existing temporal contexts require a verified trading-prefix migration';
 END IF;
END $$;
INSERT INTO security.permissions VALUES('ReadTrades');
INSERT INTO security.role_permissions SELECT id,'ReadTrades' FROM security.roles WHERE code IN('trader','risk_analyst');
CREATE SCHEMA trading;
CREATE TABLE trading.publications (
 catalog_id uuid NOT NULL REFERENCES market_data.catalogs(id),publication_order integer NOT NULL CHECK(publication_order>0),publication_xid xid8 NOT NULL,
 PRIMARY KEY(catalog_id,publication_order),UNIQUE(catalog_id,publication_order,publication_xid)
);
CREATE TABLE trading.knowledge_receipts (
 catalog_id uuid NOT NULL,publication_order integer NOT NULL,publication_xid xid8 NOT NULL,known_from ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,publication_order),FOREIGN KEY(catalog_id,publication_order,publication_xid) REFERENCES trading.publications(catalog_id,publication_order,publication_xid)
);
CREATE TABLE trading.contexts (
 catalog_id uuid NOT NULL,context_id uuid NOT NULL,known_through integer NOT NULL CHECK(known_through>=0),
 PRIMARY KEY(catalog_id,context_id),FOREIGN KEY(catalog_id,context_id) REFERENCES market_data.market_contexts(catalog_id,context_id)
);
CREATE TABLE trading.portfolios (
 catalog_id uuid NOT NULL,id uuid NOT NULL,name text NOT NULL CHECK(btrim(name)<>'' AND length(name)<=80),
 publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.books (
 catalog_id uuid NOT NULL,id uuid NOT NULL,portfolio_id uuid NOT NULL,name text NOT NULL CHECK(btrim(name)<>'' AND length(name)<=80),
 publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),FOREIGN KEY(catalog_id,portfolio_id) REFERENCES trading.portfolios(catalog_id,id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.futures_sides (
 catalog_id uuid NOT NULL,id uuid NOT NULL,definition_revision_id uuid NOT NULL,curve_code ref_data.code NOT NULL,contract_id uuid NOT NULL,
 implementation text NOT NULL CHECK(implementation='fixed_total_cash_execution_pnl_v1'),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),UNIQUE(catalog_id,definition_revision_id,curve_code,contract_id,implementation),
 FOREIGN KEY(catalog_id,definition_revision_id,curve_code,contract_id) REFERENCES market_data.curve_members(catalog_id,revision_id,curve_code,contract_id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.instruments (
 catalog_id uuid NOT NULL,id uuid NOT NULL,publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.instrument_sides (
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,side_id uuid NOT NULL,coefficient ref_data.exact_number NOT NULL CHECK(coefficient=1),
 publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,instrument_id),UNIQUE(catalog_id,side_id),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.instruments(catalog_id,id),FOREIGN KEY(catalog_id,side_id) REFERENCES trading.futures_sides(catalog_id,id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.trades (
 catalog_id uuid NOT NULL,id uuid NOT NULL,book_id uuid NOT NULL,operation_id uuid NOT NULL,actor_id uuid NOT NULL REFERENCES security.principals(id),
 request jsonb NOT NULL,publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,id),UNIQUE(catalog_id,operation_id),FOREIGN KEY(catalog_id,book_id) REFERENCES trading.books(catalog_id,id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
CREATE TABLE trading.trade_instruments (
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,binding_id uuid NOT NULL,instrument_id uuid NOT NULL,
 lots ref_data.exact_number NOT NULL CHECK(lots<>0 AND lots=trunc(lots) AND abs(lots)<=100000),execution_price ref_data.exact_number NOT NULL,
 settlement_state text NOT NULL CHECK(settlement_state='unprocessed'),publication_order integer NOT NULL,effective_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,trade_id,binding_id),FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.trades(catalog_id,id),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.instruments(catalog_id,id),
 FOREIGN KEY(catalog_id,publication_order) REFERENCES trading.publications(catalog_id,publication_order)
);
ALTER TABLE market_data.knowledge_clocks ADD COLUMN trading_certified_head integer NOT NULL DEFAULT 0 CHECK(trading_certified_head>=0);
ALTER TABLE security.request_contexts ADD COLUMN trading_as_of ref_data.instant;

CREATE FUNCTION security.trading_access(catalog uuid,permission text) RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.has_permission(permission) AND security.market_access(catalog,'ReadMarketData');
$$;
CREATE FUNCTION security.use_trading_context(catalog uuid,as_of timestamptz) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'No trading access' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM security.request_contexts c JOIN market_data.temporal_contexts t ON(t.catalog_id,t.id)=(c.market_catalog_id,c.market_context_id)
  JOIN trading.contexts x ON(x.catalog_id,x.context_id)=(t.catalog_id,t.id)
  WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user
  AND t.catalog_id=catalog AND t.effective_on=(as_of AT TIME ZONE 'UTC')::date AND c.trading_as_of IS NULL)
 THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
 UPDATE security.request_contexts SET trading_as_of=as_of WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
END $$;
CREATE FUNCTION security.trading_visible(catalog uuid,ordinal integer,effective_at timestamptz) RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.trading_access(catalog,'ReadTrades') AND EXISTS(
  SELECT 1 FROM security.request_contexts c JOIN market_data.temporal_contexts t ON(t.catalog_id,t.id)=(c.market_catalog_id,c.market_context_id)
  JOIN trading.contexts x ON(x.catalog_id,x.context_id)=(t.catalog_id,t.id)
  JOIN trading.knowledge_receipts k ON k.catalog_id=catalog AND k.publication_order=ordinal
  WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user
  AND t.catalog_id=catalog AND ordinal<=x.known_through AND k.known_from<=t.known_at AND effective_at<=c.trading_as_of);
$$;
CREATE FUNCTION security.trading_context_visible(catalog uuid,context uuid) RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT security.trading_access(catalog,'ReadTrades') AND EXISTS(SELECT 1 FROM security.request_contexts c
 WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=pg_current_xact_id_if_assigned() AND c.runtime_login=session_user
 AND(c.market_catalog_id,c.market_context_id)=(catalog,context));
$$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['publications','knowledge_receipts','contexts','portfolios','books','futures_sides','instruments','instrument_sides','trades','trade_instruments'] LOOP
  EXECUTE format('ALTER TABLE trading.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE trading.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.%I FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt()',t);
  EXECUTE format('GRANT SELECT,INSERT ON trading.%I TO openetrm_security_owner',t);
  EXECUTE format('GRANT SELECT ON trading.%I TO openetrm_runtime',t);
  IF t='contexts' THEN
   EXECUTE format('CREATE POLICY scoped_read ON trading.%I FOR SELECT TO openetrm_runtime USING(security.trading_context_visible(catalog_id,context_id))',t);
  ELSIF t IN('publications','knowledge_receipts') THEN
   EXECUTE format('CREATE POLICY scoped_read ON trading.%I FOR SELECT TO openetrm_runtime USING(security.trading_visible(catalog_id,publication_order,TIMESTAMPTZ ''0001-01-01 00:00:00+00''))',t);
  ELSE
   EXECUTE format('CREATE POLICY scoped_read ON trading.%I FOR SELECT TO openetrm_runtime USING(security.trading_visible(catalog_id,publication_order,effective_at))',t);
  END IF;
 END LOOP;
END $$;
GRANT USAGE ON SCHEMA trading TO openetrm_runtime,openetrm_security_owner;
GRANT SELECT ON ref_data.futures_products,ref_data.futures_series,ref_data.futures_milestones,ref_data.quote_specifications,
 market_data.contracts,market_data.curves,market_data.curve_members,market_data.revision_periods TO openetrm_security_owner;

ALTER FUNCTION security.capture_date_context(uuid,date,timestamptz) RENAME TO capture_market_and_schedule_context;
REVOKE ALL ON FUNCTION security.capture_market_and_schedule_context(uuid,date,timestamptz) FROM openetrm_runtime;
CREATE FUNCTION security.capture_date_context(catalog uuid,effective_date date,requested_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE clock market_data.knowledge_clocks; row record; commit_at timestamptz; last_commit timestamptz; token uuid; cutoff timestamptz; head integer;
BEGIN
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'No current temporal read permission' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF requested_at IS NOT NULL AND EXISTS(SELECT 1 FROM market_data.temporal_contexts t WHERE t.catalog_id=catalog AND t.effective_on=effective_date AND t.known_at=requested_at
  AND NOT EXISTS(SELECT 1 FROM trading.contexts x WHERE(x.catalog_id,x.context_id)=(t.catalog_id,t.id)))
 THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
 SELECT * INTO clock FROM market_data.knowledge_clocks WHERE catalog_id=catalog FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
 SELECT known_from INTO last_commit FROM trading.knowledge_receipts WHERE catalog_id=catalog ORDER BY publication_order DESC LIMIT 1;
 FOR row IN SELECT * FROM trading.publications WHERE catalog_id=catalog AND publication_order>clock.trading_certified_head ORDER BY publication_order LOOP
  IF row.publication_order<>clock.trading_certified_head+1 THEN RAISE EXCEPTION 'knowledge_coverage' USING ERRCODE='P0001'; END IF;
  commit_at=security.checked_commit_time(row.publication_xid);
  IF commit_at<last_commit OR (clock.certified_through IS NOT NULL AND commit_at<=clock.certified_through) THEN RAISE EXCEPTION 'knowledge_clock' USING ERRCODE='P0001'; END IF;
  INSERT INTO trading.knowledge_receipts VALUES(catalog,row.publication_order,row.publication_xid,commit_at);
  clock.trading_certified_head=row.publication_order;last_commit=commit_at;
 END LOOP;
 token=security.capture_market_and_schedule_context(catalog,effective_date,requested_at);
 SELECT known_at INTO cutoff FROM market_data.temporal_contexts WHERE catalog_id=catalog AND id=token;
 IF last_commit>(SELECT certified_through FROM market_data.knowledge_clocks WHERE catalog_id=catalog) THEN RAISE EXCEPTION 'knowledge_clock' USING ERRCODE='P0001'; END IF;
 UPDATE market_data.knowledge_clocks SET trading_certified_head=clock.trading_certified_head WHERE catalog_id=catalog;
 SELECT coalesce(max(publication_order),0) INTO head FROM trading.knowledge_receipts WHERE catalog_id=catalog AND known_from<=cutoff;
 INSERT INTO trading.contexts VALUES(catalog,token,head) ON CONFLICT DO NOTHING;
 IF NOT security.market_access(catalog,'ReadMarketData') THEN RAISE EXCEPTION 'Temporal authority expired during certification' USING ERRCODE='42501'; END IF;
 RETURN token;
END $$;

CREATE FUNCTION security.futures_booking_status(catalog uuid,operation uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb; actor uuid;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'No trading access' USING ERRCODE='42501'; END IF;
 SELECT actor_id INTO actor FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 SELECT jsonb_build_object('operationId',t.operation_id,'tradeId',t.id,'bookId',t.book_id,'instrumentId',p.instrument_id,'bindingId',p.binding_id,
  'sideId',m.side_id,'settlement',p.settlement_state,'controlState','current') INTO result
 FROM trading.trades t JOIN trading.trade_instruments p ON(p.catalog_id,p.trade_id)=(t.catalog_id,t.id)
 JOIN trading.instrument_sides m ON(m.catalog_id,m.instrument_id)=(p.catalog_id,p.instrument_id)
 WHERE t.catalog_id=catalog AND t.operation_id=operation AND t.actor_id=actor;
 IF NOT security.trading_access(catalog,'ReadTrades') THEN RAISE EXCEPTION 'Trading access expired' USING ERRCODE='42501'; END IF;
 RETURN result;
END $$;
CREATE FUNCTION security.book_futures(catalog uuid,operation uuid,book uuid,revision uuid,curve text,contract uuid,
 valuation timestamptz,executed timestamptz,lots numeric,execution numeric,implementation text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts; prior trading.trades; request_value jsonb; ordinal integer; side uuid; instrument uuid; trade uuid; binding uuid; starts timestamptz; ends timestamptz;
 q ref_data.quote_specifications; product ref_data.futures_products; series_row ref_data.futures_series;
 contract_row market_data.contracts; curve_row market_data.curves; definition_from timestamptz;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'No booking access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(730849102);
 IF NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'Booking access expired' USING ERRCODE='42501'; END IF;
 IF operation IS NULL OR operation='00000000-0000-0000-0000-000000000000'::uuid OR executed IS NULL OR NOT isfinite(executed) OR valuation IS NULL OR NOT isfinite(valuation) OR implementation IS DISTINCT FROM 'fixed_total_cash_execution_pnl_v1' THEN RAISE EXCEPTION 'futures_input' USING ERRCODE='P0001'; END IF;
 request_value=jsonb_build_object('book',book,'revision',revision,'curve',curve,'contract',contract,'valuation',valuation AT TIME ZONE 'UTC','executed',executed AT TIME ZONE 'UTC','lots',lots,'execution',execution,'implementation',implementation);
 SELECT * INTO prior FROM trading.trades WHERE catalog_id=catalog AND operation_id=operation;
 IF FOUND THEN
  IF prior.actor_id<>c.actor_id OR prior.request<>request_value THEN RAISE EXCEPTION 'futures_conflict' USING ERRCODE='P0001'; END IF;
  RETURN security.futures_booking_status(catalog,operation);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM trading.books b JOIN trading.portfolios p ON(p.catalog_id,p.id)=(b.catalog_id,b.portfolio_id) WHERE b.catalog_id=catalog AND b.id=book AND b.effective_at<=executed AND p.effective_at<=executed) THEN RAISE EXCEPTION 'futures_book' USING ERRCODE='P0001'; END IF;
 IF(SELECT count(*) FROM trading.trades WHERE catalog_id=catalog)>=256 THEN RAISE EXCEPTION 'futures_limit' USING ERRCODE='P0001'; END IF;
 IF lots IS NULL OR lots<>trunc(lots) OR lots=0 OR abs(lots)>100000 THEN RAISE EXCEPTION 'futures_lots' USING ERRCODE='P0001'; END IF;
 SELECT * INTO contract_row FROM market_data.contracts WHERE catalog_id=catalog AND revision_id=revision AND id=contract;
 SELECT * INTO curve_row FROM market_data.curves WHERE catalog_id=catalog AND revision_id=revision AND code=curve;
 IF contract_row.kind IS DISTINCT FROM 'future' OR curve_row.rule IS DISTINCT FROM 'direct' OR curve_row.direct_role IS DISTINCT FROM 'daily_settlement' OR
  NOT EXISTS(SELECT 1 FROM market_data.curve_members WHERE catalog_id=catalog AND revision_id=revision AND curve_code=curve AND contract_id=contract) THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 SELECT p.* INTO product FROM ref_data.futures_series s JOIN ref_data.futures_products p ON(p.catalog_id,p.revision_id,p.code)=(s.catalog_id,s.revision_id,s.product_code)
 WHERE(s.catalog_id,s.revision_id,s.code)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code) AND s.definition_state='synthetic';
 IF product.definition_state IS DISTINCT FROM 'synthetic' OR product.settlement_method IS DISTINCT FROM 'cash' OR product.lot_basis IS DISTINCT FROM 'fixed_total' OR product.lot_unit_code IS DISTINCT FROM product.quote_unit_code THEN RAISE EXCEPTION 'futures_convention' USING ERRCODE='P0001'; END IF;
 SELECT * INTO series_row FROM ref_data.futures_series WHERE(catalog_id,revision_id,code)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code);
 IF series_row.delivery_from IS DISTINCT FROM contract_row.delivery_from OR series_row.delivery_to IS DISTINCT FROM contract_row.delivery_to OR
  curve_row.commodity_code IS DISTINCT FROM product.commodity_code OR curve_row.location_code IS DISTINCT FROM product.location_code THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 SELECT * INTO q FROM ref_data.quote_specifications WHERE(catalog_id,revision_id,code)=(curve_row.reference_catalog_id,curve_row.reference_revision_id,curve_row.quote_code);
 IF q.kind IS DISTINCT FROM 'outright' OR q.currency_code IS DISTINCT FROM product.quote_currency_code OR q.multiplier IS DISTINCT FROM product.quote_multiplier OR q.trading_tick IS DISTINCT FROM product.outright_tick_size OR
  (SELECT count(*) FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,commodity_code,unit_code)=(q.catalog_id,q.revision_id,product.commodity_code,product.quote_unit_code))<>1 OR
  NOT EXISTS(SELECT 1 FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code,commodity_code,unit_code)=(q.catalog_id,q.revision_id,q.quantity_code,product.commodity_code,product.quote_unit_code))
 THEN RAISE EXCEPTION 'futures_convention' USING ERRCODE='P0001'; END IF;
 SELECT event_at INTO starts FROM ref_data.futures_milestones WHERE(catalog_id,revision_id,series_code,milestone)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code,'first_trading') AND value_state='known';
 SELECT event_at INTO ends FROM ref_data.futures_milestones WHERE(catalog_id,revision_id,series_code,milestone)=(contract_row.reference_catalog_id,contract_row.reference_revision_id,contract_row.futures_series_code,'last_trading') AND value_state='known';
 IF ends IS DISTINCT FROM contract_row.expiry_at THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 IF starts IS NULL OR executed<starts OR executed>=ends OR executed>valuation OR valuation<starts OR valuation>=ends OR execution IS NULL OR execution<q.minimum OR execution>q.maximum OR mod(execution,product.outright_tick_size)<>0 THEN RAISE EXCEPTION 'futures_execution' USING ERRCODE='P0001'; END IF;
 SELECT (effective_from::timestamp AT TIME ZONE 'UTC') INTO definition_from FROM market_data.revision_periods WHERE catalog_id=catalog AND revision_id=revision AND effective_from<=(executed AT TIME ZONE 'UTC')::date AND(executed AT TIME ZONE 'UTC')::date<effective_to;
 IF definition_from IS NULL OR NOT EXISTS(SELECT 1 FROM market_data.revisions WHERE catalog_id=catalog AND id=revision AND state='sealed') THEN RAISE EXCEPTION 'futures_definition' USING ERRCODE='P0001'; END IF;
 SELECT coalesce(max(publication_order),0)+1 INTO ordinal FROM trading.publications WHERE catalog_id=catalog;
 INSERT INTO trading.publications VALUES(catalog,ordinal,pg_current_xact_id());
 SELECT id INTO side FROM trading.futures_sides WHERE catalog_id=catalog AND definition_revision_id=revision AND curve_code=curve AND contract_id=contract AND futures_sides.implementation=book_futures.implementation;
 IF side IS NULL THEN
  side=gen_random_uuid();instrument=gen_random_uuid();
  INSERT INTO trading.futures_sides VALUES(catalog,side,revision,curve,contract,implementation,ordinal,definition_from);
  INSERT INTO trading.instruments VALUES(catalog,instrument,ordinal,definition_from);
  INSERT INTO trading.instrument_sides VALUES(catalog,instrument,side,1,ordinal,definition_from);
 ELSE SELECT instrument_id INTO instrument FROM trading.instrument_sides WHERE catalog_id=catalog AND side_id=side; END IF;
 trade=gen_random_uuid();binding=gen_random_uuid();
 INSERT INTO trading.trades VALUES(catalog,trade,book,operation,c.actor_id,request_value,ordinal,executed);
 INSERT INTO trading.trade_instruments VALUES(catalog,trade,binding,instrument,lots,execution,'unprocessed',ordinal,executed);
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'BookTrade') THEN RAISE EXCEPTION 'Booking access expired' USING ERRCODE='42501'; END IF;
 RETURN security.futures_booking_status(catalog,operation);
END $$;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='security' AND p.proname IN('trading_access','use_trading_context','trading_visible','trading_context_visible','capture_date_context','futures_booking_status','book_futures') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO openetrm_security_owner',f.signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO openetrm_runtime',f.signature);
 END LOOP;
END $$;
COMMIT;
