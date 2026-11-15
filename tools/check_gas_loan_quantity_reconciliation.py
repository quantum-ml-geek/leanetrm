"""Exact loan corrections, retained source authority and independent cash continuation."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
from check_reference_editing import main
from gas_loan_quantity_fixture import fixture,configure
from gas_loan_reconciliation_upgrade import checks as upgrade
from gas_loan_retirement import checks as retirement_checks
from gas_loan_maturity_checks import checks as maturity_checks
from gas_loan_source_authority import checks as authority_checks


def withdrawal_checks(query,manifest):
    state=configure(query,manifest)
    root=Path(__file__).resolve().parents[1]
    path=Path(query('SHOW unix_socket_directories;'))/'gas-loan-correction.json'
    subprocess.run([os.environ.get('DOTNET','dotnet'),'run','--project','tests/OpenEtrm.Api.Checks','--no-build','--no-restore',
        '--','--gas-loan-correction-form',str(path)],cwd=root,check=True)
    catalog,tenant,workspace=(manifest[key] for key in ('catalogId','tenantId','workspaceId'))
    issuer=manifest['identityIssuer'];at=state['at']
    def call(sql):
        token=query("SET SESSION AUTHORIZATION preview_authenticator;SELECT security.issue_context("
            f"'{issuer}','trader','human_interactive','{tenant}','{workspace}',NULL,'preview_runtime',60);")
        return query(f"SET SESSION AUTHORIZATION preview_runtime;BEGIN;SELECT security.use_context('{token}');{sql}COMMIT;")
    def read(loan,context):
        return call(f"SELECT security.use_market_context('{catalog}','{context}');SELECT security.use_trading_context('{catalog}','{at}');"
            f"SELECT security.read_gas_loan_reconciliation('{catalog}','{loan}','{context}','{at}')::text;")
    authority_checks(query,call,read,manifest,state['loan']['id'],state['currentContextId'])
    retirement_checks(query,manifest,state=state)


if __name__=='__main__':
    parser=argparse.ArgumentParser(add_help=False)
    parser.add_argument('--case',choices=('all','withdrawal','maturity'),default='all')
    selected,rest=parser.parse_known_args();sys.argv=[sys.argv[0],*rest]
    if selected.case in ('all','withdrawal'):main(checks=withdrawal_checks,fixture_factory=fixture,before_migration=upgrade)
    if selected.case in ('all','maturity'):main(checks=maturity_checks,fixture_factory=fixture,before_migration=upgrade)
