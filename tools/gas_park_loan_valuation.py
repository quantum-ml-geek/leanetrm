"""Run independent whole-book PV and ordinary scenario checkpoints."""
import json
import os
from pathlib import Path
import subprocess


def checkpoint(f, booked, book, exposure, unpaid, service_components, name):
    dotnet = os.environ.get('DOTNET')
    if not dotnet:
        return
    market = f.valuation_inputs()
    directory = Path(f.query('SHOW unix_socket_directories;')).resolve()
    packet = dict(host=str(directory), manifest=f.manifest, at=f.at, businessDate=f.day, contextId=f.capture(),
        bookId=book, tradeId=booked['tradeId'], contractId=f.contract, markId=market['markId'], rateIds=market['rateIds'],
        bumpSize='1', expectedBase=str(exposure * 3 + unpaid), expectedUp=str(exposure * 4 + unpaid),
        expectedDown=str(exposure * 2 + unpaid), expectedServiceComponents=service_components, checkpoint=name)
    path = directory / 'park-loan-valuation.json'
    path.write_text(json.dumps(packet)); path.chmod(0o600)
    root = Path(__file__).resolve().parents[1]
    subprocess.run([str(Path(dotnet).resolve()), str(root / 'tests/OpenEtrm.Api.Checks/bin/Debug/net10.0/OpenEtrm.Api.Checks.dll'),
        '--gas-park-loan-native', str(path)], cwd=root, check=True, timeout=120)
