"""Exact native quantity admission preserves the managed numerical contract."""
from copy import deepcopy
import json
from uuid import uuid4
from check_booked_side_programs import runtime_query
from synthetic_schedule_stage import copy_stage


def run_checks(query, manifest, request):
    catalog=manifest['catalogId'];rc=manifest['referenceCatalogId'];rr=manifest['referenceRevisionId']
    code=request['scheduled']['first']['quantity']['code']
    signature='security.require_dated_quantities(uuid,uuid,jsonb,jsonb,numeric)'
    ratio_signature='security.dated_quantity_ratio(uuid,uuid,text,text)'
    literal=lambda value:"'"+json.dumps(value).replace("'","''")+"'::jsonb"
    # A new isolated unit connected by 1/3 keeps the declared graph consistent.
    # Converting each authored amount 1 and 2 requires rounding; cancellation in
    # the total cannot make either input an exact 18-decimal quantity.
    accepted=[]
    for case in ('fractional_input','ratio_bound'):
        operation=str(uuid4());native=deepcopy(request)
        prefix=copy_stage(catalog,request['operationId'],operation)+f'GRANT EXECUTE ON FUNCTION {signature},{ratio_signature} TO openetrm_runtime;SET LOCAL session_replication_role=replica;'
        if case=='fractional_input':
            for side in (native['scheduled']['first'],native['scheduled']['second']):
                side['quantity']['code']='synthetic_thirds_quantity'
                for n,period in enumerate(side['periods']):period['amount']=str(n+1)
            prefix+=f"""INSERT INTO ref_data.units SELECT catalog_id,revision_id,'synthetic_thirds_unit','t',dimension_code
              FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code)=('{rc}','{rr}','{code}');
             INSERT INTO ref_data.quantity_specifications SELECT catalog_id,revision_id,'synthetic_thirds_quantity',commodity_code,basis_code,'synthetic_thirds_unit',dimension_code
              FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code)=('{rc}','{rr}','{code}');
             INSERT INTO ref_data.unit_conversions SELECT catalog_id,revision_id,'synthetic_thirds_unit',unit_code,dimension_code,1,3
              FROM ref_data.quantity_specifications WHERE(catalog_id,revision_id,code)=('{rc}','{rr}','{code}');"""
            shape=[dict(relativeNumerator='1',relativeDenominator='1',periods=[dict(numerator=str(n),denominator='3') for n in (1,2)]) for _ in range(2)]
            call=f"security.require_dated_quantities('{catalog}','{operation}',{literal(native)},{literal(shape)},1)"
        else:
            prefix+=f"""INSERT INTO ref_data.units SELECT '{rc}','{rr}','synthetic_ratio_'||i,'r',q.dimension_code
              FROM generate_series(0,54) i CROSS JOIN ref_data.quantity_specifications q WHERE(q.catalog_id,q.revision_id,q.code)=('{rc}','{rr}','{code}');
             INSERT INTO ref_data.unit_conversions SELECT '{rc}','{rr}','synthetic_ratio_'||i,'synthetic_ratio_'||(i+1),q.dimension_code,100000000000000000000000,1
              FROM generate_series(0,53) i CROSS JOIN ref_data.quantity_specifications q WHERE(q.catalog_id,q.revision_id,q.code)=('{rc}','{rr}','{code}');"""
            call=f"security.dated_quantity_ratio('{rc}','{rr}','{code}','{code}')"
        prefix+='SET LOCAL session_replication_role=origin;'
        try:runtime_query(query,manifest,f"""DO $admit$BEGIN BEGIN PERFORM {call};RAISE EXCEPTION 'native_quantity_mutation_accepted:{case}';
         EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'side_schedule_definition' THEN RAISE;END IF;END;END$admit$;""",prefix=prefix,commit=False)
        except RuntimeError as error:
            if 'native_quantity_mutation_accepted:' not in str(error):raise
            accepted.append(case)
    assert not accepted,f'Native quantity policy accepted: {accepted}'
    print('PASS native quantity numerical policy: nonterminating input conversion and a consistent 4096-bit overflow path refuse',flush=True)
