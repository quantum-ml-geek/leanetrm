"""Exercise job ownership through authenticated HTTP and the RLS boundary."""
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from preview_client import PreviewClient


def prepare(query,manifest):
    # This projection is synthetic. No Docker or host connection is configured.
    tenant,workspace=manifest['tenantId'],manifest['workspaceId']
    worker=str(uuid4())
    query(f"""CREATE ROLE jobs_fixture_worker LOGIN IN ROLE openetrm_scheduler;
    INSERT INTO security.principals VALUES('{worker}','service',true);
    INSERT INTO security.workspace_memberships VALUES('{tenant}','{workspace}','{worker}','jobs_fixture_worker','Synthetic infrastructure observer',true,1);
    INSERT INTO security.role_grants SELECT gen_random_uuid(),'{worker}',id,'{tenant}','{workspace}',clock_timestamp(),'9999-12-31',false FROM security.roles WHERE code='viewer';
    INSERT INTO automation.workers VALUES('jobs_fixture_worker','{worker}','{tenant}','{workspace}','controller');
    INSERT INTO automation.clusters VALUES('syntheticcluster00000000001','Synthetic cluster','jobs_fixture_worker','{tenant}','{workspace}',true);
    INSERT INTO security.role_permissions SELECT id,'ManageInfrastructure' FROM security.roles WHERE code='access_administrator';
    INSERT INTO automation.installation_operators SELECT principal_id,'ManageInfrastructure',clock_timestamp()+interval '1 hour' FROM security.workspace_memberships WHERE(tenant_id,workspace_id,login_handle)=('{tenant}','{workspace}','admin');
    SET SESSION AUTHORIZATION jobs_fixture_worker;
    SELECT automation.observe_nodes('syntheticcluster00000000001','[{{"id":"syntheticnode0000000000001","version":7,"name":"Synthetic shared worker","role":"worker","state":"ready","availability":"active","cpuNano":1000000000,"memoryBytes":1073741824,"workloadNode":true}}]'::jsonb);""")


def run_checks(url,query=None):
    client = PreviewClient(url)
    client.bootstrap()
    client.call('profile', {'profile': 'viewer'})
    if query is not None:
        # Job-only members can resolve their own wall clocks without market access.
        query("DELETE FROM security.role_permissions WHERE permission='ReadMarketData' AND role_id=(SELECT id FROM security.roles WHERE code='viewer');")
        try:
            assert 'ReadMarketData' not in client.call('access')['permissions']
            candidates=client.call('time/inspect',{'localTime':'2040-01-02T08:30:00','timeZone':'Asia/Tokyo'})['candidates']
            assert len(candidates)==1 and candidates[0]['instant'].startswith('2040-01-01T23:30:00')
        finally:
            query("INSERT INTO security.role_permissions SELECT id,'ReadMarketData' FROM security.roles WHERE code='viewer';")
    now = datetime.now(timezone.utc)
    body = dict(requestId=str(uuid4()),name='Synthetic HTTP readiness',operation='worker_check',
                dueAt=(now+timedelta(minutes=1)).isoformat(),expiresAt=(now+timedelta(hours=1)).isoformat(),
                intervalSeconds=None,timeZone='UTC',misfire='run_once',overlap='forbid',
                timeoutSeconds=30,maximumAttempts=2,profileId=None,profileVersion=None)
    job = client.call('jobs/create', body)
    assert client.call('jobs/create', body)['id'] == job['id']
    client.call('jobs/create', {**body,'name':'Changed replay'},expected=409)
    client.call('jobs/create', {**body,'ownerId':str(uuid4())},expected=400)
    directory=client.call('jobs')
    assert any(j['id']==job['id'] for j in directory['jobs'])
    assert directory['infrastructure']['nodes'][0]['actions']==[]
    client.call('infrastructure/availability',dict(requestId=str(uuid4()),clusterId='syntheticcluster00000000001',nodeId='syntheticnode0000000000001',expectedVersion=7,availability='pause'),expected=403)
    client.call('profile', {'profile':'editor'})
    assert not any(j['id']==job['id'] for j in client.call('jobs')['jobs'])
    control = dict(requestId=str(uuid4()),id=job['id'],action='pause',expectedVersion=job['version'])
    client.call('jobs/control',control,expected=403)
    client.call('profile',{'profile':'admin'})
    paused = client.call('jobs/control',control)
    assert paused['state']=='paused'
    client.call('profile',{'profile':'viewer'})
    resumed=client.call('jobs/control',{**control,'requestId':str(uuid4()),'action':'resume','expectedVersion':paused['version']})
    assert resumed['state']=='active'
    cancelled=client.call('jobs/control',{**control,'requestId':str(uuid4()),'action':'cancel','expectedVersion':resumed['version']})
    assert cancelled['state']=='cancelled'
    print('PASS HTTP job creation, idempotency, owner isolation, administrator control and cancellation',flush=True)
