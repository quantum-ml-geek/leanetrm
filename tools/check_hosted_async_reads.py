"""Real hosted authentication and expiry for owned asynchronous read workers."""
import http.client
import json
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlsplit
from uuid import uuid4
from assistant_context import holding


def run_checks(Client, provision, query, origin, tls, password, psql, environment):
    assert psql and environment, 'Hosted async checks require the owned database controller'
    account = provision('async_reader', ['trader', 'market_data_editor'])
    provision('async_stranger', ['trader', 'market_data_editor'])

    class Stream:
        def __init__(self, client, channel):
            address = urlsplit(origin)
            self.connection = http.client.HTTPSConnection(address.hostname, address.port, context=tls, timeout=15)
            self.connection.request('GET', '/api/async-reads/events?channelId='+channel, headers={
                'Cookie': '; '.join(f'{cookie.name}={cookie.value}' for cookie in client.cookies),
                'Accept': 'text/event-stream', 'Sec-Fetch-Site': 'same-origin', 'Sec-Fetch-Mode': 'cors'})
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
                        name, _, value = line.partition(':')
                        fields[name] = value.lstrip()
                if fields.get('event') == kind:
                    return json.loads(fields['data'])

        def close(self):
            self.response.close()
            self.connection.close()

    def open_reader():
        client = Client(); client.login('async_reader', password)
        boot = client.bootstrap()
        assert boot['profile'] == account and boot['asyncReadProtocol'] == 'async_reads_v1'
        workspace = client.call('/api/workspace/catalog')[0]
        frame = next(f for f in workspace['frames'] if f['at'].startswith('2020-12-18') and not f.get('contextId'))
        channel = client.call('/api/async-reads/channels', {'clientId':str(uuid4())})[0]
        assert channel['profile'] == account and channel['context'] is None
        stream = Stream(client, channel['channelId'])
        assert stream.response.status == 200 and stream.event('ready') == {
            'protocol': 'async_reads_v1', 'channelId': channel['channelId']}
        return client, frame, channel['channelId'], stream

    def request(channel, frame):
        return {'channelId': channel, 'requestId': str(uuid4()), 'operation': 'curve.evaluate.v1',
                'body': {'snapshotId': frame['id'], 'curve': 'future', 'includeSources': True,
                         'includeWorkspace': False, 'contractDisplay': {'version': 'curve_display_v1', 'contracts': 'eligible_contracts_v1'}}}

    def waiting():
        deadline = time.monotonic()+5
        sql = "SELECT count(*) FROM pg_locks WHERE relation='market_data.observations'::regclass AND NOT granted AND mode='AccessShareLock';"
        while int(query(sql)) < 1:
            assert time.monotonic() < deadline, 'Hosted worker did not continue independently after HTTP acceptance'
            time.sleep(.025)

    client, frame, channel, stream = open_reader()
    try:
        stranger = Client(); stranger.login('async_stranger', password); stranger.bootstrap()
        denied = Stream(stranger, channel)
        try:
            assert denied.response.status == 410, 'Another hosted sign-in subscribed to this channel'
        finally:
            denied.close()
        pending = request(channel, frame)
        expected = client.call('/api/evaluate', pending['body'])[0]

        def submit_blocked():
            ack = client.call('/api/async-reads', pending, expected=202)[0]
            assert ack['requestId'] == pending['requestId']
            waiting()
            client.call('/api/access')

        holding(psql, environment, 'LOCK market_data.observations IN ACCESS EXCLUSIVE MODE', submit_blocked)
        completed = stream.event('response')
        assert completed['state'] == 'completed' and completed['result'] == expected
        print('PASS hosted async: exact sign-in identity survives HTTP completion and another sign-in cannot subscribe', flush=True)

        # An admitted transaction fences sign-out until it leaves the database. Start
        # sign-out while work is held, then release that work before awaiting logout.
        with ThreadPoolExecutor(max_workers=1) as executor:
            logout = None
            def signout_blocked():
                nonlocal logout
                client.call('/api/async-reads', request(channel, frame), expected=202)
                waiting()
                logout = executor.submit(client.call, '/api/logout', {})
                deadline = time.monotonic()+4
                while query("SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%revoke_hosted_session(%';") == '0':
                    assert not logout.done(), 'Sign-out bypassed the admitted transaction fence'
                    assert time.monotonic() < deadline, 'Sign-out did not reach its admitted transaction fence'
                    time.sleep(.025)

            holding(psql, environment, 'LOCK market_data.observations IN ACCESS EXCLUSIVE MODE', signout_blocked)
            logout.result(timeout=10)
        terminal = stream.event('response')
        assert terminal is None or terminal['state'] != 'completed' and terminal.get('result') is None
        client.call('/api/bootstrap', expected=401)
        print('PASS hosted async: signing out while a worker is blocked prevents disclosure', flush=True)
    finally:
        stream.close()

    client, frame, channel, stream = open_reader()
    try:
        # Expiry is clock based. Set it before admission: updating this row after
        # admission would itself wait behind the transaction's authentication fence.
        query(f"UPDATE security.hosted_sessions SET expires_at=clock_timestamp()+interval '3 seconds' WHERE principal_id='{account}' AND revoked_at IS NULL;")
        def expire_blocked():
            client.call('/api/async-reads', request(channel, frame), expected=202)
            waiting()
            deadline = time.monotonic()+5
            while query(f"SELECT bool_and(expires_at<clock_timestamp()) FROM security.hosted_sessions WHERE principal_id='{account}' AND revoked_at IS NULL;") != 't':
                assert time.monotonic() < deadline, 'The owned sign-in did not expire'
                time.sleep(.025)

        holding(psql, environment, 'LOCK market_data.observations IN ACCESS EXCLUSIVE MODE', expire_blocked)
        terminal = stream.event('response')
        assert terminal is None or terminal['state'] != 'completed' and terminal.get('result') is None
        client.call('/api/bootstrap', expected=401)
        print('PASS hosted async: database sign-in expiry while a worker is blocked prevents disclosure', flush=True)
    finally:
        stream.close()
