"""Complete active/withdrawn operator books through native PV and real workers."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from uuid import uuid4

from check_gas_operator_quantity_reconciliation import checks as native_checks
from check_gas_operator_physical_value import market_inputs
from check_lifecycle_economic_worker import children,worker_checks
from check_reference_editing import main as native_main
from gas_operator_browser_cases import seed,prepare,verify
from gas_operator_physical_value_fixture import fixture
from gas_operator_source_authority import _state


def checks(query,manifest,call,capture,read,record,amend,packet):
    catalog=manifest['catalogId'];cases=[];at='2020-12-23T16:00:00Z'
    for zero in [False,True]:
        case=seed(query,manifest,call,capture,record,zero=zero)
        prepare(query,manifest,call,capture,record,case,zero=zero)
        body=dict(implementation='gas_operator_quantity_reconciliation_v1',rootClaimId=case['rootClaimId'],
            claims=case['claims'],consumptions=case['consumptions'],
            cashout=dict(ordering='replay_original_settlement_publication_prefix_v1',adjustmentDueAt=None),
            evidence='Synthetic explicit complete operator ordinary-use and zero correction')
        literal="'"+json.dumps(body).replace("'","''")+"'::jsonb"
        context=capture('2020-12-23')
        outcome=json.loads(call(f"SELECT security.reconcile_gas_operator_quantities('{catalog}','{uuid4()}','{case['accountId']}',"
            f"{literal},'{at}','{context}','{case['policyId']}',{case['policyRevision']},false)::text;"))
        assert outcome['changed'] and outcome['cashChanges']==[]
        verify(query,manifest,call,capture,case)
        cases.append(case)
    assert len({case['bookId'] for case in cases})==2
    context=capture('2020-12-20');directory=Path(query('SHOW unix_socket_directories;')).resolve()
    selected=dict(manifest=manifest,host=str(directory),cases=cases,contextId=context,at='2020-12-20T16:00:00Z',
        profiles=[profile for case in cases for profile in case['profiles']],economicSession=cases[0]['economicSession'],
        **market_inputs(query,manifest,context,loss_units=1))
    path=directory/'gas-operator-ordinary-value.json';path.write_text(json.dumps(selected));path.chmod(0o600)
    financial=_state(query,catalog)
    worker_checks(query,manifest,path,submit_mode='--gas-operator-ordinary-value',check_labels=False)
    assert _state(query,catalog)==financial,'Ordinary/zero operator PV or workers changed a native financial, bank or receipt fact.'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['pg-bin','dotnet']:parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--no-build',action='store_true');args=parser.parse_args()
    for path in [args.pg_bin/'psql',args.dotnet]:
        if not path.is_file():parser.error('An installed executable is required: '+str(path))
    os.environ['DOTNET']=str(args.dotnet.resolve());root=Path(__file__).resolve().parents[1]
    if not args.no_build:
        subprocess.run([str(args.dotnet),'build','tests/OpenEtrm.Api.Checks','--no-restore','--disable-build-servers',
            '-m:1','-p:UseSharedCompilation=false','-nodeReuse:false'],cwd=root,check=True,timeout=120)
    native_main(checks=lambda query,manifest:native_checks(query,manifest,after_writer=checks),fixture_factory=fixture,
        arguments=['--pg-bin',str(args.pg_bin.resolve())],cleanup_ready=lambda:not children)


if __name__=='__main__':main()
