"""Fully performed positive native loan heads do not require commodity inputs."""
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from gas_loan_quantity_fixture import configure
from gas_loan_maturity import checks as mature


def checks(query,manifest):
    state=configure(query,manifest);cash=mature(query,manifest,state)
    catalog=manifest['catalogId'];definition=state['original']['definition_revision_id']
    rates=json.loads(query("SELECT jsonb_agg(o.id ORDER BY t.ordinal)::text FROM market_data.rate_curves c JOIN market_data.rate_curve_tenors t "
        "ON(t.catalog_id,t.revision_id,t.curve_code)=(c.catalog_id,c.revision_id,c.code) JOIN market_data.observations o "
        "ON(o.catalog_id,o.definition_revision_id,o.series_id,o.source_code)=(c.catalog_id,c.revision_id,t.series_id,c.source_code) "
        f"WHERE(c.catalog_id,c.revision_id,c.code)=('{catalog}','{definition}','interest_rates') "
        "AND o.role='parameter' AND o.publication_state='final' AND o.observed_at='2020-12-18T16:00:00Z' "
        "AND NOT EXISTS(SELECT 1 FROM market_data.observations n WHERE(n.catalog_id,n.corrects_id)=(o.catalog_id,o.id));"))
    tenors=int(query(f"SELECT count(*) FROM market_data.rate_curve_tenors WHERE(catalog_id,revision_id,curve_code)=('{catalog}','{definition}','interest_rates');"))
    assert rates and len(rates)==tenors and query(f"SELECT bool_and(value=0) FROM market_data.observations WHERE catalog_id='{catalog}' AND id=ANY(ARRAY["+
        ','.join("'"+rate+"'::uuid" for rate in rates)+"]);")=='t'
    host=Path(query('SHOW unix_socket_directories;'));path=host/'gas-loan-maturity.json'
    path.write_text(json.dumps(dict(manifest=manifest,host=str(host),rateIds=rates,**cash)));path.chmod(0o600)
    subprocess.run([os.environ.get('DOTNET','dotnet'),'run','--project','tests/OpenEtrm.Api.Checks','--no-build','--no-restore',
        '--','--gas-loan-maturity-fee',str(path)],cwd=Path(__file__).resolve().parents[1],check=True)
