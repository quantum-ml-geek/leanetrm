"""Independent synthetic calendar publication and lifecycle authority probes."""
from uuid import uuid4


def independent_calendar(query,manifest):
    reference=manifest['referenceCatalogId']
    source,definition,revision=(str(uuid4()) for _ in range(3))
    query(f"""BEGIN;
      INSERT INTO ref_data.revisions(catalog_id,id,revision_key) VALUES('{reference}','{revision}','synthetic_lifecycle_calendar');
      INSERT INTO ref_data.clock_rules VALUES('{reference}','{revision}','synthetic_utc','fixed_offset',0,NULL,NULL);
      INSERT INTO ref_data.calendars VALUES('{reference}','{revision}','synthetic_days','synthetic_utc',0,'2020-01-01','2100-01-01');
      UPDATE ref_data.revisions SET state='sealed' WHERE(catalog_id,id)=('{reference}','{revision}');
      INSERT INTO market_data.catalogs VALUES('{source}','synthetic_lifecycle_calendar_source');
      INSERT INTO security.market_catalog_scopes VALUES('{source}','{manifest['tenantId']}','{manifest['workspaceId']}');
      INSERT INTO market_data.revisions VALUES('{source}','{definition}','{reference}','{revision}','draft',0);
      INSERT INTO market_data.revision_periods VALUES('{source}','{definition}','2020-01-01','2022-01-01');
      UPDATE market_data.revisions SET state='sealed' WHERE(catalog_id,id)=('{source}','{definition}');COMMIT;
    """)
    return source,dict(revision=dict(catalogId=reference,revisionId=revision),code='synthetic_days')


def check_calendar_authority(query,manifest,source,statements):
    catalog,tenant,workspace=(manifest[k] for k in ('catalogId','tenantId','workspaceId'))
    tables=('lifecycle.commands','settlement_data.swap_commands','settlement_data.swap_determinations',
            'settlement_data.swap_cash_payments','settlement_data.swap_payment_allocations')
    def retained():
        return {table:query(f"SELECT encode(sha256(convert_to(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb)::text,'UTF8')),'hex') FROM {table} t;") for table in tables}
    before=retained()
    for label,statement in statements:
        token=query("SET SESSION AUTHORIZATION preview_authenticator;SELECT security.issue_context("
                    f"'https://preview.invalid','trader','human_interactive','{tenant}','{workspace}',NULL,'preview_runtime',60);")
        query(f"BEGIN;DELETE FROM security.market_catalog_scopes WHERE catalog_id='{source}';"
              f"SET SESSION AUTHORIZATION preview_runtime;SELECT security.use_context('{token}');"
              f"DO $probe$BEGIN IF NOT security.market_access('{catalog}','ReadMarketData') OR security.market_access('{source}','ReadMarketData') "
              "THEN RAISE EXCEPTION 'Synthetic scope control failed';END IF;BEGIN "
              +statement.replace('SELECT ','PERFORM ')+";RAISE EXCEPTION 'Calendar revocation was ignored';"
              "EXCEPTION WHEN insufficient_privilege THEN IF SQLERRM<>'side_calendar_denied' THEN RAISE;END IF;END;END$probe$;ROLLBACK;")
        assert retained()==before,label+' changed an original financial outcome or request'
    print('PASS lifecycle independent calendar authority: '+', '.join(label for label,_ in statements)+' refused after isolated source revocation; original outcome and request bytes unchanged',flush=True)
