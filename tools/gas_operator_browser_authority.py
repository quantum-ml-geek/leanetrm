"""Bounded same-actor permission loss during an owned operator browser check."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import json
from threading import Event
from uuid import uuid4


@contextmanager
def control(query,manifest,directory):
    assert directory.name.startswith('oetrm-ref-')
    request=directory/'operator-authority-request.json';response=directory/'operator-authority-response.json'
    actor=query("SELECT principal_id FROM security.identity_bindings WHERE issuer='https://preview.invalid' AND subject='trader';")
    tenant,workspace=manifest['tenantId'],manifest['workspaceId']
    selected=f"permission='RecordGasOwnedHoldings' AND role_id IN(SELECT role_id FROM security.role_grants WHERE principal_id='{actor}' " \
        f"AND tenant_id='{tenant}' AND workspace_id='{workspace}' AND NOT revoked)"
    saved=query(f"SELECT jsonb_agg(to_jsonb(p) ORDER BY role_id) FROM security.role_permissions p WHERE {selected};")
    assert saved and json.loads(saved)
    def allowed():return query(f"SELECT security.principal_has_permission('{actor}','{tenant}','{workspace}','RecordGasOwnedHoldings',clock_timestamp());")
    assert allowed()=='t'
    nonce=str(uuid4());stopped=Event()
    def restore():
        literal="'"+saved.replace("'","''")+"'::jsonb"
        query("INSERT INTO security.role_permissions SELECT * FROM jsonb_populate_recordset(NULL::security.role_permissions,"+literal+") ON CONFLICT DO NOTHING;")
    def monitor():
        previous=None
        while not stopped.wait(.01):
            if not request.is_file():continue
            message=json.loads(request.read_text())
            if message==previous:continue
            assert message.get('nonce')==nonce and message.get('stage') in ('revoke','restore'),message
            stage=message['stage']
            if stage=='revoke':
                assert previous is None
                query(f"DELETE FROM security.role_permissions WHERE {selected};")
                assert allowed()=='f'
            else:
                assert previous is not None and previous['stage']=='revoke'
                restore();assert allowed()=='t'
            previous=message
            temporary=response.with_suffix('.tmp');temporary.write_text(json.dumps(dict(nonce=nonce,stage=stage)));temporary.chmod(0o600);temporary.replace(response)
    with ThreadPoolExecutor(max_workers=1) as executor:
        future=executor.submit(monitor)
        try:yield dict(nonce=nonce)
        finally:
            stopped.set()
            try:future.result(timeout=5)
            finally:restore()
    assert query(f"SELECT jsonb_agg(to_jsonb(p) ORDER BY role_id) FROM security.role_permissions p WHERE {selected};")==saved
