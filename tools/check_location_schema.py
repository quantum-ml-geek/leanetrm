"""Additive location checks inside check_reference_schema's owned cluster only."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CAT = '10000000-0000-0000-0000-000000000001'
REV = 'd0000000-0000-0000-0000-000000000001'
KEY = f"'{CAT}','{REV}'"


def run_checks(query, reject):
    query((ROOT/'db/migrations/0004_location_coordinates.sql').read_text(),
          label='location coordinate migration applies to existing retained reference data')
    assert query("SELECT latitude IS NULL AND longitude IS NULL FROM ref_data.locations "
                 f"WHERE catalog_id='{CAT}' AND revision_id='20000000-0000-0000-0000-000000000001' AND code='test_hub_a';") == 't'
    query('SELECT 1;',label='migration preserves unknown points without backfilling zero')
    query(f"INSERT INTO ref_data.revisions (catalog_id,id,revision_key) VALUES ('{CAT}','{REV}','location_checks');")
    for kind in ['pipeline','node','hub','region','terminal','delivery_point','physical_site']:
        query(f"INSERT INTO ref_data.location_types VALUES ({KEY},'test_{kind}','Synthetic {kind}');")
    columns='(catalog_id,revision_id,code,name,type_code,latitude,longitude)'
    def insert(code,kind,lat,lon):
        return f"INSERT INTO ref_data.locations {columns} VALUES ({KEY},'{code}','Synthetic location','test_{kind}',{lat},{lon});"
    query(insert('test_site','physical_site','12.345678','-45.678912'),label='physical point retains exact latitude and longitude')
    assert query(f"SELECT latitude::text||','||longitude::text FROM ref_data.locations WHERE catalog_id='{CAT}' AND revision_id='{REV}' AND code='test_site';") == '12.345678,-45.678912'
    query(insert('test_origin','node','0','0'),label='explicit zero coordinates remain a real supplied point')
    query(insert('test_pipeline','pipeline','NULL','NULL')+insert('test_region','region','NULL','NULL')+insert('test_hub','hub','NULL','NULL'),label='pipelines regions and hubs do not require invented point coordinates')
    query(insert('test_north','node','90','180')+insert('test_south','node','-90','-180'),label='coordinate bounds include poles and antimeridian')
    for name,lat,lon in [('latitude north','90.000001','0'),('latitude south','-90.000001','0'),('longitude east','0','180.000001'),('longitude west','0','-180.000001'),('missing longitude','1','NULL'),('missing latitude','NULL','1'),('not a number',"'NaN'",'0'),('infinity','0',"'Infinity'"),('excess precision','0.1234567890123456789','0')]:
        reject('location rejects '+name,insert('invalid','physical_site',lat,lon),'23514')
    reject('new coordinate fields retain exact location-type foreign key',
           f"INSERT INTO ref_data.locations {columns} VALUES ({KEY},'invalid','Synthetic invalid','missing_type',1,2);",'23503')
    query(f"UPDATE ref_data.revisions SET state='sealed' WHERE catalog_id='{CAT}' AND id='{REV}';")
    reject('retained coordinates cannot be rewritten',f"UPDATE ref_data.locations SET latitude=13 WHERE catalog_id='{CAT}' AND revision_id='{REV}' AND code='test_site';",'55000')
    reject('sealed location revision cannot gain new coordinates',insert('late','physical_site','1','2'),'55000')
