"""Sampled futures observations retain complete ordered canonical source terms."""
from copy import deepcopy
import json
from uuid import uuid4
from preview_fixture import CAT,TENANT,WORKSPACE
from check_booked_side_programs import runtime_query
from synthetic_schedule_stage import copy_stage


def run_checks(query,request):
    source=request['operationId'];manifest=dict(tenantId=TENANT,workspaceId=WORKSPACE)
    retained=json.loads(query(f"SELECT request FROM trading.swap_trade_revisions WHERE(catalog_id,operation_id)=('{CAT}','{source}');"))
    literal=lambda value:"'"+json.dumps(value).replace("'","''")+"'::jsonb"
    target=f"(SELECT h.side_id FROM trading.side_schedule_request_items i JOIN trading.side_schedules h ON(h.catalog_id,h.id)=(i.catalog_id,i.schedule_id) WHERE(i.catalog_id,i.request_id,i.slot)=('{CAT}','{source}',1))"
    pins=next(entry['evidence']['observationPins'] for entry in retained['sideFixings'] if entry['slot']==1)
    pin_array="ARRAY["+','.join(repr(pin) for pin in pins)+"]::uuid[]"
    observations=json.loads(query(f"""SELECT jsonb_agg(jsonb_build_object('ordinal',o.ordinal,'contractId',o.contract_id,'seriesId',o.series_id,'sourceCode',o.source_code,
     'observationFrom',o.observation_from,'observationTo',o.observation_to,'fixingAt',o.fixing_at,'selectionAt',o.selection_at,
     'observationId',(SELECT id FROM market_data.observations p WHERE p.catalog_id=o.catalog_id AND p.definition_revision_id=o.definition_revision_id AND p.series_id=o.series_id AND p.id=ANY({pin_array}))) ORDER BY o.ordinal)
     FROM trading.swap_contract_observations o WHERE(o.catalog_id,o.side_id,o.period_ordinal)=('{CAT}',{target},0);"""))
    mutations={
        'duplicate':('{Periods,0,ContractObservations}',"(economic_identity::jsonb#>'{Periods,0,ContractObservations}')||jsonb_build_array(economic_identity::jsonb#>'{Periods,0,ContractObservations,0}')"),
        'source_order':('{Periods,0,ContractObservations}',"(SELECT jsonb_agg(x ORDER BY n DESC) FROM jsonb_array_elements(economic_identity::jsonb#>'{Periods,0,ContractObservations}') WITH ORDINALITY p(x,n))"),
        'source_tag':('{Periods,0,ContractObservations,0,contract}',"to_jsonb('unsupported'::text)"),
        'market_tag':('{Periods,0,ContractObservations,0,Market,0}',"to_jsonb('unsupported'::text)"),
        'futures_series':('{Periods,0,ContractObservations,0,Contract,6}',"'null'::jsonb"),
        'index_fixings':('{Periods,0,Fixings}',"'[{}]'::jsonb"),
        'custom_projection':('{Periods,0,CustomProjection}',"'{}'::jsonb"),
        'date_settlement':('{DateSettlement}',"'{}'::jsonb")}
    for mutation in (None,*mutations,'pricing_binding'):
        body=deepcopy(request);operation=str(uuid4());body['operationId']=operation
        parties={key:body[key] for key in ('legalEntityId','legalEntityRevision','counterpartyId','counterpartyRevision')}
        prefix=copy_stage(CAT,source,operation)+f"""INSERT INTO trading.side_schedule_request_seals SELECT catalog_id,'{operation}',slot_count,input_count FROM trading.side_schedule_request_seals WHERE(catalog_id,request_id)=('{CAT}','{source}');
         ALTER TABLE trading.side_schedule_requests DISABLE TRIGGER USER;
         UPDATE trading.side_schedule_requests SET command_hash=sha256(convert_to(trading.scheduled_swap_command({literal(body)},'{retained['valuation']}',{literal(parties)})::text,'UTF8')) WHERE(catalog_id,request_id)=('{CAT}','{operation}');
         ALTER TABLE trading.side_schedule_requests ENABLE TRIGGER USER;"""
        if mutation:
            change="pricing_binding_identity='{}'" if mutation=='pricing_binding' else f"economic_identity=jsonb_set(economic_identity::jsonb,'{mutations[mutation][0]}',{mutations[mutation][1]})::text"
            prefix+=f"SET LOCAL session_replication_role=replica;UPDATE trading.sides SET {change} WHERE(catalog_id,id)=('{CAT}',{target});SET LOCAL session_replication_role=origin;"
        compiled=[dict(relativeNumerator='1',relativeDenominator='1',periods=[dict(numerator='1',denominator='1',fixingPins=[])]) for _ in range(2)]
        compiled[1]['periods'][0].update(contractObservations=observations,fixingPins=pins)
        write=f"""result=security.save_scheduled_swap('{CAT}',{literal(body)},{literal(compiled)},31,'{retained['valuation']}',{literal(parties)},{pin_array});
         PERFORM security.publish_side_schedules('{CAT}','{operation}',(result->>'instrumentId')::uuid);"""
        if mutation:write="BEGIN "+write+f"RAISE EXCEPTION 'sampled_contract_mutation_accepted:{mutation}';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'side_schedule_definition' THEN RAISE;END IF;END;"
        runtime_query(query,manifest,'DO $sample$DECLARE result jsonb;BEGIN '+write+'END$sample$;',prefix=prefix,commit=False)
    print('PASS native sampled sources: ordered control publishes; duplicate/reordered/altered canonical sources, foreign source modes and pricing identity refuse',flush=True)
