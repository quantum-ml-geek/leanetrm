-- Stable readable references accompany exact immutable entity identities.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT pg_advisory_xact_lock(730849102);
LOCK TABLE trading.trades,trading.instruments IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE trading.trade_references (
 catalog_id uuid NOT NULL,trade_id uuid NOT NULL,reference_number integer NOT NULL CHECK(reference_number>0),
 PRIMARY KEY(catalog_id,trade_id),UNIQUE(catalog_id,reference_number),
 FOREIGN KEY(catalog_id,trade_id) REFERENCES trading.trades(catalog_id,id)
);
CREATE TABLE trading.instrument_references (
 catalog_id uuid NOT NULL,instrument_id uuid NOT NULL,reference_number integer NOT NULL CHECK(reference_number>0),
 PRIMARY KEY(catalog_id,instrument_id),UNIQUE(catalog_id,reference_number),
 FOREIGN KEY(catalog_id,instrument_id) REFERENCES trading.instruments(catalog_id,id)
);
INSERT INTO trading.trade_references
 SELECT catalog_id,id,row_number() OVER(PARTITION BY catalog_id ORDER BY publication_order,id)::integer FROM trading.trades;
INSERT INTO trading.instrument_references
 SELECT catalog_id,id,row_number() OVER(PARTITION BY catalog_id ORDER BY publication_order,id)::integer FROM trading.instruments;
CREATE FUNCTION security.assign_trading_reference() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(730849102);
 IF TG_TABLE_SCHEMA<>'trading' THEN RAISE EXCEPTION 'Invalid reference target' USING ERRCODE='55000'; END IF;
 IF TG_TABLE_NAME='trades' THEN
  INSERT INTO trading.trade_references SELECT NEW.catalog_id,NEW.id,coalesce(max(reference_number),0)+1 FROM trading.trade_references WHERE catalog_id=NEW.catalog_id;
 ELSIF TG_TABLE_NAME='instruments' THEN
  INSERT INTO trading.instrument_references SELECT NEW.catalog_id,NEW.id,coalesce(max(reference_number),0)+1 FROM trading.instrument_references WHERE catalog_id=NEW.catalog_id;
 ELSE RAISE EXCEPTION 'Invalid reference target' USING ERRCODE='55000'; END IF;
 RETURN NEW;
END $$;
ALTER FUNCTION security.assign_trading_reference() OWNER TO openetrm_security_owner;
REVOKE ALL ON FUNCTION security.assign_trading_reference() FROM PUBLIC;
CREATE TRIGGER assign_reference AFTER INSERT ON trading.trades FOR EACH ROW EXECUTE FUNCTION security.assign_trading_reference();
CREATE TRIGGER assign_reference AFTER INSERT ON trading.instruments FOR EACH ROW EXECUTE FUNCTION security.assign_trading_reference();
ALTER TABLE trading.trade_references ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading.trade_references FORCE ROW LEVEL SECURITY;
ALTER TABLE trading.instrument_references ENABLE ROW LEVEL SECURITY;
ALTER TABLE trading.instrument_references FORCE ROW LEVEL SECURITY;
CREATE POLICY scoped_read ON trading.trade_references FOR SELECT TO openetrm_runtime
 USING(EXISTS(SELECT 1 FROM trading.trades t WHERE(t.catalog_id,t.id)=(trade_references.catalog_id,trade_references.trade_id)));
CREATE POLICY scoped_read ON trading.instrument_references FOR SELECT TO openetrm_runtime
 USING(EXISTS(SELECT 1 FROM trading.instruments i WHERE(i.catalog_id,i.id)=(instrument_references.catalog_id,instrument_references.instrument_id)));
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.trade_references FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON trading.instrument_references FOR EACH ROW EXECUTE FUNCTION market_data.guard_knowledge_receipt();
GRANT SELECT,INSERT ON trading.trade_references,trading.instrument_references TO openetrm_security_owner;
GRANT SELECT ON trading.trade_references,trading.instrument_references TO openetrm_runtime;
COMMIT;
