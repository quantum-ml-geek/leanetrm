"""Independent operator title and debt counterpart corrections."""
from datetime import datetime,timezone
from decimal import Decimal
import json
from uuid import uuid4

PRESERVE='preserve_unallocated_source_quantity_v1'


def checks(query,manifest,call,capture,read,record,amend,packet):
    catalog=manifest['catalogId'];results=[]
    for case in packet['counterpartCases']:
        claim=case['claimId'];before_context=capture();source=read(claim,before_context)
        assert len(source['settlements'])==1
        step=source['settlements'][0];positive=step['receiptLotId'] is not None
        original_quantity=Decimal('10') if positive else Decimal('2')
        revised=Decimal('9') if positive else Decimal('1.5')
        assert Decimal(step['quantity'])==original_quantity
        old_evidence=next(row for row in source['evidence'] if row['id']==step['evidenceId'])
        assert old_evidence['capturedHead']
        source_quantity=Decimal(old_evidence['quantity'])
        revised_source=(abs(source_quantity)-(original_quantity-revised))*(1 if source_quantity>=0 else -1)
        occurred=datetime.fromisoformat(old_evidence['occurred_at']).astimezone(timezone.utc).isoformat().replace('+00:00','Z')
        evidence=record('evidence',dict(sourceKey=old_evidence['source_key'],kind=old_evidence['kind'],quantity=str(revised_source),occurredAt=occurred,
            expectedRevision=old_evidence['revision'],evidence='Synthetic explicit operator counterpart source correction'),target=old_evidence['account_id'])['id']
        claim_quantity=source['claim']['quantity'];claim_evidence=source['claim']['evidenceId']
        if positive:
            statement=next(row for row in source['evidence'] if row['id']==claim_evidence)
            when=datetime.fromisoformat(statement['occurred_at']).astimezone(timezone.utc).isoformat().replace('+00:00','Z')
            claim_evidence=record('evidence',dict(sourceKey=statement['source_key'],kind=statement['kind'],quantity=str(Decimal(statement['quantity'])-1),
                occurredAt=when,expectedRevision=statement['revision'],evidence='Synthetic revised operator entitlement with exact title counterpart'),target=statement['account_id'])['id']
            claim_quantity='9'
        receipt=next((row for row in source['positions'] if row['id']==step['receiptLotId']),None)
        used=next((row for row in source['consumptions'] if row['id']==step['consumptionId']),None)
        assert (receipt is not None)==positive and (used is None)==positive
        def state():return query("SELECT jsonb_object_agg(name,digest) FROM("+' UNION ALL '.join(
            "SELECT '"+table+"'::text name,(SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]')::text) FROM trading."+table+f" x WHERE x.catalog_id='{catalog}') digest"
            for table in ['gas_owned_positions','gas_owned_consumptions','gas_owned_claim_settlements','gas_owned_fees','gas_owned_fee_payments'])+")s;")
        original=state();pub=int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))
        body=dict(implementation='gas_operator_quantity_reconciliation_v1',rootClaimId=claim,claims=[dict(claimId=claim,
            expectedRevision=source['claim']['expectedRevision'],quantity=claim_quantity,evidenceId=claim_evidence,sourceAllocation=PRESERVE,
            settlements=[dict(settlementId=step['id'],expectedRevision=step['expectedRevision'],quantity=str(revised),evidenceId=evidence,
                sourceObservationId=None,expectedReceiptRevision=receipt['expectedRevision'] if positive else None,
                expectedConsumptionRevision=used['expectedRevision'] if not positive else None,lotId=used['lotId'] if not positive else None,
                reservationId=used['reservation_id'] if not positive else None,sourceAllocation=PRESERVE)])],consumptions=[],cashout=dict(ordering='replay_original_settlement_publication_prefix_v1',adjustmentDueAt=None),
            evidence='Synthetic complete exact operator title or debt counterpart correction')
        operation=str(uuid4());context=capture();outcome=amend(body,operation,context)
        assert outcome['changed'] and not outcome['semanticAcknowledgement'] and outcome['cashChanges']==[]
        current_context=capture();current=read(claim,current_context);assert current['claim']['expectedRevision']==(2 if positive else source['claim']['expectedRevision'])
        assert current['claim']['quantity']==claim_quantity and current['claim']['evidenceId']==claim_evidence
        assert Decimal(current['claim']['remainingQuantity'])==(Decimal('0') if positive else Decimal('-1.5'))
        current_step=current['settlements'][0]
        assert current_step['id']==step['id'] and current_step['expectedRevision']==2 and Decimal(current_step['quantity'])==revised
        assert current_step['receiptLotId']==step['receiptLotId'] and current_step['consumptionId']==step['consumptionId']
        if positive:
            selected=next(row for row in current['positions'] if row['id']==receipt['id'])
            assert selected['expectedRevision']==2 and Decimal(selected['quantity'])==9 and selected['evidenceId']==evidence
            assert current_step['receiptRevision']==2
            assert len(current['consumptions'])==len(source['consumptions'])
            assert [(row['id'],row['quantity'],row['expectedRevision']) for row in current['consumptions']]==[
                (row['id'],row['quantity'],row['expectedRevision']) for row in source['consumptions']]
        else:
            selected=next(row for row in current['consumptions'] if row['id']==used['id'])
            assert selected['expectedRevision']==2 and Decimal(selected['quantity'])==Decimal('1.5') and selected['evidenceId']==evidence
            assert selected['lotId']==used['lotId'] and selected['reservation_id']==used['reservation_id'] and current_step['consumptionRevision']==2
            assert [(row['id'],row['quantity'],row['expectedRevision']) for row in current['positions']]==[
                (row['id'],row['quantity'],row['expectedRevision']) for row in source['positions']]
        assert state()==original,'An operator counterpart correction rewrote original title, use, settlement, cash or bank rows.'
        assert int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))==pub+1
        books=json.loads(query("SELECT jsonb_agg(DISTINCT a.book_id) FROM trading.gas_owned_accounts a "
            f"WHERE a.catalog_id='{catalog}' AND a.id IN('{source['accountId']}','{old_evidence['account_id']}');"))
        book_sql='ARRAY['+','.join(repr(value) for value in books)+']::uuid[]'
        def native_views(day):
            selected_context=capture(day);when=day+'T16:00:00Z'
            prefix=f"SELECT security.use_market_context('{catalog}','{selected_context}');SELECT security.use_trading_context('{catalog}','{when}','{day}'::date);"
            holdings=json.loads(call(prefix+f"SELECT security.read_gas_owned_holdings('{catalog}','{selected_context}','{when}',{book_sql})::text;"))
            known=json.loads(call(prefix+f"SELECT security.read_gas_owned_known_history('{catalog}','{selected_context}','{when}',{book_sql})::text;"))
            return holdings,known
        held,known=native_views('2020-12-20');held_ids={row['id']:row for row in held['positions']}
        if positive:
            assert claim not in held_ids,'A raw original settlement created a synthetic negative claim residual.'
            assert Decimal(held_ids[receipt['id']]['remaining_quantity'])==9
            later,later_known=native_views('2020-12-23')
            assert claim not in {row['id'] for row in later['positions']}
            assert Decimal(next(row for row in later['positions'] if row['id']==receipt['id'])['remaining_quantity'])==7
            assert any(row['id']==source['consumptions'][0]['id'] and Decimal(str(row['quantity']))==2 for row in later_known['consumptions'])
        else:
            assert Decimal(held_ids[claim]['remaining_quantity'])==Decimal('-1.5')
            assert Decimal(held_ids[used['lotId']]['remaining_quantity'])==Decimal('1.5')
        known_step=next(row for row in known['settlements'] if row['id']==step['id'])
        assert Decimal(str(known_step['quantity']))==revised and known_step['financial_revision']==2
        assert known_step['original_publication_order']==step['originalPublicationOrder']
        assert known_step['publication_order']==step['originalPublicationOrder'] and known_step['financial_publication_order']==pub+1
        historical=read(claim,before_context)
        assert historical['settlements'][0]['expectedRevision']==1 and Decimal(historical['settlements'][0]['quantity'])==original_quantity
        assert amend(body,operation,context)==outcome
        # Requesting a previously accepted physical fact under a fresh nonce
        # acknowledges that exact snapshot and preserves the later paired heads.
        original_fact=json.loads(json.dumps(body));original_claim=original_fact['claims'][0];original_step=original_claim['settlements'][0]
        original_claim.update(expectedRevision=source['claim']['expectedRevision'],quantity=source['claim']['quantity'],evidenceId=source['claim']['evidenceId'])
        original_step.update(expectedRevision=step['expectedRevision'],quantity=step['quantity'],evidenceId=step['evidenceId'],
            expectedReceiptRevision=receipt['expectedRevision'] if positive else None,expectedConsumptionRevision=used['expectedRevision'] if not positive else None)
        acknowledgement=amend(original_fact,str(uuid4()),capture())
        assert not acknowledgement['changed'] and acknowledgement['semanticAcknowledgement'] and acknowledgement['cashChanges']==[]
        member=acknowledgement['claims'][0];accepted=member['settlements'][0]
        assert member['acknowledgedRevision']==source['claim']['expectedRevision'] and member['currentRevision']==current['claim']['expectedRevision']
        assert accepted['acknowledgedRevision']==1 and accepted['currentRevision']==2 and Decimal(accepted['currentQuantity'])==revised
        assert int(query(f"SELECT max(publication_order) FROM trading.publications WHERE catalog_id='{catalog}';"))==pub+1
        retained=read(claim,capture());assert retained['settlements'][0]['expectedRevision']==2 and Decimal(retained['settlements'][0]['quantity'])==revised
        assert state()==original
        results.append(dict(claimId=claim,accountId=source['accountId'],settlementId=step['id'],receiptLotId=step['receiptLotId'],
            consumptionId=step['consumptionId'],fundingLotId=used['lotId'] if used else None,
            lossIds=[row['id'] for row in source['consumptions'] if row['kind']=='loss' and row['lotId']==step['receiptLotId']],
            originalContextId=before_context,currentContextId=current_context,asOf=packet['at'],body=body,
            operationId=operation,contextId=context,outcome=outcome,originalSource=source,source=current))
        print('PASS exact operator '+('receipt' if positive else 'debt funding')+': same native IDs, revised paired quantity/evidence, retained future use/original cash and bank, historical prefix, first receipt and fresh-nonce old-fact acknowledgement without rewind',flush=True)
    return results
