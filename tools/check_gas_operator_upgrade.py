"""Qualify operator source bridge guards against exact native metadata drift."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from check_reference_editing import main
from gas_operator_source_upgrade import checks,verify


if __name__=='__main__':main(checks=lambda query,_:verify(query),before_migration=checks,fixture_factory=lambda _:('','','',{}))
