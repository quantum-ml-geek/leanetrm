"""Rate curve storage checks in the schema runner's owned cluster only."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CAT='40000000-0000-0000-0000-000000000001'
RCAT='10000000-0000-0000-0000-000000000001'
RREV='20000000-0000-0000-0000-000000000001'
REV='f0000000-0000-0000-0000-000000000001'
SERIES='f1000000-0000-0000-0000-000000000001'
REF=f"'{RCAT}','{RREV}'"


def run_checks(query,reject):
    query((ROOT/'db/migrations/0006_rate_curves.sql').read_text(),label='rate curve migration applies with protected roles')
    def definition(revision=REV,value_type='test_dimensionless'):
        return f"""INSERT INTO market_data.revisions VALUES ('{CAT}','{revision}',{REF},'draft',0);
        INSERT INTO market_data.series VALUES ('{CAT}','{revision}','{SERIES}','zero_rate',{REF},NULL,NULL,'{value_type}');
        INSERT INTO market_data.rate_curves VALUES ('{CAT}','{revision}','rates',{REF},'test_interest','fixture','valuation_utc_date');"""
    def point(revision=REV,maturity='2042-01-01',sid=SERIES):
        return f"INSERT INTO market_data.rate_curve_points VALUES ('{CAT}','{revision}','rates','{maturity}','{sid}',0);"
    def seal(revision=REV):return f"UPDATE market_data.revisions SET state='sealed' WHERE catalog_id='{CAT}' AND id='{revision}';"
    def issue(n):
        return query("SET SESSION AUTHORIZATION openetrm_authenticator; SELECT security.issue_context("
                     f"'https://identity.invalid','subject_{n}','human_interactive','b0000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',NULL,'openetrm_runtime',60);")
    def runtime(n,sql):return f"SET SESSION AUTHORIZATION openetrm_runtime; BEGIN; SELECT security.use_context('{issue(n)}'); {sql} COMMIT;"
    query("UPDATE security.role_grants SET granted_to=CURRENT_TIMESTAMP+INTERVAL '1 day',revoked=false WHERE principal_id='b2000000-0000-0000-0000-000000000003';")
    query(definition(),label='rates reuse typed series without dated delivery contracts')
    reject('rate curve cannot seal without dated samples',seal(),'23514')
    reject('rate sample requires exact series FK',point(sid='f1000000-0000-0000-0000-000000000099'),'23503')
    reject('rate date outside supported horizon rejected',point(maturity='2300-01-01'),'23514')
    # Editor writes through RLS and existing revision generation fencing.
    query(runtime(2,point()),label='market editor writes rate samples under current scoped access')
    assert query(f"SELECT generation FROM market_data.revisions WHERE catalog_id='{CAT}' AND id='{REV}';")=='3'
    query('SELECT 1;',label='rate writes increment locked revision generation')
    query(runtime(4,f"SELECT security.seal_market_revision('{CAT}','{REV}');"),label='approver seals rate definitions through checked operation')
    reject('sealed rate samples remain immutable',f"UPDATE market_data.rate_curve_points SET maturity='2043-01-01' WHERE catalog_id='{CAT}' AND revision_id='{REV}';",'55000')
    bad='f0000000-0000-0000-0000-000000000002'
    reject('quantity ratios cannot masquerade as annual rates',definition(bad,'test_conversion_ratio')+point(bad)+seal(bad),'23514')
    conflicting='f0000000-0000-0000-0000-000000000003'
    reject('one rate series cannot acquire conflicting maturity identities',definition(conflicting)+point(conflicting)+
           f"INSERT INTO market_data.rate_curves VALUES ('{CAT}','{conflicting}','other_rates',{REF},'test_interest','fixture','valuation_utc_date');"+
           f"INSERT INTO market_data.rate_curve_points VALUES ('{CAT}','{conflicting}','other_rates','2043-01-01','{SERIES}',0);"+seal(conflicting),'23514')
    count=f"SELECT count(*) FROM market_data.rate_curves WHERE catalog_id='{CAT}';"
    assert query('SET SESSION AUTHORIZATION openetrm_runtime; '+count)=='0'
    query('SELECT 1;',label='rate definitions deny unbound reads')
    assert query(runtime(3,count)).strip()=='1'
    query('SELECT 1;',label='viewer reads only its authorized rate definitions')
    assert query(runtime(3,"SELECT count(*) FROM market_data.rate_curve_points WHERE catalog_id='40000000-0000-0000-0000-000000000002';")).strip()=='0'
    query('SELECT 1;',label='rate sample reads remain isolated from other tenants')
    protected=query("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='market_data' AND c.relname IN ('rate_curves','rate_curve_points') AND c.relrowsecurity AND c.relforcerowsecurity;")
    assert protected=='2'
    query('SELECT 1;',label='new rate tables force row security')
    reject('viewer cannot freeze rate definitions',runtime(3,f"SELECT security.seal_market_revision('{CAT}','{REV}');"),'42501')
