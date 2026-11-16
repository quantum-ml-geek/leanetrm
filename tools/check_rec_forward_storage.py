#!/usr/bin/env python3
"""Independent native REC forward authority and atomic-admission checks."""
from uuid import uuid4
import json
from check_reference_editing import main
from preview_fixture import fixture,trading_fixture,trade_booking
from rec_fixture import extend


def run_checks(query,manifest):
    catalog=manifest['catalogId']
    def runtime(sql,actor='trader'):
        token=query("SET SESSION AUTHORIZATION preview_authenticator;SELECT security.issue_context("
            f"'https://preview.invalid','{actor}','human_interactive','{manifest['tenantId']}','{manifest['workspaceId']}',NULL,'preview_runtime',120);")
        return query('\\set VERBOSITY verbose\nBEGIN;SET LOCAL SESSION AUTHORIZATION preview_runtime;'+f"SELECT security.use_context('{token}');"+sql+'COMMIT;')
    def reject(sql,code,actor='trader'):
        try:runtime(sql,actor)
        except RuntimeError as error:
            assert code in str(error),str(error)
        else:raise AssertionError('Accepted an invalid native REC forward operation')
    operation=str(uuid4())
    reject(f"SELECT security.rec_forward_booking_status('{catalog}','{operation}');",'42501','viewer')
    print('PASS REC forward storage: a caller without trade authority cannot inspect booking receipts',flush=True)
    query(trading_fixture(catalog))
    assert runtime(f"SELECT security.rec_forward_booking_status('{catalog}','{operation}');") in ('','null')
    before=query('SELECT count(*) FROM trading.trades;')
    reject(f"SELECT security.book_rec_forward('{catalog}','{{}}'::jsonb,'{{}}'::jsonb,'2020-12-15T16:00:00Z');",'rec_forward_input')
    assert query('SELECT count(*) FROM trading.trades;')==before
    reject('SELECT count(*) FROM trading.rec_forward_instruments;','permission denied')
    print('PASS REC forward storage: absent receipts remain absent and malformed direct booking cannot create facts or access raw tables',flush=True)
    owner=runtime(f"SELECT security.rec_trade_owner('{catalog}');")
    terms=dict(definitionRevisionId=manifest['revisionId'],assignmentCode='synthetic_rec_2019',productCode='synthetic_rec',
        vintageFrom='2019-01-01',vintageTo='2020-01-01',deliveryFrom='2021-02-15T00:00:00Z',deliveryTo='2021-02-16T00:00:00Z',
        quantity='10',physicalDirection='deliver',considerationDirection='receive',
        consideration=dict(mode='fixed',quoteCode='synthetic_rec_quote',fixedPrice='40',curveCode=None,contractId=None),
        paymentRule=dict(frequency='monthly',rule='days_after_period_end',days=10,dayOfMonth=None,dayBasis='calendar_days',shortMonth=None,
            adjustment='unadjusted',calendar=None,implementation='monthly_payment_date_rules_v1'),
        calendarPolicy=dict(implementation='side_calendar_policy_v1',delivery=dict(applicable=False,calendar=None),
            observation=dict(applicable=False,calendar=None),payment=dict(applicable=False,calendar=None)),discounting=False)
    body=dict(context=dict(snapshotId=str(uuid4()),convention='rec_forward_v1',knowledgeMode='current',contextId=None),
        operationId=str(uuid4()),tradeId=str(uuid4()),ownerId=owner,bookId='d1000000-0000-0000-0000-000000000001',tradeDate='2020-12-15',**trade_booking(),terms=terms)
    def book():
        text=json.dumps(body).replace("'","''")
        return f"SELECT security.book_rec_forward('{catalog}','{text}'::jsonb,'{{}}'::jsonb,'2020-12-15T16:00:00Z');"
    reject(book(),'rec_forward_price')
    terms.update(deliveryFrom='2021-01-15T00:00:00Z',deliveryTo='2021-01-16T00:00:00Z')
    reject(book(),'rec_forward_schedule')
    terms['quantity']=10
    reject(book(),'rec_forward_input')
    terms['quantity']='10'
    terms['consideration']['fixedPrice']=40
    reject(book(),'rec_forward_price')
    terms['consideration']['fixedPrice']='40'
    terms['consideration']['quoteCode']=True
    reject(book(),'rec_forward_policy')
    terms['consideration']['quoteCode']='synthetic_rec_quote'
    terms['consideration'].update(mode='selected_contract_flat_v1',fixedPrice=None,curveCode=True,contractId=str(uuid4()))
    reject(book(),'rec_forward_price')
    terms['consideration'].update(mode='fixed',fixedPrice='40',curveCode=None,contractId=None)
    body['context']['unexpectedFallback']='0'
    reject(book(),'rec_forward_input')
    del body['context']['unexpectedFallback']
    body['context']['snapshotId']='not-a-guid'
    reject(book(),'rec_forward_input')
    body['context']['snapshotId']=str(uuid4())
    terms.update(deliveryFrom='2021-01-31T00:00:00Z',deliveryTo='2021-02-01T00:00:00Z')
    terms['paymentRule']['days']=0
    reject(book(),'rec_forward_policy')
    assert query('SELECT count(*) FROM trading.trades;')==before
    print('PASS REC forward storage: the exact vintage assignment must cover delivery and valid terms still require sealed owned schedules',flush=True)

if __name__=='__main__':
    main(checks=run_checks,fixture_factory=lambda root:extend(*fixture(root)))
