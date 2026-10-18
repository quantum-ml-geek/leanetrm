"""Workspace administration behavior; only run in the owned preview check suite."""
from uuid import uuid4


def run_checks(Client, check):
    viewer = Client(); viewer.bootstrap(); viewer.call('profile', {'profile': 'viewer'})
    viewer.call('admin', expected=403)
    check('business readers cannot enumerate identities or permissions')
    admin = Client(); admin.bootstrap(); admin.call('profile', {'profile': 'admin'})
    directory = admin.call('admin')
    check('identity kinds are served with the directory', [k['code'] for k in directory['kinds']] == ['human', 'service', 'agent'] and all(k['name'] for k in directory['kinds']))
    admin.call('workspace', expected=403)
    check('access administration does not imply market-data access', len(directory['roles']) == 6)
    check('role choices carry stored display names', all(isinstance(r.get('name'), str) and r['name'].strip() for r in directory['roles']) and len({r['name'] for r in directory['roles']}) == 6)
    request = {'operationId': str(uuid4()), 'login': 'synthetic_reader', 'name': 'Synthetic reader',
               'kind': 'human', 'roles': ['viewer']}
    created = admin.call('admin/create', request)
    check('admin creates a named workspace member with explicit roles', created['name'] == request['name'] and created['roles'] == ['viewer'])
    check('retrying the exact administrative command is idempotent', admin.call('admin/create', request) == created)
    admin.call('admin/create', {**request, 'name': 'Different payload'}, expected=409)
    check('operation identity cannot be reused for another payload')
    admin.call('profile', {'profile': request['login']})
    inputs = admin.call('workspace'); frame = inputs['frames'][0]
    check('new human preview identity uses persisted permissions', inputs['profile'] == request['login'])
    admin.call('admin', expected=403)
    admin.call('profile', {'profile': 'admin'})
    update = {'operationId': str(uuid4()), 'id': created['id'], 'expectedVersion': created['version'],
              'name': 'Synthetic reader renamed', 'enabled': False, 'roles': ['viewer']}
    disabled = admin.call('admin/update', update)
    check('workspace access can be suspended without deleting history', not disabled['enabled'] and disabled['version'] == created['version'] + 1)
    admin.call('admin/update', {**update, 'operationId': str(uuid4())}, expected=409)
    admin.call('profile', {'profile': request['login']})
    admin.call('evaluate', {'snapshotId': frame['id'], 'curve': 'local_power'}, expected=403)
    check('suspension blocks replay of retained market inputs')
    admin.call('profile', {'profile': 'admin'})
    restored = admin.call('admin/update', {**update, 'operationId': str(uuid4()), 'expectedVersion': disabled['version'], 'enabled': True})
    admin.call('profile', {'profile': request['login']})
    check('restoration uses unchanged historical market pins', bool(admin.call('evaluate', {'snapshotId': frame['id'], 'curve': 'local_power'})['points']))
    admin.call('profile', {'profile': 'admin'})
    own = next(m for m in admin.call('admin')['members'] if m['login'] == 'admin')
    error = admin.call('admin/update', {'operationId': str(uuid4()), 'id': own['id'], 'expectedVersion': own['version'],
        'name': own['name'], 'enabled': False, 'roles': own['roles']}, expected=422)
    check('last current workspace administrator cannot be removed', error['code'] == 'last_administrator')
    agent = admin.call('admin/create', {**request, 'operationId': str(uuid4()), 'login': 'synthetic_agent', 'name': 'Synthetic agent', 'kind': 'agent'})
    check('agents have distinct immutable identity kinds', agent['kind'] == 'agent')
    admin.call('profile', {'profile': 'synthetic_agent'}, expected=403)
    check('agent grants cannot become a human preview login')
    audit = admin.call('admin')['audit']
    check('committed administration has actor and before-after evidence', any(a['operationId'] == update['operationId'] and a['before']['enabled'] and not a['after']['enabled'] for a in audit))
    check('administrative retry produces one audit entry', sum(a['operationId'] == request['operationId'] for a in audit) == 1)
