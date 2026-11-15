"""A normally published gas agent reviews independent loan and fixed-fee effects."""
from datetime import datetime, timezone
from decimal import Decimal
import json
from uuid import uuid4


def financial_state(query,catalog):
    tables=('publications','knowledge_receipts','gas_owned_commands','gas_owned_loan_quantities',
        'gas_owned_position_quantities','gas_owned_consumption_quantities','gas_loan_quantity_corrections',
        'gas_owned_fees','gas_owned_fee_payments','gas_loan_fee_terms','gas_loan_fee_changes','gas_loan_fee_cash_members')
    return query('SELECT jsonb_build_object('+','.join(
        f"'{table}',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]') FROM trading.{table} r WHERE catalog_id='{catalog}')"
        for table in tables)+')::text;')


def checks(query,manifest,base,invoke,call,capture):
    catalog=manifest['catalogId'];at=base['at'];actor=base['principal']
    def literal(value):return "'"+json.dumps(value).replace("'","''")+"'::jsonb"
    rows=json.loads(query(f"SELECT jsonb_agg(to_jsonb(l)) FROM trading.gas_owned_loans l JOIN trading.gas_owned_accounts a "
        f"ON(a.catalog_id,a.id)=(l.catalog_id,l.account_id) WHERE l.catalog_id='{catalog}' AND a.code='synthetic_owned_inventory_1';"))
    assert len(rows)==1 and Decimal(rows[0]['quantity'])==100,rows
    loan=rows[0];account=loan['account_id'];loan_id=loan['id']
    book=query(f"SELECT book_id FROM trading.gas_owned_accounts WHERE(catalog_id,id)=('{catalog}','{account}');")
    fees=query(f"SELECT jsonb_agg(to_jsonb(f) ORDER BY id)::text FROM trading.gas_owned_fees f WHERE(catalog_id,loan_id)=('{catalog}','{loan_id}');")
    original=json.loads(fees);assert len(original)==1 and Decimal(original[0]['amount'])==-2
    bank=query(f"SELECT jsonb_agg(to_jsonb(p) ORDER BY id)::text FROM trading.gas_owned_fee_payments p WHERE p.catalog_id='{catalog}';")
    def record(action,body):
        return json.loads(call(f"SELECT security.record_gas_owned('{catalog}','{uuid4()}','{action}','{account}',{literal(body)},'{at}','{capture()}',NULL,NULL,false)::text;"))
    def policy(action):
        identity=str(uuid4())
        call(f"SELECT lifecycle.save_policy('{catalog}',{literal(dict(operationId=str(uuid4()),policyId=identity,expectedRevision=0,
            action=action,mode='review',fromAt='2020-01-01T00:00:00Z',untilAt='2022-01-01T00:00:00Z',implementation='explicit_lifecycle_action_policy_v1'))});")
        record('bind_policy',dict(action=action,policyId=identity,policyRevision=1,effectiveAt='2020-12-18T00:00:00Z'))
        return identity
    quantity_policy=policy('gas.loan.reconcile_quantity');fee_policy=policy('gas.loan.amend_fee')
    head=json.loads(query(f"SELECT to_jsonb(q) FROM trading.gas_owned_loan_quantities q WHERE(catalog_id,loan_id,revision)=('{catalog}','{loan_id}',1);"))
    title=[]
    for key in ('title_evidence_id','agreement_evidence_id'):
        evidence=json.loads(query(f"SELECT to_jsonb(e) FROM trading.gas_owned_evidence e WHERE(catalog_id,id)=('{catalog}','{head[key]}');"))
        assert evidence['revision']==1 and Decimal(evidence['quantity'])==100
        occurred=datetime.fromisoformat(evidence['occurred_at']).astimezone(timezone.utc).isoformat().replace('+00:00','Z')
        title.append(record('evidence',dict(sourceKey=evidence['source_key'],kind=evidence['kind'],quantity='101',occurredAt=occurred,
            expectedRevision=1,evidence='Synthetic revised loan source observed before delegated review'))['id'])
    selection=dict(loanId=loan_id,expectedRevision=1,stockExpectedRevision=1,returnExpectedRevision=1,quantity='101',
        titleEvidenceId=title[0],agreementEvidenceId=title[1],sourceAllocation='preserve_unallocated_source_quantity_v1',
        feeDisposition='retain_fixed_fee_memberships_v1',consumptions=[],evidence='Synthetic explicitly reviewed delegated loan correction')
    packets=[]
    for name,handler,selected,selected_policy,expected in (
        ('loan','gas_loan_quantity_reconciliation',selection,quantity_policy,dict(currentRevision=2,currentQuantity='101')),
        ('fee','gas_loan_fee_amendment',dict(loanId=loan_id,expectedRevision=1,amount='-2.5',dueAt='2020-12-23T12:00:00Z',
            effectiveAt='2020-12-20T15:50:00Z',implementation='gross_timed_fixed_fee_adjustments_v1',
            evidence='Synthetic explicitly reviewed delegated fixed fee'),fee_policy,dict(currentRevision=2,currentAmount='-2.5'))):
        packet={key:value for key,value in base.items() if key not in ('approvedRequest','deniedReplay')}
        packet.update(handler=handler,accountId=account,loanId=loan_id,operationId=str(uuid4()),policyId=selected_policy,
            selection=selected,contextId=capture(),expectedOutcome=expected)
        publication=int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))
        path=invoke(name,packet);packets.append(path)
        assert int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))==publication+1
        table='gas_loan_quantity_corrections' if name=='loan' else 'gas_loan_fee_changes'
        assert query(f"SELECT count(*) FROM trading.{table} WHERE(catalog_id,operation_id,actor_id)=('{catalog}','{packet['operationId']}','{actor}') AND publication_order={publication+1};")=='1'
        context=capture()
        source=json.loads(call(f"SELECT security.use_market_context('{catalog}','{context}');SELECT security.use_trading_context('{catalog}','{at}');"
            f"SELECT security.read_gas_owned_holdings('{catalog}','{context}','{at}',ARRAY['{book}']::uuid[])::text;"))
        positions={row['id']:row for row in source['positions']}
        assert Decimal(positions[loan['received_lot_id']]['remaining_quantity'])==1
        assert Decimal(positions[loan['return_position_id']]['remaining_quantity'])==-71
        assert query(f"SELECT jsonb_agg(to_jsonb(p) ORDER BY id)::text FROM trading.gas_owned_fee_payments p WHERE p.catalog_id='{catalog}';")==bank
        if name=='loan':
            assert query(f"SELECT jsonb_agg(to_jsonb(f) ORDER BY id)::text FROM trading.gas_owned_fees f WHERE(catalog_id,loan_id)=('{catalog}','{loan_id}');")==fees
        else:
            current=json.loads(query(f"SELECT jsonb_agg(to_jsonb(f) ORDER BY id) FROM trading.gas_owned_fees f WHERE(catalog_id,loan_id)=('{catalog}','{loan_id}');"))
            assert len(current)==3 and next(row for row in current if row['id']==original[0]['id'])==original[0]
            additions=[row for row in current if row['id']!=original[0]['id']]
            assert sorted((Decimal(row['amount']),datetime.fromisoformat(row['due_at']),datetime.fromisoformat(row['effective_at'])) for row in additions)==[
                (Decimal('-2.5'),datetime(2020,12,23,12,tzinfo=timezone.utc),datetime(2020,12,20,15,50,tzinfo=timezone.utc)),
                (Decimal('2'),datetime(2020,12,21,12,tzinfo=timezone.utc),datetime(2020,12,20,15,50,tzinfo=timezone.utc))]
            assert sum(Decimal(row['amount']) for row in current)==Decimal('-2.5')
            fee_source=json.loads(call(f"SELECT security.use_market_context('{catalog}','{context}');SELECT security.use_trading_context('{catalog}','{at}');"
                f"SELECT security.read_gas_loan_fee_terms('{catalog}','{loan_id}','{context}','{at}')::text;"))
            assert Decimal(fee_source['currentPaid'])==Decimal('-.5') and len(fee_source['payments'])==2
    print('PASS normally configured agent: loan101 leaves native stock1/debt-71; fixed fee retains gross -2/+2/-2.5 cash and every original bank revision',flush=True)
    return packets
