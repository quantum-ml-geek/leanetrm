"""Publish real direct Final TraderMarks without financial or operating authority."""
import json
import os
from uuid import uuid4

from check_reference_editing import main
from point_trader_mark_fixture import PointTraderMarkFixture, fixture, literal


def rejected(work, code):
    try:
        work()
    except RuntimeError as error:
        assert code in str(error), str(error)
    else:
        raise AssertionError('Expected ' + code)


def checks(query, manifest):
    f = PointTraderMarkFixture(query, manifest)
    context = f.market_context()
    proof = json.loads(f.call(f"SELECT security.use_market_context('{f.catalog}','{context}');"
        f"SELECT jsonb_build_object('definition',security.market_fact_visible('{f.catalog}','{f.definition_revision}',NULL),"
        f"'reference',security.reference_version_visible('{f.reference}','{f.valuation_reference}'),"
        "'read',security.has_permission('ReadMarketData'),'import',security.has_permission('ImportObservations'),"
        "'trades',security.has_permission('ReadTrades'),'gas',security.has_permission('ReadGasOperations'));", profile='editor'))
    assert proof == {'definition': True, 'reference': True, 'read': True, 'import': True, 'trades': False, 'gas': False}, proof
    assert query(f"SELECT count(*) FROM market_data.observations WHERE(catalog_id,definition_revision_id,series_id)="
        f"('{f.catalog}','{f.definition_revision}','{f.series}');") == '0'
    assert query(f"SELECT count(*) FROM market_data.curves c JOIN market_data.curve_members m "
        "ON(m.catalog_id,m.revision_id,m.curve_code)=(c.catalog_id,c.revision_id,c.code) "
        "JOIN market_data.series s ON(s.catalog_id,s.revision_id,s.contract_id,s.quote_code)=(c.catalog_id,c.revision_id,m.contract_id,c.quote_code) "
        f"WHERE(c.catalog_id,c.revision_id,c.code,s.id)=('{f.catalog}','{f.definition_revision}','transport_rights','{f.series}') "
        "AND c.rule='direct' AND c.direct_role='trader_mark';") == '1'
    print('PASS genuine empty direct point, exact independent reference and market-only editor are executable before publisher admission.', flush=True)

    booking = f.booking(key='synthetic_missing_first_point')
    financial = f.book_financial(booking)
    missing = f.read_financial(financial['tradeId'])
    assert missing['mark'] is None and missing['unpricedReason'] == 'rights_mark_required'
    from gas_transport_financial_managed import value
    value(f, financial['tradeId'], rate_ids=[], reason='rights_mark_required')

    first_body, first_operation = f.command('20.00'), str(uuid4())
    before = f.publication_heads()
    first = f.publish(first_body, operation=first_operation, context=context)
    assert first['operationId'] == first_operation and first['changed'] is True and first['value'] == '20'
    assert first['previousObservationId'] is None and first['knowledgeEventOrder'] > 0 and first['publicationXid'].isdecimal()
    row = json.loads(query(f"SELECT to_jsonb(o) FROM market_data.observations o WHERE(catalog_id,id)=('{f.catalog}','{first['observationId']}');"))
    assert row['definition_revision_id'] == f.definition_revision and row['series_id'] == f.series
    assert row['role'] == 'trader_mark' and row['publication_state'] == 'final' and row['value'] == 20
    assert row['source_event_id'] == first_body['target']['sourceEventId']
    assert row['source_revision_id'] == first_body['target']['sourceRevisionToken']
    assert first['sourceRevisionId'] == row['source_revision_id'] and 'sourceRevisionToken' not in first
    published = f.publication_heads()
    before_counts, published_counts = json.loads(before), json.loads(published)
    assert published_counts == [before_counts[0] + 1, before_counts[1] + 1, before_counts[2]], (before_counts, published_counts)
    assert f.read_financial(financial['tradeId'])['mark'] is None, 'Publishing a market value must not adopt it to a financial agreement.'
    f.observation = first['observationId']
    adopted = f.record_financial(f.mark(financial['tradeId'], booking['operationId']))
    current = f.read_financial(financial['tradeId'])
    assert current['mark']['id'] == adopted['markId'] and current['mark']['observationId'] == first['observationId']
    value(f, financial['tradeId'], rate_ids=f.rate_observations[f.valuation_at], mark=current['mark'], expected='7.5')
    imported_id = str(uuid4())
    imported_event = ' Synthetic imported event:\nopaque\u00a0 '
    imported_revision = 'manualXpointYrevisionZv1:opaque-imported-revision'
    f.call(f"INSERT INTO market_data.observations SELECT(jsonb_populate_record(NULL::market_data.observations,to_jsonb(o)||"
        f"jsonb_build_object('id','{imported_id}','series_id','{f.provider_series}','source_event_id',({literal(imported_event)}#>>'{{}}'),"
        f"'source_revision_id','{imported_revision}','value',-20,'corrects_id',NULL,'received_at',clock_timestamp()))).* "
        f"FROM market_data.observations o WHERE(o.catalog_id,o.id)=('{f.catalog}','{first['observationId']}');", profile='editor')
    imported_target = f.point_target(previous=imported_id, event=imported_event, curve='provider_transport_rights',
        contract=f.provider_contract, series=f.provider_series)
    imported_before = f.publication_heads()
    imported_ack = f.publish(f.command('-20', target=imported_target))
    assert imported_ack['observationId'] == imported_id and imported_ack['changed'] is False
    assert imported_ack['sourceRevisionId'] == imported_revision and imported_ack['sourceEventId'] == imported_event
    assert imported_ack['previousObservationId'] is None and f.publication_heads() == imported_before
    print('PASS a genuine imported Final predecessor acknowledges its equal value and opaque event/revision lineage without a manual observation receipt or broad prefix restriction.', flush=True)
    after = f.publication_heads()
    assert f.publish(first_body, operation=first_operation, context=context) == first
    ack = f.publish(f.command('20', evidence='Synthetic later receipt cannot replace original evidence'), context=context)
    assert ack['changed'] is False and ack['observationId'] == first['observationId'] and ack['operationId'] != first_operation
    assert f.publication_heads() == after
    rejected(lambda: f.publish(f.command('21'), context=context), 'point_trader_mark_conflict')
    rejected(lambda: f.publish(f.command('20'), profile='viewer'), 'point_trader_mark_denied')

    second_target = f.point_target(previous=first['observationId'], event=first['sourceEventId'])
    second = f.publish(f.command('21', target=second_target))
    third_target = f.point_target(previous=second['observationId'], event=second['sourceEventId'])
    third = f.publish(f.command('20', target=third_target))
    assert len({first['observationId'], second['observationId'], third['observationId']}) == 3
    assert third['previousObservationId'] == second['observationId'] and third['sourceEventId'] == first['sourceEventId']
    after = f.publication_heads()
    assert f.publish(first_body, operation=first_operation, context=context) == first
    assert f.publish(first_body, context=context)['observationId'] == first['observationId']
    assert f.publish(f.command('20', target=third_target))['observationId'] == third['observationId']
    assert f.publication_heads() == after
    print('PASS first20, correction21, genuine new20, exact old retry and retained revision acknowledgement preserve one immutable current stream.', flush=True)

    # A prospective successor token is not a fact/reservation when the value
    # equals its explicitly selected predecessor. Only an observation owns it.
    fourth_target = f.point_target(previous=third['observationId'], event=third['sourceEventId'])
    from point_trader_mark_seals import same_value_changed
    same_value_changed(f, second, fourth_target, rejected)
    unchanged_body, unchanged_operation, unchanged_context = f.command('20.0', target=fourth_target), str(uuid4()), f.market_context()
    unchanged = f.publish(unchanged_body, operation=unchanged_operation, context=unchanged_context)
    second_unchanged = f.publish(unchanged_body)
    assert unchanged['changed'] is False and unchanged['observationId'] == third['observationId']
    assert unchanged['sourceRevisionId'] == third['sourceRevisionId'] and unchanged['previousObservationId'] == second['observationId']
    assert second_unchanged['observationId'] == third['observationId'] and f.publication_heads() == after
    assert query(f"SELECT count(*) FROM market_data.observations WHERE catalog_id='{f.catalog}' "
        f"AND source_revision_id='{fourth_target['sourceRevisionToken']}';") == '0'
    fourth = f.publish(f.command('21', target=fourth_target))
    assert fourth['changed'] is True and fourth['observationId'] != third['observationId']
    assert fourth['sourceRevisionId'] == fourth_target['sourceRevisionToken'] and fourth['previousObservationId'] == third['observationId']
    after_fourth = f.publication_heads()
    assert f.publish(unchanged_body, operation=unchanged_operation, context=unchanged_context) == unchanged
    assert f.publish(unchanged_body)['observationId'] == third['observationId']
    assert f.publication_heads() == after_fourth
    print('PASS two equal-predecessor acknowledgements never reserve a prospective revision; a real changed value can use it, and old no-op recovery never rewinds that new head.', flush=True)
    from point_trader_mark_setup import setup
    setup(f, rejected)
    from point_trader_mark_boundaries import boundaries
    boundaries(f, first, rejected)
    from point_trader_mark_authority import authority
    authority(f, rejected)
    from point_trader_mark_final_admission import final_admission
    final_admission(f, rejected)


if __name__ == '__main__':
    if not os.environ.get('DOTNET'):
        raise SystemExit('DOTNET is required for the real managed financial consumer checks.')
    main(checks, fixture_factory=fixture)
