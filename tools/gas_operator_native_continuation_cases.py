"""Original-operation acknowledgements and accepted-prefix continuation."""
from decimal import Decimal
import json
from uuid import uuid4

from gas_operator_cashout_cases import _body
from gas_operator_source_authority import _state


def _financial_state(query,catalog):
    state=json.loads(_state(query,catalog));del state['gas_owned_commands']
    commands=int(query(f"SELECT count(*) FROM trading.gas_owned_commands WHERE catalog_id='{catalog}';"))
    return state,commands


def checks(query,manifest,call,capture,read,record,amend,packet):
    print('Operator315 exact native predecessors: '+query("SELECT jsonb_object_agg(signature,md5(p.prosrc)) FROM (VALUES"
        "('security.record_gas_owned(uuid,uuid,text,uuid,jsonb,timestamptz,uuid,uuid,integer,boolean)'),"
        "('trading.apply_gas_owned_financial(uuid,uuid,text,jsonb,timestamptz,uuid,uuid,integer)'),"
        "('trading.check_gas_owned_integrity()'))s(signature) JOIN pg_proc p ON p.oid=signature::regprocedure;"),flush=True)
    catalog=manifest['catalogId'];account=packet['accountId'];terms=packet['cashoutTerms'];tag='synthetic_operator_continuation_'+uuid4().hex
    point=str(uuid4())
    query("INSERT INTO market_data.observations SELECT catalog_id,"+f"'{point}',definition_revision_id,series_id,reference_catalog_id,reference_revision_id,"
        f"source_code,'{tag}','1',role,'final','2020-12-19T15:08:00Z',clock_timestamp(),1.005,NULL "
        f"FROM market_data.observations WHERE(catalog_id,id)=('{catalog}','{packet['originalObservationId']}');")
    def evidence(suffix,kind,quantity,revision=0):
        return record('evidence',dict(sourceKey=tag+suffix,kind=kind,quantity=quantity,occurredAt='2020-12-19T12:00:00Z' if kind=='operator_statement' else '2020-12-20T13:00:00Z',
            expectedRevision=revision,evidence='Synthetic accepted-prefix continuation'))['id']
    statement=evidence('_statement','operator_statement','3')
    claim=record('operator_claim',dict(evidenceId=statement,quantity='3',effectiveAt='2020-12-19T12:00:00Z',dueAt='2020-12-24T12:00:00Z',
        carrying='currency_curve_v1',settlementMode='cashout_final_price_v1',cashout=dict(source=terms['source_code'],role=terms['role'],
            observedAt='2020-12-19T15:08:00Z',cashDueAt='2020-12-24T12:00:00Z',rounding=terms['rounding'])),'gas.operator.record')['id']
    document=evidence('_determination','cashout_determination','3')
    binding=json.loads(query("SELECT jsonb_build_object('id',policy_id,'revision',policy_revision) FROM trading.gas_owned_action_bindings "
        f"WHERE(catalog_id,account_id,action,revision)=('{catalog}','{account}','gas.operator.settle',1);"))
    def execute(body,operation=None,context=None):
        return json.loads(call(f"SELECT security.record_gas_owned('{catalog}','{operation or uuid4()}','operator_settle','{account}',"
            +"'"+json.dumps(body).replace("'","''")+"'::jsonb,"+f"'2020-12-22T16:00:00Z','{context or capture('2020-12-22')}','{binding['id']}',{binding['revision']},false)::text;"))
    def body(quantity,selected_document=document):return dict(positionId=claim,quantity=quantity,ownedAccountId=None,lotId=None,reservationId=None,
        evidenceId=selected_document,effectiveAt='2020-12-20T13:00:00Z',availableAt=None,sourceObservationId=point)
    first_operation=str(uuid4());first_context=capture('2020-12-22');first=execute(body('1'),first_operation,first_context)
    second=execute(body('2'));ids=[first['id'],second['id']]
    assert [Decimal(row['effect']['cashAmount']) for row in [first,second]]==[Decimal('1'),Decimal('2.02')]
    record('fee_payment',dict(feeId=first['cashId'],businessKey=tag+'_bank',expectedRevision=0,amount='0.5',paidAt='2020-12-20T14:00:00Z',
        evidence='Synthetic retained native bank payment'),'gas.cash.record_payment')
    originals=query("SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM trading.gas_owned_claim_settlements s "
        f"WHERE(s.catalog_id,s.position_id)=('{catalog}','{claim}');")
    cash=query("SELECT jsonb_agg(to_jsonb(f) ORDER BY f.id) FROM trading.gas_owned_fees f "
        f"WHERE f.catalog_id='{catalog}' AND f.id IN('{first['cashId']}','{second['cashId']}');")
    bank=query(f"SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.id),'[]')::text) FROM trading.gas_owned_fee_payments p WHERE p.catalog_id='{catalog}';")
    revised_statement=evidence('_statement','operator_statement','3.25',1)
    revised_document=evidence('_determination','cashout_determination','2.25',1)
    selection=_body(read(claim,capture()),point);owner=selection['claims'][0]
    owner.update(quantity='3.25',evidenceId=revised_statement)
    for row,quantity in zip(owner['settlements'],['0.75','1.5']):row.update(quantity=quantity,evidenceId=revised_document)
    correction=amend(selection,str(uuid4()),capture());assert correction['changed']
    current=read(claim,capture());assert [Decimal(row['cashAmount']) for row in current['settlements']]==[Decimal('.75'),Decimal('1.51')]
    failures=[]
    ack_context=capture('2020-12-22');before=_state(query,catalog);financial,commands=_financial_state(query,catalog)
    try:ack=execute(body('0.75',revised_document),context=ack_context)
    except RuntimeError as error:
        assert any(code in str(error) for code in ['gas_owned_evidence_capacity','gas_operator_quantity_origin','gas_operator_capacity','gas_operator_settlement']),str(error)
        failures.append('corrected original fact acknowledgement');print('ACTUAL RED corrected native operator fact refused: '+str(error).splitlines()[0],flush=True)
    else:
        assert ack['id']==ids[0] and not ack['changed'] and ack['semanticAcknowledgement']
        assert ack['acknowledgedFinancialRevision']==ack['currentFinancialRevision']==2
        assert Decimal(ack['acknowledgedQuantity'])==Decimal(ack['currentQuantity'])==Decimal('.75')
        assert ack['cashId']==first['cashId'] and Decimal(ack['effect']['cashAmount'])==1 and ack['originalCashAmount']=='1'
        assert Decimal(ack['acknowledgedCashAmount'])==Decimal(ack['currentCashAmount'])==Decimal('.75')
        after_financial,after_commands=_financial_state(query,catalog)
        assert after_financial==financial and after_commands==commands+1,'A successful corrected-fact acknowledgement published another financial effect.'
    if failures:assert _state(query,catalog)==before,'A refused acknowledgement changed the native ledger.'
    financial,commands=_financial_state(query,catalog)
    assert execute(body('1'),first_operation,first_context)==first
    assert _financial_state(query,catalog)==(financial,commands),'An exact original receipt retry changed financial rows or command count.'
    historical_context=capture('2020-12-22');financial,commands=_financial_state(query,catalog)
    historical=execute(body('1'),context=historical_context);assert historical['id']==ids[0] and not historical['changed'] and historical['semanticAcknowledgement']
    after_financial,after_commands=_financial_state(query,catalog)
    assert after_financial==financial and after_commands==commands+1,'A successful historical acknowledgement published another financial effect.'
    if historical.get('acknowledgedFinancialRevision')!=1 or historical.get('currentFinancialRevision')!=2:
        failures.append('original historical fact financial metadata');print('ACTUAL RED original operator acknowledgement omits accepted/current financial identity',flush=True)
    else:
        assert Decimal(historical['acknowledgedQuantity'])==1 and Decimal(historical['currentQuantity'])==Decimal('.75')
        assert historical['cashId']==first['cashId'] and historical['effect']['cashAmount']=='1' and historical['originalCashAmount']=='1'
        assert historical['acknowledgedCashAmount']=='1' and Decimal(historical['currentCashAmount'])==Decimal('.75')
    new_document=evidence('_additional','cashout_determination','1')
    new_context=capture('2020-12-22');before_new=_state(query,catalog)
    try:added=execute(body('1',new_document),context=new_context)
    except RuntimeError as error:
        assert any(code in str(error) for code in ['gas_operator_quantity_origin','gas_operator_cashout','gas_operator_capacity','gas_operator_settlement']),str(error)
        assert _state(query,catalog)==before_new
        failures.append('new native settlement current prefix');print('ACTUAL RED new operator settlement ignored accepted prefix: '+str(error).splitlines()[0],flush=True)
    else:
        assert added['changed'] and not added['semanticAcknowledgement'] and added['id'] not in ids
        assert Decimal(added['effect']['cashAmount'])==Decimal('1.01'),'New quantity1 must contribute3.27-2.26=1.01; the original raw prefix would give1.00.'
        source=read(claim,capture());assert Decimal(source['claim']['remainingQuantity'])==0
        assert [Decimal(row['quantity']) for row in source['settlements']]==[Decimal('.75'),Decimal('1.5'),Decimal('1')]
        assert [Decimal(row['cashAmount']) for row in source['settlements']]==[Decimal('.75'),Decimal('1.51'),Decimal('1.01')]
        successor=str(uuid4())
        query("INSERT INTO market_data.observations SELECT catalog_id,"+f"'{successor}',definition_revision_id,series_id,reference_catalog_id,reference_revision_id,"
            f"source_code,source_event_id,'2',role,'final',observed_at,clock_timestamp(),1.015,id FROM market_data.observations WHERE(catalog_id,id)=('{catalog}','{point}');")
        updated=amend(_body(read(claim,capture()),successor),str(uuid4()),capture())
        assert sorted(Decimal(row['amount']) for row in updated['cashChanges'])==[Decimal('.01')]*3
        after=read(claim,capture());assert [Decimal(row['cashAmount']) for row in after['settlements']]==[Decimal('.76'),Decimal('1.52'),Decimal('1.02')]
        birth=json.loads(query("SELECT to_jsonb(q) FROM trading.gas_operator_settlement_quantities q "
            f"WHERE(q.catalog_id,q.settlement_id,q.revision)=('{catalog}','{added['id']}',1);"))
        assert birth['previous_settlement_id']==ids[1] and birth['previous_settlement_revision']==2 and Decimal(str(birth['cash_amount']))==Decimal('1.01')
        assert query("SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM trading.gas_owned_claim_settlements s "
            f"WHERE s.catalog_id='{catalog}' AND s.id IN('{ids[0]}','{ids[1]}');")==originals
        assert query("SELECT jsonb_agg(to_jsonb(f) ORDER BY f.id) FROM trading.gas_owned_fees f "
            f"WHERE f.catalog_id='{catalog}' AND f.id IN('{first['cashId']}','{second['cashId']}');")==cash
        assert query(f"SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.id),'[]')::text) FROM trading.gas_owned_fee_payments p WHERE p.catalog_id='{catalog}';")==bank
    assert not failures,'Unsupported original operator continuation: '+', '.join(failures)
    print('PASS native operator acknowledgements and continuation: original receipts unchanged, current-prefix1.01 contribution, complete three-member correcting prefix and immutable bank/birth cash',flush=True)
    from gas_operator_native_additional_cases import checks as additional
    additional(query,manifest,call,capture,read,record,amend,packet)
