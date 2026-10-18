"""Authored TOU product checks; only invoked against the runner's newly owned fixture."""

SEEDED = {'pjm', 'nyiso', 'isone', 'miso', 'spp', 'ercot', 'caiso'}


def run_checks(Client, check):
    viewer = Client(); viewer.bootstrap(); viewer.call('profile', {'profile': 'viewer'})
    editor = Client(); editor.bootstrap(); editor.call('profile', {'profile': 'editor'})
    approver = Client(); approver.bootstrap(); approver.call('profile', {'profile': 'approver'})
    admin = Client(); admin.bootstrap(); admin.call('profile', {'profile': 'admin'})
    library = viewer.call('tou-products')
    check('the usual ISO peak definitions start as published TOU products',
          {v['code'] for v in library['versions']} == SEEDED and all(v['state'] == 'published' for v in library['versions']))
    pjm = next(v for v in library['versions'] if v['code'] == 'pjm')
    caiso = next(v for v in library['versions'] if v['code'] == 'caiso')
    check('seeded products keep exact clocks and peak windows',
          (pjm['peakStartHour'], pjm['peakEndHour'], pjm['peakSaturday']) == (7, 23, False)
          and (caiso['peakStartHour'], caiso['peakEndHour'], caiso['peakSaturday']) == (6, 22, True)
          and {c['reference']['code'] for c in library['clocks']} >= {pjm['clock']['code'], caiso['clock']['code']})
    check('readers cannot author TOU products', not library['canEdit'] and not library['canPublish'])
    clock = pjm['clock']
    frame = viewer.call('workspace')['frames'][0]
    catalog = viewer.call('power/catalog', {'snapshotId': frame['id']})
    check('the power calculation offers exactly the published products', {p['code'] for p in catalog['products']} == SEEDED)
    draft_body = {'code': 'synthetic_peak', 'name': 'Synthetic weekday peak', 'clock': clock,
                  'peakStartHour': 8, 'peakEndHour': 20, 'peakSaturday': False}
    viewer.call('tou-products/save', draft_body, expected=403)
    check('readers cannot save TOU products')
    for changed, code in [({**draft_body, 'peakStartHour': 20}, 'tou_definition'), ({**draft_body, 'peakEndHour': 25}, 'tou_definition'),
                          ({**draft_body, 'name': ' '}, 'tou_definition'), ({**draft_body, 'code': 'Bad Code'}, 'tou_definition'),
                          ({**draft_body, 'clock': {**clock, 'code': 'absent_clock'}}, 'clock_reference'),
                          ({**draft_body, 'clock': {**clock, 'revisionId': '00000000-0000-0000-0000-000000000000'}}, 'clock_reference'),
                          ({**draft_body, 'code': 'pjm'}, 'tou_conflict')]:
        error = editor.call('tou-products/save', changed, expected=422 if code != 'tou_conflict' else 409)
        check('invalid TOU product definitions are rejected: ' + code, error['code'] == code)
    draft = editor.call('tou-products/save', draft_body)
    check('an editor saves a TOU product draft', draft['state'] == 'draft' and draft['version'] == 1 and draft['clock'] == clock)
    check('drafts stay out of readers and the power calculation',
          all(v['code'] != 'synthetic_peak' for v in viewer.call('tou-products')['versions'])
          and all(p['code'] != 'synthetic_peak' for p in viewer.call('power/catalog', {'snapshotId': frame['id']})['products']))
    renamed = editor.call('tou-products/save', {**draft_body, 'id': draft['id'], 'version': 1, 'generation': draft['generation'], 'expectedState': 'draft', 'name': 'Synthetic day peak'})
    editor.call('tou-products/save', {**draft_body, 'id': draft['id'], 'version': 1, 'generation': draft['generation'], 'expectedState': 'draft'}, expected=409)
    check('stale draft saves cannot overwrite newer edits', renamed['generation'] == draft['generation'] + 1)
    publish = {'id': renamed['id'], 'version': 1, 'generation': renamed['generation']}
    editor.call('tou-products/publish', publish, expected=403)
    check('editors cannot publish TOU products')
    published = approver.call('tou-products/publish', publish)
    check('approvers publish, and the product joins the power calculation', published['state'] == 'published'
          and any(p['code'] == 'synthetic_peak' and p['name'] == 'Synthetic day peak' for p in viewer.call('power/catalog', {'snapshotId': frame['id']})['products']))
    check('repeat publication is idempotent', approver.call('tou-products/publish', publish) == published)
    following = editor.call('tou-products/save', {**draft_body, 'id': published['id'], 'version': 1, 'generation': published['generation'], 'expectedState': 'published', 'name': 'Synthetic day peak', 'peakEndHour': 21})
    check('editing a published product creates the next draft and leaves the published one in use',
          following['version'] == 2 and following['state'] == 'draft'
          and next(p for p in viewer.call('power/catalog', {'snapshotId': frame['id']})['products'] if p['code'] == 'synthetic_peak')['version'] == 1)
    stale = {'snapshotId': frame['id'], 'curve': 'local_power_all_in', 'contractId': viewer.call('power/catalog', {'snapshotId': frame['id']})['curves'][0]['contracts'][0]['id'],
             'product': 'pjm', 'productVersion': 2, 'block': 'all', 'minutes': 60, 'hourLabels': 'HE', 'megawatts': '10', 'priceType': 'Test', 'timing': 'End of day',
             'nonHolidays': '1' * 168, 'holidays': '1' * 168, 'numericalPolicy': catalog['numericalPolicy']}
    error = viewer.call('power/preview', stale, expected=409)
    check('a power check built from another product version is rejected, never re-evaluated under the newer one', error['code'] == 'tou_conflict')
    admin.call('tou-products', expected=403)
    check('access administration does not grant TOU product reads')
    editor.call('market/context', {'effectiveOn': '2020-12-17', 'knownAt': None, 'mode': 'current', 'selection': 'latest_correction'})
    error = editor.call('tou-products', expected=422)
    check('a historical market view never substitutes current TOU products', error['code'] == 'power_historical')
    editor.call('market/current', {})
