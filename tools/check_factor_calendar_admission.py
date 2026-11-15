"""Native scheduled publication preserves the managed factor composition rules."""
from copy import deepcopy
import json
from uuid import uuid4
from check_booked_side_programs import runtime_query
from synthetic_schedule_stage import copy_stage


def run_checks(query,manifest,request):
    catalog=manifest['catalogId'];source=request['operationId'];accepted=[]
    literal=lambda value:"'"+json.dumps(value).replace("'","''")+"'::jsonb"
    for mutation in (None,'second_quantity','same_commodity'):
        body=deepcopy(request);operation=str(uuid4());body['operationId']=operation
        shape=[dict(relativeNumerator=str(ratio),relativeDenominator='1',periods=[dict(numerator=str(n),denominator='3',fixingPins=[]) for n in (1,2)]) for ratio in (1,7)]
        prefix=copy_stage(catalog,source,operation)
        if mutation=='second_quantity':body['scheduled']['second']['quantity']['code']='factor_gas_bundle'
        if mutation=='same_commodity':
            body['commodity']='test_gas'
            body['scheduled']['first']=deepcopy(body['scheduled']['second']);body['scheduled']['first']['basis']='period_total'
            for period,amount in zip(body['scheduled']['first']['periods'],('100','200')):period['amount']=amount
            gas=body['scheduled']['second']['quantity'];body['scheduled']['factor'].update(value='7',numeratorQuantity=gas,denominatorQuantity=gas)
            prefix+=f"""SET LOCAL session_replication_role=replica;UPDATE trading.side_schedule_request_items SET schedule_id=(SELECT schedule_id FROM trading.side_schedule_request_items WHERE(catalog_id,request_id,slot)=('{catalog}','{source}',1)) WHERE(catalog_id,request_id,slot)=('{catalog}','{operation}',0);SET LOCAL session_replication_role=origin;"""
        parties={key:body[key] for key in ('legalEntityId','legalEntityRevision','counterpartyId','counterpartyRevision')}
        prefix+=f"""INSERT INTO trading.side_schedule_request_seals SELECT catalog_id,'{operation}',slot_count,input_count
         FROM trading.side_schedule_request_seals WHERE(catalog_id,request_id)=('{catalog}','{source}');
         ALTER TABLE trading.side_schedule_requests DISABLE TRIGGER USER;
         UPDATE trading.side_schedule_requests SET command_hash=sha256(convert_to(trading.scheduled_swap_command({literal(body)},'2020-12-18T16:00:00Z',{literal(parties)})::text,'UTF8')) WHERE(catalog_id,request_id)=('{catalog}','{operation}');
         ALTER TABLE trading.side_schedule_requests ENABLE TRIGGER USER;"""
        write=f"""result=security.save_scheduled_swap('{catalog}',{literal(body)},{literal(shape)},300,'2020-12-18T16:00:00Z',{literal(parties)},'{{}}'::uuid[]);
         PERFORM security.publish_side_schedules('{catalog}','{operation}',(result->>'instrumentId')::uuid);"""
        if mutation:write="BEGIN "+write+f"RAISE EXCEPTION 'factor_mutation_accepted:{mutation}';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'side_schedule_definition' THEN RAISE;END IF;END;"
        try:runtime_query(query,manifest,'DO $factor$DECLARE result jsonb;BEGIN '+write+'END$factor$;',prefix=prefix,commit=False)
        except RuntimeError as error:
            if 'factor_mutation_accepted:' not in str(error):raise
            accepted.append(mutation)
    assert not accepted,f'Native scheduled factor publication accepted: {accepted}'
    print('PASS native factor admission: equivalent-unit control publishes; derived-unit override and same-commodity factor refuse',flush=True)
