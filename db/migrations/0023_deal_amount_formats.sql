-- Shared current presentation metadata for a deal and its fixed/floating roles.
-- This never changes financial facts, identity, cash rounding or historical inputs.
BEGIN;
CREATE TABLE presentation.trade_amount_formats (
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,role text NOT NULL CHECK(role IN('trade','fixed','floating')),
 revision integer NOT NULL CHECK(revision BETWEEN 1 AND 1000000),
 money smallint NOT NULL CHECK(money BETWEEN 0 AND 18),price smallint NOT NULL CHECK(price BETWEEN 0 AND 18),
 quantity smallint NOT NULL CHECK(quantity BETWEEN 0 AND 18),factor smallint NOT NULL CHECK(factor BETWEEN 0 AND 18),
 actor_id uuid NOT NULL REFERENCES security.principals(id),updated_at ref_data.instant NOT NULL,
 PRIMARY KEY(catalog_id,trade_id,role),FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.trades(catalog_id,id)
);
COMMENT ON TABLE presentation.trade_amount_formats IS 'Current shared deal display only. Side roles describe this bounded two-side editor; policies do not follow reusable sides across trades or amend financial history.';
ALTER TABLE presentation.trade_amount_formats ENABLE ROW LEVEL SECURITY;
ALTER TABLE presentation.trade_amount_formats FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON presentation.trade_amount_formats FOR SELECT TO openetrm_runtime
 USING(EXISTS(SELECT 1 FROM trading.trades t WHERE(t.catalog_id,t.id)=(trade_amount_formats.catalog_id,trade_amount_formats.trade_id)));
GRANT SELECT ON presentation.trade_amount_formats TO openetrm_runtime;
GRANT USAGE ON SCHEMA presentation TO openetrm_security_owner;
GRANT SELECT,INSERT,UPDATE ON presentation.trade_amount_formats TO openetrm_security_owner;
CREATE FUNCTION security.save_trade_amount_format(catalog uuid,trade uuid,part text,expected integer,money_places integer,price_places integer,quantity_places integer,factor_places integer) RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c security.request_contexts;head presentation.trade_amount_formats;version integer;
BEGIN
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'AmendTrade') THEN RAISE EXCEPTION 'No deal presentation write access' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM security.request_contexts WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned() AND runtime_login=session_user;
 IF c.market_context_id IS NOT NULL THEN RAISE EXCEPTION 'historical_read_only' USING ERRCODE='P0001'; END IF;
 IF part IS NULL OR part NOT IN('trade','fixed','floating') OR expected IS NULL OR expected<0 OR
   money_places IS NULL OR money_places NOT BETWEEN 0 AND 18 OR price_places IS NULL OR price_places NOT BETWEEN 0 AND 18 OR
   quantity_places IS NULL OR quantity_places NOT BETWEEN 0 AND 18 OR factor_places IS NULL OR factor_places NOT BETWEEN 0 AND 18
 THEN RAISE EXCEPTION 'amount_format' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(catalog::text||trade::text||'amount_formats',0));
 IF NOT EXISTS(SELECT 1 FROM trading.trades t WHERE(t.catalog_id,t.id)=(catalog,trade)) OR
   (part<>'trade' AND NOT EXISTS(SELECT 1 FROM trading.swap_trade_revisions WHERE catalog_id=catalog AND trade_id=trade))
 THEN RAISE EXCEPTION 'amount_format' USING ERRCODE='P0001'; END IF;
 SELECT * INTO head FROM presentation.trade_amount_formats f WHERE(f.catalog_id,f.trade_id,f.role)=(catalog,trade,part);
 IF coalesce(head.revision,0)<>expected THEN RAISE EXCEPTION 'amount_format_conflict' USING ERRCODE='P0001'; END IF;
 version=expected+1;
 INSERT INTO presentation.trade_amount_formats VALUES(catalog,trade,part,version,money_places,price_places,quantity_places,factor_places,c.actor_id,clock_timestamp())
 ON CONFLICT(catalog_id,trade_id,role) DO UPDATE SET revision=excluded.revision,money=excluded.money,price=excluded.price,quantity=excluded.quantity,factor=excluded.factor,actor_id=excluded.actor_id,updated_at=excluded.updated_at;
 IF NOT security.trading_access(catalog,'ReadTrades') OR NOT security.trading_access(catalog,'AmendTrade') THEN RAISE EXCEPTION 'Deal presentation access expired' USING ERRCODE='42501'; END IF;
 RETURN version;
END $$;
ALTER FUNCTION security.save_trade_amount_format(uuid,uuid,text,integer,integer,integer,integer,integer) OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.save_trade_amount_format(uuid,uuid,text,integer,integer,integer,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION security.save_trade_amount_format(uuid,uuid,text,integer,integer,integer,integer,integer) TO openetrm_runtime;
COMMIT;
