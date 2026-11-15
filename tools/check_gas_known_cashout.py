"""Source-known future cashout quantities and bank cash through real risk workers."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from check_gas_operator_quantity_reconciliation import checks as native_checks
from check_lifecycle_economic_worker import children, worker_checks
from check_reference_editing import main as native_main
from gas_known_cashout_fixture import configure, fixture
from gas_operator_source_authority import _state


def checks(query, manifest, call, capture, read, record, amend, packet):
    selected = configure(query, manifest, call, capture, read, record, amend, packet)
    selected['cases'] = [configure(query, manifest, call, capture, read, record, amend, packet, mode=mode)
                         for mode in ('zero', 'due', 'paid')]
    directory = Path(query('SHOW unix_socket_directories;')).resolve()
    path = directory / 'gas-known-cashout.json'
    path.write_text(json.dumps(selected | dict(manifest=manifest, host=str(directory))))
    path.chmod(0o600)
    before = _state(query, manifest['catalogId'])
    worker_checks(query, manifest, path, submit_mode='--gas-known-cashout', check_labels=False)
    assert _state(query, manifest['catalogId']) == before, 'Economic cashout projection persisted a financial or bank fact.'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    parser.add_argument('--dotnet', type=Path, required=True)
    parser.add_argument('--no-build', action='store_true')
    args = parser.parse_args()
    for path in [args.pg_bin / 'psql', args.dotnet]:
        if not path.is_file():parser.error('An installed executable is required: ' + str(path))
    os.environ['DOTNET'] = str(args.dotnet.resolve())
    if not args.no_build:
        subprocess.run([str(args.dotnet), 'build', 'tests/OpenEtrm.Api.Checks', '--no-restore', '--disable-build-servers',
            '-m:1', '-p:UseSharedCompilation=false', '-nodeReuse:false'], cwd=Path(__file__).resolve().parents[1], check=True, timeout=120)
    native_main(checks=lambda query, manifest:native_checks(query, manifest, after_writer=checks),
        fixture_factory=fixture, arguments=['--pg-bin', str(args.pg_bin.resolve())], cleanup_ready=lambda:not children)


if __name__ == '__main__':main()
