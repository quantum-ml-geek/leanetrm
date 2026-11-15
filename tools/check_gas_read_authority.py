"""All gas read consumers retain the same original bound at final shared return."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from check_reference_editing import main
from gas_loan_quantity_fixture import fixture,configure
from gas_loan_reconciliation_upgrade import checks as loan_upgrade
from gas_owned_fact_upgrade import checks as fact_upgrade
from gas_read_final_authority import checks as read_checks
from gas_read_deadline_upgrade import checks as read_upgrade


def checks(query,manifest):read_checks(query,manifest,configure(query,manifest))


def upgrade(query,migration):loan_upgrade(query,migration);fact_upgrade(query,migration);read_upgrade(query,migration)


if __name__=='__main__':main(checks=checks,fixture_factory=fixture,before_migration=upgrade)
