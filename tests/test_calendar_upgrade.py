"""The native calendar upgrade matrix cannot silently lose one consumer."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from check_calendar_upgrade import REQUIRED_SIGNATURES, run_checks


class CalendarUpgradeTests(unittest.TestCase):
    def test_omitting_any_pinned_consumer_fails_before_database_work(self):
        for number in REQUIRED_SIGNATURES:
            path = next((ROOT / 'db/migrations').glob(number + '_*.sql'))
            original = path.read_text().split('$calendar_helpers$')
            dependencies = json.loads(original[1])
            for omitted in dependencies:
                with self.subTest(migration=number, helper=omitted['signature']):
                    changed = original.copy()
                    changed[1] = json.dumps([d for d in dependencies if d != omitted])
                    class Migration:
                        name = path.name
                        def read_text(self):
                            return '$calendar_helpers$'.join(changed)
                    with self.assertRaisesRegex(AssertionError, 'omitted or changed a required native consumer'):
                        run_checks(lambda sql: self.fail('An incomplete matrix reached the database'), Migration())
