"""A composition cannot silently acquire scheduled-power generation terms."""
from copy import deepcopy
import json
from uuid import uuid4
from check_booked_side_programs import runtime_query
from synthetic_schedule_stage import copy_stage


def run_checks(query, manifest, request, donor):
    catalog=manifest['catalogId'];source=request['operationId']
    original=json.loads(query(f"SELECT request::text FROM trading.swap_trade_revisions WHERE operation_id='{source}';"))
    original.pop('sideFixings',None)
    literal=lambda value:"'"+json.dumps(value).replace("'","''")+"'::jsonb"
    def side(operation, slot):
        return f"(SELECT h.side_id FROM trading.side_schedule_request_items i JOIN trading.side_schedules h ON(h.catalog_id,h.id)=(i.catalog_id,i.schedule_id) WHERE(i.catalog_id,i.request_id,i.slot)=('{catalog}','{operation}',{slot}))"
    accepted=[]
    for changed in (None,0,1):
        operation=str(uuid4());payload=literal(original)
        prefix=copy_stage(catalog,source,operation)+f"""
         INSERT INTO trading.side_schedule_request_seals SELECT catalog_id,'{operation}',slot_count,input_count
          FROM trading.side_schedule_request_seals WHERE(catalog_id,request_id)=('{catalog}','{source}');
         ALTER TABLE trading.side_schedule_requests DISABLE TRIGGER USER;
         UPDATE trading.side_schedule_requests SET command_hash=sha256(convert_to(({payload})::text,'UTF8'))
          WHERE(catalog_id,request_id)=('{catalog}','{operation}');
         ALTER TABLE trading.side_schedule_requests ENABLE TRIGGER USER;
         SET LOCAL session_replication_role=replica;
         DELETE FROM trading.swap_fixed_sides WHERE(catalog_id,id)=('{catalog}',{side(operation,0)});
        """
        if changed is not None:
            prefix+=f"""DO $change$DECLARE supplied jsonb;schedule uuid;BEGIN
             SELECT economic_identity::jsonb INTO STRICT supplied FROM trading.sides
              WHERE(catalog_id,id)=('{catalog}',{side(donor['operationId'],changed)});
             supplied=jsonb_set(supplied,'{{PowerQuantity,Periods}}',jsonb_build_array(supplied#>'{{PowerQuantity,Periods,0}}'));
             UPDATE trading.sides SET economic_identity=jsonb_set(jsonb_set(economic_identity::jsonb,'{{PowerQuantity}}',supplied->'PowerQuantity'),
              '{{Periods,0,DeliveryCompletionAt}}',supplied#>'{{Periods,0,DeliveryCompletionAt}}')::text
              WHERE(catalog_id,id)=('{catalog}',{side(operation,changed)});
             SELECT schedule_id INTO STRICT schedule FROM trading.side_schedule_request_items WHERE(catalog_id,request_id,slot)=('{catalog}','{operation}',{changed});
             UPDATE trading.side_schedule_programs SET content=convert_to(trading.side_program_document(catalog_id,schedule_id)::text,'UTF8'),
              content_hash=sha256(convert_to(trading.side_program_document(catalog_id,schedule_id)::text,'UTF8')) WHERE(catalog_id,schedule_id)=('{catalog}',schedule);
             PERFORM trading.require_side_program_content('{catalog}',schedule,content) FROM trading.side_schedule_programs WHERE(catalog_id,schedule_id)=('{catalog}',schedule);
            END$change$;"""
        prefix+='SET LOCAL session_replication_role=origin;'
        write=f"""result=security.save_composed_swap('{catalog}','{operation}',NULL,NULL,(p->>'book')::uuid,
         (p->>'definition')::uuid,(p->>'referenceCatalog')::uuid,(p->>'referenceRevision')::uuid,p->>'commodity',
         p->'fixed',NULL,p->'floating',(p->>'quantity')::numeric,(p->>'coefficient')::numeric,(p->>'discounting')::boolean,
         (p->>'valuation')::timestamptz,(p->>'effective')::timestamptz,p->>'reason',p->>'implementation',p->>'memo',p->'booking','{{}}'::uuid[]);
         PERFORM security.publish_side_schedules('{catalog}','{operation}',(result->>'instrumentId')::uuid);"""
        if changed is not None:
            write="BEGIN "+write+"RAISE EXCEPTION 'unauthored_power_accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'side_schedule_definition' THEN RAISE;END IF;END;"
        try:
            runtime_query(query,manifest,f'DO $admit$DECLARE result jsonb;p jsonb={payload};BEGIN '+write+'END$admit$;',prefix=prefix,commit=False)
        except RuntimeError as error:
            if 'unauthored_power_accepted' not in str(error):raise
            accepted.append(changed)
    assert not accepted,f'Composed admission accepted unauthored power for slots {accepted}'
    print('PASS composed clock admission: control publishes; unauthored power terms on either Side refuse',flush=True)
