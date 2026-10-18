"""Certified schedule time travel using fresh owned HTTP test clients."""
from datetime import datetime, timedelta
import re


def run_checks(Client, check):
    editor = Client(); editor.bootstrap(); editor.call('profile', {'profile': 'editor'})
    approver = Client(); approver.bootstrap(); approver.call('profile', {'profile': 'approver'})
    viewer = Client(); viewer.bootstrap(); viewer.call('profile', {'profile': 'viewer'})
    def capture(day='2021-02-15', known=None):
        return viewer.call('date-schedules/context', {'effectiveOn': day, 'knownAt': known, 'mode': 'current' if known is None else 'at'})
    def resolve(ctx):
        return viewer.call('date-schedules/resolve', {'expression': 'oe.temporal', 'context': ctx})
    def instant(value): return datetime.fromisoformat(re.sub(r'\.(\d+)(?=[Z+-])', lambda match: '.'+(match.group(1)+'000000')[:6], value).replace('Z', '+00:00'))
    before = capture()['context']
    definition = {'name': 'Temporal monthly dates', 'symbol': 'oe.temporal', 'firstMonth': '2021-01', 'lastMonth': '2021-04',
                  'anchor': 'day', 'day': 1, 'shortMonth': 'reject', 'adjustment': 'unadjusted',
                  'calendar': None}
    calendar = next(c['reference'] for c in viewer.call('date-schedules')['calendars'] if c['reference']['code'] == 'test_business')
    save = {'definition': definition, 'calendar': calendar, 'selection': 'context_month', 'effectiveFrom': '2021-01-01', 'effectiveTo': '2021-05-01'}
    draft = editor.call('date-schedules/save', save)
    approver.call('date-schedules/publish', {k: draft[k] for k in ['id', 'version', 'generation']})
    first_snapshot = capture()
    first = resolve(first_snapshot['context'])
    check('knowledge context is retained with exact coordinates and certified coverage', first_snapshot['context']['contextId'] and first_snapshot['context']['knownAt'] and instant(first_snapshot['coverageFrom']) <= instant(first_snapshot['context']['knownAt']) <= instant(first_snapshot['certifiedThrough']))
    check('time-based resolution retains half-open temporal bounds', first['date'] == '2021-02-01' and instant(first['source']['temporal']['knownFrom']) <= instant(first_snapshot['context']['knownAt']))
    missing = viewer.call('date-schedules/resolve', {'expression': 'oe.temporal', 'context': before}, expected=422)
    check('earlier known context excludes later publication', missing['code'] == 'schedule_unpublished')
    boundary = first['source']['temporal']['knownFrom']
    check('commit boundary includes publication exactly at known_from', resolve(capture(known=boundary)['context'])['date'] == '2021-02-01')
    just_before = (instant(boundary) - timedelta(microseconds=1)).isoformat()
    viewer.call('date-schedules/resolve', {'expression': 'oe.temporal', 'context': capture(known=just_before)['context']}, expected=422)
    check('one microsecond before commit boundary excludes publication')
    revised = editor.call('date-schedules/save', {**save, 'id': draft['id'], 'version': 1, 'generation': draft['generation'], 'expectedState': 'published',
        'definition': {**definition, 'name': 'February correction', 'day': 2}, 'effectiveFrom': '2021-02-01', 'effectiveTo': '2021-03-01'})
    approver.call('date-schedules/publish', {k: revised[k] for k in ['id', 'version', 'generation']})
    current = capture()['context']
    corrected = resolve(current)
    check('backdated correction changes the newer knowledge view', corrected['date'] == '2021-02-02' and corrected['source']['version'] == 2)
    check('retained historical context and receipt replay exactly after correction', resolve(first_snapshot['context']) == first)
    check('partial correction preserves January outside corrected effective interval', resolve(capture('2021-01-15')['context'])['date'] == '2021-01-01')
    check('partial correction preserves March at excluded effective boundary', resolve(capture('2021-03-01')['context'])['date'] == '2021-03-01')
    check('context capture at identical coordinates reuses immutable receipt', capture(known=first_snapshot['context']['knownAt'])['context'] == first_snapshot['context'])
    for changes in [{'effectiveOn': '2021-03-15'}, {'knownThrough': 0}, {'knownAt': before['knownAt']}]:
        result = viewer.call('date-schedules/resolve', {'expression': 'oe.temporal', 'context': {**current, **changes}}, expected=422)
        check('a retained context cannot be reinterpreted: ' + next(iter(changes)), result['code'] == 'temporal_context')
    for day, known in [('2021-01-15', '2020-01-01T00:00:00Z'), ('2021-01-15', '2099-01-01T00:00:00Z')]:
        error = viewer.call('date-schedules/context', {'effectiveOn': day, 'knownAt': known, 'mode': 'at'}, expected=422)
        check('unverifiable knowledge date has no current fallback', error['code'] == 'knowledge_coverage')
    error = viewer.call('date-schedules/context', {'effectiveOn': '2021-01-15', 'knownAt': '2026-10-17T01:02:03.1234567Z', 'mode': 'at'}, expected=422)
    check('unrepresentable knowledge precision is rejected rather than rounded', error['code'] == 'temporal_precision')
    for body in [{'effectiveOn': '2021-01-15'}, {'effectiveOn': '2021-01-15', 'mode': 'current', 'knownAt': boundary}, {'effectiveOn': '2021-01-15', 'mode': 'at'}]:
        viewer.call('date-schedules/context', body, expected=422)
        check('knowledge capture mode is explicit')
    candidate = {'code': 'temporal_contracts', 'name': 'Historical contract dates', 'context': first_snapshot['context'],
        'contracts': [{'label': 'February', 'start': 'oe.temporal', 'end': 'oe.temporal[1]', 'lastTrading': 'oe.temporal - 3bd', 'cutoffUtc': '15:30'}]}
    historical = viewer.call('date-schedules/contracts/preview', candidate)
    check('one exact temporal context flows through all contract date fields', historical['contracts'][0]['start'] == '2021-02-01' and historical['contracts'][0]['startReference']['source']['context'] == historical['contracts'][0]['endReference']['source']['context'] == first_snapshot['context'])
    check('a later contract date view reflects the partial correction', viewer.call('date-schedules/contracts/preview', {**candidate, 'context': current})['contracts'][0]['start'] == '2021-02-02')
    editor.call('date-schedules/publish', {k: revised[k] for k in ['id', 'version', 'generation']}, expected=403)
    viewer.call('date-schedules/save', save, expected=403)
    check('temporal context does not grant editing or publishing permission')
