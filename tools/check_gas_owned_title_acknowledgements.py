"""Original title and borrower commands acknowledge exact accepted snapshots."""
from check_reference_editing import main
from gas_loan_quantity_fixture import fixture,configure
from gas_owned_title_acknowledgements import checks as fact_checks
from gas_owned_title_upgrade import checks as upgrade_checks,verify


def checks(query,manifest):
    verify(query)
    fact_checks(query,manifest,configure(query,manifest))


if __name__=='__main__':main(checks=checks,fixture_factory=fixture,before_migration=upgrade_checks)
