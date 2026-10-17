"""Retirement guards, run only in the schema check's newly owned cluster."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
RETIRED=['day_count_conventions','compounding_conventions','fx_rate_definitions','heat_rate_definitions']


def run_checks(query,reject):
    migration=(ROOT/'db/migrations/0005_retire_unused_definitions.sql').read_text()
    # Failed scripts abort their transaction; no retained content is discarded.
    prefix="""INSERT INTO ref_data.catalogs VALUES ('e0000000-0000-0000-0000-000000000001','retirement_check','Synthetic');
      INSERT INTO ref_data.revisions (catalog_id,id,revision_key) VALUES
      ('e0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','retirement_check');
      INSERT INTO ref_data.day_count_conventions VALUES
      ('e0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','retained','synthetic','1');"""
    reject('reference retirement refuses retained data',prefix+migration,'55000')
    reject('reference retirement rejects stale repeatable-read snapshots',
           'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;'+migration,'25000')
    reject('reference retirement rejects serializable snapshots',
           'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;'+migration,'25000')
    owners='CREATE ROLE retirement_filtered_owner NOLOGIN NOBYPASSRLS; GRANT USAGE,CREATE ON SCHEMA ref_data TO retirement_filtered_owner;'
    for table in RETIRED+['interest_rate_definitions']:
        owners+=f'ALTER TABLE ref_data.{table} OWNER TO retirement_filtered_owner;'
    owners+='ALTER TABLE ref_data.day_count_conventions ENABLE ROW LEVEL SECURITY; ALTER TABLE ref_data.day_count_conventions FORCE ROW LEVEL SECURITY; CREATE POLICY hide ON ref_data.day_count_conventions USING (false); SET SESSION AUTHORIZATION retirement_filtered_owner;'
    reject('reference retirement refuses filtered RLS visibility',prefix+owners+migration,'42501')
    reject('reference retirement refuses dependent extensions without cascade',
           'CREATE TABLE public.retirement_dependency (catalog_id uuid, revision_id uuid, code text, FOREIGN KEY (catalog_id,revision_id,code) REFERENCES ref_data.compounding_conventions(catalog_id,revision_id,code));'+migration,'2BP01')
    assert query("SELECT count(*) FROM pg_tables WHERE schemaname='ref_data' AND tablename IN ('day_count_conventions','compounding_conventions','fx_rate_definitions','heat_rate_definitions');")=='4'
    query('SELECT 1;',label='failed retirement is atomic')
    query(migration,label='unused empty reference catalogs are retired')
    assert query("SELECT count(*) FROM pg_tables WHERE schemaname='ref_data' AND tablename IN ('day_count_conventions','compounding_conventions','fx_rate_definitions','heat_rate_definitions');")=='0'
