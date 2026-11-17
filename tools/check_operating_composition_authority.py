"""Native receipt-expiry regression for a caller-owned disposable preview only."""
from copy import deepcopy
import json
from uuid import UUID, uuid4


def run_checks(query, manifest, request, saved):
    """Run after saving the supplied v2 command in the owned HTTP fixture."""
    catalog, tenant, workspace = (str(UUID(manifest[key])) for key in
                                  ('catalogId', 'tenantId', 'workspaceId'))
    instrument = str(UUID(saved['instrumentId']))
    trade = str(UUID(saved['tradeId']))
    composition = request['plan']['composition']
    assert composition['implementation'] == 'operating_side_composition_v2'
    assert request['plan']['valuation'] is None

    def text_literal(value):
        return "'" + value.replace("'", "''") + "'"

    def literal(value):
        return text_literal(json.dumps(value)) + '::jsonb'

    valuation = query("SELECT effective_at::text FROM trading.power_operating_instruments "
                      f"WHERE(catalog_id,instrument_id)=('{catalog}','{instrument}');")
    assert valuation, 'The authority probe requires an actual saved operating instrument'
    prepared = dict(instrumentId=instrument, members=[dict(slot=slot, name=side['name'])
                    for slot, side in enumerate(composition['sides'])])

    def native(body, expiry, ending='COMMIT;'):
        token = str(UUID(query("SET SESSION AUTHORIZATION preview_authenticator;"
            "SELECT security.issue_context('https://preview.invalid','trader','human_interactive',"
            f"'{tenant}','{workspace}',NULL,'preview_runtime',{expiry});")))
        return ("\\set VERBOSITY verbose\nBEGIN;SET LOCAL SESSION AUTHORIZATION preview_runtime;"
                f"SELECT security.use_context('{token}');"
                f"SELECT security.book_operating_right('{catalog}',{literal(body)},"
                f"{literal(prepared)},{text_literal(valuation)}::timestamptz);" + ending)

    control = deepcopy(request)
    control['operationId'] = str(uuid4())
    result = json.loads(query(native(control, 30, 'ROLLBACK;')))
    assert result['tradeId'] == trade and result['changed'] is False, \
        'The positive control must reach the existing business fact without staged programs'

    operation = str(uuid4())
    duplicate = deepcopy(request)
    duplicate['operationId'] = operation
    suffix = uuid4().hex
    function = 'operating_expiry_' + suffix
    sequence = 'operating_expiry_signal_' + suffix
    trigger = 'operating_expiry_' + suffix
    before = query(f"SELECT count(*) FROM trading.trades WHERE catalog_id='{catalog}';")
    cleanup = (f"DROP TRIGGER IF EXISTS {trigger} ON trading.operating_booking_requests;"
               f"DROP FUNCTION IF EXISTS trading.{function}();"
               f"DROP SEQUENCE IF EXISTS trading.{sequence};")
    try:
        query(f"""BEGIN;
            CREATE SEQUENCE trading.{sequence};
            ALTER SEQUENCE trading.{sequence} OWNER TO openetrm_security_owner;
            REVOKE ALL ON SEQUENCE trading.{sequence} FROM PUBLIC;
            CREATE FUNCTION trading.{function}() RETURNS trigger
            LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
            DECLARE deadline timestamptz;
            BEGIN
             IF NEW.operation_id='{operation}'::uuid THEN
              SELECT expires_at INTO deadline FROM security.request_contexts
              WHERE backend_pid=pg_backend_pid() AND transaction_id=pg_current_xact_id_if_assigned()
               AND runtime_login=session_user;
              IF deadline IS NULL OR deadline<=clock_timestamp() THEN
               RAISE EXCEPTION 'operating_expiry_probe_not_admitted';
              END IF;
              PERFORM nextval('trading.{sequence}'::regclass);
              PERFORM pg_sleep(2.2);
              IF deadline>clock_timestamp() THEN RAISE EXCEPTION 'operating_expiry_probe_not_expired';END IF;
             END IF;
             RETURN NEW;
            END$$;
            ALTER FUNCTION trading.{function}() OWNER TO openetrm_security_owner;
            REVOKE ALL ON FUNCTION trading.{function}() FROM PUBLIC;
            CREATE TRIGGER {trigger} BEFORE INSERT ON trading.operating_booking_requests
             FOR EACH ROW EXECUTE FUNCTION trading.{function}();
            COMMIT;""")
        refused = False
        try:
            query(native(duplicate, 2))
        except RuntimeError as error:
            assert '42501' in str(error), str(error)
            refused = True
        assert query(f"SELECT is_called AND last_value=1 FROM trading.{sequence};") == 't', \
            'The receipt trigger must be entered under valid authority before the controlled expiry'
        receipts = query("SELECT count(*) FROM trading.operating_booking_requests "
                         f"WHERE(catalog_id,operation_id)=('{catalog}','{operation}');")
        assert refused, 'Native semantic no-op returned a receipt after its request authority expired'
        assert receipts == '0', 'Expired native semantic no-op must leave no command receipt'
        assert query(f"SELECT count(*) FROM trading.trades WHERE catalog_id='{catalog}';") == before, \
            'A refused semantic no-op must not create another trade'
        print('PASS operating composition authority: native semantic no-op refuses expired receipt publication and rolls back', flush=True)
        return 1
    finally:
        query(cleanup)
