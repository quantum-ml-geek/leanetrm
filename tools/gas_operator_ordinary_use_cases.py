"""Operator receipt correction requires an explicit surviving ordinary-use plan."""
from datetime import datetime,timezone
import json
from uuid import uuid4

PRESERVE='preserve_unallocated_source_quantity_v1'


def _literal(value):return "'"+json.dumps(value).replace("'","''")+"'::jsonb"


def checks(query,manifest,call,capture,read,record,amend,packet):
    catalog=manifest['catalogId'];case=next(row for row in packet['counterpartCases'] if row['receiptLotId'])
    claim=case['claimId'];lot=case['receiptLotId'];loss=case['lossIds'][0];at='2020-12-23T16:00:00Z'
    def source(context):return json.loads(call(f"SELECT security.use_market_context('{catalog}','{context}');"
        f"SELECT security.use_trading_context('{catalog}','{at}','2020-12-23'::date);"
        f"SELECT security.read_gas_operator_quantity_reconciliation('{catalog}','{claim}','{context}','{at}')::text;"))
    before_context=capture('2020-12-23');before=source(before_context)
    assert before['claim']['quantity']=='9' and before['claim']['remainingQuantity']=='0'
    step=before['settlements'][0];use=next(row for row in before['consumptions'] if row['id']==loss)
    assert use['editable'] is True and use['quantity']=='2' and step['receiptLotId']==lot
    receipt=next(row for row in before['positions'] if row['id']==lot)
    def revised(evidence_id,quantity):
        old=next(row for row in before['evidence'] if row['id']==evidence_id)
        occurred=datetime.fromisoformat(old['occurred_at']).astimezone(timezone.utc).isoformat().replace('+00:00','Z')
        return record('evidence',dict(sourceKey=old['source_key'],kind=old['kind'],quantity=quantity,occurredAt=occurred,
            expectedRevision=old['revision'],evidence='Synthetic explicit operator receipt and ordinary-use correction'),target=old['account_id'])['id']
    claim_evidence=revised(before['claim']['evidenceId'],'1');receipt_evidence=revised(step['evidenceId'],'1');loss_evidence=revised(use['evidenceId'],'1')
    body=dict(implementation='gas_operator_quantity_reconciliation_v1',rootClaimId=claim,claims=[dict(claimId=claim,
        expectedRevision=before['claim']['expectedRevision'],quantity='1',evidenceId=claim_evidence,sourceAllocation=PRESERVE,
        settlements=[dict(settlementId=step['id'],expectedRevision=step['expectedRevision'],quantity='1',evidenceId=receipt_evidence,
            sourceObservationId=None,expectedReceiptRevision=receipt['expectedRevision'],expectedConsumptionRevision=None,
            lotId=None,reservationId=None,sourceAllocation=PRESERVE)])],consumptions=[],
        cashout=dict(ordering='replay_original_settlement_publication_prefix_v1',adjustmentDueAt=None),
        evidence='Synthetic complete selected claim, title receipt and ordinary loss closure')
    context=capture('2020-12-23')
    def correct(selection,operation,selected_context=context):return json.loads(call(f"SELECT security.reconcile_gas_operator_quantities("
        f"'{catalog}','{operation}','{packet['accountId']}',{_literal(selection)},'{at}','{selected_context}','{packet['policyId']}',{packet['policyRevision']},false)::text;"))
    publication=query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")
    try:correct(body,str(uuid4()))
    except RuntimeError as error:assert 'gas_stock_capacity' in str(error),str(error)
    else:raise AssertionError('A reduced operator title silently resized or omitted its independent surviving loss.')
    assert query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")==publication
    body['consumptions']=[dict(consumptionId=loss,expectedRevision=use['expectedRevision'],lotId=lot,quantity='1',retracted=False,
        evidenceId=loss_evidence,reservationId=use['reservation_id'],sourceAllocation=PRESERVE)]
    operation=str(uuid4());outcome=correct(body,operation)
    assert outcome['changed'] and not outcome['semanticAcknowledgement'] and outcome['cashChanges']==[]
    assert len(outcome['consumptions'])==1
    taken=outcome['consumptions'][0]
    assert taken['consumptionId']==loss and taken['currentRevision']==2 and taken['currentQuantity']=='1' and taken['changed']
    current=source(capture('2020-12-23'))
    assert current['claim']['quantity']=='1' and current['claim']['remainingQuantity']=='0'
    assert current['settlements'][0]['quantity']=='1' and current['settlements'][0]['expectedRevision']==3
    assert next(row for row in current['positions'] if row['id']==lot)['quantity']=='1'
    assert next(row for row in current['consumptions'] if row['id']==loss)['quantity']=='1'
    book=next(row['book_id'] for row in current['accounts'] if row['id']==receipt['account_id'])
    selected_context=capture('2020-12-23')
    held=json.loads(call(f"SELECT security.use_market_context('{catalog}','{selected_context}');SELECT security.use_trading_context('{catalog}','{at}','2020-12-23'::date);"
        f"SELECT security.read_gas_owned_holdings('{catalog}','{selected_context}','{at}',ARRAY['{book}']::uuid[])::text;"))
    assert claim not in {row['id'] for row in held['positions']} and lot not in {row['id'] for row in held['positions']}
    assert int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))==int(publication)+1
    assert correct(body,operation)==outcome
    old=source(before_context)
    assert old['claim']['quantity']=='9' and old['settlements'][0]['quantity']=='9' and next(row for row in old['consumptions'] if row['id']==loss)['quantity']=='2'
    print('PASS explicit operator ordinary-use closure: omitted loss refuses; selected title1/loss1 publish once with zero stock and claim residual, retained oldK and first outcome',flush=True)
    # Full withdrawal keeps every native identity and zero head. The new raw
    # source heads explicitly withdraw all allocations; no event is deleted.
    withdrawn=json.loads(json.dumps(body));chosen=withdrawn['claims'][0];chosen_step=chosen['settlements'][0];chosen_use=withdrawn['consumptions'][0]
    def zero(evidence_id):
        previous=next(row for row in current['evidence'] if row['id']==evidence_id)
        occurred=datetime.fromisoformat(previous['occurred_at']).astimezone(timezone.utc).isoformat().replace('+00:00','Z')
        return record('evidence',dict(sourceKey=previous['source_key'],kind=previous['kind'],quantity='0',occurredAt=occurred,
            expectedRevision=previous['revision'],evidence='Synthetic explicit all-zero operator allocation withdrawal'),target=previous['account_id'])['id']
    withdraw='withdraw_all_source_allocations_v1'
    chosen.update(expectedRevision=current['claim']['expectedRevision'],quantity='0',evidenceId=zero(current['claim']['evidenceId']),sourceAllocation=withdraw)
    chosen_step.update(expectedRevision=current['settlements'][0]['expectedRevision'],quantity='0',evidenceId=zero(current['settlements'][0]['evidenceId']),
        expectedReceiptRevision=next(row for row in current['positions'] if row['id']==lot)['expectedRevision'],sourceAllocation=withdraw)
    current_use=next(row for row in current['consumptions'] if row['id']==loss)
    chosen_use.update(expectedRevision=current_use['expectedRevision'],quantity='0',retracted=True,evidenceId=zero(current_use['evidenceId']),sourceAllocation=withdraw)
    withdrawn_context=capture('2020-12-23');withdrawn_operation=str(uuid4());withdrawn_outcome=correct(withdrawn,withdrawn_operation,withdrawn_context)
    assert withdrawn_outcome['changed'] and withdrawn_outcome['cashChanges']==[]
    retired=source(capture('2020-12-23'))
    assert retired['claim']['quantity']=='0' and retired['claim']['remainingQuantity']=='0' and retired['claim']['expectedRevision']==4
    assert retired['settlements'][0]['quantity']=='0' and retired['settlements'][0]['expectedRevision']==4
    assert next(row for row in retired['positions'] if row['id']==lot)['quantity']=='0'
    assert next(row for row in retired['consumptions'] if row['id']==loss)['quantity']=='0'
    assert correct(withdrawn,withdrawn_operation,withdrawn_context)==withdrawn_outcome
    print('PASS explicit operator all-zero withdrawal: exact claim/receipt/use heads retire together without deleting native title, loss, settlement or cash identities',flush=True)
    # Selecting another lawful allocation contract is an accepted state too.
    # Its first new snapshot is versioned; a fresh nonce then acknowledges it.
    policy=json.loads(json.dumps(withdrawn));policy_claim=policy['claims'][0];policy_step=policy_claim['settlements'][0];policy_use=policy['consumptions'][0]
    policy_claim.update(expectedRevision=4,sourceAllocation=PRESERVE)
    policy_step.update(expectedRevision=4,expectedReceiptRevision=next(row for row in retired['positions'] if row['id']==lot)['expectedRevision'],sourceAllocation=PRESERVE)
    policy_use.update(expectedRevision=next(row for row in retired['consumptions'] if row['id']==loss)['expectedRevision'],sourceAllocation=PRESERVE)
    policy_context=capture('2020-12-23');policy_operation=str(uuid4());policy_outcome=correct(policy,policy_operation,policy_context)
    assert policy_outcome['changed'] and policy_outcome['cashChanges']==[]
    policy_head=source(capture('2020-12-23'))
    assert policy_head['claim']['expectedRevision']==5 and policy_head['settlements'][0]['expectedRevision']==5, \
        'An explicit allocation-policy-only state must advance its exact typed native heads once.'
    assert next(row for row in policy_head['consumptions'] if row['id']==loss)['expectedRevision']==4
    policy_publication=query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")
    acknowledged=correct(policy,str(uuid4()),capture('2020-12-23'))
    assert acknowledged['semanticAcknowledgement'] and not acknowledged['changed']
    old_policy=correct(withdrawn,str(uuid4()),capture('2020-12-23'))
    assert old_policy['semanticAcknowledgement'] and not old_policy['changed']
    assert query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")==policy_publication
    assert source(capture('2020-12-23'))['settlements'][0]['expectedRevision']==5
    print('PASS operator allocation-policy identity: zero-value Preserve/Withdraw snapshots retain distinct accepted heads, exact retry/new-nonce acknowledgements and no rewind',flush=True)
