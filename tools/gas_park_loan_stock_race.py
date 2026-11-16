"""A reviewed return cannot cross a later known stock change."""
import json
from uuid import uuid4

from gas_park_loan_fixture import literal, rejected


def checks(f, template):
    saved_at, saved_day = f.at, f.day
    owned, book = f.account('park_loan_stock_race')
    policies = {action: f.bind(owned, action) for action in ['gas.loan.borrow', 'gas.loan.repay', 'gas.owned.dispatch']}
    f.at, f.day = '2020-12-19T16:00:00Z', '2020-12-19'
    body = {**template, 'operationId': str(uuid4()), 'bookId': book, 'ownedAccountId': owned, 'claimAccountId': None,
        'serviceKind': 'loan', 'perspective': 'customer', 'fixedFeeAmount': '0', 'feeDirection': 'pay', 'feeDueAt': None,
        'contextId': f.capture()}
    booked = json.loads(f.call(f"SELECT security.book_gas_park_loan('{f.catalog}',{literal(body)},'{f.at}')::text;"))
    trade = booked['tradeId']
    opening = f.capture(day='2020-12-18')
    bound = f"SELECT security.use_market_context('{f.catalog}','{opening}');SELECT security.use_trading_context('{f.catalog}','2020-12-18T16:00:00Z');"
    assert f.call(bound + f"SELECT security.require_gas_park_loan_scope('{f.catalog}','{opening}','2020-12-18T16:00:00Z',ARRAY['{book}']::uuid[],ARRAY[]::uuid[]);") == 'f'
    assert f.call(bound + f"SELECT security.gas_park_loan_projection_fence('{f.catalog}','{opening}','2020-12-18T16:00:00Z','2020-12-20T16:00:00Z',ARRAY['{book}']::uuid[]);") == 't'
    assert f.call(bound + f"SELECT security.gas_park_loan_projection_fence('{f.catalog}','{opening}','2020-12-18T16:00:00Z','2020-12-20T16:00:00Z',ARRAY['{book}']::uuid[],ARRAY['{trade}']::uuid[]);") == 't'
    assert f.call(bound + f"SELECT security.gas_park_loan_projection_fence('{f.catalog}','{opening}','2020-12-18T16:00:00Z','2020-12-20T16:00:00Z',ARRAY['{book}']::uuid[],ARRAY['{uuid4()}']::uuid[]);") == 'f'
    f.at, f.day = '2020-12-20T16:00:00Z', '2020-12-20'

    def record(action, selection, operation=None, context=None, preview=False):
        return json.loads(f.call(f"SELECT security.record_gas_park_loan('{f.catalog}','{operation or uuid4()}','{trade}',"
            f"'{action}',{literal(selection)},'{f.at}','{context or f.capture()}',{str(preview).lower()})::text;"))

    def version():
        return int(f.query(f"SELECT greatest(t.publication_order,coalesce(a.publication_order,0)) FROM trading.gas_park_loan_trades t "
            f"LEFT JOIN trading.gas_park_loan_advances a ON(a.catalog_id,a.trade_id)=(t.catalog_id,t.trade_id) WHERE(t.catalog_id,t.trade_id)=('{f.catalog}','{trade}');"))

    agreement = f.evidence(owned, 'synthetic_race_agreement', 'loan_agreement', '720', '2020-12-20T10:00:00Z')
    title = f.evidence(owned, 'synthetic_race_title', 'title_receipt', '720', '2020-12-20T10:00:00Z')
    advance = dict(expectedVersion=version(), agreementEvidenceId=agreement, evidenceId=title, claimEvidenceId=None,
        lotId=None, reservationId=None, effectiveAt='2020-12-20T10:00:00Z')
    operation, original = str(uuid4()), f.capture()
    accepted = record('advance', advance, operation, original)
    evidence = f.evidence(owned, 'synthetic_race_return', 'loan_return', '270', '2020-12-20T12:00:00Z')
    returned = dict(expectedVersion=version(), businessKey='synthetic_reviewed_return', evidenceId=evidence,
        lotId=accepted['stockId'], reservationId=None, quantity='270', effectiveAt='2020-12-20T12:00:00Z')
    pinned = f.capture()
    record('return', returned, context=pinned, preview=True)
    sale = f.evidence(owned, 'synthetic_race_dispatch', 'physical_delivery', '10', '2020-12-20T11:00:00Z')
    f.native(owned, 'dispatch', dict(lotId=accepted['stockId'], evidenceId=sale, quantity='10', reservationId=None,
        effectiveAt='2020-12-20T11:00:00Z'), policy=policies['gas.owned.dispatch'])
    rejected(lambda: record('return', returned, context=pinned), 'gas_owned_context')
    assert f.query(f"SELECT count(*) FROM trading.gas_park_loan_returns WHERE(catalog_id,trade_id)=('{f.catalog}','{trade}');") == '0'
    assert f.query(f"SELECT count(*) FROM trading.gas_owned_repayments WHERE(catalog_id,loan_id)=('{f.catalog}','{accepted['loanId']}');") == '0'
    policy_context = f.capture()
    record('return', returned, context=policy_context, preview=True)
    f.bind(owned, 'gas.loan.repay')
    rejected(lambda: record('return', returned, context=policy_context), 'gas_owned_policy_changed')
    assert f.query(f"SELECT count(*) FROM trading.gas_park_loan_returns WHERE(catalog_id,trade_id)=('{f.catalog}','{trade}');") == '0'
    assert record('advance', advance, operation, original) == accepted
    f.at, f.day = saved_at, saved_day
    print('PASS Park and Loan reviewed return refuses a later 10-unit stock consumption despite sufficient stock; accepted advance retains its first outcome', flush=True)
