#!/usr/bin/env python3
"""Qualify the operating schedule grammar using disposable synthetic staging."""
import json
from uuid import uuid4
from check_reference_editing import main
from assistant_context import migration_body


def run_checks(query, manifest):
    catalog, definition, reference, revision, tenant, workspace = [manifest[k] for k in
        ('catalogId', 'revisionId', 'referenceCatalogId', 'referenceRevisionId', 'tenantId', 'workspaceId')]
    def literal(value):
        return "'" + json.dumps(value).replace("'", "''") + "'::jsonb"
    def runtime(sql):
        token=query("SET SESSION AUTHORIZATION preview_authenticator;SELECT security.issue_context("
            f"'https://preview.invalid','trader','human_interactive','{tenant}','{workspace}',NULL,'preview_runtime',120);")
        return query('BEGIN;SET LOCAL SESSION AUTHORIZATION preview_runtime;'+f"SELECT security.use_context('{token}');"+sql+'COMMIT;')
    policy={'contract':'side_calendar_policy_v1','Delivery':{'contract':'side_calendar_binding_v1','Applicable':False,'Calendar':None,'DefinitionDigest':None,'Publication':None},
        'Observation':{'contract':'side_calendar_binding_v1','Applicable':False,'Calendar':None,'DefinitionDigest':None,'Publication':None},
        'Payment':{'contract':'side_calendar_binding_v1','Applicable':False,'Calendar':None,'DefinitionDigest':None,'Publication':None},'PaymentTiming':None}
    command={'convention':'supplied_operating_right_trade_v1','plan':{'valuation':{'paymentRule':{'frequency':'monthly','rule':'days_after_period_end','days':18,'dayOfMonth':None,
        'dayBasis':'calendar_days','shortMonth':None,'adjustment':'unadjusted','calendar':None,'implementation':'calendar_payment_rule_v1'}}}}
    header={'family':'operating','definitionRevisionId':definition,'referenceCatalogId':reference,'referenceRevisionId':revision,
        'economicIdentity':json.dumps({'contract':'synthetic_staging_identity_v1','CalendarPolicy':policy}),
        'pricingBindingIdentity':'synthetic_staging_v1','schemaVersion':'side_schedule_blocks_v2','generatorVersion':'whole_term_side_blocks_v3',
        'manifest':'0'*64,'rowCount':1,'edgeCount':0,'bindingCount':0,'rootCount':1,'portCount':0,'gridCount':0}
    schedule=runtime(f"SELECT security.begin_side_schedule('{catalog}','{uuid4()}',0,{literal(command)},'BookTrade',NULL,NULL,{literal(header)});")
    assert schedule, 'An operating schedule was not staged'
    print('PASS operating schedule storage: explicit supplied-plan family and inapplicable calendar policy stage under current authority',flush=True)
    assert query("SELECT trading.side_schedule_parameters('operating_contract_price','{\"selection\":\"selected_contract_flat_v1\"}'::jsonb);")=='t'
    for params in ({'selection':'inferred'}, {'selection':'selected_contract_flat_v1','fallback':'0'}, {}):
        assert query(f"SELECT trading.side_schedule_parameters('operating_contract_price',{literal(params)});")=='f'
    print('PASS operating schedule storage: explicit flat contract source grammar rejects inference, fallback and missing selection',flush=True)

def before_migration(query, migration):
    if migration.name!='0342_operating_retained_programs.sql':
        return
    body=migration_body(migration.read_text())
    # The function set is the migration's exact declared predecessor contract.
    contracts=json.loads(body.split('$contracts$')[1])
    for expected in contracts:
        signature=expected['signature']
        for alteration in ("SET work_mem='64kB'", 'SECURITY INVOKER' if expected['definer'] else 'SECURITY DEFINER',
                           'CALLED ON NULL INPUT' if expected['strict'] else 'STRICT',
                           'VOLATILE' if expected['volatility']!='v' else 'STABLE'):
            try:
                query('BEGIN;ALTER FUNCTION '+signature+' '+alteration+';'+body+';ROLLBACK;')
            except RuntimeError as error:
                assert 'operating_program_upgrade: unexpected helper' in str(error), str(error)
            else:
                raise AssertionError('Accepted altered predecessor helper: '+signature+' '+alteration)
    print('PASS operating schedule upgrade: exact bodies, authority and execution modes refuse predecessor drift',flush=True)

if __name__=='__main__':
    main(checks=run_checks, before_migration=before_migration)
