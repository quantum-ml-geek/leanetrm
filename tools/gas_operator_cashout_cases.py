"""Independent cashout fixing, prefix rounding and immutable-bank examples."""
from decimal import Decimal
import json
from uuid import uuid4


PRESERVE='preserve_unallocated_source_quantity_v1'


def _literal(value):return "'"+json.dumps(value).replace("'","''")+"'::jsonb"


def checks(query,manifest,call,capture,read,record,amend,packet):
    catalog=manifest['catalogId'];account=packet['accountId'];terms=packet['cashoutTerms']
    assert terms['rounding']=='payment_total_half_even_2dp_v1'
    assert query("SELECT count(*) FROM trading.gas_owned_action_bindings "
        f"WHERE(catalog_id,account_id,action)=('{catalog}','{account}','gas.cash.record_payment');")=='0'
    payment_policy=str(uuid4())
    call(f"SELECT lifecycle.save_policy('{catalog}',"+_literal(dict(operationId=str(uuid4()),policyId=payment_policy,expectedRevision=0,
        action='gas.cash.record_payment',mode='manual',fromAt='2020-01-01T00:00:00Z',untilAt='2022-01-01T00:00:00Z',
        implementation='explicit_lifecycle_action_policy_v1'))+");")
    record('bind_policy',dict(action='gas.cash.record_payment',policyId=payment_policy,policyRevision=1,effectiveAt='2020-12-18T00:00:00Z'))
    results=[]
    for case in [dict(tag='credit',quantity='3',observed='2020-12-19T15:01:00Z',paid='0.5',
        initial=['1','2.02'],prices=[('1.015',['1.02','2.02'],['1.02','3.04'],['0.02']),
            ('1.025',['1.02','2.06'],['1.02','3.08'],['0.04']),('0',['0','0'],['0','0'],['-1.02','-2.06']),
            ('-1.005',['-1','-2.02'],['-1','-3.02'],['-1','-2.02'])]),
        dict(tag='debt',quantity='-3',observed='2020-12-19T15:02:00Z',paid='-0.5',
        initial=['-1','-2.02'],prices=[('1.015',['-1.02','-2.02'],['-1.02','-3.04'],['-0.02']),
            ('1.025',['-1.02','-2.06'],['-1.02','-3.08'],['-0.04']),('0',['0','0'],['0','0'],['1.02','2.06']),
            ('-1.005',['1','2.02'],['1','3.02'],['1','2.02'])])]:
        results.append(_cohort(query,capture,read,record,amend,catalog,account,terms,packet,case))
    reverse_order(query,capture,read,record,amend,catalog,account,terms,packet)
    return results


def _cohort(query,capture,read,record,amend,catalog,account,terms,packet,case):
    tag='synthetic_operator_fixing_'+case['tag'];point=str(uuid4())
    query("INSERT INTO market_data.observations SELECT catalog_id,"+f"'{point}',definition_revision_id,series_id,reference_catalog_id,reference_revision_id,"
        f"source_code,'{tag}','1',role,'final','{case['observed']}',clock_timestamp(),1.005,NULL "
        f"FROM market_data.observations WHERE(catalog_id,id)=('{catalog}','{packet['originalObservationId']}');")
    def evidence(suffix,kind,quantity,at):return record('evidence',dict(sourceKey=tag+'_'+suffix,kind=kind,quantity=quantity,occurredAt=at,
        expectedRevision=0,evidence='Synthetic independent signed cashout source'))['id']
    statement=evidence('statement','operator_statement',case['quantity'],'2020-12-19T12:00:00Z')
    claim=record('operator_claim',dict(evidenceId=statement,quantity=case['quantity'],effectiveAt='2020-12-19T12:00:00Z',dueAt='2020-12-24T12:00:00Z',
        carrying='currency_curve_v1',settlementMode='cashout_final_price_v1',cashout=dict(source=terms['source_code'],role=terms['role'],
            observedAt=case['observed'],cashDueAt='2020-12-24T12:00:00Z',rounding=terms['rounding'])),'gas.operator.record')
    document=evidence('determination','cashout_determination',case['quantity'],'2020-12-20T13:00:00Z')
    native=[record('operator_settle',dict(positionId=claim['id'],quantity=quantity,ownedAccountId=None,lotId=None,reservationId=None,evidenceId=document,
        effectiveAt='2020-12-20T13:00:00Z',availableAt=None,sourceObservationId=point),'gas.operator.settle') for quantity in ['1','2']]
    ids=[row['id'] for row in native];cash_ids=[row['cashId'] for row in native]
    assert all(cash_ids) and len(set(ids))==2 and len(set(cash_ids))==2
    record('fee_payment',dict(feeId=cash_ids[0],businessKey=tag+'_bank',expectedRevision=0,amount=case['paid'],
        paidAt='2020-12-20T14:00:00Z',evidence='Synthetic original signed bank payment'),'gas.cash.record_payment')
    original_context=capture();source=read(claim['id'],original_context)
    assert source['accountId']==account and source['claim']['id']==claim['id'] and source['claim']['quantity']==case['quantity']
    assert source['cashoutTerms']['source_code']==terms['source_code'] and source['cashoutTerms']['role']==terms['role']
    assert source['cashoutTerms']['observed_at'].startswith(case['observed'][:-1])
    _heads(source,ids,case['initial'],None,point,1)
    original_order=[row['originalPublicationOrder'] for row in source['settlements']]
    assert original_order[0]<original_order[1]
    original_cash_sql="SELECT jsonb_agg(to_jsonb(f) ORDER BY f.id) FROM trading.gas_owned_fees f "\
        f"WHERE f.catalog_id='{catalog}' AND f.id IN({','.join(repr(value) for value in cash_ids)});"
    bank_sql=f"SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.id),'[]')::text) FROM trading.gas_owned_fee_payments p WHERE p.catalog_id='{catalog}';"
    original_cash=query(original_cash_sql);bank=query(bank_sql)
    initial_body=_body(source,point)
    first=None;head=point
    for revision,(price,amounts,totals,adjustments) in enumerate(case['prices'],2):
        successor=str(uuid4())
        query("INSERT INTO market_data.observations SELECT catalog_id,"+f"'{successor}',definition_revision_id,series_id,reference_catalog_id,reference_revision_id,"
            f"source_code,source_event_id,'{revision}',role,'final',observed_at,clock_timestamp(),{price},id "
            f"FROM market_data.observations WHERE(catalog_id,id)=('{catalog}','{head}');")
        current_context=capture();before=read(claim['id'],current_context);body=_body(before,successor)
        publication=int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))
        operation=str(uuid4());outcome=amend(body,operation,current_context)
        assert outcome['changed'] and not outcome['semanticAcknowledgement']
        assert sorted(Decimal(row['amount']) for row in outcome['cashChanges'])==sorted(Decimal(value) for value in adjustments)
        assert all(row['positionId']==claim['id'] and row['dueAt'].startswith('2020-12-25T12:00:00') and
            row['effectiveAt'].startswith('2020-12-20T13:00:00') for row in outcome['cashChanges'])
        assert int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))==publication+1
        after=read(claim['id'],capture());_heads(after,ids,amounts,totals,successor,revision)
        assert [row['originalPublicationOrder'] for row in after['settlements']]==original_order
        assert all(row['effectiveAt'].startswith('2020-12-20T13:00:00') and row['cashId']==cash_ids[index]
            for index,row in enumerate(after['settlements']))
        assert query(original_cash_sql)==original_cash and query(bank_sql)==bank
        if first is None:first=(body,operation,current_context,outcome)
        head=successor
    retained_publication=query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")
    assert amend(first[0],first[1],first[2])==first[3],'A later fixing changed the retained first command outcome'
    acknowledged=amend(initial_body,str(uuid4()),original_context)
    assert not acknowledged['changed'] and acknowledged['semanticAcknowledgement'] and acknowledged['cashChanges']==[]
    current=read(claim['id'],capture());_heads(current,ids,case['prices'][-1][1],case['prices'][-1][2],head,5)
    assert query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")==retained_publication
    historical=read(claim['id'],original_context);_heads(historical,ids,case['initial'],None,point,1)
    stale=_body(historical,point)
    for selected,quantity in zip(stale['claims'][0]['settlements'],['0.9','2.1']):selected['quantity']=quantity
    try:amend(stale,str(uuid4()),original_context)
    except RuntimeError as error:assert 'gas_quantity_revision' in str(error),str(error)
    else:raise AssertionError('A historical source read admitted a new effect without the current native financial head.')
    assert query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")==retained_publication
    assert query(original_cash_sql)==original_cash and query(bank_sql)==bank
    print('PASS signed operator cashout '+case['tag']+': exact1+2 prefix, fixing-only corrections, versioned zero deltas, zero/negative prices, original signed bank and cash, historical source and first/old-fact outcomes without rewind',flush=True)
    return dict(claimId=claim['id'],settlementIds=ids,cashIds=cash_ids,originalContextId=original_context,originalObservationId=point,
        currentObservationId=head,source=current)


def _body(source,observation):
    claim=source['claim']
    return dict(implementation='gas_operator_quantity_reconciliation_v1',rootClaimId=claim['id'],claims=[dict(claimId=claim['id'],
        expectedRevision=claim['expectedRevision'],quantity=claim['quantity'],evidenceId=claim['evidenceId'],sourceAllocation=PRESERVE,
        settlements=[dict(settlementId=row['id'],expectedRevision=row['expectedRevision'],quantity=row['quantity'],evidenceId=row['evidenceId'],
            sourceObservationId=observation,expectedReceiptRevision=None,expectedConsumptionRevision=None,lotId=None,reservationId=None,sourceAllocation=PRESERVE)
            for row in source['settlements']])],consumptions=[],cashout=dict(ordering='replay_original_settlement_publication_prefix_v1',
            adjustmentDueAt='2020-12-25T12:00:00Z'),evidence='Synthetic independently reviewed fixing-only cashout correction')


def _heads(source,ids,amounts,totals,observation,revision):
    rows=source['settlements'];assert [row['id'] for row in rows]==ids
    assert [row['expectedRevision'] for row in rows]==[revision,revision]
    assert [Decimal(row['cashAmount']) for row in rows]==[Decimal(value) for value in amounts]
    if totals is not None:assert [Decimal(row['roundedTotal']) for row in rows]==[Decimal(value) for value in totals]
    assert all(row['sourceObservationId']==observation for row in rows)
    assert rows[0]['previousSettlementId'] is None and rows[0]['previousSettlementRevision'] is None
    assert rows[1]['previousSettlementId']==ids[0] and rows[1]['previousSettlementRevision']==revision


def reverse_order(query,capture,read,record,amend,catalog,account,terms,packet):
    tag='synthetic_operator_native_prefix_order';point=str(uuid4())
    query("INSERT INTO market_data.observations SELECT catalog_id,"+f"'{point}',definition_revision_id,series_id,reference_catalog_id,reference_revision_id,"
        f"source_code,'{tag}','1',role,'final','2020-12-19T15:04:00Z',clock_timestamp(),1.005,NULL "
        f"FROM market_data.observations WHERE(catalog_id,id)=('{catalog}','{packet['originalObservationId']}');")
    def evidence(suffix,kind):return record('evidence',dict(sourceKey=tag+'_'+suffix,kind=kind,quantity='3',occurredAt='2020-12-19T12:00:00Z' if suffix=='statement' else '2020-12-20T13:00:00Z',
        expectedRevision=0,evidence='Synthetic original-publication prefix order'))['id']
    statement=evidence('statement','operator_statement')
    claim=record('operator_claim',dict(evidenceId=statement,quantity='3',effectiveAt='2020-12-19T12:00:00Z',dueAt='2020-12-24T12:00:00Z',
        carrying='currency_curve_v1',settlementMode='cashout_final_price_v1',cashout=dict(source=terms['source_code'],role=terms['role'],
            observedAt='2020-12-19T15:04:00Z',cashDueAt='2020-12-24T12:00:00Z',rounding=terms['rounding'])),'gas.operator.record')
    document=evidence('determination','cashout_determination')
    original=[record('operator_settle',dict(positionId=claim['id'],quantity=quantity,ownedAccountId=None,lotId=None,reservationId=None,evidenceId=document,
        effectiveAt='2020-12-20T13:00:00Z',availableAt=None,sourceObservationId=point),'gas.operator.settle') for quantity in ['1','2']]
    ids=[row['id'] for row in original];context=capture();source=read(claim['id'],context);body=_body(source,point)
    for step,quantity in zip(body['claims'][0]['settlements'],['0.75','2.25']):step['quantity']=quantity
    body['claims'][0]['settlements'].reverse()
    before=query(f"SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]')::text) FROM trading.gas_owned_fee_payments x WHERE catalog_id='{catalog}';")
    operation=str(uuid4());outcome=amend(body,operation,context)
    assert outcome['changed'] and sorted(Decimal(row['amount']) for row in outcome['cashChanges'])==[Decimal('-.25'),Decimal('.25')]
    assert [row['settlementId'] for row in outcome['claims'][0]['settlements']]==ids
    retained=json.loads(query(f"SELECT request#>'{{body,claims}}' FROM trading.gas_owned_commands WHERE(catalog_id,request_id)=('{catalog}','{operation}');"))
    assert [row['settlementId'] for row in retained[0]['settlements']]==ids[::-1],'The producer rewrote the explicitly reviewed request order.'
    _heads(read(claim['id'],capture()),ids,['0.75','2.27'],['0.75','3.02'],point,2)
    publication=query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")
    same=json.loads(json.dumps(body));same['claims'][0]['settlements'].reverse()
    acknowledged=amend(same,str(uuid4()),capture())
    assert acknowledged['semanticAcknowledgement'] and not acknowledged['changed']
    assert query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';")==publication
    assert amend(body,operation,context)==outcome
    assert query(f"SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]')::text) FROM trading.gas_owned_fee_payments x WHERE catalog_id='{catalog}';")==before
    print('PASS explicit native prefix law: reverse-click proposal retains reviewed order, computes original-publication .75/2.27, and acknowledges the equal normal-order snapshot without money or bank rewind',flush=True)
