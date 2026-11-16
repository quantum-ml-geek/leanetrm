"""Exact aliases, temporal cuts, ordinary fact domains and readonly recovery."""
import json
from uuid import uuid4

from point_trader_mark_fixture import literal


def raw_observation(f, sample, fields):
    f.call(f"INSERT INTO market_data.observations SELECT(jsonb_populate_record(NULL::market_data.observations,"
        f"to_jsonb(o)||{literal(fields)}||jsonb_build_object('received_at',clock_timestamp()))).* "
        f"FROM market_data.observations o WHERE(o.catalog_id,o.id)=('{f.catalog}','{sample}');", profile='editor')


def boundaries(f, first, rejected):
    base = ['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333', 'synthetic_marks', 'trader_mark', '2020-12-19T16:00:00.000000Z']
    event = 'manual_point_event_v1:aa3a46ea0f3bbcff426d35997be62055325720d4d204f3ddc7d5bfaf806b3dd6'
    previous = '44444444-4444-4444-4444-444444444444'
    vectors = [('manual_point_event_v1', base, event.split(':')[1]),
        ('manual_point_revision_v1', base + [event, ''], '54861ecc22b49b11f9f70d24e23c2765c5e1cf3b59ac011518a53cd7ee5b266d'),
        ('manual_point_revision_v1', base + [' synthetic:é🙂:event ', previous], '7eb91ec132dca0c64cb25d695cc315e147928b1ef69be41aa06ad29f30fc4e07'),
        ('manual_point_revision_v1', base + ['synthetic\nevent', previous], '66051651b652e47170591ba80f335d6c97ff735217f6e5f9658f5a059b8fc854'),
        ('manual_point_revision_v1', base + ['synthetic:e\u0301', previous], '87b15bf1cf7e2411c7ecf8b667c99a6046c0b7bfcea7311ce3651ad8824ad5c9'),
        ('manual_point_revision_v1', base + ['synthetic:é', previous], '82f72034b99e1cfa9a72cb9081b9c511b41faa4db1e5e10c3179fa070f967523'),
        ('manual_point_event_v1', base[:-1] + ['2020-12-19T16:00:00.000001Z'], '3a97ab6e1cddb17d56b7eed347151e0931a22f04729d2cad6efad6ae47dcd617'),
        ('manual_point_event_v1', base[:-1] + ['2020-12-19T16:00:00.120000Z'], '7f2babeb6d3169c435d3f38e268d9496d9576c681bfc1f9ebf1b67df474d2b6b')]
    for domain, fields, digest in vectors:
        actual = f.query(f"SELECT market_data.point_trader_mark_identity('{domain}',ARRAY(SELECT jsonb_array_elements_text({literal(fields)})));")
        assert actual == domain + ':' + digest
    print('PASS eight independent native identity vectors preserve UTF-8 scalar bytes, opaque newline/spacing, distinct Unicode normalization and fixed-six microseconds.', flush=True)
    original_at = f.valuation_at
    before = f.publication_heads()
    alias = {**f.point_target(), 'curveCode': 'transport_rights_alias'}
    accepted = f.publish(f.command('20', target=alias))
    assert accepted['observationId'] == first['observationId'] and accepted['changed'] is False
    rejected(lambda: f.publish(f.command('20', target={**alias, 'curveCode': 'missing_alias'})), 'point_trader_mark_source')
    rejected(lambda: f.publish(f.command('20', target={**alias, 'contractId': f.provider_contract})), 'point_trader_mark_source')
    assert f.publication_heads() == before
    role = f.query("SELECT id FROM security.roles WHERE code='market_data_editor';")
    f.query(f"DELETE FROM security.role_permissions WHERE(role_id,permission)=('{role}','ImportObservations');")
    try:
        status = json.loads(f.call(f"SELECT security.point_trader_mark_status('{f.catalog}','{first['operationId']}');", profile='editor'))
        assert status['found'] and status['outcome'] == first and status['authorityUntil']
        absent = json.loads(f.call(f"SELECT security.point_trader_mark_status('{f.catalog}','{uuid4()}');", profile='editor'))
        assert absent['found'] is False and absent['authorityUntil']
        rejected(lambda: f.publish(f.command('20')), 'point_trader_mark_denied')
    finally:
        f.query(f"INSERT INTO security.role_permissions VALUES('{role}','ImportObservations');")
    rejected(lambda: f.call(f"SELECT security.point_trader_mark_status('{f.catalog}','{first['operationId']}');", profile='viewer'), 'point_trader_mark_conflict')
    assert f.query("SELECT NOT has_function_privilege('openetrm_risk_worker','security.record_point_trader_mark(uuid,uuid,jsonb,uuid,timestamptz)','EXECUTE') "
        "AND NOT has_table_privilege('openetrm_runtime','market_data.point_trader_mark_commands','SELECT');") == 't'
    print('PASS genuine aliases share point identity, forged aliases refuse, and actor-bound status needs market read without import or trade authority.', flush=True)
    try:
        f.valuation_at = '2020-12-19T16:00:00.000010Z'
        before = f.publication_heads()
        rejected(lambda: f.publish(f.command('1000000000')), 'point_trader_mark_input')
        for value in ['0.0000000000000000001', '1000000000000000000000000', '1e2', '+20', '01']:
            rejected(lambda: f.publish(f.command(value)), 'point_trader_mark_input')
        assert f.publication_heads() == before
        zero = f.publish(f.command('0.00'))
        assert zero['changed'] is True and zero['value'] == '0'
        f.valuation_at = '2020-12-19T16:00:00.000011Z'
        negative = f.publish(f.command('-12.5'))
        assert negative['changed'] is True and negative['value'] == '-12.5'

        f.valuation_at = '2020-12-19T16:00:00.000012Z'
        old_context = f.market_context()
        preliminary = str(uuid4())
        event = 'synthetic_preliminary_' + preliminary
        raw_observation(f, first['observationId'], dict(id=preliminary, source_event_id=event, source_revision_id='legacy_preliminary',
            publication_state='preliminary', observed_at=f.valuation_at, value=20, corrects_id=None))
        rejected(lambda: f.publish(f.command('20'), context=old_context), 'point_trader_mark_stale')
        rejected(lambda: f.publish(f.command('20', target=f.point_target(previous=preliminary, event=event))), 'point_trader_mark_source')

        f.valuation_at = '2020-12-19T16:00:00.000013Z'
        candidates = []
        for value in [1, 2]:
            observation = str(uuid4());event = 'synthetic_competing_' + observation
            raw_observation(f, first['observationId'], dict(id=observation, source_event_id=event, source_revision_id='legacy_revision',
                observed_at=f.valuation_at, value=value, corrects_id=None))
            candidates.append((observation, event))
        rejected(lambda: f.publish(f.command('3', target=f.point_target(previous=candidates[0][0], event=candidates[0][1]))), 'point_trader_mark_stale')

        f.valuation_at = '2020-12-19T16:00:00.000014Z'
        a = f.publish(f.command('1'));old_context = f.market_context();imported = str(uuid4())
        raw_observation(f, a['observationId'], dict(id=imported, source_revision_id='synthetic_late_import', value=2, corrects_id=a['observationId']))
        rejected(lambda: f.publish(f.command('3', target=f.point_target(previous=a['observationId'], event=a['sourceEventId'])), context=old_context), 'point_trader_mark_stale')
        refreshed = f.publish(f.command('3', target=f.point_target(previous=imported, event=a['sourceEventId'])))
        assert refreshed['changed'] is True and refreshed['previousObservationId'] == imported

        f.valuation_at = '2020-12-19T23:00:00Z'
        context = f.market_context(day='2020-12-20')
        cross = f.publish(f.command('4'), context=context)
        assert cross['observedAt'] == '2020-12-19T23:00:00.000000Z'
        assert f.call(f"SELECT security.use_market_context('{f.catalog}','{context}');"
            f"SELECT security.market_fact_visible('{f.catalog}','{f.definition_revision}','{cross['observationId']}');", profile='editor') == 'f'
        current = f.market_context(day='2020-12-20')
        assert f.call(f"SELECT security.use_market_context('{f.catalog}','{current}');"
            f"SELECT security.market_fact_visible('{f.catalog}','{f.definition_revision}','{cross['observationId']}');", profile='editor') == 't'
        print('PASS exact signed/zero/domain facts, preliminary and ambiguous-stream refusal, hidden corrections versus genuine refresh, and independent business-date knowledge cuts.', flush=True)
    finally:
        f.valuation_at = original_at
