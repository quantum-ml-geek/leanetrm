"""Explicit synthetic provider-test configuration for disposable verification installations."""
from uuid import uuid4

INSTRUCTION = 'Synthetic connectivity test instructions.'
PROMPT = 'Synthetic connectivity test question.'


def configure_probe(admin):
    path = 'settings/ai/page-prompts'
    versions = admin.call(path)['configuration']['prompts']
    for scope, text in (('provider_test:instructions', INSTRUCTION), ('provider_test:question', PROMPT)):
        current = max((v['version'] for v in versions if v['page'] == scope), default=0)
        admin.call(path + '/save', {'operationId': str(uuid4()), 'page': scope, 'expectedVersion': current, 'instructions': text})
