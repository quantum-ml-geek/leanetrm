"""Unpriced pure-market setup preserves exact source and point coordinates."""
import json

from point_trader_mark_fixture import literal


def setup(f, rejected):
    at = '2020-12-19T16:00:00.000001Z'
    context = f.market_context()
    filters = dict(curveCode='transport_rights', contractId=f.contract, search='', offset=0, limit=10,
        quoteFilter=None, eligibility=None)

    def read(selected=filters, *, profile='editor', when=at):
        return json.loads(f.call(f"SELECT security.point_trader_mark_setup('{f.catalog}','{context}','{when}',"
            f"'{f.definition_revision}','{f.reference}','{f.valuation_reference}',{literal(selected)});", profile=profile))

    before = f.publication_heads()
    found = read()
    assert found['contextId'] == context and found['source'] == dict(definitionRevisionId=f.definition_revision,
        referenceCatalogId=f.reference, referenceRevisionId=f.valuation_reference)
    assert found['asOf'] == at and found['effectiveOn'] == f.valuation_at[:10]
    assert len(found['choices']) == 1 and found['choices'][0]['target'] == f.point_target(at=at)
    assert found['choices'][0]['previous'] is None and found['choices'][0]['currency'] == 'USD'
    assert found['choices'][0]['valueUnit'] == 'package · quote multiplier 1' and found['canPublish'] is True
    assert found['page'] == dict(offset=0, limit=10, hasMore=False, search='')
    f.query("DELETE FROM security.role_permissions WHERE role_id=(SELECT id FROM security.roles WHERE code='viewer') AND permission='ReadTrades';")
    readonly = read(profile='viewer')
    assert readonly['choices'] == found['choices'] and readonly['canPublish'] is False
    assert f.publication_heads() == before
    rejected(lambda: read({k: v for k, v in filters.items() if k != 'eligibility'}), 'point_trader_mark_input')
    rejected(lambda: read({**filters, 'quoteFilter': dict(quantityCode='whole_transport_package')}), 'point_trader_mark_input')
    assert read({**filters, 'quoteFilter': dict(quantityCode='whole_transport_package', currencyCode='usd', multiplier='1')})['choices'] == found['choices']
    assert read({**filters, 'quoteFilter': dict(quantityCode='whole_transport_package', currencyCode='usd', multiplier='2')})['choices'] == []
    expired = read(when='2020-12-21T00:00:00Z')
    assert len(expired['choices']) == 1 and 'expired' in expired['choices'][0]['label'].lower()
    assert read({**filters, 'eligibility': 'live_at_value_time_v1'}, when='2020-12-21T00:00:00Z')['choices'] == []
    # Publication records an observed fact even when a financial consumer's
    # explicitly selected live-source law cannot execute it at this instant.
    expired_at = '2020-12-21T00:00:00Z'
    expired_context = f.market_context(day='2020-12-21')
    expired_body = f.command('17', target=f.point_target(at=expired_at))
    expired_fact = json.loads(f.call(f"SELECT security.record_point_trader_mark('{f.catalog}',gen_random_uuid(),"
        f"{literal(expired_body)},'{expired_context}','{expired_at}');", profile='editor'))
    assert expired_fact['changed'] is True and expired_fact['value'] == '17'
    print('PASS pure-market setup reads a genuinely empty point without trade authority, preserves exact time/source/units, and applies only explicitly selected quote/lifecycle filters.', flush=True)
