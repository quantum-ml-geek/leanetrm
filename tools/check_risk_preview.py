"""Shared scenario checks in the owner's disposable synthetic fixture only."""
from decimal import Decimal
from uuid import uuid4


def run_checks(Client, check):
    risk = Client(); risk.bootstrap(); risk.call('profile', {'profile': 'risk'})
    workspace = risk.call('workspace')
    frame = next(f for f in workspace['frames'] if f['at'].startswith('2020-12-18'))
    context = {'snapshotId': frame['id'], 'convention': 'fixed_total_cash_execution_pnl_v1', 'knowledgeMode': 'current'}
    holdings = risk.call('futures/holdings', context)
    retained = {**context, 'knowledgeMode': 'retained', 'contextId': holdings['context']['contextId']}
    catalog = risk.call('futures/risk/catalog', retained)
    factor = next(f for f in catalog['factors'] if 'future' in f['curves'] and f['deliveryFrom'] == '2021-01-01')
    request = {'context': retained, 'bookIds': [], 'portfolioIds': [], 'bumps': [{'seriesId': factor['seriesId'], 'quote': factor['quote'], 'size': '0.1', 'convention': catalog['bumpConvention']}],
               'convention': catalog['convention'], 'numericalPolicy': catalog['numericalPolicy']}
    before = risk.call('evaluate', {'snapshotId': frame['id'], 'curve': 'future'})
    result = risk.call('futures/risk', request)
    check('risk pins the same historical context and independent observation receipt', result['context'] == holdings['context'] and result['factors'][0]['factor']['observation'] == factor['observation'])
    check('risk names execution P&L and retains explicit bump and model policies', result['measure'] == 'execution_pnl' and result['factors'][0]['bump'] == '0.1' and result['modelContracts'][0]['modelVersion'] == 'fixed_total_open_mark_v1')
    terms = result['inputs']['marketBindings'][0]
    check('risk retains dated contract lot basis settlement and execution price policies',
          terms['contract']['id'] == factor['contractId'] and terms['series']['code']
          and terms['lotBasis'] == 'FixedTotal' and terms['settlementMethod'] == 'cash'
          and terms['tradingTick'] and terms['clearingIncrement'] and terms['minimumPrice'] and terms['maximumPrice'])
    rows = {(r['tradeId'], r['bindingId']): r for r in holdings['holdings']}
    for p in result['factors'][0]['positions']:
        h = rows[(p['tradeId'], p['bindingId'])]
        quantity = Decimal(h['quantity'])
        check('shared shock reconciles each holding to an independent signed quantity oracle',
              Decimal(p['values']['base']) == Decimal(h['executionPnl']) and Decimal(p['values']['upPnl']) == quantity / 10 and Decimal(p['values']['downPnl']) == -quantity / 10 and Decimal(p['values']['delta']) == quantity and p['values']['gamma'] == '0')
    check('repeated held contract calls one unit pricer per base up and down', result['work']['uniqueValuations'] == 1 and result['work']['unitPricerCalls'] == 3 and result['work']['scenarioCount'] == 3)
    check('risk changes no live quote or booked holding', risk.call('evaluate', {'snapshotId': frame['id'], 'curve': 'future'}) == before and risk.call('futures/holdings', retained) == holdings)
    again = risk.call('futures/risk', request)
    check('identical pinned risk requests are deterministic without cross-request caches', again == result)
    selected = risk.call('futures/risk', {**request, 'bookIds': [holdings['holdings'][0]['bookId']]})
    check('risk scope uses selected books before presentation filters', len(selected['factors'][0]['totals']) == 1 and all(p['bookId'] == holdings['holdings'][0]['bookId'] for p in selected['factors'][0]['positions']))
    other = next(f for f in catalog['factors'] if 'power_basis' in f['curves'])
    unrelated = risk.call('futures/risk', {**request, 'bumps': [{**request['bumps'][0], 'seriesId': other['seriesId'], 'quote': other['quote']}]})
    check('unrelated factor retains explicit zero sensitivity without repricing units', unrelated['work']['unitPricerCalls'] == 1 and all(p['values']['delta'] == '0' for p in unrelated['factors'][0]['positions']))
    for patch in [{'convention': None}, {'numericalPolicy': None}, {'bumps': []}, {'bumps': [None]}, {'bookIds': [str(uuid4())]}, {'bumps': [{**request['bumps'][0], 'size': '0'}]}, {'bumps': [{**request['bumps'][0], 'convention': 'relative'}]}, {'bumps': [{**request['bumps'][0], 'quote': other['quote']}]}, {'bumps': request['bumps'] * 2}]:
        risk.call('futures/risk', {**request, **patch}, expected=422)
        check('risk rejects missing ambiguous or unsupported financial choices')
    trader = Client(); trader.bootstrap(); trader.call('profile', {'profile': 'trader'})
    trader_frame = next(f for f in trader.call('workspace')['frames'] if f['at'] == frame['at'])
    trader_context = {**context, 'snapshotId': trader_frame['id']}
    trader.call('futures/risk/catalog', trader_context, expected=403)
    trader.call('futures/risk', {**request, 'context': trader_context}, expected=403)
    check('trading permission does not silently grant scenario execution')
    admin = Client(); admin.bootstrap(); admin.call('profile', {'profile': 'admin'})
    member = next(m for m in admin.call('admin')['members'] if m['login'] == 'risk')
    changed = admin.call('admin/update', {'operationId': str(uuid4()), 'id': member['id'], 'expectedVersion': member['version'], 'name': member['name'], 'enabled': True, 'roles': ['trader']})
    risk.call('futures/risk', request, expected=403)
    check('revoking scenario authority blocks a retained historical risk request')
    admin.call('admin/update', {'operationId': str(uuid4()), 'id': member['id'], 'expectedVersion': changed['version'], 'name': member['name'], 'enabled': True, 'roles': ['risk_analyst']})
    check('restoring scenario authority leaves retained inputs and values unchanged', risk.call('futures/risk', request) == result)
