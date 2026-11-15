"""Exact physical, ambiguous and zero-born operator continuation facts."""
from decimal import Decimal
import json
from uuid import uuid4
from gas_operator_cashout_cases import _body
from gas_operator_native_continuation_cases import _financial_state


def checks(query,manifest,call,capture,read,record,amend,packet):
    _zero_cash(query,manifest,call,capture,read,record,amend,packet)
    _ambiguous(query,manifest,call,capture,read,record,amend,packet)
    _physical(query,manifest,call,capture,read,record,packet)


def _settle(query,catalog,account,call,capture,body,context):
    from gas_operator_seal_cases import _literal
    policy=json.loads(query("SELECT jsonb_build_object('id',policy_id,'revision',policy_revision) FROM trading.gas_owned_action_bindings "
        f"WHERE(catalog_id,account_id,action,revision)=('{catalog}','{account}','gas.operator.settle',1);"))
    return json.loads(call(f"SELECT security.record_gas_owned('{catalog}','{uuid4()}','operator_settle','{account}',{_literal(body)},"
        f"'2020-12-22T16:00:00Z','{context}','{policy['id']}',{policy['revision']},false)::text;"))


def _seed(query,manifest,record,packet,minute,price,quantity):
    catalog=manifest['catalogId'];tag='synthetic_operator_native_'+uuid4().hex;point=str(uuid4());terms=packet['cashoutTerms']
    query("INSERT INTO market_data.observations SELECT catalog_id,"+f"'{point}',definition_revision_id,series_id,reference_catalog_id,reference_revision_id,"
        f"source_code,'{tag}','1',role,'final','2020-12-19T15:{minute}:00Z',clock_timestamp(),{price},NULL "
        f"FROM market_data.observations WHERE(catalog_id,id)=('{catalog}','{packet['originalObservationId']}');")
    statement=record('evidence',dict(sourceKey=tag+'_statement',kind='operator_statement',quantity=quantity,occurredAt='2020-12-19T12:00:00Z',
        expectedRevision=0,evidence='Synthetic independent native continuation'))['id']
    claim=record('operator_claim',dict(evidenceId=statement,quantity=quantity,effectiveAt='2020-12-19T12:00:00Z',dueAt='2020-12-24T12:00:00Z',
        carrying='currency_curve_v1',settlementMode='cashout_final_price_v1',cashout=dict(source=terms['source_code'],role=terms['role'],
            observedAt=f'2020-12-19T15:{minute}:00Z',cashDueAt='2020-12-24T12:00:00Z',rounding=terms['rounding'])),'gas.operator.record')['id']
    document=record('evidence',dict(sourceKey=tag+'_determination',kind='cashout_determination',quantity=quantity,occurredAt='2020-12-20T13:00:00Z',
        expectedRevision=0,evidence='Synthetic independent native continuation'))['id']
    def body(quantity,observation=point):return dict(positionId=claim,quantity=quantity,ownedAccountId=None,lotId=None,reservationId=None,evidenceId=document,
        effectiveAt='2020-12-20T13:00:00Z',availableAt=None,sourceObservationId=observation)
    return point,claim,body


def _zero_cash(query,manifest,call,capture,read,record,amend,packet):
    catalog=manifest['catalogId'];point,claim,body=_seed(query,manifest,record,packet,'10','0','1')
    original=record('operator_settle',body('1'),'gas.operator.settle');assert original['cashId'] is None and original['effect']['cashAmount']=='0'
    successor=str(uuid4());query("INSERT INTO market_data.observations SELECT catalog_id,"+f"'{successor}',definition_revision_id,series_id,reference_catalog_id,reference_revision_id,"
        f"source_code,source_event_id,'2',role,'final',observed_at,clock_timestamp(),1.005,id FROM market_data.observations WHERE(catalog_id,id)=('{catalog}','{point}');")
    result=amend(_body(read(claim,capture()),successor),str(uuid4()),capture())
    assert [row['amount'] for row in result['cashChanges']]==['1'] and result['claims'][0]['settlements'][0]['cashAmount']=='1'
    # Capture the wrapper's own business context before the no-effect snapshot.
    context=capture('2020-12-22');financial,commands=_financial_state(query,catalog)
    acknowledged=_settle(query,catalog,packet['accountId'],call,capture,body('1',successor),context)
    assert acknowledged['id']==original['id'] and acknowledged['cashId'] is None and not acknowledged['changed'] and acknowledged['semanticAcknowledgement']
    assert acknowledged['effect']['cashAmount']=='0' and acknowledged['originalCashAmount'] is None
    assert acknowledged['acknowledgedCashAmount']==acknowledged['currentCashAmount']=='1'
    after_financial,after_commands=_financial_state(query,catalog)
    assert after_financial==financial and after_commands==commands+1
    assert query("SELECT count(*) FROM trading.gas_owned_fees f JOIN trading.gas_owned_claim_settlements s "
        "ON(f.catalog_id,f.id)=(s.catalog_id,s.cash_id) "
        f"WHERE(s.catalog_id,s.id)=('{catalog}','{original['id']}');")=='0'
    print('PASS zero-born cashout: later accepted contribution1 has only its signed adjustment; original cashId stays null and original native effect0 is retained',flush=True)


def _ambiguous(query,manifest,call,capture,read,record,amend,packet):
    catalog=manifest['catalogId'];point,claim,body=_seed(query,manifest,record,packet,'09','1.005','3')
    originals=[record('operator_settle',body(quantity),'gas.operator.settle') for quantity in ['1','2']]
    selected=_body(read(claim,capture()),point)
    for row in selected['claims'][0]['settlements']:row['quantity']='1.5'
    result=amend(selected,str(uuid4()),capture());assert result['changed']
    assert len({row['id'] for row in originals})==2
    context=capture('2020-12-22');financial,commands=_financial_state(query,catalog)
    try:_settle(query,catalog,packet['accountId'],call,capture,body('1.5'),context)
    except RuntimeError as error:assert 'gas_owned_fact_ambiguous' in str(error),str(error)
    else:raise AssertionError('Two exact accepted native settlement identities were silently resolved by row order.')
    assert _financial_state(query,catalog)==(financial,commands)
    print('PASS original operator ambiguity: two current equal snapshots refuse instead of choosing a native identity',flush=True)


def _physical(query,manifest,call,capture,read,record,packet):
    catalog=manifest['catalogId'];case=next(row for row in packet['counterpartCases'] if row['consumptionId'] is not None)
    claim=case['claimId'];source=read(claim,capture());step=source['settlements'][0]
    assert step['expectedRevision']==2 and Decimal(step['quantity'])==Decimal('1.5')
    original=json.loads(query("SELECT c.request->'body' FROM trading.gas_operator_settlement_quantities q JOIN trading.gas_owned_commands c "
        "ON(c.catalog_id,c.request_id)=(q.catalog_id,q.origin_request_id) "
        f"WHERE(q.catalog_id,q.settlement_id,q.revision)=('{catalog}','{step['id']}',1);"))
    selected={**original,'quantity':'1.5','evidenceId':step['evidenceId']}
    context=capture('2020-12-22');financial,commands=_financial_state(query,catalog)
    acknowledged=_settle(query,catalog,packet['accountId'],call,capture,selected,context)
    assert acknowledged['id']==step['id'] and acknowledged['acknowledgedFinancialRevision']==acknowledged['currentFinancialRevision']==2
    assert acknowledged['originalCashAmount'] is None and acknowledged['acknowledgedCashAmount'] is None and acknowledged['currentCashAmount'] is None
    after_financial,after_commands=_financial_state(query,catalog);assert after_financial==financial and after_commands==commands+1
    document=record('evidence',dict(sourceKey='synthetic_operator_final_debt_'+uuid4().hex,kind='physical_delivery',quantity='1.5',occurredAt='2020-12-20T15:00:00Z',
        expectedRevision=0,evidence='Synthetic explicitly identified remaining operator debt'),target=selected['ownedAccountId'])['id']
    added=record('operator_settle',{**selected,'evidenceId':document,'effectiveAt':'2020-12-20T15:00:00Z'},'gas.operator.settle')
    assert added['changed'] and added['id']!=step['id']
    after=read(claim,capture());assert Decimal(after['claim']['remainingQuantity'])==0
    assert [Decimal(row['quantity']) for row in after['settlements']]==[Decimal('1.5')]*2
    assert sum(Decimal(row['quantity']) for row in after['consumptions'] if row['lotId']==case['fundingLotId'])==3
    book=next(row['book_id'] for row in after['accounts'] if row['id']==after['accountId']);context=capture('2020-12-22')
    holdings=json.loads(call(f"SELECT security.use_market_context('{catalog}','{context}');"
        f"SELECT security.use_trading_context('{catalog}','2020-12-22T16:00:00Z','2020-12-22'::date);"
        f"SELECT security.read_gas_owned_holdings('{catalog}','{context}','2020-12-22T16:00:00Z',ARRAY['{book}']::uuid[])::text;"))
    assert not {claim,case['fundingLotId']}&{row['id'] for row in holdings['positions']}
    print('PASS native physical operator continuation: corrected original use acknowledged once; new remaining1.5 exhausts exact funding3 and debt3 without cash',flush=True)
