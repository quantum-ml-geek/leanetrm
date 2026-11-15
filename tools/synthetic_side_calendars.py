"""Explicit calendar terms for synthetic contracts, never application defaults."""
from copy import deepcopy


def all_dates_policy(*, observation):
    """Select the named synthetic all-dates contract for a dated payment Side."""
    from preview_fixture import RCAT, RREV
    reference=dict(revision=dict(catalogId=RCAT,revisionId=RREV),code='test_utc_every_day')
    return side_calendar_policy(reference,delivery=True,observation=observation,payment=True)


def side_calendar_policy(reference, *, delivery, observation, payment):
    return dict(implementation='side_calendar_policy_v1', **{
        purpose:dict(applicable=applies, calendar=deepcopy(reference) if applies else None)
        for purpose, applies in [('delivery', delivery), ('observation', observation), ('payment', payment)]})
