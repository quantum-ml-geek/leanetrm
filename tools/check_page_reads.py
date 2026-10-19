"""Bounded page-read checks for an owned synthetic preview."""


def run_checks(c, check):
    c.call('profile', {'profile': 'viewer'})
    catalog = c.call('workspace/catalog')
    full = c.call('workspace')
    check('navigation catalog omits observation history explicitly',
          catalog['observationScope'] == 'on_demand' and catalog['observations'] == [])
    check('navigation preserves exact definitions, references and input frames',
          all(catalog[k] == full[k] for k in ['definitions', 'references', 'frames', 'initialFrameIds']))
    unit_tables = {'dimensions', 'units', 'unit_conversions', 'commodities',
                   'measurement_bases', 'quantity_specifications'}
    check('unit conversion catalog contains only its consumed reference tables',
          set(catalog['unitCatalog']['references']) == unit_tables)

    frame = next(f for f in full['frames'] if f['at'].startswith('2020-12-18'))
    by_id = {o['id']: o for o in full['observations']}
    fact_fields = ('series_id', 'source_code', 'source_event_id', 'observed_at', 'role')

    def fact(row):
        return tuple(row[k] for k in fact_fields)

    facts = {fact(by_id[i]) for i in frame['observationIds']}
    expected = {o['id'] for o in full['observations'] if fact(o) in facts}
    check('read fixture distinguishes selected facts from unrelated history',
          expected and len(expected) < len(full['observations']))
    for curve in ['local_power', 'interest_rates']:
        body = {'snapshotId': frame['id'], 'curve': curve}
        ordinary = c.call('evaluate', body)
        sources = c.call('evaluate', {**body, 'includeSources': True})
        observations = sources.pop('observations')
        check('price sources have the explicit selected-frame scope: ' + curve,
              sources.pop('observationScope') == 'selected_frame')
        check('source loading preserves exact prices and provenance: ' + curve,
              sources == ordinary)
        ids = [o['id'] for o in observations]
        check('price sources contain all same-fact versions without unrelated rows: ' + curve,
              set(ids) == expected and len(ids) == len(set(ids))
              and all(by_id[o['id']] == o for o in observations))
        check('every selected price lineage has its authorized source: ' + curve,
              all(set(p['lineage']) <= set(ids) for p in sources['points']))

    # A different context must not retain the preceding response's rows.
    earlier = min(full['frames'], key=lambda f: f['at'])
    other = c.call('evaluate', {'snapshotId': earlier['id'], 'curve': 'local_power',
                              'includeSources': True})
    earlier_facts = {fact(by_id[i]) for i in earlier['observationIds']}
    check('price sources are replaced for the requested historical input frame',
          {o['id'] for o in other['observations']} ==
          {o['id'] for o in full['observations'] if fact(o) in earlier_facts})
    c.call('profile', {'profile': 'admin'})
    c.call('workspace/catalog', expected=403)
    c.call('evaluate', {'snapshotId': frame['id'], 'curve': 'local_power',
                        'includeSources': True}, expected=403)
    check('navigation and on-demand sources recheck current business authority')
