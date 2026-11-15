"""A complete synthetic physical book for corrected operator value and risk."""
import json
from decimal import Decimal
from uuid import uuid4

from preview_fixture import fixture as base_fixture


CALENDAR = 'synthetic_operator_loss_horizon'
SESSION = 'synthetic_operator_physical_value'


def fixture(root):
    reference, market, security, manifest = base_fixture(root)
    catalog, revision = manifest['referenceCatalogId'], manifest['referenceRevisionId']
    # This consumer crosses the known Tuesday loss at the next stated close.
    # Existing calendars and every ordinary baseline session retain their dates.
    extra = f"""INSERT INTO ref_data.calendars
      SELECT catalog_id,revision_id,'{CALENDAR}',clock_code,weekend_mask,coverage_from,coverage_to
      FROM ref_data.calendars WHERE(catalog_id,revision_id,code)=('{catalog}','{revision}','test_business');
      INSERT INTO ref_data.calendar_days
      SELECT catalog_id,revision_id,'{CALENDAR}',business_date,is_business_day,description
      FROM ref_data.calendar_days WHERE(catalog_id,revision_id,calendar_code)=('{catalog}','{revision}','test_business');
      INSERT INTO ref_data.calendar_days VALUES
       ('{catalog}','{revision}','{CALENDAR}','2020-12-21',false,'Synthetic operator risk closure'),
       ('{catalog}','{revision}','{CALENDAR}','2020-12-22',false,'Synthetic operator risk closure');"""
    assert reference.count('COMMIT;') >= 1
    reference = reference.replace('COMMIT;', extra + '\nCOMMIT;', 1)
    return reference, market, security, manifest


def configure(query, manifest, call, capture, read, record, *, name='operator_value'):
    """Use ordinary native operations, then the shared paired-correction checks."""
    catalog = manifest['catalogId']
    at = '2020-12-20T16:00:00Z'
    literal = lambda value: "'" + json.dumps(value).replace("'", "''") + "'::jsonb"
    template = json.loads(query("SELECT to_jsonb(a) FROM trading.gas_owned_accounts a "
        f"WHERE(a.catalog_id,a.code)=('{catalog}','synthetic_owned_inventory_1');"))
    operator_template = json.loads(query("SELECT to_jsonb(a) FROM trading.gas_owned_accounts a "
        f"WHERE(a.catalog_id,a.code)=('{catalog}','synthetic_operator_balance_2');"))
    assert template['kind'] == 'owned_inventory' and operator_template['kind'] == 'operator_balance'
    book, owned, operator = (str(uuid4()) for _ in range(3))
    query(f"""BEGIN;
      INSERT INTO trading.publications SELECT '{catalog}',max(publication_order)+1,pg_current_xact_id()
       FROM trading.publications WHERE catalog_id='{catalog}';
      INSERT INTO trading.books SELECT catalog_id,'{book}',portfolio_id,'Synthetic operator physical value',
       (SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}'),'2020-12-18T00:00:00Z'
       FROM trading.books WHERE(catalog_id,id)=('{catalog}','{template['book_id']}');COMMIT;""")
    for identity, native, code in [(owned, template, f'synthetic_{name}_stock'),
                                   (operator, operator_template, f'synthetic_{name}_claim')]:
        record('account', dict(code=code, kind=native['kind'], bookId=book,
            legalEntityId=native['legal_entity_id'], legalEntityRevision=native['legal_entity_revision'],
            counterpartyId=native['counterparty_id'], counterpartyRevision=native['counterparty_revision'],
            referenceCatalogId=native['reference_catalog_id'], referenceRevisionId=native['reference_revision_id'],
            definitionRevisionId=native['definition_revision_id'], markCurve=native['mark_curve_code'],
            markContractId=native['mark_contract_id'], quantity=native['quantity_code'], currency=native['currency_code'],
            location=native['location_code'], titlePolicy=native['title_policy'], lossPolicy=native['loss_policy'],
            effectiveAt='2020-12-18T00:00:00Z'), target=identity)
    policies = {}
    for target, actions in [(owned, ['gas.owned.receive_title', 'gas.owned.loss']),
                            (operator, ['gas.operator.record', 'gas.operator.settle', 'gas.operator.reconcile_quantity'])]:
        for action in actions:
            policy = str(uuid4())
            call(f"SELECT lifecycle.save_policy('{catalog}'," + literal(dict(operationId=str(uuid4()), policyId=policy,
                expectedRevision=0, action=action, mode='manual', fromAt='2020-01-01T00:00:00Z',
                untilAt='2022-01-01T00:00:00Z', implementation='explicit_lifecycle_action_policy_v1')) + ');')
            record('bind_policy', dict(action=action, policyId=policy, policyRevision=1,
                effectiveAt='2020-12-18T00:00:00Z'), target=target)
            policies[target, action] = policy

    def evidence(target, key, kind, quantity, when):
        return record('evidence', dict(sourceKey=key, kind=kind, quantity=quantity, occurredAt=when,
            expectedRevision=0, evidence='Synthetic independent operator value evidence'), target=target)['id']

    def claim(quantity, suffix):
        document = evidence(operator, 'synthetic_value_' + suffix, 'operator_statement', quantity, '2020-12-19T12:00:00Z')
        return record('operator_claim', dict(evidenceId=document, quantity=quantity, effectiveAt='2020-12-19T12:00:00Z',
            dueAt='2020-12-24T12:00:00Z', carrying='nominal_mark_v1', settlementMode='return_quantity_v1', cashout=None),
            'gas.operator.record', operator)['id']

    positive = claim('10', 'positive_statement')
    title = evidence(owned, 'synthetic_value_positive_title', 'title_receipt', '10', '2020-12-20T12:00:00Z')
    settled = record('operator_settle', dict(positionId=positive, quantity='10', ownedAccountId=owned, lotId=None,
        reservationId=None, evidenceId=title, effectiveAt='2020-12-20T12:00:00Z', availableAt='2020-12-20T12:00:00Z',
        sourceObservationId=None), 'gas.operator.settle', operator)
    positive_source = read(positive, capture())
    receipt = positive_source['settlements'][0]['receiptLotId']
    assert positive_source['settlements'][0]['id'] == settled['id'] and receipt
    loss_document = evidence(owned, 'synthetic_value_future_loss', 'physical_loss', '2', '2020-12-22T12:00:00Z')
    loss = record('loss', dict(lotId=receipt, quantity='2', evidenceId=loss_document, reservationId=None,
        effectiveAt='2020-12-22T12:00:00Z'), 'gas.owned.loss', owned)
    funding_document = evidence(owned, 'synthetic_value_debt_funding', 'title_receipt', '3', '2020-12-19T12:00:00Z')
    funding = record('receive_title', dict(evidenceId=funding_document, quantity='3', titleAt='2020-12-19T12:00:00Z',
        availableAt='2020-12-19T12:00:00Z', originPolicy='opening_owned_stock_v1', carrying='nominal_mark_v1'),
        'gas.owned.receive_title', owned)['id']
    negative = claim('-3', 'negative_statement')
    dispatch_document = evidence(owned, 'synthetic_value_debt_dispatch', 'physical_delivery', '-2', '2020-12-20T13:00:00Z')
    dispatch = record('operator_settle', dict(positionId=negative, quantity='2', ownedAccountId=owned, lotId=funding,
        reservationId=None, evidenceId=dispatch_document, effectiveAt='2020-12-20T13:00:00Z', availableAt=None,
        sourceObservationId=None), 'gas.operator.settle', operator)
    negative_source = read(negative, capture())
    use = negative_source['settlements'][0]['consumptionId']
    assert negative_source['settlements'][0]['id'] == dispatch['id'] and use
    profiles = []
    for target in [owned, operator]:
        profile = str(uuid4())
        body = dict(profileId=profile, expectedRevision=0, implementation='gas_accepted_quantity_lifecycle_projection_v3',
            quantityDisposition='retain_quantity_obligations_v1', effectiveAt='2020-12-18T00:00:00Z', performances=[],cashouts=[])
        configured = json.loads(call(f"SELECT security.configure_gas_owned_projection('{catalog}','{uuid4()}',"
            f"'projection_profile','{target}',{literal(body)},'{at}','{capture()}',false)::text;"))
        assert configured['changed']
        profiles.append(dict(accountId=target, profileId=profile, revision=1))
    original_context = capture()
    policy = policies[operator, 'gas.operator.reconcile_quantity']

    def amend(body, operation, context, receipt_only=False):
        return json.loads(call(f"SELECT security.reconcile_gas_operator_quantities('{catalog}','{operation}','{operator}',"
            f"{literal(body)},'{at}','{context}','{policy}',1,{'true' if receipt_only else 'false'})::text;"))

    from gas_operator_counterpart_cases import checks as counterpart_checks
    counterpart_checks(query, manifest, call, capture, read, record, amend,
        dict(at=at,counterpartCases=[dict(claimId=positive), dict(claimId=negative)]))
    from close_session_fixture import sql_session
    session=SESSION if name=='operator_value' else 'synthetic_'+name+'_value'
    sql_session(query, manifest, session, CALENDAR, '16:00:00', ['future'], [], effective=('2020-01-01', '2022-01-01'))
    current_context = capture()
    assert Decimal(read(positive, current_context)['claim']['remainingQuantity']) == 0
    assert Decimal(read(negative, current_context)['claim']['remainingQuantity']) == Decimal('-1.5')
    return dict(bookId=book, accountId=owned, operatorAccountId=operator, profiles=profiles, at=at,
        originalContextId=original_context, contextId=current_context, receiptId=receipt, fundingId=funding,
        positiveClaimId=positive, negativeClaimId=negative, receiptSettlementId=settled['id'],
        dispatchSettlementId=dispatch['id'], consumptionId=use, futureLossId=loss['id'], economicSession=session,policyId=policy,policyRevision=1)
