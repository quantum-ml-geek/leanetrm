"""Native flat-contract operating risk with an independent quantity oracle."""
from copy import deepcopy
from fractions import Fraction
from uuid import uuid4
from exact_values import fraction


def run_checks(client, original, hedge_trade_id, context):
    frame=context['snapshotId'];route='physical/power-trades/'
    client.call('profile',{'profile':'editor'})
    facility=client.call('physical/power-facilities/get',dict(snapshotId=frame,
        facilityId=original['plan']['facilityId'],version=original['plan']['facilityVersion']))
    revised=deepcopy(facility)
    revised['version']+=1;revised['effectiveFrom']='2021-01-01T00:00:00Z'
    client.call('physical/power-facilities/save',dict(snapshotId=frame,requestId=str(uuid4()),
        expectedVersion=facility['version'],facility=revised))
    client.call('profile',{'profile':'trader'})
    catalog=client.call(route+'catalog',dict(snapshotId=frame))
    prices=[p for p in catalog['operating']['priceContracts'] if p['curveCode']=='local_power_all_in'
        and p['deliveryFrom']=='2021-01-01' and p['deliveryTo']=='2021-02-01']
    assert len(prices)==1
    price=prices[0]
    request=deepcopy(original);request['operationId']=str(uuid4())
    plan=request['plan'];plan['facilityVersion']=revised['version']
    plan['grid']['operatingDate']='2021-01-15';plan['batteryState']['at']='2021-01-15T00:00:00Z'
    plan['valuation']['energyPrice']=dict(mode='selected_contract_flat_v1',quoteCode=price['quoteCode'],
        fixedPrice=None,curveCode=price['curveCode'],contractId=price['contractId'])
    # The original fixture independently supplies a January outright mark 28.95.
    # A fixed plan delivers 8.1 MWh and purchases 10 MWh at 20: no inferred upstream
    # exposure or redispatch participates in this oracle.
    expected=Fraction('8.1')*Fraction('28.95')-10*20
    assert fraction(client.call(route+'preview',request)['valuation']['value'])==expected
    saved=client.call(route+'book',request,timeout=60)
    assert fraction(client.call(route+'valuation',dict(snapshotId=frame,tradeId=saved['tradeId']))['valuation']['value'])==expected
    scope=dict(context=context,bookIds=[request['bookId']],portfolioIds=[],tradeIds=[saved['tradeId'],hedge_trade_id])
    risks=client.call('portfolio/risk/catalog',scope)
    factors=[t for t in risks['scenarioTargets'] if t['kind']=='parallel'
        and t['factor']['target']['curve']['code']==price['curveCode']]
    assert len(factors)==1
    selected=dict(context,knowledgeMode='retained',contextId=risks['context']['contextId'])
    report=client.call(route+'hedges',dict(context=selected,bookIds=scope['bookIds'],
        operatingTradeId=saved['tradeId'],hedgeTradeIds=[hedge_trade_id],
        bumps=[dict(factor=factors[0]['factor'],size='1',convention=risks['bumpConvention'])],
        convention='operating_right_price_hedge_v1',numericalPolicy=risks['numericalPolicy'],
        pricingPolicy=risks['pricingPolicy'],aggregationPolicy='shared_price_changes_v1'))
    assert len(report['priceChanges'])==1
    changes=report['priceChanges'][0]
    assert Fraction(changes['operating']['upPnl'])==Fraction('8.1')
    assert Fraction(changes['operating']['downPnl'])==Fraction('-8.1')
    assert Fraction(changes['operating']['delta'])==Fraction('8.1')
    assert Fraction(changes['operating']['gamma'])==0
    assert Fraction(changes['hedges']['upPnl'])==0 and changes['net']==changes['operating']
    print('PASS operating market HTTP: retained explicit outright contract and shared native repricing give 8.1 price delta without upstream exposure',flush=True)
