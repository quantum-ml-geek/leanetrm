"""HTTP authoring checks for explicit, backend-generated dated observations."""
from copy import deepcopy
from uuid import uuid4


def run(c, context, template):
    catalog = c.call('swaps/catalog', context)
    sources = catalog['contractObservationSources']
    source = next(s for s in sources if s['curve'] == 'future')
    assert source['commodity'] == template['commodity']
    assert source['roles'] == ['daily_settlement']
    assert source['samplings'] == [dict(resetFrequency='daily', averagingMethod='arithmetic')]
    assert 'carry_final_settlement' not in source['expiryPolicies']
    assert 'carry_final_settlement' in next(s for s in sources if s['curve'] == 'future_carry')['expiryPolicies']
    assert all(s['curve'] not in ('base_forward', 'daily_gas') for s in sources)
    clock = next(k['reference'] for k in source['clocks'] if k['reference']['code'] == 'test_utc')
    floating = template['scheduled']['second']['periods'][0]['floating']
    request = dict(calendarPolicy=template['scheduled']['second']['calendarPolicy'], context=context, definitionRevisionId=source['definitionRevisionId'],
                   commodity=source['commodity'], curve=source['curve'], currency=source['currencyCode'],
                   deliveryFrom=floating['deliveryFrom'], deliveryTo=floating['deliveryTo'],
                   paymentSchedule=floating['paymentSchedule'], spread='0',
                   source=dict(implementation='contract_observation_source_v1',
                               historyPolicy='visible_corrections_at_cutoff_v1', role='daily_settlement',
                               expiryPolicy='require_live',
                               selection=dict(mode='prompt_offset', contract=None, promptOffset=0,
                                              roll='contract_expiry_roll_v1', boundaries=None),
                               fixingClock=dict(clock=clock, time='16:00:00',
                                                ambiguousTime='reject', invalidTime='reject')))
    generated = c.call('swaps/contract-observation-preview', request)
    terms = generated['floating']
    rows = terms['contractObservations']['observations']
    assert len(rows) == 31
    assert rows[0] == dict(ordinal=0, **{'from': '2021-01-01'}, to='2021-01-02', fixingAt='2021-01-01T16:00:00+00:00')
    assert rows[-1]['to'] == '2021-02-01'
    assert terms['index'] is None and terms['settlement'] is None
    authored = deepcopy(template)
    authored['operationId'] = str(uuid4())
    authored['scheduled']['second']['periods'][0]['floating'] = terms
    expected = c.call('swaps/preview', template)['valuation']['presentValue']
    assert c.call('swaps/preview', authored)['valuation']['presentValue'] == expected
    booked = c.call('swaps/book', authored)
    reopened = c.call('swaps/editor', dict(context=context, tradeId=booked['tradeId'], revision=None))
    assert reopened['valuation']['presentValue'] == expected
    assert reopened['state']['terms']['scheduled']['second']['periods'][0]['floating']['contractObservations']['observations'] == rows
    late = deepcopy(request)
    late['source']['fixingClock'].update(
        clock=next(k['reference'] for k in source['clocks'] if k['reference']['code'] == 'synthetic_fixed_est'),
        time='23:00:00')
    late['paymentSchedule'] = dict(frequency='monthly', rule='day_of_following_month', days=None,
        dayOfMonth=1, dayBasis=None, shortMonth='reject', adjustment='unadjusted', calendar=None,
        implementation='monthly_payment_date_rules_v1')
    # January 31 at 23:00 fixed UTC-05 is February 1 at 04:00Z. The
    # contractual February 1 payment day permits that day's later fixing.
    same_day = c.call('swaps/contract-observation-preview', late)
    assert same_day['floating']['contractObservations']['observations'][-1]['fixingAt'].startswith('2021-02-01T04:00:00')
    # A January 31 payment precedes the completion and fixing day.
    late['paymentSchedule'].update(rule='days_after_period_end',days=0,dayOfMonth=None,dayBasis='calendar_days',shortMonth=None)
    c.call('swaps/contract-observation-preview', late, expected=422)
    for name, mutate in [
        ('missing fixing policy', lambda r: r['source']['fixingClock'].pop('ambiguousTime')),
        ('missing selection offset', lambda r: r['source']['selection'].pop('promptOffset')),
        ('wrong commodity', lambda r: r.update(commodity='test_power')),
        ('unqualified curve', lambda r: r.update(curve='base_forward')),
        ('unauthorized final carry', lambda r: r['source'].update(expiryPolicy='carry_final_settlement')),
    ]:
        invalid = deepcopy(request)
        mutate(invalid)
        # Missing required JSON fields are rejected by request admission; domain
        # incompatibilities are structured business errors.
        c.call('swaps/contract-observation-preview', invalid,
               expected=400 if name.startswith('missing') else 422)
    print('PASS dated observation authoring: qualified sources, explicit policies, backend daily instants, preview/book/reopen parity and invalid-combination refusal', flush=True)
