"""Separate immutable synthetic daily gas/power market bundle for swap schedules."""
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from preview_fixture import CAT, RCAT, RREV, identity

REVISION = '60000000-0000-0000-0000-000000000002'


def fixture():
    m = f"'{CAT}','{REVISION}'"; r = f"'{RCAT}','{RREV}'"
    rows = ['BEGIN;', f"INSERT INTO market_data.revisions VALUES ({m},{r},'draft',0);"]
    prices = []
    for n, commodity, quote, target in [(0, 'gas', 'test_gas_outright', 'test_index_target'), (1, 'power', 'test_power_outright', 'test_power_target')]:
        curve = 'daily_'+commodity
        rows.append(f"INSERT INTO market_data.curves VALUES ({m},'{curve}',{r},'test_{commodity}','test_hub_a','{quote}','test_uniform','{target}','direct','fixture','trader_mark');")
        for day in range(1, 32):
            start = date(2021, 1, day); end = start+timedelta(days=1)
            cid = identity('5', 2000+n*100+day); sid = identity('9', 2000+n*100+day)
            rows.extend([f"INSERT INTO market_data.contracts VALUES ({m},'{cid}',{r},'forward','{start}','{end}','{end} 00:00:00+00',NULL);",
                         f"INSERT INTO market_data.curve_members VALUES ({m},'{curve}','{cid}',{day-1});",
                         f"INSERT INTO market_data.series VALUES ({m},'{sid}','swap_{commodity}_{day}',{r},'{cid}','{quote}',NULL);"])
            prices.append((2000+n*100+day, sid, Decimal('3')+Decimal(day)/100 if n==0 else Decimal('40')+Decimal(day)/10, 'trader_mark'))
    rows.append(f"INSERT INTO market_data.rate_curves VALUES ({m},'interest_rates',{r},'test_interest','fixture','valuation_utc_date');")
    for n, maturity in enumerate(['2021-01-18', '2021-06-18', '2021-12-18']):
        sid=identity('9', 2800+n)
        rows.extend([f"INSERT INTO market_data.series VALUES ({m},'{sid}','swap_rate_{n}',{r},NULL,NULL,'test_zero_rate');",
                     f"INSERT INTO market_data.rate_curve_points VALUES ({m},'interest_rates','{maturity}','{sid}',{n});"])
        prices.append((2800+n,sid,Decimal('.025')+Decimal(n)/200,'parameter'))
    rows.extend([f"INSERT INTO market_data.revision_periods VALUES ({m},'2020-01-01','2022-01-01');",
                 f"UPDATE market_data.revisions SET state='sealed' WHERE catalog_id='{CAT}' AND id='{REVISION}';"])
    now=datetime.now(timezone.utc).isoformat();frames=[]
    for day in range(15, 19):
        pins=[]
        for number, sid, value, role in prices:
            oid=identity('7', 300000+day*10000+number);pins.append(oid)
            adjusted=value-Decimal(18-day)* (Decimal('.0001') if role=='parameter' else Decimal('.01'))
            rows.append(f"INSERT INTO market_data.observations VALUES ('{CAT}','{oid}','{REVISION}','{sid}',{r},'fixture','swap_{day}_{number}','1','{role}','final','2020-12-{day} 16:00:00+00','{now}',{adjusted},NULL);")
        frames.append({'at':f'2020-12-{day}T16:00:00Z','observationIds':pins,'curveContracts':{}})
    rows.append('COMMIT;')
    return '\n'.join(rows), {'revisionId':REVISION,'frames':frames}
