#!/usr/bin/env python3
"""Select conservative CI groups from the complete local Git diff."""
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess

from check_all import ALL_GROUPS, GROUPS

# Only independently invoked browser scenarios are narrowed. Shared helpers and
# new scenarios deliberately take the full gate until their consumers are known.
BROWSER_GROUPS = {
    'ai-settings.mjs': ('assistant',),
    'agent-settings.mjs': ('assistant',),
    'usage-settings.mjs': ('assistant',),
    'assistant-panel.mjs': ('assistant',),
    'swaps.mjs': ('frontend', 'standard', 'trading'),
    'swap-observations.mjs': ('trading',),
    'factor-swaps.mjs': ('trading',),
    'demo-instruments.mjs': ('trading',),
    'position-popout.mjs': ('trading',),
    'scheduled-authoring.mjs': ('settlement',),
    'scheduled-swaps.mjs': ('settlement',),
    'swap-settlement.mjs': ('settlement',),
    'swap-netting.mjs': ('settlement',),
    'ppa.mjs': ('ppa',),
    'pilot-close.mjs': ('portfolio',),
    'valuation-status.mjs': ('portfolio',),
    'risk.mjs': ('frontend', 'standard', 'risk'),
    'risk-closes.mjs': ('risk',),
    'jobs.mjs': ('workspace',),
}
# API and MarketData check projects also export fixtures and execute database
# modes. Until those relationships are narrower, their edits require every group.
MANAGED_CHECKS = frozenset(('OpenEtrm.Rates.Checks', 'OpenEtrm.Shared.Checks'))
ROOT_DOCUMENTS = frozenset(('README.md', 'CONTRIBUTING.md', 'CLA.md', 'SECURITY.md'))


def consumers(path):
    parts = PurePosixPath(path).parts
    if path in ROOT_DOCUMENTS or (path.startswith('docs/') and path.endswith('.md')):
        return ('repository',)
    if path.startswith(('site/', 'specs/settlement/')):
        return ('repository',)
    if len(parts) == 2 and parts[0] == 'tests' and parts[1].startswith('test_') and path.endswith('.py'):
        return ('repository',)
    if path.startswith('web/tests/'):
        return ('frontend',)
    if len(parts) >= 3 and parts[0] == 'tests' and parts[1] in MANAGED_CHECKS:
        return ('managed',)
    if len(parts) == 3 and parts[:2] == ('tests', 'browser') and parts[2] in BROWSER_GROUPS:
        return BROWSER_GROUPS[parts[2]]
    if path.startswith('web/src/'):
        # The shared shell and bundles serve every preview, including the owned
        # database integration consumers. Managed unit tests do
        # not consume presentation source.
        return ('repository', 'frontend', 'database', *GROUPS)
    return ALL_GROUPS


def plan(paths, *, event):
    selected = {'repository'}
    reason = 'Selected the union of declared path consumers.'
    if event != 'pull_request' or not paths:
        selected.update(ALL_GROUPS)
        reason = 'Master pushes, manual/unknown events and unavailable/empty diffs require the full gate.'
    else:
        for path in paths:
            selected.update(consumers(path))
    groups = [group for group in ALL_GROUPS if group in selected]
    return {'groups': groups, 'full': groups == list(ALL_GROUPS), 'reason': reason}


def changed_paths(root, event, payload):
    def git(*arguments):
        return subprocess.check_output(['git', *arguments], cwd=root, stderr=subprocess.PIPE)

    def revision(value):
        if not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{40}', value) or value == '0' * 40:
            raise ValueError('Missing commit identity')
        git('cat-file', '-e', value + '^{commit}')
        return value

    try:
        if event == 'pull_request':
            request = payload['pull_request']
            base, head = (revision(request[side]['sha']) for side in ('base', 'head'))
            for parent in (base, head):
                git('merge-base', '--is-ancestor', parent, 'HEAD')
            before = git('merge-base', base, head).decode('ascii').strip()
            # Checkout is the PR merge result: include target changes since the
            # common ancestor, rather than qualifying only an unmerged topic.
            after = 'HEAD'
        elif event == 'push':
            before, after = (revision(payload[key]) for key in ('before', 'after'))
        else:
            return None
        raw = git('diff', '--no-ext-diff', '--no-renames', '--name-only', '-z', before, after, '--')
        return [os.fsdecode(path) for path in raw.split(b'\0') if path]
    except (KeyError, TypeError, ValueError, OSError, subprocess.CalledProcessError):
        return None


def main():
    event = os.environ.get('GITHUB_EVENT_NAME', '')
    try:
        payload = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        paths = changed_paths(Path.cwd(), event, payload)
    except (KeyError, ValueError, OSError):
        paths = None
    result = plan(paths, event=event)
    print(json.dumps(result))
    if output := os.environ.get('GITHUB_OUTPUT'):
        with Path(output).open('a') as stream:
            stream.write('groups=' + json.dumps(result['groups'], separators=(',', ':')) + '\n')
            stream.write('full=' + str(result['full']).lower() + '\n')


if __name__ == '__main__':
    main()
