"""Market checks invoked only inside check_reference_schema's owned cluster."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CAT = '40000000-0000-0000-0000-000000000001'
REV = '60000000-0000-0000-0000-000000000001'
RCAT = '10000000-0000-0000-0000-000000000001'
RREV = '20000000-0000-0000-0000-000000000001'
REF = f"'{RCAT}','{RREV}'"
CTX = f"'{CAT}','{REV}'"


def contract(n):
    return f'50000000-0000-0000-0000-{n:012d}'


def observation(n):
    return f'70000000-0000-0000-0000-{n:012d}'


def run_checks(query, reject, connection, wait_for_lock, psql, environment, children):
    query((ROOT / 'db/migrations/0002_market_data.sql').read_text(), label='market migration applies')
    reject('quantity cannot refer to absent basis',
           f"INSERT INTO ref_data.quantity_specifications VALUES ({REF},'invalid','test_gas','absent','energy_a','energy');")
    reject('quote cannot refer to absent currency',
           f"INSERT INTO ref_data.measurement_bases VALUES ({REF},'invalid_basis','test_gas','energy');"
           f"INSERT INTO ref_data.quantity_specifications VALUES ({REF},'invalid_quantity','test_gas','invalid_basis','energy_a','energy');"
           f"INSERT INTO ref_data.quote_specifications VALUES ({REF},'invalid_quote','test_gas','outright','invalid_quantity','absent',1,0.01,0.01,-100,100);")
    reject('quantity dimension must match basis and unit',
           f"INSERT INTO ref_data.measurement_bases VALUES ({REF},'invalid_basis','test_gas','volume');"
           f"INSERT INTO ref_data.quantity_specifications VALUES ({REF},'invalid','test_gas','invalid_basis','energy_a','volume');")
    query((ROOT / 'tests/fixtures/market-synthetic.sql').read_text(), label='five-layer synthetic market definitions seal and observations load')
    assert query(f"SELECT count(*) FROM market_data.curves WHERE catalog_id='{CAT}';") == '9'
    assert query(f"SELECT count(*) FROM ref_data.quantity_specifications WHERE commodity_code='test_gas';") == '2'
    query('SELECT 1;', label='gas energy and volume specifications coexist without implicit conversion')

    def clone(revision, changes=None, omit=None):
        changes = changes or {}
        omit = omit or {}
        sql = [f"INSERT INTO market_data.revisions VALUES ('{CAT}','{revision}',{REF},'draft',0);"]
        for table in ('contracts', 'curves', 'series', 'curve_members', 'curve_inputs', 'constituent_mappings'):
            columns = query("SELECT column_name FROM information_schema.columns "
                            f"WHERE table_schema='market_data' AND table_name='{table}' ORDER BY ordinal_position;").splitlines()
            expressions = [f"'{revision}'" if c == 'revision_id' else changes.get((table, c), c) for c in columns]
            sql.append(f"INSERT INTO market_data.{table} ({','.join(columns)}) SELECT {','.join(expressions)} "
                       f"FROM market_data.{table} WHERE catalog_id='{CAT}' AND revision_id='{REV}' " + omit.get(table, '') + ';')
        return '\n'.join(sql)

    serial = 100
    def invalid_bundle(label, changes=None, omit=None):
        nonlocal serial
        serial += 1
        revision = f'60000000-0000-0000-0000-{serial:012d}'
        reject(label, clone(revision, changes, omit) +
               f"UPDATE market_data.revisions SET state='sealed' WHERE catalog_id='{CAT}' AND id='{revision}';", '23514')

    invalid_bundle('seal rejects missing constituent mapping', omit={'constituent_mappings': "AND NOT (curve_code='local_power' AND slot='spread')"})
    invalid_bundle('seal rejects explicit dependency cycle', changes={
        ('curve_inputs', 'source_curve_code'): "CASE WHEN curve_code='base_forward' AND slot='base' THEN 'local_gas' ELSE source_curve_code END",
        ('constituent_mappings', 'source_curve_code'): "CASE WHEN curve_code='base_forward' AND slot='base' THEN 'local_gas' ELSE source_curve_code END",
        ('constituent_mappings', 'source_contract_id'): f"CASE WHEN curve_code='base_forward' AND slot='base' THEN '{contract(3)}'::uuid ELSE source_contract_id END"})
    invalid_bundle('seal rejects all-in input in spread slot', changes={
        ('curves', 'quote_code'): "CASE WHEN code='gas_basis' THEN 'test_gas_outright' ELSE quote_code END"})
    invalid_bundle('same dated contract cannot switch commodity across curves', changes={
        ('curves', 'quote_code'): "CASE WHEN code='gas_basis' THEN 'test_power_basis' ELSE quote_code END",
        ('curves', 'commodity_code'): "CASE WHEN code='gas_basis' THEN 'test_power' ELSE commodity_code END"})
    invalid_bundle('seal rejects unsupported frozen composite source', changes={
        ('curve_inputs', 'expiry_rule'): "CASE WHEN curve_code='local_gas' AND slot='base' THEN 'freeze_final_future' ELSE expiry_rule END"})
    invalid_bundle('seal rejects incompatible numeric multiplier units', changes={
        ('series', 'value_specification_code'): "CASE WHEN quote_code IS NULL THEN 'test_dimensionless' ELSE value_specification_code END"})
    invalid_bundle('seal rejects a futures curve with the wrong specified location', changes={
        ('curves', 'location_code'): "CASE WHEN code='future' THEN 'test_hub_b' ELSE location_code END"})
    invalid_bundle('seal rejects futures expiry differing from reference milestone', changes={
        ('contracts', 'expiry_at'): "CASE WHEN kind='future' THEN expiry_at + INTERVAL '1 day' ELSE expiry_at END"})
    invalid_bundle('seal rejects mismatched dated delivery period', changes={
        ('contracts', 'delivery_to'): "CASE WHEN kind='future' THEN delivery_to + 1 ELSE delivery_to END"})
    invalid_bundle('seal rejects incompatible index settlement units', changes={
        ('curves', 'settlement_target_code'): "CASE WHEN code='local_power' THEN 'test_index_target' ELSE settlement_target_code END"})
    reject('numeric series input requires explicit observation role',
        clone('60000000-0000-0000-0000-000000000198', changes={('curve_inputs','numeric_role'): 'NULL'}), '23514')
    constant_revision = '60000000-0000-0000-0000-000000000199'
    constant_changes = {
        ('curve_inputs','source_series_id'): 'NULL',
        ('curve_inputs','constant_value'): "CASE WHEN slot='multiplier' THEN 7 ELSE NULL END",
        ('curve_inputs','value_specification_code'): "CASE WHEN slot='multiplier' THEN 'test_conversion_ratio' ELSE NULL END",
        ('curve_inputs','numeric_role'): 'NULL', ('curve_inputs','numeric_source_code'): 'NULL'}
    query('BEGIN; ' + clone(constant_revision,constant_changes) +
        f"UPDATE market_data.revisions SET state='sealed' WHERE catalog_id='{CAT}' AND id='{constant_revision}'; ROLLBACK;",
        label='generic explicitly typed constant can replace a numeric series binding')
    reject('sealed curve cannot be edited', "UPDATE market_data.curves SET rule='direct';", '55000')
    reject('sealed bundle cannot reopen', "UPDATE market_data.revisions SET state='draft';", '55000')
    reject('reference extensions obey sealed revision guard',
           f"INSERT INTO ref_data.measurement_bases VALUES ({REF},'late','test_gas','energy');", '55000')
    reject('cannot create already sealed market definitions',
           f"INSERT INTO market_data.revisions VALUES ('{CAT}','60000000-0000-0000-0000-000000000099',{REF},'sealed',0);", '55000')

    def obs(n, value='3.05', corrects=1, event='event_1', source_revision='2', contract_number=1):
        previous = 'NULL' if corrects is None else f"'{observation(corrects)}'"
        return (f"('{CAT}','{observation(n)}','{REV}','90000000-0000-0000-0000-{contract_number:012d}',{REF},"
                f"'fixture','{event}','{source_revision}','daily_settlement','final',"
                f"'2040-12-18 16:00:00+00','2040-12-19 16:01:00+00',{value},{previous})")

    query('INSERT INTO market_data.observations VALUES ' + obs(10) + ';', label='correction appends with exact predecessor')
    assert query(f"SELECT value FROM market_data.observations WHERE id='{observation(1)}';") == '3'
    assert query(f"SELECT value FROM market_data.observations WHERE id='{observation(10)}';") == '3.05'
    query('SELECT 1;', label='original and corrected observation remain separately addressable')
    assert query(f"SELECT string_agg(value::text,',' ORDER BY received_at) FROM market_data.observations WHERE catalog_id='{CAT}' AND series_id='90000000-0000-0000-0000-000000000001';") == '3,3.05'
    assert query(f"SELECT value FROM market_data.observations WHERE catalog_id='{CAT}' AND series_id='90000000-0000-0000-0000-000000000006';") == '7'
    query('SELECT 1;', label='price corrections and numeric histories use the same series observation storage')
    reject('source revision identity cannot be reused with changed content',
           'INSERT INTO market_data.observations VALUES ' + obs(11, value='9', corrects=None) + ';', '23505')
    reject('correction cannot retarget another source event',
           'INSERT INTO market_data.observations VALUES ' + obs(11, corrects=10, event='other', source_revision='3') + ';', '23514')
    reject('correction cannot retarget another contract',
           'INSERT INTO market_data.observations VALUES ' + obs(11, corrects=10, source_revision='3', contract_number=2) + ';', '23514')
    reject('forward-reference multirow correction is rejected',
           'INSERT INTO market_data.observations VALUES ' + obs(20, corrects=21, source_revision='3') + ',' + obs(21, corrects=None, source_revision='4') + ';')
    reject('correction cycle cannot be inserted as a multirow statement',
           'INSERT INTO market_data.observations VALUES ' + obs(20, corrects=21, source_revision='3') + ',' + obs(21, corrects=20, source_revision='4') + ';')
    reject('observation cannot be rewritten', "UPDATE market_data.observations SET value=0;", '55000')
    reject('out-of-domain observed value rejected',
           'INSERT INTO market_data.observations VALUES ' + obs(12, value='1001', corrects=None, event='new') + ';', '23514')
    reject('over-precision observed value is never rounded',
           'INSERT INTO market_data.observations VALUES ' + obs(12, value='0.0000000000000000001', corrects=None, event='new') + ';', '23514')
    reject('off-grid clearing observation is rejected without rounding',
           'INSERT INTO market_data.observations VALUES ' + obs(12, value='3.0001', corrects=None, event='new') + ';', '23514')

    # Semantic sealing has a stronger race contract than reference freeze alone.
    # The writer inserts a structurally invalid curve with no constituents.
    for index, isolation in enumerate(('READ COMMITTED', 'REPEATABLE READ', 'SERIALIZABLE')):
        for writer_first in (True, False):
            revision = f'60000000-0000-0000-0000-{500 + 2 * index + int(writer_first):012d}'
            query(f"INSERT INTO market_data.revisions VALUES ('{CAT}','{revision}',{REF},'draft',0);")
            write = (f"INSERT INTO market_data.curves SELECT catalog_id,'{revision}',code,reference_catalog_id,reference_revision_id,"
                     "commodity_code,location_code,quote_code,profile_code,settlement_target_code,rule,direct_source_code,direct_role "
                     f"FROM market_data.curves WHERE catalog_id='{CAT}' AND revision_id='{REV}' AND code='future';")
            seal = f"UPDATE market_data.revisions SET state='sealed' WHERE catalog_id='{CAT}' AND id='{revision}';"
            first = connection(f'BEGIN ISOLATION LEVEL {isolation}; ' + (write if writer_first else seal), 'market_first')
            second = subprocess.Popen(psql, env={**environment, 'PGAPPNAME': 'market_second'}, stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            children.append(second)
            second.stdin.write(f'BEGIN ISOLATION LEVEL {isolation}; ' + (seal if writer_first else write) + ' COMMIT;')
            second.stdin.close(); second.stdin = None
            wait_for_lock('market_second')
            first.stdin.write('COMMIT;\n'); first.stdin.flush()
            _, error = first.communicate(timeout=10)
            assert first.returncode == 0, error
            _, error = second.communicate(timeout=10)
            allowed = ('23514:', '40001:') if writer_first else ('55000:', '40001:')
            assert second.returncode != 0 and any(code in error for code in allowed), error
            state = query(f"SELECT state FROM market_data.revisions WHERE catalog_id='{CAT}' AND id='{revision}';")
            assert state == ('draft' if writer_first else 'sealed'), state
            query('SELECT 1;', label=f'invalid-content seal race {isolation}, writer_first={writer_first}')
