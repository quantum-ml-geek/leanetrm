"""Project-authored synthetic data for a newly owned local preview cluster."""
from datetime import date, datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import re

CAT = '40000000-0000-0000-0000-000000000001'
REV = '60000000-0000-0000-0000-000000000001'
RCAT = '10000000-0000-0000-0000-000000000001'
RREV = '20000000-0000-0000-0000-000000000001'
TENANT = 'b0000000-0000-0000-0000-000000000001'
WORKSPACE = 'b1000000-0000-0000-0000-000000000001'
R = f"'{RCAT}','{RREV}'"
M = f"'{CAT}','{REV}'"


# Synthetic display names; every curve in this fixture must have exactly one.
CURVE_NAMES = {
    'future': 'Gas futures', 'bridge_basis': 'Futures–forward spread', 'base_forward': 'Gas forwards',
    'gas_basis': 'Regional gas spread', 'local_gas': 'Regional gas forwards', 'power_spread': 'Power spread',
    'hub_power': 'Hub power forwards', 'power_basis': 'Local power spread', 'local_power': 'Local power forwards',
    'local_power_all_in': 'Local power · all-in prices', 'interest_rates': 'Interest rates'}


def named_curves(sql):
    """Append each curve's display name to its positional insert; unknown codes fail."""
    return re.sub(r"(INSERT INTO market_data\.(?:rate_)?curves VALUES \('[^']*','[^']*','([a-z0-9_]+)'[^;]*)\);",
                  lambda m: f"{m.group(1)},'{CURVE_NAMES[m.group(2)]}');", sql)


def installed_tzdb():
    """The tzdb release the API will use (same lookup as TimeZoneDatabase); the preview declares it explicitly."""
    tzdir = os.environ.get('TZDIR')
    if tzdir == '':
        raise RuntimeError('TZDIR is set but empty; set a zoneinfo directory or unset it')
    root = Path(tzdir or '/usr/share/zoneinfo')
    marker, data = root / '+VERSION', root / 'tzdata.zi'
    if marker.is_file():
        return marker.read_text().strip()
    first = data.read_text().splitlines()[0] if data.is_file() else ''
    if not first.startswith('# version '):
        raise RuntimeError('Cannot determine the installed tzdb release for the power clock rules')
    return first.removeprefix('# version ').strip()


def identity(prefix, n):
    return f'{prefix}0000000-0000-0000-0000-{n:012d}'


def fixture(root):
    def historical(text):
        for old, new in [('2039','2019'),('2040','2020'),('2041','2021'),('2042','2022')]:
            text = text.replace(old, new)
        return text
    reference = historical((root / 'tests/fixtures/reference-synthetic.sql').read_text())
    market = historical((root / 'tests/fixtures/market-synthetic.sql').read_text())
    extra_ref=[]; extra_market=[]; extra_obs=[]
    # The power-hours consumer requires an actual MWh definition, never an
    # assumed conversion from the fixture's unrelated synthetic energy units.
    power_units=[
        f"INSERT INTO ref_data.units (catalog_id,revision_id,code,symbol,dimension_code) VALUES ({R},'megawatt_hour','MWh','energy');",
        f"INSERT INTO ref_data.units (catalog_id,revision_id,code,symbol,dimension_code) VALUES ({R},'megawatt','MW','power');",
        f"INSERT INTO ref_data.commodity_units VALUES ({R},'test_power','megawatt_hour','energy');"]
    reference=reference.replace('COMMIT;', '\n'.join(power_units)+'\nCOMMIT;',1)
    market=market.replace("'test_power_energy','energy_a','energy'", "'test_power_energy','megawatt_hour','energy'")
    for index_code in ('test_power_price','test_power_price_b'):
        market=market.replace(f"'{index_code}','test_power','test_hub_a','test_currency_a','energy_a'",
                              f"'{index_code}','test_power','test_hub_a','test_currency_a','megawatt_hour'")
    for kind in ['pipeline','node','region','terminal','delivery_point','physical_site']:
        extra_ref.append(f"INSERT INTO ref_data.location_types VALUES ({R},'test_{kind}','Synthetic {kind.replace('_',' ')}');")
    extra_ref.append(f"INSERT INTO ref_data.locations (catalog_id,revision_id,code,name,type_code,clock_code,latitude,longitude) VALUES ({R},'test_facility_a','Synthetic facility A','test_physical_site','test_utc',12.345678,-45.678912);")
    for kind in ['pipeline','node','region','terminal','delivery_point']:
        extra_ref.append(f"INSERT INTO ref_data.locations (catalog_id,revision_id,code,name,type_code,clock_code) VALUES ({R},'test_{kind}_a','Synthetic {kind.replace('_',' ')} A','test_{kind}','test_utc');")
    # Market clocks for the TOU products, and weekday closures in the business calendar.
    tzdb=installed_tzdb()
    for code,zone in [('synthetic_eastern','America/New_York'),('synthetic_central','America/Chicago'),('synthetic_pacific','America/Los_Angeles')]:
        extra_ref.append(f"INSERT INTO ref_data.clock_rules (catalog_id,revision_id,code,kind,iana_zone,tzdb_version) VALUES ({R},'{code}','iana','{zone}','{tzdb}');")
    extra_ref.append(f"INSERT INTO ref_data.clock_rules (catalog_id,revision_id,code,kind,fixed_offset_seconds) VALUES ({R},'synthetic_fixed_est','fixed_offset',-18000);")
    for closed in ['2021-01-01','2021-03-15']:
        extra_ref.append(f"INSERT INTO ref_data.calendar_days VALUES ({R},'test_business','{closed}',false,'Synthetic weekday closure');")
    now=datetime.now(timezone.utc).isoformat()
    market=market.replace('2020-12-18 16:01:00+00',now)
    # A separately observed all-in alternative demonstrates independent inputs.
    extra_market.append(f"INSERT INTO market_data.curves VALUES ({M},'local_power_all_in',{R},'test_power','test_hub_a','test_power_outright','test_uniform','test_power_target','direct','fixture','trader_mark');")
    curves=[('future',1),('bridge_basis',2),('base_forward',2),('gas_basis',3),('local_gas',3),
            ('power_spread',4),('hub_power',4),('power_basis',5),('local_power',5),('local_power_all_in',5)]
    mappings=[('base_forward',2,'future',1,'bridge_basis'),('local_gas',3,'base_forward',2,'gas_basis'),
              ('hub_power',4,'local_gas',3,'power_spread'),('local_power',5,'hub_power',4,'power_basis')]
    extra_ref.append(f"INSERT INTO ref_data.value_specifications VALUES ({R},'test_zero_rate','dimensionless',NULL,NULL,-0.1,1);")
    extra_market.append(f"INSERT INTO market_data.rate_curves VALUES ({M},'interest_rates',{R},'test_interest','fixture','valuation_utc_date');")
    for ordinal,maturity in enumerate(['2021-01-18','2021-06-18','2021-12-18']):
        sid=identity('9',800+ordinal)
        extra_market.append(f"INSERT INTO market_data.series VALUES ({M},'{sid}','zero_rate_{ordinal}',{R},NULL,NULL,'test_zero_rate');")
        extra_market.append(f"INSERT INTO market_data.rate_curve_points VALUES ({M},'interest_rates','{maturity}','{sid}',{ordinal});")
    series=[]
    for month in range(6):
        start=date(2021,month+1,1); end=date(2021,month+2,1)
        if month:
            previous=date(2020,12,28) if month==0 else date(2021,month,28)
            code=f'test_gas_2021{month+1:02d}'
            extra_ref.extend([
                f"INSERT INTO ref_data.futures_series VALUES ({R},'{code}','test_gas_future','2021-{month+1:02d}','synthetic','{start}','{end}');",
                f"INSERT INTO ref_data.futures_milestones VALUES ({R},'{code}','first_trading','known','2020-01-01','2020-01-01 00:00:00+00','test_utc','fixture');",
                f"INSERT INTO ref_data.futures_milestones VALUES ({R},'{code}','last_trading','known','{previous}','{previous} 15:30:00+00','test_utc','fixture');"])
            for n in range(1,6):
                cid=identity('5',month*5+n)
                kind='future' if n==1 else 'forward'
                expiry=f'{previous} 15:30:00+00' if n==1 else f'{end} 00:00:00+00'
                series_code=f"'{code}'" if n==1 else 'NULL'
                extra_market.append(f"INSERT INTO market_data.contracts VALUES ({M},'{cid}',{R},'{kind}','{start}','{end}','{expiry}',{series_code});")
            for curve,n in curves:
                extra_market.append(f"INSERT INTO market_data.curve_members VALUES ({M},'{curve}','{identity('5',month*5+n)}',{month});")
            for target,n,source,sn,spread in mappings:
                for slot,sc,cn in [('base',source,sn),('spread',spread,n)]:
                    extra_market.append(f"INSERT INTO market_data.constituent_mappings VALUES ({M},'{target}','{slot}','{identity('5',month*5+n)}','{sc}','{identity('5',month*5+cn)}');")
        else:
            extra_market.append(f"INSERT INTO market_data.curve_members VALUES ({M},'local_power_all_in','{identity('5',5)}',0);")
        for n, quote in [(1,'gas_outright'),(2,'gas_basis'),(3,'gas_basis'),(4,'power_basis'),(5,'power_basis'),(7,'power_outright')]:
            number=month*100+n; sid=identity('9',number); cn=5 if n==7 else n
            if month or n==7:
                extra_market.append(f"INSERT INTO market_data.series VALUES ({M},'{sid}','series_{number}',{R},'{identity('5',month*5+cn)}','test_{quote}',NULL);")
            series.append((number,n,month))
    series.append((6,6,0))
    series.extend((800+n,8+n,0) for n in range(3))
    frames=[]
    for day in range(15,19):
        pins=[]; distance=18-day
        for number,n,month in series:
            oid=identity('7',number if day==18 else 10000+day*1000+number)
            pins.append(oid)
            if day==18 and number<=6: continue
            m=Decimal(month); d=Decimal(distance)
            values={1:Decimal('3')+m*Decimal('.05')-d*Decimal('.01'),
                    2:Decimal('.1')+m*Decimal('.005'),3:Decimal('.2')+m*Decimal('.01'),
                    4:Decimal('4')+m*Decimal('.1'),5:Decimal('2')+m*Decimal('.05'),
                    8:Decimal('.025')-d*Decimal('.0001'),9:Decimal('.03')-d*Decimal('.0001'),10:Decimal('.035')-d*Decimal('.0001'),
                    6:Decimal('7')-d*Decimal('.02'),7:Decimal('29.1')+m*Decimal('.605')-d*Decimal('.05')}
            role='daily_settlement' if n==1 else 'parameter' if n==6 or n>=8 else 'trader_mark'
            event=f'event_{number}' if day==18 else f'history_{day}_{number}'
            extra_obs.append(f"INSERT INTO market_data.observations VALUES ('{CAT}','{oid}','{REV}','{identity('9',number)}',{R},'fixture','{event}','1','{role}','final','2020-12-{day} 16:00:00+00','{now}',{values[n]},NULL);")
        frames.append({'at':f'2020-12-{day}T16:00:00Z','observationIds':pins,
                       'curveContracts':{code:[identity('5',month*5+n) for month in range(6)] for code,n in curves}})
    market=market.replace('UPDATE ref_data.revisions SET', '\n'.join(extra_ref)+'\nUPDATE ref_data.revisions SET',1)
    extra_market.append(f"INSERT INTO market_data.revision_periods VALUES ({M},'2020-01-01','2022-01-01');")
    market=market.replace('UPDATE market_data.revisions SET','\n'.join(extra_market)+'\nUPDATE market_data.revisions SET',1)
    market=market.rsplit('COMMIT;',1)[0]+'\n'+'\n'.join(extra_obs)+'\nCOMMIT;\n'
    market=named_curves(market)
    # Common ISO peak conventions as published TOU products (verify before any settlement use).
    # Peak is hour-beginning [start, end) Monday–Friday, or Monday–Saturday where marked.
    tou=[]
    for n,(code,name,clock,start,end,saturday) in enumerate([
            ('pjm','PJM · Eastern prevailing','synthetic_eastern',7,23,'false'),
            ('nyiso','NYISO · Eastern prevailing','synthetic_eastern',7,23,'false'),
            ('isone','ISO-NE · Eastern prevailing','synthetic_eastern',7,23,'false'),
            ('miso','MISO settlement / FTR · fixed EST','synthetic_fixed_est',6,22,'false'),
            ('spp','SPP · Central prevailing','synthetic_central',6,22,'false'),
            ('ercot','ERCOT · Central prevailing','synthetic_central',6,22,'false'),
            ('caiso','CAISO / WECC · Pacific prevailing','synthetic_pacific',6,22,'true')],start=1):
        pid=identity('d',n)
        tou.append(f"INSERT INTO market_data.tou_products VALUES ('{CAT}','{pid}','{code}');")
        tou.append(f"INSERT INTO market_data.tou_product_versions(catalog_id,product_id,version,generation,state,name,clock_catalog_id,clock_revision_id,clock_code,peak_start_hour,peak_end_hour,peak_saturday,publication_order,published_at) VALUES ('{CAT}','{pid}',1,1,'published','{name}',{R},'{clock}',{start},{end},{saturday},{n},'{now}');")
    market=market.rsplit('COMMIT;',1)[0]+'\n'.join(tou)+'\nCOMMIT;\n'
    manifest={'mode':'local-synthetic-preview','catalogId':CAT,'revisionId':REV,'referenceCatalogId':RCAT,'referenceRevisionId':RREV,
              'tenantId':TENANT,'workspaceId':WORKSPACE,'frames':frames,
              'schedules':[{'curve':'future','from':'2020-12-01T00:00:00Z','to':'2021-05-28T15:30:00Z','exampleAt':'2020-12-28T15:29:00Z'}],
              'example':{'at':'2020-12-18T16:00:00Z','curve':'local_power'}}
    return reference, market, security_fixture(CAT,RCAT), manifest


def security_fixture(catalog,reference_catalog):
    security=[f"INSERT INTO security.tenants VALUES ('{TENANT}','preview');",
              f"INSERT INTO security.workspaces VALUES ('{TENANT}','{WORKSPACE}','synthetic_market');",
              f"INSERT INTO security.market_catalog_scopes VALUES ('{catalog}','{TENANT}','{WORKSPACE}');",
              f"INSERT INTO security.reference_catalog_scopes VALUES ('{reference_catalog}','{TENANT}','{WORKSPACE}','owner');"]
    for n,slug,role in [(1,'viewer',1),(2,'editor',4),(3,'approver',5),(4,'admin',6)]:
        pid=identity('c',n)
        security.extend([f"INSERT INTO security.principals VALUES ('{pid}','human',true);",
            f"INSERT INTO security.identity_bindings VALUES ('https://preview.invalid','{slug}','{pid}','human_interactive');",
            f"INSERT INTO security.workspace_memberships VALUES ('{TENANT}','{WORKSPACE}','{pid}','{slug}','Synthetic {slug}',true,1);",
            f"INSERT INTO security.role_grants VALUES (gen_random_uuid(),'{pid}','a0000000-0000-0000-0000-{role:012d}','{TENANT}','{WORKSPACE}',CURRENT_TIMESTAMP-INTERVAL '1 day',CURRENT_TIMESTAMP+INTERVAL '1 day',false);"])
    security.extend(['CREATE ROLE preview_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS INHERIT IN ROLE openetrm_runtime;',
                     'CREATE ROLE preview_authenticator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS INHERIT IN ROLE openetrm_authenticator;'])
    return '\n'.join(security)
