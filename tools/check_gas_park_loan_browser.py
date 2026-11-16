"""Book and perform Park and Loan through this tree's owned full application."""
import argparse
from decimal import Decimal
import json
import os
from pathlib import Path
from uuid import uuid4

from check_reference_editing import main as native_main
from close_session_fixture import sql_session
from gas_park_loan_fixture import ParkLoanFixture, fixture, literal
from owned_lifecycle_browser import build_assets, run as run_browser


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['pg-bin', 'dotnet', 'browser']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--no-build', action='store_true')
    args = parser.parse_args()
    for path in [args.pg_bin / 'psql', args.dotnet, args.browser]:
        if not path.is_file():
            parser.error('An installed executable is required: ' + str(path))
    os.environ['DOTNET'] = str(args.dotnet.resolve())
    children = []
    if not args.no_build:
        build_assets(args.dotnet.resolve())

    def checks(query, manifest):
        f = ParkLoanFixture(query, manifest)
        cases = []
        for kind, perspective, receiver in [('loan', 'customer', True), ('loan', 'provider', False),
                                            ('park', 'customer', False), ('park', 'provider', True)]:
            label = 'browser_' + kind + '_' + perspective
            owned, book = f.account(label)
            claim = f.account(label + '_claim', kind='operator_balance', book=book)[0] if not receiver else None
            policies = {}
            for action in ['gas.owned.receive_title', 'gas.owned.dispatch', 'gas.loan.borrow', 'gas.loan.repay', 'gas.cash.record_payment']:
                policies[action] = f.bind(owned, action)
            if claim:
                for action in ['gas.operator.record', 'gas.operator.settle', 'gas.cash.record_payment']:
                    policies[action] = f.bind(claim, action)
            f.at, f.day = '2020-12-23T16:00:00Z', '2020-12-23'
            stock = None
            if not receiver:
                supply = f.evidence(owned, label + '_funding', 'title_receipt', '720', '2020-12-18T08:00:00Z')
                stock = f.native(owned, 'receive_title', dict(evidenceId=supply, quantity='720', titleAt='2020-12-18T08:00:00Z',
                    availableAt='2020-12-18T08:00:00Z', originPolicy='opening_owned_stock_v1', carrying='nominal_mark_v1'),
                    policy=policies['gas.owned.receive_title'])['id']
            cases.append(dict(serviceKind=kind, perspective=perspective, receiver=receiver,
                feeDirection='pay' if perspective == 'customer' else 'receive', feeAmount=-12.5 if perspective == 'customer' else 12.5,
                bookId=book, ownedAccountId=owned,
                claimAccountId=claim, fundingLotId=stock, legalEntityId=f.entity, counterpartyId=f.party, policies=policies,
                agreementEvidenceId=f.evidence(owned, label + '_agreement', 'loan_agreement', '720', '2020-12-20T10:00:00Z'),
                evidenceId=f.evidence(owned, label + '_advance', 'title_receipt' if receiver else 'physical_delivery', '720', '2020-12-20T10:00:00Z'),
                claimEvidenceId=f.evidence(claim, label + '_claim', 'operator_statement', '720', '2020-12-20T10:00:00Z') if claim else None,
                partialEvidenceId=f.evidence(owned, label + '_partial', 'loan_return' if receiver else 'title_receipt', '270', '2020-12-20T12:00:00Z'),
                finalEvidenceId=f.evidence(owned, label + '_final', 'loan_return' if receiver else 'title_receipt', '450', '2020-12-23T10:00:00Z')))

        market = f.valuation_inputs()
        session = 'synthetic_park_loan_close'
        sql_session(query, manifest, session, 'test_utc_every_day', '16:00:00', ['future'], ['trader'], effective=('2020-01-01', '2022-01-01'))
        query("INSERT INTO security.role_permissions SELECT role_id,'PublishMarketData' FROM security.role_permissions WHERE permission='AmendTrade' ON CONFLICT DO NOTHING;")
        closes = {}
        for label, day in [('before', '2020-12-18'), ('advance', '2020-12-20'), ('after', '2020-12-23')]:
            closes[label] = f.call(f"SELECT security.register_market_close('{f.catalog}','{manifest['revisionId']}','{uuid4()}',"
                f"'Synthetic Park and Loan {label}','{session}','{day}','{day}T16:00:00Z',{literal(market['pins'])},{literal(market['members'])});")
        packet = dict(session=session, closes=closes, cases=cases, **{key: market[key] for key in ['markId', 'rateIds', 'contractId', 'definitionRevisionId']})
        run_browser(query, manifest, args.dotnet.resolve(), args.browser.resolve(), children, packet, 'tests/browser/gas-park-loan.mjs',
            worker_enabled=False, timeout=540, artifacts=['gas-park-loan-booked.png', 'gas-park-loan-review.png', 'gas-park-loan-mobile.png', 'gas-park-loan-risk.png'])
        for case in cases:
            trade = query(f"SELECT trade_id FROM trading.gas_park_loan_trades WHERE(catalog_id,owned_account_id)=('{f.catalog}','{case['ownedAccountId']}');")
            assert trade and '\n' not in trade
            context = f.capture()
            source = json.loads(f.call(f"SELECT security.use_market_context('{f.catalog}','{context}');SELECT security.use_trading_context('{f.catalog}','{f.at}');"
                f"SELECT security.read_gas_park_loan('{f.catalog}','{trade}','{context}','{f.at}')::text;"))
            assert source['balances'] == dict(acceptedPrincipal='720', acceptedReturn='720', outstandingPrincipal='0')
            assert Decimal(source['fee']['unpaid']) == Decimal('-7.5' if case['feeAmount'] < 0 else '7.5')
            assert len(source['returns']) == 2 and not source['reconciliationRequired']
        print('PASS real Park and Loan booking/reopen, both perspectives, accepted native principal/returns, independent bank fee and retained-command recovery', flush=True)

    native_main(checks=checks, fixture_factory=fixture, arguments=['--pg-bin', str(args.pg_bin.resolve())], cleanup_ready=lambda: not children)


if __name__ == '__main__':
    main()
