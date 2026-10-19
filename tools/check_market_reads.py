"""Market and reference reads called without a session match their pages; driven by check_page_reads.py."""
import json
import subprocess
from pathlib import Path


def page_view(c, name, context=None):
    """Record the selected view's page reads in an existing session, so no session is spent."""
    full = c.call('workspace')
    effective = context['effectiveOn'] if context else '2020-12-17'
    frame = next(f for f in full['frames'] if f['at'].startswith(effective))
    evaluations = {curve: c.call('evaluate', {'snapshotId': frame['id'], 'curve': curve})
                   for curve in ['local_power', 'interest_rates']}
    contract = evaluations['local_power']['points'][0]['contractId']
    return {'name': name, 'context': context, 'frames': full['frames'],
            'initialFrameIds': full['initialFrameIds'], 'frameId': frame['id'],
            'workspace': full, 'catalog': c.call('workspace/catalog'),
            'curveNames': c.call('curve-names'),
            'references': c.call('reference/catalog?table=currencies'),
            'evaluations': evaluations,
            'history': {'curve': 'local_power', 'contractId': contract,
                        'response': c.call('history', {'snapshotId': frame['id'],
                                                       'curve': 'local_power',
                                                       'contractId': contract})}}


def run_checks(views, dotnet, environment, directory):
    fixture = Path(directory) / 'market-reads.json'
    fixture.write_text(json.dumps({'profile': 'viewer', 'views': views}))
    subprocess.run([str(dotnet), 'run', '--project', 'tests/OpenEtrm.Api.Checks', '--',
                    '--market-reads', str(fixture)],
                   cwd=Path(__file__).resolve().parents[1], env=environment, check=True,
                   timeout=120)
