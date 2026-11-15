"""A complete withdrawal keeps native proof and surviving fixed fee/bank facts."""
import json
from decimal import Decimal
from uuid import uuid4


def checks(query,call,record,evidence,capture,state,manifest):
    catalog,account,loan,at=(manifest['catalogId'],state['account'],state['loan'],state['at'])
    def literal(value):return "'"+json.dumps(value).replace("'","''")+"'::jsonb"
    before=capture()
    original=json.loads(call(f"SELECT security.use_market_context('{catalog}','{before}');SELECT security.use_trading_context('{catalog}','{at}');"
        f"SELECT security.read_gas_loan_reconciliation('{catalog}','{loan['id']}','{before}','{at}')::text;"))
    assert Decimal(original['loan']['quantity'])==Decimal('.375')
    fee_state=query(f"SELECT md5(string_agg(value,E'\\n' ORDER BY value)) FROM(SELECT row_to_json(f)::text value FROM trading.gas_owned_fees f WHERE(catalog_id,loan_id)=('{catalog}','{loan['id']}') "
        f"UNION ALL SELECT row_to_json(p)::text FROM trading.gas_owned_fee_payments p JOIN trading.gas_owned_fees f ON(f.catalog_id,f.id)=(p.catalog_id,p.fee_id) WHERE(f.catalog_id,f.loan_id)=('{catalog}','{loan['id']}'))rows;")
    sources={row['id']:row for row in original['evidence']}
    def withdraw(source):
        head=max((row for row in original['evidence'] if row['source_key']==source['source_key']),key=lambda row:row['revision'])
        return evidence(head['source_key'],head['kind'],'0',head['occurred_at'].replace('+00:00','Z'),head['revision'])
    title=withdraw(sources[original['loan']['title_evidence_id']])
    agreement=withdraw(sources[original['loan']['agreement_evidence_id']])
    repayment_consumption=next(row['consumption_id'] for row in original['repayments'] if row['id']==state['repayment'])
    selected=[]
    for use in original['consumptions']:
        if use['id'] not in [state['dispatch'],repayment_consumption]:continue
        selected.append(dict(consumptionId=use['id'],expectedRevision=use['financialRevision'],lotId=use['lot_id'],quantity='0',
            evidenceId=withdraw(sources[use['evidence_id']]),reservationId=use['reservation_id'],retracted=True,
            sourceAllocation='withdraw_all_source_allocations_v1'))
    assert len(selected)==2
    body=dict(loanId=loan['id'],expectedRevision=original['loan']['expectedRevision'],stockExpectedRevision=original['stock']['financialRevision'],
        returnExpectedRevision=original['return']['financialRevision'],quantity='0',titleEvidenceId=title,agreementEvidenceId=agreement,
        sourceAllocation='withdraw_all_source_allocations_v1',feeDisposition='retain_fixed_fee_memberships_v1',consumptions=selected,
        evidence='Synthetic explicit withdrawal of the complete observed loan and its recorded uses')
    context=capture();operation=str(uuid4());publication=query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")
    result=json.loads(call(f"SELECT security.reconcile_gas_loan_quantities('{catalog}','{operation}','{account}',{literal(body)},'{at}','{context}','{state['policy']}',1,false)::text;"))
    assert result['changed'] and result['currentQuantity']=='0' and len(result['sourceAllocations'])==4
    assert int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))==int(publication)+1
    assert query(f"SELECT quantity FROM trading.gas_owned_loans_current WHERE(catalog_id,id)=('{catalog}','{loan['id']}');")=='0'
    assert query(f"SELECT bool_and(quantity=0) FROM trading.gas_owned_positions_current WHERE catalog_id='{catalog}' AND id IN('{loan['stockId']}','{loan['returnId']}');")=='t'
    assert query(f"SELECT md5(string_agg(value,E'\\n' ORDER BY value)) FROM(SELECT row_to_json(f)::text value FROM trading.gas_owned_fees f WHERE(catalog_id,loan_id)=('{catalog}','{loan['id']}') "
        f"UNION ALL SELECT row_to_json(p)::text FROM trading.gas_owned_fee_payments p JOIN trading.gas_owned_fees f ON(f.catalog_id,f.id)=(p.catalog_id,p.fee_id) WHERE(f.catalog_id,f.loan_id)=('{catalog}','{loan['id']}'))rows;")==fee_state
    old=json.loads(call(f"SELECT security.use_market_context('{catalog}','{before}');SELECT security.use_trading_context('{catalog}','{at}');"
        f"SELECT security.read_gas_owned_operations('{catalog}','{before}','{at}','{account}')::text;"))
    assert Decimal(next(row for row in old['loans'] if row['id']==loan['id'])['quantity'])==Decimal('.375')
    print('PASS complete zero loan withdrawal: both exact stock/return owners and recorded uses retired, old view stable, fixed fee and bank bytes unchanged',flush=True)
    return dict(contextId=capture(),loanId=loan['id'],stockId=loan['stockId'],returnId=loan['returnId'],
        dispatchId=state['dispatch'],repaymentId=state['repayment'],repaymentConsumptionId=repayment_consumption,fundingId=state['funding'],accountId=account)
