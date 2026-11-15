"""Shared operator action against an owned native cashout correction fixture."""
import copy
import json
import os
from pathlib import Path
import subprocess
from uuid import uuid4


def checks(query, manifest, call, capture, read, record, amend, packet):
    context = capture()
    selection = copy.deepcopy(packet['body'])
    for claim in selection['claims']:
        source = read(claim['claimId'], context)
        claim['expectedRevision'] = source['claim']['expectedRevision']
        current = {row['id']: row for row in source['settlements']}
        for step in claim['settlements']:
            step['expectedRevision'] = current[step['settlementId']]['expectedRevision']
    selection['claims'][0]['settlements'][0]['quantity'] = '0.875'
    selection['claims'][0]['settlements'][1]['quantity'] = '2.125'
    selection['cashout']['adjustmentDueAt'] = '2020-12-26T12:00:00Z'
    selection['evidence'] = 'Synthetic reviewed operator settlement reallocation'
    host = Path(query('SHOW unix_socket_directories;'))
    account = json.loads(query("SELECT to_jsonb(a) FROM trading.gas_owned_accounts a "
        f"WHERE(a.catalog_id,a.id)=('{manifest['catalogId']}','{packet['accountId']}');"))
    path = host / 'gas-operator-managed.json'
    path.write_text(json.dumps(dict(manifest=manifest, host=str(host), contextId=context,
        accountId=packet['accountId'], rootClaimId=packet['rootClaimId'], otherClaimId=packet['otherClaimId'], at=packet['at'],
        policyId=packet['policyId'], operationId=str(uuid4()), selection=selection,
        quantityUnit=account['quantity_code'], currency=account['currency_code'],
        adjustmentDueAt=selection['cashout']['adjustmentDueAt'])))
    result = subprocess.run([os.environ.get('DOTNET', 'dotnet'), 'run', '--no-build', '--no-restore',
        '--project', 'tests/OpenEtrm.Api.Checks', '--', '--gas-operator-correction', str(path)],
        cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True, timeout=120)
    print(result.stdout, flush=True)
    if result.returncode:
        raise RuntimeError(result.stderr)
