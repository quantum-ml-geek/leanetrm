"""Closed selector and original-authority checks for read-only presence admission."""
from uuid import uuid4

from gas_park_loan_fixture import rejected


def checks(f, book, context, at):
    def selected(values):
        return 'ARRAY[' + ','.join("'" + value + "'" for value in values) + ']::uuid[]'

    def call(books, trades, until=None):
        deadline = until or f"settlement_data.futures_margin_preview_authority('{f.catalog}')"
        return f.call(f"SELECT security.require_gas_park_loan_presence('{f.catalog}','{context}','{at}',"
            f"{selected(books)},{selected(trades)},{deadline});")

    call([book], [])
    zero = '00000000-0000-0000-0000-000000000000'
    trade = str(uuid4())
    for books, trades in [([], []), ([zero], []), ([book, book], []), ([book], [zero]), ([book], [trade, trade])]:
        rejected(lambda: call(books, trades), 'gas_park_loan_scope')
    rejected(lambda: call([book], [], "clock_timestamp()-interval '1 second'"), 'futures_margin_denied')
    print('PASS read-only service presence: closed exact selectors and expired original authority without an admitted source slot', flush=True)
