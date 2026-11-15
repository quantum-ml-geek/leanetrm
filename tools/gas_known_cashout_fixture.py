"""A complete synthetic book with source-known future cashout memberships."""
import json
from decimal import Decimal
from uuid import uuid4
from preview_fixture import fixture as base_fixture
CALENDAR = 'synthetic_accepted_cashout_horizon'
SESSION = 'synthetic_accepted_cashout_value'

def fixture(root):
    reference, market, security, manifest = base_fixture(root)
    cat, rev = (manifest['referenceCatalogId'], manifest['referenceRevisionId'])
    extra = f"INSERT INTO ref_data.calendars SELECT catalog_id,revision_id,'{CALENDAR}',clock_code,weekend_mask,coverage_from,coverage_to FROM ref_data.calendars WHERE(catalog_id,revision_id,code)=('{cat}','{rev}','test_business');\n INSERT INTO ref_data.calendar_days SELECT catalog_id,revision_id,'{CALENDAR}',business_date,is_business_day,description FROM ref_data.calendar_days WHERE(catalog_id,revision_id,calendar_code)=('{cat}','{rev}','test_business');\n INSERT INTO ref_data.calendar_days VALUES('{cat}','{rev}','{CALENDAR}','2020-12-21',false,'Synthetic accepted cashout closure'),('{cat}','{rev}','{CALENDAR}','2020-12-22',false,'Synthetic accepted cashout closure');"
    reference = reference.replace('COMMIT;', extra + '\nCOMMIT;', 1)
    return (reference, market, security, manifest)

def configure(query, manifest, call, capture, read, record, amend, packet, *, mode='normal'):
    assert mode in ('normal','zero','due','paid')
    zero=mode=='zero'
    cat = manifest['catalogId']
    at = packet['at']
    fix_at = {'normal':'2020-12-21T12:00:00Z','zero':'2020-12-21T11:00:00Z','due':'2020-12-21T10:00:00Z','paid':'2020-12-21T09:00:00Z'}[mode]
    due_at='2020-12-22T12:00:00Z' if mode=='due' else '2020-12-24T12:00:00Z'
    official_price = '0' if zero else '1.005'
    literal = lambda x: "'" + json.dumps(x).replace("'", "''") + "'::jsonb"
    template = json.loads(query(f"SELECT to_jsonb(a) FROM trading.gas_owned_accounts a WHERE(catalog_id,id)=('{cat}','{packet['accountId']}');"))
    book, account = (str(uuid4()), str(uuid4()))
    query(f"BEGIN;INSERT INTO trading.publications SELECT '{cat}',max(publication_order)+1,pg_current_xact_id() FROM trading.publications WHERE catalog_id='{cat}';INSERT INTO trading.books SELECT catalog_id,'{book}',portfolio_id,'Synthetic accepted cashout',(SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{cat}'),'2020-12-18T00:00:00Z' FROM trading.books WHERE(catalog_id,id)=('{cat}','{template['book_id']}');COMMIT;")
    record('account', dict(code='synthetic_accepted_cashout_'+mode, kind='operator_balance', bookId=book, legalEntityId=template['legal_entity_id'], legalEntityRevision=template['legal_entity_revision'], counterpartyId=template['counterparty_id'], counterpartyRevision=template['counterparty_revision'], referenceCatalogId=template['reference_catalog_id'], referenceRevisionId=template['reference_revision_id'], definitionRevisionId=template['definition_revision_id'], markCurve=template['mark_curve_code'], markContractId=template['mark_contract_id'], quantity=template['quantity_code'], currency=template['currency_code'], location=template['location_code'], titlePolicy=template['title_policy'], lossPolicy=template['loss_policy'], effectiveAt='2020-12-18T00:00:00Z'), target=account)
    for action in ['gas.operator.record', 'gas.operator.settle', 'gas.cash.record_payment']:
        policy = str(uuid4())
        call(f"SELECT lifecycle.save_policy('{cat}'," + literal(dict(operationId=str(uuid4()), policyId=policy, expectedRevision=0, action=action, mode='manual', fromAt='2020-01-01T00:00:00Z', untilAt='2022-01-01T00:00:00Z', implementation='explicit_lifecycle_action_policy_v1')) + ');')
        record('bind_policy', dict(action=action, policyId=policy, policyRevision=1, effectiveAt='2020-12-18T00:00:00Z'), target=account)

    def evidence(key, kind, quantity, when):
        return record('evidence', dict(sourceKey=key, kind=kind, quantity=quantity, occurredAt=when, expectedRevision=0, evidence='Synthetic accepted cashout evidence'), target=account)['id']
    point = str(uuid4())
    terms = packet['cashoutTerms']
    query('INSERT INTO market_data.observations SELECT catalog_id,' + f"'{point}',definition_revision_id,series_id,reference_catalog_id,reference_revision_id,source_code,'synthetic_accepted_cashout_{mode}','1',role,'final','{fix_at}',clock_timestamp(),{official_price},NULL FROM market_data.observations WHERE(catalog_id,id)=('{cat}','{packet['originalObservationId']}');")
    statement = evidence('synthetic_accepted_cashout_statement', 'operator_statement', '3', '2020-12-19T12:00:00Z')
    claim = record('operator_claim', dict(evidenceId=statement, quantity='3', effectiveAt='2020-12-19T12:00:00Z', dueAt=due_at, carrying='nominal_mark_v1', settlementMode='cashout_final_price_v1', cashout=dict(source=terms['source_code'], role=terms['role'], observedAt=fix_at, cashDueAt=due_at, rounding=terms['rounding'])), 'gas.operator.record', account)['id']
    settlements = []
    for key, quantity, when in [('first', '1', '2020-12-21T13:00:00Z'), ('second', '2', '2020-12-21T14:00:00Z')]:
        doc = evidence('synthetic_accepted_cashout_' + key, 'cashout_determination', quantity, when)
        settlements.append(record('operator_settle', dict(positionId=claim, quantity=quantity, ownedAccountId=None, lotId=None, reservationId=None, evidenceId=doc, effectiveAt=when, availableAt=None, sourceObservationId=point), 'gas.operator.settle', account))
    for index,amount in ([] if zero else [(0,'1'),(1,'2.02')] if mode=='paid' else [(0,'0.25')]):
        record('fee_payment',dict(feeId=settlements[index]['cashId'],businessKey='synthetic_accepted_cashout_bank',expectedRevision=0,amount=amount,paidAt='2020-12-22T15:00:00Z',evidence='Synthetic original bank payment'),'gas.cash.record_payment',account)
    profile = str(uuid4())
    body = dict(profileId=profile, expectedRevision=0, implementation='gas_accepted_quantity_lifecycle_projection_v3', quantityDisposition='retain_quantity_obligations_v1', effectiveAt='2020-12-18T00:00:00Z', performances=[], cashouts=[])
    call(f"SELECT security.configure_gas_owned_projection('{cat}','{uuid4()}','projection_profile','{account}',{literal(body)},'{at}','{capture()}',false);")
    from close_session_fixture import sql_session
    if mode=='normal':sql_session(query, manifest, SESSION, CALENDAR, '16:00:00', ['future'], [], effective=('2020-01-01', '2022-01-01'))
    context = capture()
    native = read(claim, context)
    assert native['claim']['remainingQuantity'] == '3'
    assert sorted((Decimal(row['amount']) for row in native['cash'])) == ([] if zero else [Decimal('1'), Decimal('2.02')])
    mark = '70000000-0000-0000-0000-000000000001'
    price = Decimal(query(f"SELECT value FROM market_data.observations WHERE(catalog_id,id)=('{cat}','{mark}');"))
    scale = Decimal(query(f"SELECT q.multiplier FROM market_data.curves c JOIN ref_data.quote_specifications q ON(q.catalog_id,q.revision_id,q.code)=(c.reference_catalog_id,c.reference_revision_id,c.quote_code) WHERE(c.catalog_id,c.revision_id,c.code)=('{cat}','{manifest['revisionId']}','future');"))
    rates = json.loads(query('SELECT jsonb_agg(o.id ORDER BY t.ordinal) FROM market_data.rate_curves c JOIN market_data.rate_curve_tenors t ON(t.catalog_id,t.revision_id,t.curve_code)=(c.catalog_id,c.revision_id,c.code) JOIN market_data.observations o ON(o.catalog_id,o.definition_revision_id,o.series_id,o.source_code)=(c.catalog_id,c.revision_id,t.series_id,c.source_code) ' + f"WHERE(c.catalog_id,c.revision_id,c.code)=('{cat}','{manifest['revisionId']}','interest_rates') AND o.role='parameter' AND o.publication_state='final' AND o.observed_at='2020-12-18T16:00:00Z' AND NOT EXISTS(SELECT 1 FROM market_data.observations n WHERE(n.catalog_id,n.corrects_id)=(o.catalog_id,o.id));"))
    assert rates and query(f"SELECT bool_and(value=0) FROM market_data.observations WHERE catalog_id='{cat}' AND id=ANY(ARRAY[{','.join((repr(x) + '::uuid' for x in rates))}]);") == 't'
    return dict(mode=mode,contextId=context, at=at, bookId=book, accountId=account, positionId=claim, cashIds=[] if zero else [settlements[0]['cashId'],settlements[1]['cashId']], profileId=profile, economicSession=SESSION, markId=mark, rateIds=rates if mode=='normal' else [], contractId=template['mark_contract_id'], expectedOpening=str(3 * price * scale), expectedResidual='0' if mode in ('zero','paid') else '2.77',expectedCash='0' if zero else '3.02' if mode=='paid' else '0.25',cashResiduals=[] if zero else ['0','0'] if mode=='paid' else ['0.75','2.02'],bankAmounts=[] if zero else ['1','2.02'] if mode=='paid' else ['0.25','0'], expectedPnl=str((Decimal('0') if zero else Decimal('3.02')) - 3 * price * scale), expectedHistoricalVar=str(3 * price * scale - Decimal('3.02')))
