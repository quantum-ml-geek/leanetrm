"""Populated-schema drift checks for the canonical calendar migration chain."""
import json
from check_fact_anchor_upgrade import run_checks as check_helpers
from assistant_context import check_guard, migration_body

# Installed consumers, kept separately from the migration guard documents.
REQUIRED_SIGNATURES = {
    '0335': {
        'security.side_payment_provenance(uuid,uuid,uuid,date,date)',
        'ref_data.clock_boundary(uuid,uuid,text,date)',
        'ref_data.clock_local(uuid,uuid,text,timestamp with time zone)',
        'security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)',
        'security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])',
        'security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid)',
        'security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[],uuid)',
        'security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamp with time zone,timestamp with time zone,text,text,text,jsonb,uuid[])',
        'security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamp with time zone,jsonb,uuid[])',
        'security.side_calendar_policy_document(uuid,uuid)',
        'security.staged_economic_side(uuid,uuid,integer)',
    },
    '0334': {
        'security.market_access(uuid,text)',
        'security.reference_access(uuid,text)',
        'security.market_fact_visible(uuid,uuid,uuid)',
        'security.reference_version_visible(uuid,uuid)',
        'security.side_calendar_proofs_visible(uuid,uuid,uuid)',

        'security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])',
        'security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamp with time zone,timestamp with time zone,text,text,text,jsonb,uuid[])',
        'security.side_policy_calendar(jsonb,text)',
        'security.swap_observation_sampling(text,text)',
    },
    '0318': {
        'security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)',
        'security.read_instrument_side_programs(uuid,uuid,uuid,timestamp with time zone)',
        'security.seal_side_schedule_program(uuid,uuid,uuid,bytea)',
        'trading.require_side_program_content(uuid,uuid,bytea)',
        'trading.side_program_document(uuid,uuid)',
    },
    '0319': {
        'market_data.guard_knowledge_receipt()',
        'security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)',
        'security.market_access(uuid,text)',
        'security.reference_access(uuid,text)',
        'security.reference_version_visible(uuid,uuid)',
        'security.request_market_cut()',
        'security.require_side_schedule_read(uuid,uuid,uuid,uuid,timestamp with time zone)',
        'security.seal_side_schedule(uuid,uuid,uuid,text)',
        'security.side_schedule_visible(uuid,uuid)',
        'security.trading_access(uuid,text)',
        'security.visible_side_schedules()',
    },
    '0320': {
        'market_data.guard_tou_product_version()',
        'security.publish_tou_product(uuid,uuid,integer,integer)',
        'security.read_side_calendar(uuid,uuid,text)',
        'security.reference_access(uuid,text)',
    },
    '0321': {
        'security.require_swap_metadata_references(uuid,uuid)',
        'security.side_calendar_proofs_visible(uuid,uuid,uuid)',
        'trading.require_retained_swap_period(jsonb,boolean)',
        'security.ppa_schedule_document(jsonb,jsonb)',
        'security.ppa_side_document(uuid,uuid)',
        'security.ppa_terms_document(uuid,uuid)',
        'security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,jsonb,uuid[])',
        'security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)',
        'security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])',
        'security.read_side_calendar(uuid,uuid,text)',
        'security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)',
        'security.retain_floating_swap_side(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])',
        'security.retain_ppa_terms(uuid,jsonb,integer,timestamp with time zone)',
        'security.retain_swap_observation_schedule(uuid,uuid,uuid,uuid,text,text,ref_data.quote_specifications,date,date,text,jsonb,jsonb,integer,timestamp with time zone)',
        'security.retain_swap_payment_rule(uuid,uuid,uuid,jsonb,integer,timestamp with time zone)',
        'security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamp with time zone,timestamp with time zone,text,text,text,jsonb,uuid[])',
        'security.save_ppa_booking(uuid,uuid,jsonb)',
        'security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamp with time zone,jsonb,uuid[])',
        'security.side_schedule_request_authority(uuid,uuid)',
        'security.swap_observation_rows(uuid,uuid,uuid,uuid,text,text,date,date,text,jsonb)',
        'security.swap_payment_date(uuid,uuid,date,date,jsonb)',
        'trading.indexed_whole_term_swap_period_input(uuid,uuid,integer)',
        'trading.read_swap_revisions(uuid,uuid,boolean,uuid[])',
        'trading.read_swap_revisions(uuid,uuid,boolean,uuid[],uuid[])',
        'trading.scheduled_swap_terms(uuid,uuid,integer,uuid)',
        'trading.stamp_whole_term_swap_identity()',
        'trading.swap_observation_terms(uuid,uuid[])',
        'trading.swap_revision_terms(uuid,uuid,integer)',
        'trading.whole_term_swap_period_input(uuid,uuid,integer)',
    },
    '0322': {
        'security.book_physical_crude(uuid,jsonb,timestamp with time zone)',
        'security.book_physical_gas(uuid,jsonb,timestamp with time zone)',
        'security.book_physical_lng(uuid,jsonb,timestamp with time zone)',
        'security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,jsonb,uuid[])',
        'security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)',
        'security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])',
        'security.retain_fixed_swap_side(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid)',
        'security.save_composed_swap(uuid,uuid,uuid,integer,uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,numeric,numeric,boolean,timestamp with time zone,timestamp with time zone,text,text,text,jsonb,uuid[])',
        'security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamp with time zone,jsonb,uuid[])',
        'security.swap_business_day(uuid,uuid,text,date)',
        'security.swap_fixing_evidence(uuid,uuid,uuid,uuid,text,text,date,date,text,timestamp with time zone,timestamp with time zone,uuid[])',
        'security.swap_observation_fixing_evidence(uuid,uuid,uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid[],jsonb)',
        'security.write_gas_composition(uuid,jsonb,timestamp with time zone,boolean)',
        'trading.require_crude_program_shape(uuid,uuid,integer,timestamp with time zone,timestamp with time zone,timestamp with time zone,numeric,market_data.crude_valuation_assignments)',
        'trading.require_gas_index_cash_shape(uuid,uuid,trading.gas_component_terms,market_data.gas_valuation_assignments,jsonb)',
    },
    '0323': {
        'security.ppa_side_document(uuid,uuid)',
        'security.publish_admitted_side_schedules(uuid,uuid,uuid)',
        'security.publish_side_schedules(uuid,uuid,uuid)',
        'security.side_payment_date(jsonb,date,date,jsonb)',
        'security.staged_economic_side(uuid,uuid,integer)',
        'security.swap_payment_date(uuid,uuid,date,date,jsonb)',
    },
    '0324': {
        'security.book_physical_crude(uuid,jsonb,timestamp with time zone)',
        'security.record_crude_lifecycle(uuid,text,jsonb,timestamp with time zone,uuid)',
        'trading.require_crude_program_shape(uuid,uuid,integer,timestamp with time zone,timestamp with time zone,timestamp with time zone,numeric,market_data.crude_valuation_assignments)',
    },
    '0325': {
        'security.market_access(uuid,text)',
        'security.read_side_calendar(uuid,uuid,text)',
        'security.reference_access(uuid,text)',
        'security.side_calendar_cutoff(uuid,uuid)',
    },
    '0326': {
        'security.write_gas_composition(uuid,jsonb,timestamp with time zone,boolean)',
        'trading.gas_identity_reference(uuid,uuid,text)',
        'trading.require_gas_index_cash_shape(uuid,uuid,trading.gas_component_terms,market_data.gas_valuation_assignments,jsonb)',
        'trading.require_gas_program_shape(uuid,uuid,integer,date,date,timestamp with time zone,numeric,numeric,market_data.gas_valuation_assignments,ref_data.gas_delivery_conventions,timestamp with time zone)',
        'trading.require_gas_program_shape(uuid,uuid,integer,date,date,timestamp with time zone,numeric,numeric,market_data.gas_valuation_assignments,ref_data.gas_delivery_conventions,timestamp with time zone,jsonb)',
    },
    '0327': {
        'ref_data.guard_definition()',
        'security.reference_display_tables()',
    },
    '0328': {
        'ref_data.clock_boundary(uuid,uuid,text,date)',
        'security.prepare_contract_observation_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,jsonb,uuid[])',
        'security.prepare_fixed_swap_period(uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone)',
        'security.prepare_floating_swap_period(uuid,uuid,uuid,uuid,text,jsonb,timestamp with time zone,integer,timestamp with time zone,uuid[])',
        'security.save_scheduled_swap(uuid,jsonb,jsonb,numeric,timestamp with time zone,jsonb,uuid[])',
        'security.staged_economic_side(uuid,uuid,integer)',
        'trading.require_side_payment_dates(uuid,uuid,jsonb)',
    },
    '0329': {
        'market_data.ppa_day_boundary(timestamp with time zone,uuid,uuid,ref_data.code)',
        'ref_data.captured_clock_boundary(jsonb,date)',
        'ref_data.clock_boundary(uuid,uuid,text,date)',
        'security.ppa_boundary(uuid,uuid,text,integer,timestamp with time zone,boolean)',
        'security.ppa_day_start(uuid,uuid,text,date)',
        'trading.require_side_payment_dates(uuid,uuid,jsonb)',
    },
    '0330': {
        'security.book_physical_lng(uuid,jsonb,timestamp with time zone)',
        'trading.require_lng_program_shape(uuid,uuid,integer,jsonb,market_data.lng_valuation_assignments)',
    },
}


def run_checks(query, migration):
    # Every calendar migration through LNG consumes an installed native helper.
    # A removed guard fails this suite before any new writer can be enabled.
    parts = migration.read_text().split('$calendar_helpers$')
    assert len(parts) == 3, f'{migration.name} must pin its native helper contracts'
    dependencies = json.loads(parts[1])
    signatures={d['signature'] for d in dependencies}
    assert len(signatures)==len(dependencies) and signatures==REQUIRED_SIGNATURES[migration.name[:4]], f'{migration.name} omitted or changed a required native consumer'
    if migration.name.startswith('0321_'):
        signature='trading.swap_revision_terms(uuid,uuid,integer)'
        change=f"DO $test$DECLARE source text=pg_get_functiondef('{signature}'::regprocedure);BEGIN IF strpos(source,'selected_revision integer DEFAULT NULL::integer')=0 THEN RAISE EXCEPTION 'Synthetic default fixture changed';END IF;EXECUTE replace(source,'selected_revision integer DEFAULT NULL::integer','selected_revision integer DEFAULT 1');END$test$;"
        check_guard(query,migration.read_text(),'0321','calendar_contract_upgrade',[(change,signature)])
        for view in ('trading.scheduled_swap_term_projection','trading.swap_period_input_projection'):
            changes=[(sql,view) for sql in (
                f'ALTER VIEW {view} SET(security_invoker=false);',
                f'ALTER VIEW {view} SET(security_barrier=true);',
                f'ALTER VIEW {view} OWNER TO CURRENT_USER;',
                f'GRANT SELECT ON {view} TO PUBLIC;',
                f'GRANT SELECT ON {view} TO openetrm_runtime WITH GRANT OPTION;',
                f'REVOKE SELECT ON {view} FROM openetrm_risk_worker;',
                f'GRANT SELECT(catalog_id) ON {view} TO PUBLIC;',
                f'CREATE RULE synthetic_calendar_rule AS ON UPDATE TO {view} DO INSTEAD NOTHING;',
                f"UPDATE pg_rewrite SET ev_enabled='D' WHERE ev_class='{view}'::regclass;",
                f"DO $$DECLARE d text=pg_get_viewdef('{view}'::regclass);BEGIN EXECUTE 'CREATE OR REPLACE VIEW {view} WITH(security_invoker=true) AS '||replace(d,'''calendar''','''synthetic_drift''');END$$;",
            )]
            check_guard(query,migration.read_text(),'0321','calendar_contract_upgrade',changes)
    owned=[d['signature'] for d in dependencies if d['owner']=='@migration_owner']
    for owner in ('Synthetic Calendar Owner', 'select') if owned else ():
        quoted='"'+owner+'"'
        changes=''.join(f'ALTER FUNCTION {signature} OWNER TO {quoted};' for signature in owned)
        query(f'BEGIN;CREATE ROLE {quoted} SUPERUSER;{changes}SET LOCAL ROLE {quoted};'+migration_body(migration.read_text())+'ROLLBACK;')
    check_helpers(query, migration, number=migration.name[:4], guard='calendar_contract_upgrade',
                  signatures=tuple(d['signature'] for d in dependencies))


if __name__ == '__main__':
    from check_reference_editing import main

    def before(query, migration):
        if migration.name[:4] in REQUIRED_SIGNATURES:
            run_checks(query, migration)

    main(checks=lambda query, manifest: None, before_migration=before)
