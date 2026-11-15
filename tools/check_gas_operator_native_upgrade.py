"""Qualify native operator continuation against changed predecessor contracts."""
from check_reference_editing import main
from gas_operator_native_upgrade import checks,verify


if __name__=='__main__':
    main(checks=lambda query,_:verify(query),before_migration=checks,fixture_factory=lambda _:('','','',{}))
