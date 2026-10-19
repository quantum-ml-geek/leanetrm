"""Authorized, exact-snapshot date availability for the header calendar."""
from copy import deepcopy
from uuid import uuid4
from preview_client import PreviewClient


def run_checks(url,query=None,manifest=None):
    client=PreviewClient(url);boot=client.bootstrap()
    client.call('market/dates',{'curve':'ng_monthly','timeZone':'UTC'},expected=403)
    client.call('profile',{'profile':'viewer'})
    client.call('market/dates',{'timeZone':'UTC'},expected=400)
    client.call('market/dates',{'curve':None},expected=400)
    monthly=client.call('market/dates',{'curve':'ng_monthly','timeZone':'UTC'})
    assert monthly['selectionPolicy']=='exact_snapshot_no_close_substitution_v1'
    month_days={row['date']:row['frames'] for row in monthly['dates']}
    assert '2020-12-11' in month_days
    bridge=client.call('market/dates',{'curve':'bridge_basis','timeZone':'UTC'})
    assert {row['date'] for row in bridge['dates']}=={'2020-12-15','2020-12-16','2020-12-17','2020-12-18'}
    assert '2020-12-11' not in {row['date'] for row in bridge['dates']}
    tokyo=client.call('market/dates',{'curve':'ng_monthly','timeZone':'Asia/Tokyo'})
    shifted=next(row for row in tokyo['dates'] if row['date']=='2020-12-12')['frames']
    assert all(row['businessDateUTC']=='2020-12-11' and row['at'].startswith('2020-12-11T16:00:00') for row in shifted)
    assert {row['id'] for day in monthly['dates'] for row in day['frames']}=={row['id'] for day in tokyo['dates'] for row in day['frames']}
    known={row['id'] for row in boot['frames']}
    workspace=client.call('market/dates',{'curve':None,'timeZone':'UTC'})
    assert {row['id'] for day in workspace['dates'] for row in day['frames']}<=known
    client.call('market/dates',{'curve':'missing_curve','timeZone':'UTC'},expected=422)
    client.call('market/dates',{'curve':'ng_monthly','timeZone':'Not/AZone'},expected=422)
    templates={row['code']:row for row in client.call('custom-curves')['templates']}
    client.call('market/dates',{'definition':templates['ng_prompt']['definition'],'timeZone':'UTC'},expected=400)
    average=client.call('market/dates',{'curve':None,'definition':templates['ng_average']['definition'],'timeZone':'UTC'})
    assert '2020-11-18' not in {row['date'] for row in average['dates']}
    assert '2020-12-18' in {row['date'] for row in average['dates']}
    frozen=deepcopy(templates['ng_prompt']['definition'])
    next(node for node in frozen['nodes'] if node['kind']=='source')['parameters']['curve']='ng_fixed_location'
    frozen_dates=client.call('market/dates',{'curve':None,'definition':frozen,'timeZone':'UTC'})
    assert '2020-12-18' in {row['date'] for row in frozen_dates['dates']}
    assert '2020-12-17' not in {row['date'] for row in frozen_dates['dates']}
    incomplete_window=deepcopy(templates['ng_average']['definition'])
    next(node for node in incomplete_window['nodes'] if node['kind']=='dates')['parameters']['count']='100'
    no_dates=client.call('market/dates',{'curve':None,'definition':incomplete_window,'timeZone':'UTC'})
    assert no_dates['dates']==[] and no_dates['minDate'] is None and no_dates['maxDate'] is None
    invalid=deepcopy(templates['ng_average']['definition']);invalid['nodes'][-1]['inputs']={}
    client.call('market/dates',{'curve':None,'definition':invalid,'timeZone':'UTC'},expected=422)
    client.call('market/dates',{'curve':'ng_monthly','definition':templates['ng_prompt']['definition'],'timeZone':'UTC'},expected=422)
    # A retained knowledge view can only expose frames on its exact effective day.
    captured=client.call('market/context',{'effectiveOn':'2020-12-18','knownAt':None,'mode':'current','selection':'latest_correction'})
    historical=client.call('market/dates',{'curve':'ng_monthly','timeZone':'UTC'})
    assert historical['context']['contextId']==captured['context']['contextId']
    assert {row['date'] for row in historical['dates']}=={'2020-12-18'}
    assert all(row['businessDateUTC']=='2020-12-18' for day in historical['dates'] for row in day['frames'])
    if query and manifest:
        scope=manifest['referenceCatalogId']
        deleted=query(f"DELETE FROM security.reference_catalog_scopes WHERE catalog_id='{scope}' RETURNING tenant_id,workspace_id,access_mode;")
        try:client.call('market/dates',{'curve':'ng_monthly','timeZone':'UTC'},expected=403)
        finally:
            tenant,workspace,access=deleted.split('|')
            query(f"INSERT INTO security.reference_catalog_scopes VALUES('{scope}','{tenant}','{workspace}','{access}');")
    client.call('market/current',{})
    client.call('profile',{'profile':'editor'})
    frame=next(row for row in boot['frames'] if row['at'].startswith('2020-12-18T16:00:00'))
    observations=client.call('workspace')['observations']
    chosen=next(row for row in observations if row['id'] in frame['observationIds'] and row['role']=='daily_settlement')
    changed=client.call('corrections',{'snapshotId':frame['id'],'observationId':chosen['id'],'value':chosen['value']})['frame']
    duplicate=client.call('market/dates',{'curve':'ng_monthly','timeZone':'UTC'})
    closes=next(row for row in duplicate['dates'] if row['date']=='2020-12-18')['frames']
    assert {frame['id'],changed['id']}<={row['id'] for row in closes}
    print('PASS market calendar availability: exact curve dependencies, complete recipe windows, user-zone days, explicit duplicate snapshots, certified context and current reference authority',flush=True)
