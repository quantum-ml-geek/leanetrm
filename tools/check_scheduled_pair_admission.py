"""Cross-Side native compatibility is checked independently of each Side's terms."""
import json
from copy import deepcopy
from uuid import uuid4
from check_booked_side_programs import runtime_query
from synthetic_schedule_stage import copy_stage


def run_checks(query,manifest,request):
    catalog=manifest['catalogId'];rc=manifest['referenceCatalogId'];rr=manifest['referenceRevisionId'];accepted=[]
    literal=lambda value:"'"+json.dumps(value).replace("'","''")+"'::jsonb"
    shape=[dict(relativeNumerator='1',relativeDenominator='1',periods=[dict(numerator=str(n),denominator='3') for n in (1,2)]) for _ in range(2)]
    target=f"(SELECT h.side_id FROM trading.side_schedule_request_items i JOIN trading.side_schedules h ON(h.catalog_id,h.id)=(i.catalog_id,i.schedule_id) WHERE(i.catalog_id,i.request_id,i.slot)=('{catalog}','{request['operationId']}',1))"
    for mutation in (None,'currency','native_quantity'):
        body=deepcopy(request);operation=str(uuid4())
        prefix=copy_stage(catalog,request['operationId'],operation)+"GRANT EXECUTE ON FUNCTION security.require_dated_quantities(uuid,uuid,jsonb,jsonb,numeric) TO openetrm_runtime;"
        if mutation:
            prefix+=f"""SET LOCAL session_replication_role=replica;
             DO $pair$DECLARE canonical jsonb;q ref_data.quote_specifications;BEGIN
              SELECT economic_identity::jsonb INTO canonical FROM trading.sides WHERE(catalog_id,id)=('{catalog}',{target});
              SELECT * INTO STRICT q FROM ref_data.quote_specifications WHERE(catalog_id,revision_id,code)=('{rc}','{rr}',canonical#>>'{{DateQuote,1,2}}');"""
            if mutation=='currency':
                prefix+=f"""INSERT INTO ref_data.currencies SELECT(jsonb_populate_record(NULL::ref_data.currencies,to_jsonb(c)||'{{"code":"synthetic_currency","display_code":"XTS"}}'::jsonb)).* FROM ref_data.currencies c WHERE(catalog_id,revision_id,code)=('{rc}','{rr}',q.currency_code);
                 q.code='synthetic_currency_quote';q.currency_code='synthetic_currency';INSERT INTO ref_data.quote_specifications SELECT(q).*;
                 canonical=jsonb_set(canonical,'{{DateQuote,1,2}}','"synthetic_currency_quote"'::jsonb);
                 canonical=jsonb_set(canonical,'{{DateQuote,3,2}}','"synthetic_currency"'::jsonb);"""
            else:
                prefix+=f"""INSERT INTO ref_data.quantity_specifications SELECT(jsonb_populate_record(NULL::ref_data.quantity_specifications,to_jsonb(u)||'{{"code":"synthetic_quantity_alias"}}'::jsonb)).* FROM ref_data.quantity_specifications u WHERE(catalog_id,revision_id,code)=('{rc}','{rr}',q.quantity_code);
                 canonical=jsonb_set(canonical,'{{QuantityBasis,2}}','"synthetic_quantity_alias"'::jsonb);"""
            prefix+=f"UPDATE trading.sides SET economic_identity=canonical::text WHERE(catalog_id,id)=('{catalog}',{target});END$pair$;SET LOCAL session_replication_role=origin;"
        statement=f"PERFORM security.require_dated_quantities('{catalog}','{operation}',{literal(body)},{literal(shape)},300);"
        if mutation:statement="BEGIN "+statement+f"RAISE EXCEPTION 'scheduled_pair_accepted:{mutation}';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'side_schedule_definition' THEN RAISE;END IF;END;"
        try:runtime_query(query,manifest,'DO $admit$BEGIN '+statement+'END$admit$;',prefix=prefix,commit=False)
        except RuntimeError as error:
            if 'scheduled_pair_accepted:' not in str(error):raise
            accepted.append(mutation)
    assert not accepted,f'Native scheduled pair accepted: {accepted}'
    print('PASS native scheduled pair admission: shared exact currency/native quantity control; different currency or quantity refuses',flush=True)
