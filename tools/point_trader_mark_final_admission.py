"""Final source seals and concurrent commands preserve one genuine point head."""
import json
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

from point_trader_mark_fixture import literal


def final_admission(f, rejected):
    original = f.valuation_at
    try:
        f.valuation_at = '2020-12-19T16:00:00.000030Z'
        first = f.publish(f.command('1'))
        body = f.command('2', target=f.point_target(previous=first['observationId'], event=first['sourceEventId']))
        context = f.market_context()

        def command_and_import(operation, *, unrelated=False, acknowledge=False):
            selected = f.command('1') if acknowledge else body
            extra = dict(id=str(uuid4()), source_revision_id='synthetic_late_ordinary_import', value=3,
                source_event_id='synthetic_independent_point' if unrelated else first['sourceEventId'],
                observed_at='2020-12-19T16:00:00.000031Z' if unrelated else f.valuation_at)
            predecessor = 'NULL::uuid' if unrelated else f"'{accepted['observationId']}'::uuid" if acknowledge else "(accepted.outcome->>'observationId')::uuid"
            return f.call(f"WITH accepted AS MATERIALIZED(SELECT security.record_point_trader_mark('{f.catalog}','{operation}',{literal(selected)},'{context}','{f.valuation_at}') outcome) "
                "INSERT INTO market_data.observations SELECT(jsonb_populate_record(NULL::market_data.observations,"
                f"to_jsonb(o)||{literal(extra)}||jsonb_build_object('corrects_id',{predecessor},'received_at',clock_timestamp()))).* "
                f"FROM market_data.observations o CROSS JOIN accepted WHERE(o.catalog_id,o.id)=('{f.catalog}','{first['observationId']}');", profile='editor')

        before = f.publication_heads()
        operation = str(uuid4())
        rejected(lambda: command_and_import(operation), 'point_trader_mark_stale')
        assert f.publication_heads() == before
        assert f.query(f"SELECT count(*) FROM market_data.point_trader_mark_commands WHERE(catalog_id,operation_id)=('{f.catalog}','{operation}');") == '0'
        honest = str(uuid4())
        command_and_import(honest, unrelated=True)
        accepted = json.loads(f.call(f"SELECT security.point_trader_mark_status('{f.catalog}','{honest}');", profile='editor'))['outcome']
        assert accepted['changed'] is True and accepted['previousObservationId'] == first['observationId']
        # Old authentic acknowledgement remains a read of its accepted fact,
        # even if a later ordinary source correction arrives in the same write.
        command_and_import(str(uuid4()), acknowledge=True)
        orphan = dict(id=str(uuid4()), source_event_id='synthetic_orphan_manual_point',
            source_revision_id='manual_point_revision_v1:' + '0' * 64, corrects_id=None,
            observed_at='2020-12-19T16:00:00.000032Z')
        rejected(lambda: f.call("INSERT INTO market_data.observations SELECT(jsonb_populate_record(NULL::market_data.observations,"
            f"to_jsonb(o)||{literal(orphan)}||jsonb_build_object('received_at',clock_timestamp()))).* "
            f"FROM market_data.observations o WHERE(o.catalog_id,o.id)=('{f.catalog}','{first['observationId']}');", profile='editor'), 'point_trader_mark_receipt')

        for offset, values in [('000040', ['20', '20']), ('000041', ['20', '21'])]:
            f.valuation_at = '2020-12-19T16:00:00.' + offset + 'Z'
            context = f.market_context()
            commands = [f.command(value) for value in values]
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(f.publish, command, context=context) for command in commands]
                outcomes, conflicts = [], 0
                for future in futures:
                    try:
                        outcomes.append(future.result(timeout=15))
                    except RuntimeError as error:
                        assert 'point_trader_mark_conflict' in str(error), str(error)
                        conflicts += 1
            assert sum(outcome['changed'] for outcome in outcomes) == 1
            if values[0] == values[1]:
                assert conflicts == 0 and len(outcomes) == 2 and outcomes[0]['observationId'] == outcomes[1]['observationId']
            else:
                assert conflicts == 1 and len(outcomes) == 1
            assert f.query(f"SELECT count(*) FROM market_data.observations WHERE(catalog_id,definition_revision_id,series_id,observed_at)="
                f"('{f.catalog}','{f.definition_revision}','{f.series}','{f.valuation_at}');") == '1'
        print('PASS final source admission rejects a later same-transaction correction after eager validation, permits unrelated facts and authentic old acknowledgements, rejects orphan manual facts, and serializes equal/conflicting first publications.', flush=True)
    finally:
        f.valuation_at = original
