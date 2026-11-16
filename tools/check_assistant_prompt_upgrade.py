"""Prompt/context migrations refuse drift in every helper they rely on."""
import json
from uuid import uuid4
from assistant_context import migration_body
from check_fact_anchor_upgrade import run_checks as check_helpers


def run_checks(query, migration):
    number = migration.name[:4]
    contracts = json.loads(migration.read_text().split('$assistant_helpers$')[1])
    check_helpers(query, migration, number=number,
                  guard='assistant_' + ('prompt' if number == '0338' else 'context') + '_upgrade',
                  signatures=tuple(c['signature'] for c in contracts))
    if number == '0338':
        tenant, workspace, actor = uuid4(), uuid4(), uuid4()
        result = query(f"""BEGIN;
            INSERT INTO security.tenants VALUES('{tenant}','synthetic_prompt_upgrade');
            INSERT INTO security.workspaces VALUES('{tenant}','{workspace}','synthetic_prompt_upgrade');
            INSERT INTO security.principals VALUES('{actor}','human',true);
            INSERT INTO assistant.page_prompt_versions VALUES('{tenant}','{workspace}','curves',1,'Synthetic retained page text.','{actor}',clock_timestamp());
            CREATE TEMP TABLE before_prompts AS SELECT to_jsonb(v) value FROM assistant.page_prompt_versions v;
            {migration_body(migration.read_text())}
            SELECT NOT EXISTS((SELECT value FROM before_prompts EXCEPT SELECT to_jsonb(v) FROM assistant.page_prompt_versions v)
                UNION ALL(SELECT to_jsonb(v) FROM assistant.page_prompt_versions v EXCEPT SELECT value FROM before_prompts))
                AND NOT EXISTS(SELECT 1 FROM assistant.page_prompt_versions WHERE page IN('application','provider_test:instructions','provider_test:question') OR page LIKE 'tool:%');
            ROLLBACK;""")
        assert result == 't', 'prompt upgrade changed existing configuration or seeded new instructions'
        print('PASS populated prompt upgrade preserves exact existing text and introduces no default guidance', flush=True)
