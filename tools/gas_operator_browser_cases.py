"""Exact native source revisions for physical and zero operator form consumers."""
from datetime import datetime,timezone
from decimal import Decimal
import json

from gas_operator_physical_value_fixture import configure


PRESERVE='preserve_unallocated_source_quantity_v1'
WITHDRAW='withdraw_all_source_allocations_v1'


def seed(query,manifest,call,capture,record,*,zero):
    catalog=manifest['catalogId']
    def read(claim,context):return json.loads(call(f"SELECT security.use_market_context('{catalog}','{context}');"
        f"SELECT security.use_trading_context('{catalog}','2020-12-20T16:00:00Z','2020-12-20'::date);"
        f"SELECT security.read_gas_operator_quantity_reconciliation('{catalog}','{claim}','{context}','2020-12-20T16:00:00Z')::text;"))
    return configure(query,manifest,call,capture,read,record,name='operator_browser_zero' if zero else 'operator_browser_active')


def prepare(query,manifest,call,capture,record,state,*,zero):
    catalog=manifest['catalogId'];at='2020-12-23T16:00:00Z'
    def source(claim,context):return json.loads(call(f"SELECT security.use_market_context('{catalog}','{context}');"
        f"SELECT security.use_trading_context('{catalog}','{at}','2020-12-23'::date);"
        f"SELECT security.read_gas_operator_quantity_reconciliation('{catalog}','{claim}','{context}','{at}')::text;"))
    selected=capture('2020-12-23');positive=source(state['positiveClaimId'],selected);negative=source(state['negativeClaimId'],selected)
    step=positive['settlements'][0];loss=next(row for row in positive['consumptions'] if row['id']==state['futureLossId'])
    assert loss['editable'] and Decimal(loss['quantity'])==2
    assert negative['settlements'][0]['consumptionId']==state['consumptionId']
    assert next(row for row in negative['consumptions'] if row['id']==state['consumptionId'])['editable'] is False
    def document(envelope,identity,quantity):
        previous=next(row for row in envelope['evidence'] if row['id']==identity)
        occurred=datetime.fromisoformat(previous['occurred_at'].replace('Z','+00:00')).astimezone(timezone.utc).isoformat().replace('+00:00','Z')
        return record('evidence',dict(sourceKey=previous['source_key'],kind=previous['kind'],quantity=quantity,occurredAt=occurred,
            expectedRevision=previous['revision'],evidence='Synthetic explicit browser operator source correction'),target=previous['account_id'])['id']
    allocation=WITHDRAW if zero else PRESERVE;quantity='0' if zero else '8';used='0' if zero else '1'
    positive_evidence=document(positive,positive['claim']['evidenceId'],quantity)
    title_evidence=document(positive,step['evidenceId'],quantity)
    loss_evidence=document(positive,loss['evidenceId'],used)
    def member(envelope,quantity,evidence,step_quantity,step_evidence):
        row=envelope['settlements'][0]
        return dict(claimId=envelope['claimId'],expectedRevision=envelope['claim']['expectedRevision'],quantity=quantity,evidenceId=evidence,
            sourceAllocation=allocation,settlements=[dict(settlementId=row['id'],expectedRevision=row['expectedRevision'],quantity=step_quantity,evidenceId=step_evidence,
                sourceObservationId=None,expectedReceiptRevision=row['receiptRevision'],expectedConsumptionRevision=row['consumptionRevision'],
                lotId=state['fundingId'] if row['consumptionId'] else None,reservationId=None,sourceAllocation=allocation)])
    claims=[member(positive,quantity,positive_evidence,quantity,title_evidence)]
    if not zero:
        negative_evidence=document(negative,negative['settlements'][0]['evidenceId'],'-1.25')
        claims.append(member(negative,'-3',negative['claim']['evidenceId'],'1.25',negative_evidence))
    use=dict(consumptionId=loss['id'],expectedRevision=loss['expectedRevision'],lotId=state['receiptId'],quantity=used,evidenceId=loss_evidence,
        reservationId=None,retracted=zero,sourceAllocation=allocation)
    state.update(rootClaimId=state['positiveClaimId'],accountId=state['operatorAccountId'],claims=claims,consumptions=[use],zero=zero,
        protectedUseId=state['consumptionId'],protectedUseClaimId=state['negativeClaimId'],
        futureUseContext=dict(contextId=state['originalContextId'],asOf=state['at'],businessDate='2020-12-20',snapshotId=None))
    return state


def verify(query,manifest,call,capture,state):
    catalog=manifest['catalogId'];at='2020-12-23T16:00:00Z';context=capture('2020-12-23')
    def source(claim):return json.loads(call(f"SELECT security.use_market_context('{catalog}','{context}');"
        f"SELECT security.use_trading_context('{catalog}','{at}','2020-12-23'::date);"
        f"SELECT security.read_gas_operator_quantity_reconciliation('{catalog}','{claim}','{context}','{at}')::text;"))
    positive=source(state['rootClaimId']);step=positive['settlements'][0]
    assert positive['claim']['quantity']==('0' if state['zero'] else '8') and positive['claim']['expectedRevision']==3
    assert step['expectedRevision']==3 and step['quantity']==positive['claim']['quantity'] and positive['claim']['remainingQuantity']=='0'
    loss=next(row for row in positive['consumptions'] if row['id']==state['futureLossId'])
    assert loss['expectedRevision']==2 and loss['quantity']==('0' if state['zero'] else '1')
    held=json.loads(call(f"SELECT security.use_market_context('{catalog}','{context}');SELECT security.use_trading_context('{catalog}','{at}','2020-12-23'::date);"
        f"SELECT security.read_gas_owned_holdings('{catalog}','{context}','{at}',ARRAY['{state['bookId']}']::uuid[])::text;"))
    quantities={row['id']:Decimal(row['remaining_quantity']) for row in held['positions']}
    if state['zero']:
        assert state['rootClaimId'] not in quantities and state['receiptId'] not in quantities
        assert quantities[state['fundingId']]==Decimal('1.5') and quantities[state['negativeClaimId']]==Decimal('-1.5')
    else:
        negative=source(state['negativeClaimId'])
        assert negative['settlements'][0]['quantity']=='1.25' and negative['settlements'][0]['expectedRevision']==3
        assert quantities[state['receiptId']]==7 and quantities[state['fundingId']]==Decimal('1.75') and quantities[state['negativeClaimId']]==Decimal('-1.75')
    assert held['fees']==[]
