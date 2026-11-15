"""Shared asynchronous workbench reads in the launcher-owned synthetic database."""
import http.client
import json
import time
from urllib.parse import urlsplit
from uuid import uuid4
from assistant_context import holding
from preview_client import PreviewClient, initial_frame
from copy import deepcopy

PROTOCOL = 'async_reads_v1'


def financial_response(operation,value):
    """Graph execution counts measure this run; retained financial results do not."""
    if operation!='portfolio.risk.calculate.v1':return value
    copy=deepcopy(value)
    for work,key in [(copy['work'],'curveGraphEvaluatedNodes'),
                     *[(scenario['work'],'evaluatedNodes') for scenario in copy.get('connectedScenarios',[])]]:
        assert isinstance(work[key],int) and work[key]>=0, 'Invalid graph execution telemetry'
        del work[key]
    return copy


class Stream:
    def __init__(self, client, channel, headers=None):
        address = urlsplit(client.url)
        self.connection = http.client.HTTPConnection(address.hostname, address.port, timeout=15)
        self.connection.request('GET', client.api_prefix + 'async-reads/events?channelId=' + channel, headers={
            'Accept': 'text/event-stream', 'Sec-Fetch-Site': 'same-origin', 'Sec-Fetch-Mode': 'cors',
            'Cookie': '; '.join(f'{c.name}={c.value}' for c in client.jar), **(headers or {})})
        self.response = self.connection.getresponse()

    def event(self, kind):
        while True:
            fields = {}
            while True:
                line = self.response.readline()
                if not line:
                    return None
                line = line.decode().rstrip('\r\n')
                if not line:
                    break
                if not line.startswith(':'):
                    key, _, value = line.partition(':')
                    fields[key] = value.lstrip()
            if fields.get('event') == kind:
                return json.loads(fields['data'])

    def close(self):
        self.response.close()
        self.connection.close()



def run_checks(url, query, psql, environment, manifest):
    passed = 0
    def check(name, condition=True):
        nonlocal passed
        assert condition, name
        passed += 1
        print('PASS async workbench: '+name, flush=True)

    c = PreviewClient(url); boot = c.bootstrap(); c.call('profile', {'profile': 'risk'})
    client_id=str(uuid4())
    opened = c.call('async-reads/channels', {'clientId':client_id})
    working=c.call('workspace/catalog')
    frame = initial_frame(working, '2020-12-18')
    current = {'snapshotId': frame['id'], 'convention': 'trading_workspace_v1', 'knowledgeMode': 'current'}
    view = {'mode': 'trades', 'bookIds': [], 'portfolioIds': [], 'groupBy': [], 'measures': [], 'pivotConvention': None}
    blotter = c.call('trading/blotter', {'context': current, 'view': view})
    context = {**current, 'knowledgeMode': 'retained', 'contextId': blotter['context']['contextId']}
    scope = {'context': context, 'bookIds': [], 'portfolioIds': []}
    catalog = c.call('portfolio/risk/catalog', scope)
    factor = next(f for f in catalog['factors'] if 'future' in f['curves'])
    risk = {**scope, 'convention': catalog['convention'], 'numericalPolicy': catalog['numericalPolicy'],
            'pricingPolicy': catalog['pricingPolicy'], 'detail': 'books', 'stress': [],
            'bumps': [{'factor': factor['factor'], 'size': '0.1', 'convention': catalog['bumpConvention']}]}
    command={'requestId':str(uuid4()),'request':risk}
    retained_job=c.call('portfolio/risk/jobs',command)
    replayed=c.call('portfolio/risk/jobs',command)
    check('ordinary retained job submission keeps its idempotent HTTP outcome',retained_job['id']==replayed['id'])
    held = next(h for h in blotter['holdings'] if h['instrumentType']=='future')
    swap = next(h for h in blotter['holdings'] if h['instrumentType']=='financial_swap')
    single = {**scope, 'bookIds':[held['bookId']], 'tradeIds':[held['tradeId']]}
    one = c.call('portfolio/risk/catalog', single)
    history_body = {'scope': single, 'pricingPolicy': one['pricingPolicy'],
        'policy': {**one['history']['profile'], 'minimumSamples': 2},
        'calendar': {'revision': {'catalogId': manifest['referenceCatalogId'], 'revisionId': manifest['referenceRevisionId']}, 'code': 'weekdays_utc'},
        'from':'2020-12-15','to':'2020-12-19','closeTime':'16:00:00','ambiguousTime':'reject','invalidTime':'reject'}
    history = c.call('portfolio/risk/history', history_body)
    parametric = {'history':history['request'], 'policy':{**one['parametric']['profile'],'drift':one['parametric']['drifts']['zero'],'confidence':'0.99'},
        'finiteDifference':{'convention':one['parametric']['finiteDifference'],'tradingTicks':1,'deltaTolerance':{'absolute':'0','relative':'0'}}}
    curve = {'snapshotId':frame['id'], 'curve':'local_power', 'includeSources':True, 'includeWorkspace':True,
             'contractDisplay':{'version':'curve_display_v1','contracts':'eligible_contracts_v1'}}
    curve_points=c.call('evaluate',curve)['points']
    cases = [
        ('curve.evaluate.v1','evaluate',curve),
        ('curve.history.v1','history',{'snapshotId':frame['id'],'curve':'local_power','contractId':curve_points[0]['contractId'],'revisionPolicy':'exact_snapshot_pins_v1'}),
        ('curve.shapes.v1','market/curve-shapes',{'snapshotId':frame['id'],'curves':['future','local_power'],'contractDisplay':curve['contractDisplay']}),
        ('trading.directory.v1','trading/directory',context),
        ('trading.positions.v1','trading/positions',{'context':context,'bookIds':[],'portfolioIds':[],'offset':0,'limit':64}),
        ('trading.position.v1','trading/position',{'context':context,'tradeId':held['tradeId'],'bindingId':held['bindingId'],'revision':int(held['revision']),'instrumentType':'future'}),
        ('futures.editor.v1','futures/editor',{'context':{**context,'convention':working['futuresConvention']},'tradeId':held['tradeId'],'revision':int(held['revision'])}),
        ('swaps.editor.v1','swaps/editor',{'context':{**context,'convention':'independent_side_financial_swap_v2'},'tradeId':swap['tradeId'],'revision':int(swap['revision'])}),
        ('trading.workspace.v1','trading/workspace',{'context':context,'view':view,'summaries':[],'bookingCatalog':'directory'}),
        ('trading.blotter.v1','trading/blotter',{'context':context,'view':view}),
        ('portfolio.risk.catalog.v1','portfolio/risk/catalog',scope),
        ('portfolio.risk.calculate.v1','portfolio/risk',risk),
        ('portfolio.risk.jobs.list.v1','portfolio/risk/jobs',None),
        ('portfolio.risk.jobs.read.v1','portfolio/risk/jobs/'+retained_job['id'],None),
        ('portfolio.risk.statistical.setup.v1','portfolio/risk/statistical/setup',single),
        ('portfolio.risk.history.v1','portfolio/risk/history',history['request']),
        ('portfolio.risk.parametric.summary.v1','portfolio/risk/parametric/summary',parametric),
        ('portfolio.risk.archive.v1','portfolio/risk/statistical/archive?limit=10',None),
    ]
    expected = {operation:c.call(path,body) for operation,path,body in cases}
    check('channel states protocol and exact selected owner/context', opened['protocol']==PROTOCOL and opened['profile']=='risk' and opened['context'] is None)
    channel = opened['channelId']; stream = Stream(c,channel)
    try:
        check('SSE ready precedes read submissions',stream.response.status==200 and stream.event('ready')=={'protocol':PROTOCOL,'channelId':channel})
        def submit(operation,body,channel_id=None):
            request={'channelId':channel_id or channel,'requestId':str(uuid4()),'operation':operation,'body':body or {}}
            ack=c.call('async-reads',request,expected=202,timeout=5)
            assert ack=={'channelId':request['channelId'],'requestId':request['requestId'],'state':'accepted'}
            return request
        failures=[]
        for operation,path,body in cases:
            if operation=='portfolio.risk.archive.v1':body={'method':'statistical','limit':10,'before':None,'id':None}
            if operation=='portfolio.risk.jobs.read.v1':body={'id':retained_job['id']}
            request=submit(operation,body); reply=stream.event('response')
            assert reply is not None,path+': response stream ended'
            if reply.get('state')!='completed':
                failures.append(f"{path}: terminal response {reply.get('state')}: {reply.get('error')}")
                continue
            def differences(left,right,path='result'):
                if type(left) is not type(right):return [path+': type differs']
                if isinstance(left,dict):
                    if left.keys()!=right.keys():return [path+': keys differ '+str(sorted(left.keys()^right.keys()))]
                    return [item for key in left for item in differences(left[key],right[key],path+'.'+key)][:8]
                if isinstance(left,list):
                    if len(left)!=len(right):return [path+': length differs']
                    return [item for i,(a,b) in enumerate(zip(left,right)) for item in differences(a,b,path+f'[{i}]')][:8]
                return [] if left==right else [path+': values differ']
            actual=financial_response(operation,reply['result']); wanted=financial_response(operation,expected[operation])
            if actual!=wanted:
                failures.append(path+': '+', '.join(differences(actual,wanted)))
                continue
            check('HTTP/SSE financial and response-contract parity for '+path,reply['requestId']==request['requestId'] and reply['operation']==operation and
                  reply['state']=='completed' and actual==wanted)
        assert not failures,'; '.join(failures)
        def waiting(count):
            deadline=time.monotonic()+6
            while int(query("SELECT count(DISTINCT pid) FROM pg_locks WHERE relation='market_data.observations'::regclass AND NOT granted AND mode='AccessShareLock';"))!=count:
                assert time.monotonic()<deadline, 'Expected independent observation readers'
                time.sleep(.025)
        def blocked():
            requests=[submit('curve.evaluate.v1',curve),submit('portfolio.risk.calculate.v1',risk)]
            waiting(2);c.call('access',timeout=5)
            check('curve and Risk execute concurrently without blocking session navigation')
            c.call('async-reads',requests[0],expected=202,timeout=5)
            waiting(2)
            c.call('async-reads',{**requests[0],'body':{**curve,'curve':'future'}},expected=409)
            c.call('async-reads',{'channelId':channel,'requestId':str(uuid4()),'operation':'curve.evaluate.v1','body':curve},expected=429)
            check('duplicate work, conflicting identities and excess active work stay bounded')
            return requests
        requests=holding(psql,environment,'LOCK market_data.observations IN ACCESS EXCLUSIVE MODE',blocked)
        replies={r['requestId']:r for r in [stream.event('response'),stream.event('response')]}
        check('mixed concurrent work returns only its own exact result',all(financial_response(r['operation'],replies[r['requestId']]['result'])==financial_response(r['operation'],expected[r['operation']]) for r in requests))
        other=c.call('async-reads/channels',{'clientId':str(uuid4())})['channelId']
        other_stream=Stream(c,other)
        try:
            assert other_stream.event('ready') is not None
            def two_tabs():
                first=submit('curve.evaluate.v1',curve)
                second=submit('curve.evaluate.v1',curve,other)
                waiting(2)
                return first,second
            first,second=holding(psql,environment,'LOCK market_data.observations IN ACCESS EXCLUSIVE MODE',two_tabs)
            a,b=stream.event('response'),other_stream.event('response')
            check('separate workbench tabs share an account without cancelling each other',a['state']==b['state']=='completed' and a['requestId']==first['requestId'] and b['requestId']==second['requestId'])
            replacement=c.call('async-reads/channels',{'clientId':client_id})['channelId']
            assert stream.event('response') is None
            stream.close();channel=replacement;stream=Stream(c,channel)
            check('explicit retry replaces only its own tab response channel',stream.event('ready') is not None and other_stream.response.status==200)
            third=submit('curve.evaluate.v1',curve,other)
            check('another tab still completes after its neighbour reconnects',other_stream.event('response')['requestId']==third['requestId'])
        finally:
            other_stream.close()
        for operation in ['futures.book','portfolio.risk.jobs.submit.v1','arbitrary.route.v1']:
            c.call('async-reads',{'channelId':channel,'requestId':str(uuid4()),'operation':operation,'body':{}},expected=422)
        check('writes and unknown operations cannot enter the read channel')
        def revoked():
            request=submit('portfolio.risk.calculate.v1',risk);waiting(1)
            c.call('profile',{'profile':'viewer'},timeout=5)
            return request
        holding(psql,environment,'LOCK market_data.observations IN ACCESS EXCLUSIVE MODE',revoked)
        terminal=stream.event('response')
        check('account changes during Risk execution prevent former-account result delivery',terminal is None or terminal['state']!='completed')
    finally:
        stream.close()
    c.call('profile',{'profile':'risk'})
    opened=c.call('async-reads/channels',{'clientId':client_id});channel=opened['channelId'];stream=Stream(c,channel)
    assert stream.event('ready') is not None
    principal="(SELECT principal_id FROM security.identity_bindings WHERE issuer='https://preview.invalid' AND subject='risk')"
    saved=json.loads(query(f"SELECT json_agg(json_build_object('id',id,'until',granted_to)) FROM security.role_grants WHERE principal_id={principal};"))
    try:
        def expires():
            query(f"UPDATE security.role_grants SET granted_to=clock_timestamp()+interval '2 seconds' WHERE principal_id={principal};")
            submit('portfolio.risk.calculate.v1',risk);waiting(1)
            deadline=time.monotonic()+5
            while query(f"SELECT bool_and(granted_to<clock_timestamp()) FROM security.role_grants WHERE principal_id={principal};")!='t':
                assert time.monotonic()<deadline,'The owned Risk role did not expire'
                time.sleep(.025)
        holding(psql,environment,'LOCK market_data.observations IN ACCESS EXCLUSIVE MODE',expires)
        terminal=stream.event('response')
        check('Risk authority expiring during execution prevents result disclosure',terminal is None or terminal['state']!='completed')
    finally:
        stream.close()
        for grant in saved:
            query(f"UPDATE security.role_grants SET granted_to='{grant['until']}'::timestamptz WHERE id='{grant['id']}';")
    print(f'{passed} asynchronous workbench HTTP checks passed.',flush=True)
