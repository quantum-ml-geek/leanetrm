"""Original committed observation receipts require authority, not regeneration."""
import json


def run_checks(query, manifest, receipt):
    catalog=manifest['catalogId'];operation=receipt['operationId']
    original=json.loads(query(f"SELECT request::text FROM trading.swap_trade_revisions WHERE operation_id='{operation}';"))
    admitted=json.loads(json.dumps(original))
    for key in ('fixed','firstFloating','floating'):
        body=admitted.get(key)
        if body is None:continue
        policy=body.pop('calendarPolicy',None)
        if body.get('observationSchedule'):
            body['observationSchedule']['calendar']=policy['observation']['calendar']
    literal=lambda value: 'NULL' if value is None else "'"+str(value).replace("'","''")+"'"
    doc=lambda value: 'NULL' if value is None else literal(json.dumps(value))+'::jsonb'
    args=[literal(catalog),literal(operation),literal(admitted['trade']),literal(admitted['expected']),literal(admitted['book']),
          literal(admitted['definition']),literal(admitted['referenceCatalog']),literal(admitted['referenceRevision']),literal(admitted['commodity']),
          doc(admitted['fixed']),doc(admitted['firstFloating']),doc(admitted['floating']),literal(admitted['quantity']),literal(admitted['coefficient']),
          literal(str(admitted['discounting']).lower()),literal(admitted['valuation']),literal(admitted['effective']),literal(admitted['reason']),
          literal(admitted['implementation']),literal(admitted['memo']),doc(admitted['booking']),"'{}'::uuid[]"]
    call='security.save_composed_swap('+','.join(args)+')'
    token=query("SET SESSION AUTHORIZATION preview_authenticator;SELECT security.issue_context("
        f"'https://preview.invalid','trader','human_interactive','{manifest['tenantId']}','{manifest['workspaceId']}',NULL,'preview_runtime',60);")
    # The owned negative fixture restores the admitted request shape only. Its
    # completed receipt must not depend on a new policy or executable artifact.
    prefix=f"""BEGIN;
      ALTER TABLE trading.swap_trade_revisions DISABLE TRIGGER USER;
      UPDATE trading.swap_trade_revisions SET request={doc(admitted)} WHERE operation_id='{operation}';
      ALTER TABLE trading.swap_trade_revisions ENABLE TRIGGER USER;
      ALTER TABLE trading.instrument_side_schedules DISABLE TRIGGER USER;
      DELETE FROM trading.instrument_side_schedules WHERE instrument_id='{receipt['instrumentId']}';
      SET CONSTRAINTS ALL IMMEDIATE;
      ALTER TABLE trading.instrument_side_schedules ENABLE TRIGGER USER;
    """
    enter=f"SET SESSION AUTHORIZATION preview_runtime;SELECT security.use_context('{token}');"
    expected=doc(receipt)
    query(prefix+enter+f"DO $$ BEGIN IF {call} IS DISTINCT FROM {expected} THEN RAISE EXCEPTION 'receipt_changed';END IF;END$$;RESET SESSION AUTHORIZATION;DO $$BEGIN IF (SELECT request::text FROM trading.swap_trade_revisions WHERE operation_id='{operation}') IS DISTINCT FROM ({doc(admitted)})::text THEN RAISE EXCEPTION 'receipt_request_rewritten';END IF;END$$;ROLLBACK;")
    # Remove current pricing-reference authority without changing trade access.
    revoke=f"DELETE FROM security.role_permissions WHERE permission='ReadMarketData';"
    query(prefix+revoke+enter+f"DO $$ BEGIN PERFORM {call};RAISE EXCEPTION 'receipt_authority_bypassed';EXCEPTION WHEN insufficient_privilege THEN NULL;END$$;ROLLBACK;")
    assert json.loads(query(f"SELECT request::text FROM trading.swap_trade_revisions WHERE operation_id='{operation}';"))==original
    print('PASS committed observation receipt: original pre-policy request and outcome survive without regeneration; revoked current authority refuses; stored bytes remain exact',flush=True)
