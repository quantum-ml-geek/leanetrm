"""Covered page reads timed over ordinary HTTP and the response channel, in the launcher-owned standard fixture.

Workload: the standard example's seeded book at the 2020-12-18 frame, read at one retained context by the risk
profile. Each read takes one unmeasured warm-up per transport, then SAMPLES alternating ordinary and channel
requests on one client. Wire bytes are the response body as sent: the ordinary route is asked with
Accept-Encoding: gzip, and a channel result is its whole SSE data line. The two waits time GET access issued
PROBE_DELAY after the slowest ordinary read starts: once from the same session and once from another session,
which is the control. A client daemon samples the API's RSS.
"""
import gzip
import json
import statistics
import threading
import time
from urllib.request import Request
from uuid import uuid4

from benchmark_interval_series import environment
from benchmark_ppa_http import ProcessRssSampler
from check_async_workbench_http import PROTOCOL, Stream
from preview_client import PreviewClient, initial_frame

SAMPLES = 7
PROBE_DELAY = 0.05


def summary(milliseconds, wire_bytes):
    return {'medianMs': round(statistics.median(milliseconds), 1), 'maxMs': round(max(milliseconds), 1), 'wireBytes': wire_bytes}


def ordinary(c, path, body):
    """One ordinary read: elapsed milliseconds, body bytes as sent, and the parsed value."""
    headers = {'Origin': c.url, 'Accept-Encoding': 'gzip', 'Content-Type': 'application/json', 'X-Preview-CSRF': c.token}
    request = Request(c.url+c.api_prefix+path, data=json.dumps(body).encode(), headers=headers, method='POST')
    started = time.perf_counter()
    with c.opener.open(request, timeout=20) as response:
        sent = response.read()
        encoded = response.headers.get('Content-Encoding')
    elapsed = (time.perf_counter()-started)*1000
    assert encoded in (None, 'gzip'), encoded
    return elapsed, len(sent), json.loads(gzip.decompress(sent) if encoded else sent)


def channel_read(c, stream, channel, operation, body):
    """One channel read: elapsed milliseconds from submission to its response event, the event's data bytes, and its result."""
    request = {'channelId': channel, 'requestId': str(uuid4()), 'operation': operation, 'body': body}
    started = time.perf_counter()
    c.call('async-reads', request, expected=202)
    while True:
        fields = {}
        while True:
            line = stream.response.readline()
            assert line, operation+': the response stream ended'
            line = line.rstrip(b'\r\n')
            if not line:
                break
            if not line.startswith(b':'):
                key, _, value = line.partition(b':')
                fields[key] = value.lstrip()
        if fields.get(b'event') == b'response':
            break
    elapsed = (time.perf_counter()-started)*1000
    reply = json.loads(fields[b'data'])
    assert reply['requestId'] == request['requestId'] and reply['state'] == 'completed', reply.get('error')
    return elapsed, len(fields[b'data']), reply['result']


def measure(c, client_id, operation, path, body):
    opened = c.call('async-reads/channels', {'clientId': client_id})
    stream = Stream(c, opened['channelId'])
    try:
        assert stream.event('ready') == {'protocol': PROTOCOL, 'channelId': opened['channelId']}
        ordinary(c, path, body)
        channel_read(c, stream, opened['channelId'], operation, body)
        http, sse = [], []
        for _ in range(SAMPLES):
            http.append(ordinary(c, path, body)[:2])
            sse.append(channel_read(c, stream, opened['channelId'], operation, body)[:2])
    finally:
        stream.close()
    return {'operation': operation, 'route': path,
            'http': summary([ms for ms, _ in http], http[-1][1]), 'channel': summary([ms for ms, _ in sse], sse[-1][1])}


def wait_behind(holder, path, body, probe):
    """GET access timed PROBE_DELAY after an ordinary read of `holder` starts, with that read's own duration."""
    waits, held = [], []
    for _ in range(SAMPLES):
        result = {}
        def hold():
            result['ms'] = ordinary(holder, path, body)[0]
        reader = threading.Thread(target=hold)
        reader.start()
        time.sleep(PROBE_DELAY)
        started = time.perf_counter()
        probe.call('access')
        waits.append((time.perf_counter()-started)*1000)
        reader.join(timeout=30)
        assert 'ms' in result, 'the held read did not complete'
        held.append(result['ms'])
    return {'heldRead': path, 'probe': 'access', 'medianMs': round(statistics.median(waits), 1), 'maxMs': round(max(waits), 1),
            'heldMedianMs': round(statistics.median(held), 1)}


def same_session(c):
    """A second connection pool carrying the first client's session."""
    probe = PreviewClient(c.url)
    for cookie in c.jar:
        probe.jar.set_cookie(cookie)
    probe.token = c.token
    return probe


def run_benchmark(url, query, manifest, *, dotnet, api_pid):
    c = PreviewClient(url)
    c.bootstrap()
    c.call('profile', {'profile': 'risk'})
    frame = initial_frame(c.call('workspace/catalog'), '2020-12-18')
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
    curve = {'snapshotId': frame['id'], 'curve': 'local_power', 'includeSources': True, 'includeWorkspace': True,
             'contractDisplay': {'version': 'curve_display_v1', 'contracts': 'eligible_contracts_v1'}}
    contract = c.call('evaluate', curve)['points'][0]['contractId']
    cases = [
        ('curve.evaluate.v1', 'evaluate', curve),
        ('curve.history.v1', 'history', {'snapshotId': frame['id'], 'curve': 'local_power', 'contractId': contract, 'revisionPolicy': 'exact_snapshot_pins_v1'}),
        ('trading.directory.v1', 'trading/directory', context),
        ('trading.workspace.v1', 'trading/workspace', {'context': context, 'view': view, 'summaries': [], 'bookingCatalog': 'directory'}),
        ('trading.blotter.v1', 'trading/blotter', {'context': context, 'view': view}),
        ('portfolio.risk.catalog.v1', 'portfolio/risk/catalog', scope),
        ('portfolio.risk.calculate.v1', 'portfolio/risk', risk),
    ]
    client_id = str(uuid4())
    sampler = ProcessRssSampler(api_pid)
    with sampler:
        reads = [measure(c, client_id, *case) for case in cases]
        _, slowest, held = max(cases, key=lambda case: next(r for r in reads if r['operation'] == case[0])['http']['medianMs'])
        same = wait_behind(c, slowest, held, same_session(c))
        other = PreviewClient(url)
        other.bootstrap()
        other.call('profile', {'profile': 'risk'})
        control = wait_behind(c, slowest, held, other)
    holdings = blotter['holdings']
    contracts = {}
    for row in holdings:
        contracts.setdefault(row['instrumentType'], set()).add(row['contractId'])
    report = {
        'benchmark': 'page_reads_v1', 'samples': SAMPLES, 'probeDelayMs': PROBE_DELAY*1000,
        'workload': {'example': 'standard', 'frame': frame['at'], 'profile': 'risk', 'positions': len(holdings),
                     'trades': len({row['tradeId'] for row in holdings}),
                     'uniqueContracts': {kind: len(ids) for kind, ids in sorted(contracts.items())},
                     'riskScenarios': 'one factor bump of 0.1 on the future curve, all books, book detail',
                     'evaluatedWork': c.call('portfolio/risk', risk)['work']},
        'environment': environment(query, dotnet), 'apiRss': sampler.report(),
        'reads': reads, 'sameSessionWait': same, 'otherSessionWait': control}
    numbers = [value for read in reads for side in ('http', 'channel') for value in read[side].values()]
    numbers += [same['medianMs'], same['maxMs'], control['medianMs'], control['maxMs']]
    assert all(isinstance(value, (int, float)) and 0 < value < float('inf') for value in numbers), numbers
    return report
