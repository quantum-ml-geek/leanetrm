"""Canonical payment-day program admission over populated synthetic schedules."""
from pathlib import Path
from check_reference_editing import main
from check_retained_side_schedules import run_stage_checks

SIGNATURES = (
    'security.begin_side_schedule(uuid,uuid,integer,jsonb,text,uuid,integer,jsonb)',
    'trading.side_program_document(uuid,uuid)',
    'trading.require_side_program_content(uuid,uuid,bytea)',
    'security.seal_side_schedule_program(uuid,uuid,uuid,bytea)',
    'security.read_instrument_side_programs(uuid,uuid,uuid,timestamptz)',
    'security.seal_side_schedule(uuid,uuid,uuid,text)',
)


def qualification():
    predecessor = []
    migration_path = Path(__file__).resolve().parents[1] / 'db/migrations/0256_utc_payment_day_programs.sql'

    def before(query, migration):
        if migration == migration_path:
            predecessor.extend(query(f"SELECT pg_get_functiondef('{signature}'::regprocedure);") for signature in SIGNATURES)

    def checks(query, manifest):
        assert len(predecessor) == len(SIGNATURES), 'The upgrade must start from the actual preceding admission functions.'
        current_begin = query(f"SELECT pg_get_functiondef('{SIGNATURES[0]}'::regprocedure);")
        current_seal = query(f"SELECT pg_get_functiondef('{SIGNATURES[-1]}'::regprocedure);")
        # Only this newly owned database is returned to its preceding admission
        # boundary so the shared synthetic fixture can create real sealed content.
        query(';\n'.join(predecessor) + ";" + """
            ALTER TABLE trading.side_schedule_programs DROP CONSTRAINT side_schedule_programs_version_check;
            ALTER TABLE trading.side_schedule_programs ADD CONSTRAINT side_schedule_programs_version_check
            CHECK(version='booked_side_program_v1') NOT VALID;
        """)
        run_stage_checks(query, manifest, generator_version='whole_term_side_blocks_v2', program_version='booked_side_program_v1')

        def retained():
            return {table: query(f"SELECT encode(sha256(convert_to(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb)::text,'UTF8')),'hex') FROM trading.{table} t;")
                    for table in ('sides', 'side_schedules', 'side_schedule_requests', 'side_schedule_rows',
                                  'side_schedule_programs', 'side_schedule_seals')}

        original = retained()
        query(migration_path.read_text())
        query(current_begin + ';' + current_seal)
        assert retained() == original, 'An upgrade must preserve retained identities, requests, dates, manifests and executable bytes.'
        assert query("SELECT count(*) FROM trading.side_schedule_programs WHERE version='booked_side_program_v1';") != '0'
        for signature in SIGNATURES[:-1]:
            definition = query(f"SELECT pg_get_functiondef('{signature}'::regprocedure);")
            assert 'booked_side_program_v1' not in definition and 'whole_term_side_blocks_v2' not in definition
        assert query("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='trading.side_schedule_programs'::regclass AND conname='side_schedule_programs_version_check';") == "CHECK ((version = 'booked_side_program_v2'::text)) NOT VALID"
        run_stage_checks(query, manifest)
        print('PASS payment-day upgrade: original sealed programs unchanged; one admitted generator and executable version; immutable native staging parity', flush=True)

    main(checks=checks, before_migration=before)


if __name__ == '__main__':
    qualification()
