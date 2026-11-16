"""Saved operating-right trades through the owned public application routes."""
from copy import deepcopy
from fractions import Fraction
from uuid import uuid4
from exact_values import fraction
from preview_client import initial_frame
from preview_fixture import trade_booking


def run_checks(client, query, manifest, plan, *, other_plans=()):
    client.call('profile', {'profile': 'trader'})
    frame=initial_frame(client.call('workspace'),'2020-12-15')['id']
    route='physical/power-trades/'
    catalog=client.call(route+'catalog',{'snapshotId':frame})
    assert catalog['canBook'] and catalog['knownAt']
    assert 'test_utc' in catalog['operating']['operatingBookingClockCodes']
    request=dict(operationId=str(uuid4()),tradeId=None,expectedRevision=0,bookId=catalog['books'][0]['id'],
        legalEntityId=catalog['legalEntities'][0]['id'],legalEntityRevision=catalog['legalEntities'][0]['revision'],
        counterpartyId=catalog['counterparties'][0]['id'],counterpartyRevision=catalog['counterparties'][0]['revision'],
        reason='Synthetic supplied operating-right contract',convention=catalog['convention'],plan=deepcopy(plan))
    request['plan']['snapshotId']=frame
    assert fraction(client.call(route+'preview',request)['valuation']['value'])==610
    before=query('SELECT count(*) FROM trading.trades;')
    saved=client.call(route+'book',request,timeout=60)
    assert saved['changed'] and saved['revision']==1
    assert client.call(route+'book',request)==saved
    assert client.call(route+'status',{'operationId':request['operationId']})==saved
    assert int(query('SELECT count(*) FROM trading.trades;'))==int(before)+1
    conflict=deepcopy(request);conflict['reason']='Different synthetic review'
    assert client.call(route+'book',conflict,expected=409)['code']=='operating_request_conflict'
    duplicate=deepcopy(request);duplicate['operationId']=str(uuid4())
    unchanged=client.call(route+'book',duplicate,timeout=60)
    assert not unchanged['changed'] and unchanged['tradeId']==saved['tradeId']
    assert int(query('SELECT count(*) FROM trading.trades;'))==int(before)+1
    selected=dict(snapshotId=frame,tradeId=saved['tradeId'])
    reopened=client.call(route+'get',selected)
    assert reopened['instrumentId']==saved['instrumentId'] and len(reopened['sides'])==2
    assert len({s['sideId'] for s in reopened['sides']})==2
    assert len({s['scheduleId'] for s in reopened['sides']})==2
    assert reopened['terms']==request, 'Reopening preserves the original reviewed command.'
    directory=client.call(route+'directory',dict(snapshotId=frame,bookIds=[request['bookId']],offset=0,limit=50))
    assert any(t['tradeId']==saved['tradeId'] for t in directory['trades'])
    value=client.call(route+'valuation',selected)
    assert fraction(value['valuation']['value'])==610
    assert [s['coefficient'] for s in value['valuation']['sides']]==['1','-1']
    assert all(row['evidenceId'] is None for side in value['valuation']['sides'] for row in side['rows'])
    context=dict(snapshotId=frame,convention='trading_workspace_v1',knowledgeMode='current')
    facts=client.call('trading/positions',dict(context=context,bookIds=[request['bookId']],portfolioIds=[],offset=0,limit=64))
    fact=next(p for p in facts['positions'] if p['tradeId']==saved['tradeId'])
    assert fact['instrumentType']=='operating_right' and fact['bookedQuantity']=='1'
    holding=client.call('trading/position',dict(context=context,tradeId=saved['tradeId'],bindingId=saved['bindingId'],revision=1,instrumentType='operating_right'))['holding']
    assert Fraction(holding['presentValue'])==610 and holding['sideSchedules']
    for kind,physical_plan,expected_value,expected_gross in other_plans:
        other=deepcopy(request)
        other.update(operationId=str(uuid4()),reason='Synthetic '+kind+' operating-right contract',plan=deepcopy(physical_plan))
        other['plan']['snapshotId']=frame
        assert fraction(client.call(route+'preview',other)['valuation']['value'])==expected_value
        receipt=client.call(route+'book',other,timeout=60)
        assert receipt['changed'] and receipt['revision']==1
        assert client.call(route+'book',other)==receipt
        exact=dict(snapshotId=frame,tradeId=receipt['tradeId'])
        trade=client.call(route+'get',exact)
        assert trade['resourceKind']==kind and trade['facilityId']==physical_plan['facilityId']
        assert trade['terms']==other and len(trade['sides'])==len(expected_gross)
        assert len({side['scheduleId'] for side in trade['sides']})==len(expected_gross)
        priced=client.call(route+'valuation',exact)
        assert fraction(priced['valuation']['value'])==expected_value
        assert {side['name']:fraction(side['grossValue']) for side in priced['valuation']['sides']}==expected_gross
        assert all(row['evidenceId'] is None for side in priced['valuation']['sides'] for row in side['rows'])
        ordinary=client.call('trading/position',dict(context=context,tradeId=receipt['tradeId'],bindingId=receipt['bindingId'],revision=1,instrumentType='operating_right'))['holding']
        assert Fraction(ordinary['presentValue'])==expected_value and ordinary['sideSchedules'] is True
        print('PASS '+kind+' operating trade HTTP: native booking, exact replay/reopening, independent retained gross Sides and ordinary position PV',flush=True)
    risk=client.call('portfolio/risk/catalog',dict(context=context,bookIds=[request['bookId']],portfolioIds=[],tradeIds=[saved['tradeId']]))
    assert any(m['measure']=='operating_contractual_present_value' for m in risk['measures'])
    future_context=dict(snapshotId=frame,convention='contract_lot_execution_pnl_v2',knowledgeMode='current')
    future_contract=client.call('futures/catalog',future_context)['contracts'][0]
    hedge=client.call('futures/book',dict(future_context,**trade_booking(),operationId=str(uuid4()),bookId=request['bookId'],
        curve=future_contract['curve'],contractId=future_contract['id'],definitionRevisionId=future_contract['definitionRevisionId'],lots='1',executionPrice='2.9'))
    held_hedge=client.call('trading/position',dict(context=context,tradeId=hedge['tradeId'],bindingId=hedge['bindingId'],revision=1,instrumentType='future'))['holding']
    hedge_catalog=client.call('portfolio/risk/catalog',dict(context=context,bookIds=[request['bookId']],portfolioIds=[],tradeIds=[saved['tradeId'],hedge['tradeId']]))
    factor=next(t for t in hedge_catalog['scenarioTargets'] if t['kind']!='delivery_bucket' and t['factor']['target']['curve']['code']==future_contract['curve'])
    hedge_context=dict(context,knowledgeMode='retained',contextId=hedge_catalog['context']['contextId'])
    hedge_request=dict(context=hedge_context,bookIds=[request['bookId']],operatingTradeId=saved['tradeId'],hedgeTradeIds=[hedge['tradeId']],
        bumps=[dict(factor=factor['factor'],size='1',convention=hedge_catalog['bumpConvention'])],convention='operating_right_price_hedge_v1',
        numericalPolicy=hedge_catalog['numericalPolicy'],pricingPolicy=hedge_catalog['pricingPolicy'],aggregationPolicy='shared_price_changes_v1')
    hedged=client.call(route+'hedges',hedge_request)
    assert hedged['valuation']['context']['contextId']==hedge_context['contextId']
    assert len(hedged['valuation']['positions'])==2
    assert all(Fraction(r['operating']['upPnl'])==0 and r['net']==r['hedges'] for r in hedged['priceChanges'])
    assert any(Fraction(r['hedges']['upPnl'])!=0 for r in hedged['priceChanges'])
    empty=deepcopy(hedge_request);empty['bumps']=[]
    assert client.call(route+'hedges',empty,expected=422)['code']=='power_hedge_contract'
    from check_power_market_http import run_checks as check_market_price
    check_market_price(client,request,hedge['tradeId'],context)
    overlap=deepcopy(request);overlap['operationId']=str(uuid4())
    overlap['plan']['batteryDispatch'][0]['chargeMw']='8'
    overlap['plan']['batteryDispatch'][1]['dischargeMw']='6.48'
    assert client.call(route+'book',overlap,expected=409,timeout=60)['code']=='operating_right_overlap'
    # Exact retained reopening cannot substitute a new facility revision or a new
    # plan, and a historical view cannot admit another contractual right.
    client.call('market/context/retained',dict(contextId=value['contextId'],selection='latest_correction'))
    historical=initial_frame(client.call('workspace'),'2020-12-15')['id']
    retained=dict(snapshotId=historical,tradeId=saved['tradeId'])
    a=client.call(route+'valuation',retained)
    assert a==client.call(route+'valuation',retained)
    assert fraction(a['valuation']['value'])==610
    assert client.call(route+'book',request,expected=422)['code']=='historical_read_only'
    client.call('market/current',{})
    client.call('profile',{'profile':'editor'})
    assert client.call(route+'status',{'operationId':request['operationId']},expected=403)['code']=='access_denied'
    print('PASS operating trades HTTP: durable booking, first outcomes, semantic no-op, exclusive rights, retained Side PV, ordinary positions and certified reopening',flush=True)
    return dict(tradeId=saved['tradeId'],tradeReference=reopened['tradeReference'],facilityId=reopened['facilityId'],
        facilityVersion=reopened['facilityVersion'],bookId=request['bookId'],snapshotId=frame,
        hedge=dict(tradeId=hedge['tradeId'],tradeReference=held_hedge['tradeReference'],bookId=request['bookId'],curveCode=future_contract['curve']))
