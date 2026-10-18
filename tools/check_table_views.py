"""Account-owned table layouts against a disposable synthetic preview."""
from uuid import uuid4
from preview_client import PreviewClient


def run_checks(url):
    passed = 0
    def check(name, condition=True):
        nonlocal passed
        assert condition, name
        passed += 1
        print('PASS ' + name, flush=True)
    def client(profile):
        c = PreviewClient(url); c.bootstrap(); c.call('profile', {'profile': profile}); return c
    trader = client('trader'); other_browser = client('trader'); viewer = client('viewer')
    layout = dict(version=1, name='Account view', mode='trades', columns=['book','quantity','unit'],
                  bookIds=[], portfolioIds=[], groupBy=[], measures=[], query='Jan', columnFilters={})
    check('account starts without saved layouts', trader.call('table-views/blotter') == [])
    saved = trader.call('table-views/blotter', {'layout': layout, 'expectedVersion': None})
    check('layout follows account into a separate browser session', other_browser.call('table-views/blotter') == [saved])
    trader.call('table-views/blotter', {'layout': {**layout, 'snapshotId': str(uuid4())}, 'expectedVersion': saved['version']}, expected=422)
    trader.call('table-views/blotter', {'layout': layout, 'expectedVersion': None}, expected=409)
    changed = trader.call('table-views/blotter', {'layout': {**layout,'query':'Feb'}, 'expectedVersion': saved['version']})
    other_browser.call('table-views/blotter', {'layout': layout, 'expectedVersion': saved['version']}, expected=409)
    other_browser.call('table-views/blotter/delete', {'name': layout['name'], 'expectedVersion': saved['version']}, expected=409)
    check('stale saves and deletes cannot overwrite a newer layout', other_browser.call('table-views/blotter') == [changed])
    viewer.call('table-views/blotter', expected=403)
    viewer.call('table-views/blotter', {'layout': layout,'expectedVersion':None}, expected=403)
    check('market-only identity cannot read or change trading layouts')
    admin = client('admin')
    member = admin.call('admin/create', dict(operationId=str(uuid4()),login='layout_other',name='Synthetic layout user',kind='human',roles=['trader']))
    admin.call('profile', {'profile':'layout_other'})
    check('another trader has an independent layout namespace', admin.call('table-views/blotter') == [])
    admin.call('table-views/blotter/delete', {'name':layout['name'],'expectedVersion':changed['version']}, expected=409)
    own = admin.call('table-views/blotter', {'layout':layout,'expectedVersion':None})
    check('same layout name belongs independently to each account',own['version'] != changed['version'] and trader.call('table-views/blotter') == [changed])
    control = client('admin')
    disabled = control.call('admin/update',dict(operationId=str(uuid4()),id=member['id'],expectedVersion=member['version'],name=member['name'],enabled=False,roles=['trader']))
    admin.call('table-views/blotter', expected=403)
    admin.call('table-views/blotter', {'layout':layout,'expectedVersion':own['version']}, expected=403)
    check('current revocation blocks saved-layout reads and writes')
    control.call('admin/update',dict(operationId=str(uuid4()),id=member['id'],expectedVersion=disabled['version'],name=member['name'],enabled=True,roles=['trader']))
    check('restored account retains its own layout',admin.call('table-views/blotter') == [own])
    trader.call('table-views/blotter/delete', {'name':layout['name'],'expectedVersion':changed['version']})
    check('deleting a layout removes it across sessions', other_browser.call('table-views/blotter') == [])
    print(f'{passed} account table-layout checks passed.', flush=True)
