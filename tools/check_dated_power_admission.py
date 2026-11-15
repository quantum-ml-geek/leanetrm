"""Native power admission uses exact selected cells, not just endpoint offsets."""
from copy import deepcopy
import json
from hashlib import sha256
from check_booked_side_programs import runtime_query


def run_checks(query, manifest, request, receipt):
    catalog=manifest['catalogId'];trade=receipt['tradeId'];reference=manifest['referenceCatalogId'];revision=manifest['referenceRevisionId']
    literal=lambda value:"'"+json.dumps(value).replace("'","''")+"'::jsonb"
    identity=json.loads(query(f"""SELECT s.economic_identity FROM trading.side_schedule_request_items i
     JOIN trading.side_schedules h ON(h.catalog_id,h.id)=(i.catalog_id,i.schedule_id)
     JOIN trading.sides s ON(s.catalog_id,s.id)=(h.catalog_id,h.side_id)
     WHERE(i.catalog_id,i.request_id,i.slot)=('{catalog}','{request['operationId']}',0);"""))
    # Replay admitted native input coordinates. Expected cash uses the independent
    # fixture's 21 weekdays × 16 hours × 2MW, without regenerating an expected grid.
    prepared=json.loads(query(f"""SELECT jsonb_build_object('periods',jsonb_agg(jsonb_build_object('power',jsonb_build_object(
     'durationTicks',a.delivery_duration_ticks::text,'energyQuantity',a.energy_quantity_code,
     'total',jsonb_build_object('numerator',a.energy_numerator::text,'denominator',a.energy_denominator::text),
     'intervals',(SELECT jsonb_agg(jsonb_build_object('interval',jsonb_build_object('start',p.starts_at,'end',p.ends_at,'operatingDate',p.operating_date),
       'energy',jsonb_build_object('numerator',p.energy_numerator::text,'denominator',p.energy_denominator::text)) ORDER BY p.ordinal)
      FROM trading.swap_power_quantity_intervals p WHERE(p.catalog_id,p.trade_id,p.revision,p.slot,p.period_ordinal)=(a.catalog_id,a.trade_id,a.revision,a.slot,a.ordinal))
     )) ORDER BY a.ordinal)) FROM trading.swap_quantity_amounts a WHERE(a.catalog_id,a.trade_id,a.revision,a.slot)=('{catalog}','{trade}',1,0);"""))
    signature='security.dated_power_quantity(jsonb,jsonb,jsonb,integer)'
    accepted=[]
    for mutation in (None,'energy','missing_cell','rate','inner_transitions','null_contract','extra_parameter','period_contract','period_extra'):
        definition=deepcopy(identity);shape=deepcopy(prepared);side=deepcopy(request['scheduled']['first']);prefix=f'GRANT EXECUTE ON FUNCTION {signature} TO openetrm_runtime;'
        if mutation=='energy':shape['periods'][0]['power']['intervals'][0]['energy']['numerator']='3'
        if mutation=='missing_cell':shape['periods'][0]['power']['intervals'].pop(10)
        if mutation=='rate':side['periods'][0]['amount']='3'
        if mutation=='null_contract':definition['PowerQuantity']['contract']=None
        if mutation=='extra_parameter':definition['PowerQuantity']['UnexpectedRule']=True
        if mutation=='period_contract':definition['PowerQuantity']['Periods'][0]['contract']='unsupported'
        if mutation=='period_extra':definition['PowerQuantity']['Periods'][0]['UnexpectedRule']=True
        if mutation=='inner_transitions':
            capture=json.loads(definition['PowerQuantity']['ClockRules'])
            capture['Runs'].extend([dict(From='2021-01-04T12:15:00Z',Minutes=-295),dict(From='2021-01-04T12:30:00Z',Minutes=-300)])
            capture['Runs'].sort(key=lambda row:row['From'])
            payload=json.dumps(capture,separators=(',',':'))
            definition['PowerQuantity'].update(ClockRules=payload,ClockFingerprint=sha256(payload.encode()).hexdigest())
            quoted="'"+payload.replace("'","''")+"'"
            prefix+=f"""SET LOCAL session_replication_role=replica;
             UPDATE ref_data.clock_captures SET payload={quoted},definition_digest=sha256(convert_to({quoted},'UTF8'))
              WHERE(catalog_id,revision_id,clock_code)=('{reference}','{revision}','synthetic_eastern');
             SET LOCAL session_replication_role=origin;"""
        call=f'security.dated_power_quantity({literal(definition)},{literal(side)},{literal(shape)},0)'
        statement=f"IF {call}<>672 THEN RAISE EXCEPTION 'power_cash_oracle';END IF;" if mutation is None else f"""
         BEGIN PERFORM {call};RAISE EXCEPTION 'native_power_mutation_accepted:{mutation}';
          EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'side_schedule_definition' THEN RAISE;END IF;END;"""
        try:runtime_query(query,manifest,'DO $admit$BEGIN '+statement+'END$admit$;',prefix=prefix,commit=False)
        except RuntimeError as error:
            if 'native_power_mutation_accepted:' not in str(error):raise
            accepted.append(mutation)
    assert not accepted,f'Native power parameters accepted: {accepted}'
    print('PASS native power quantities: 672MWh control, altered energy/rate, omitted cell, interior clock transitions and noncanonical parameter shapes refuse',flush=True)
