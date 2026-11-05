"""Fresh Blotter reuse authorizes the exact selection and observes durable changes, without valuing trades."""
def run_checks(c,check,query,manifest):
    c.call('profile',{'profile':'trader'})
    c.call('market/current',{})
    frames=c.call('workspace/navigation')['frames']
    request={'snapshotId':frames[0]['id'],'convention':'trading_workspace_v1','knowledgeMode':'current'}
    first=c.call('trading/freshness',request)
    check('unchanged Blotter inputs have a stable opaque server version',
          len(first['version'])==64 and first==c.call('trading/freshness',request))
    check('freshness versions are bound to the selected input snapshot',
          first!=c.call('trading/freshness',{**request,'snapshotId':frames[1]['id']}))
    c.call('trading/freshness',{**request,'knowledgeMode':None},expected=422)
    c.call('trading/freshness',{**request,'convention':'invented'},expected=422)
    captured=c.call('date-schedules/context',{'effectiveOn':frames[0]['at'][:10],'knownAt':None,'mode':'current'})
    check('context capture and certification alone do not invalidate completed values',first==c.call('trading/freshness',request))
    retained={**request,'knowledgeMode':'retained','contextId':captured['context']['contextId']}
    check('freshness binds the explicitly retained cutoff',first!=c.call('trading/freshness',retained))
    catalog=manifest['catalogId']
    query('UPDATE security.epoch SET generation=generation+1 WHERE id;')
    check('current authorization changes invalidate a previously completed read',first!=c.call('trading/freshness',request))
    # A committed publication is a conservative invalidation even before certification catches up.
    before=c.call('trading/freshness',request)
    query(f"INSERT INTO trading.publications SELECT '{catalog}',coalesce(max(publication_order),0)+1,pg_current_xact_id() FROM trading.publications WHERE catalog_id='{catalog}';")
    check('committed trade publications invalidate cached values',before!=c.call('trading/freshness',request))
    c.call('profile',{'profile':'viewer'})
    c.call('trading/freshness',request,expected=403)
    check('freshness checks require current trade access')


def run_update_checks(c,check,query):
    from concurrent.futures import ThreadPoolExecutor
    import time
    c.call('profile',{'profile':'trader'})
    frame=c.call('workspace/navigation')['frames'][0]
    request={'snapshotId':frame['id'],'convention':'trading_workspace_v1','knowledgeMode':'current'}
    first=c.call('trading/freshness',request)
    check('update waits immediately return a changed authorized version',
          c.call('trading/changes',{'context':request,'version':'0'*64})==first)
    c.call('trading/changes',{'context':request,'version':'invalid'},expected=422)
    with ThreadPoolExecutor(max_workers=1) as pool:
        waiting=pool.submit(c.call,'trading/changes',{'context':request,**first})
        time.sleep(0.2)
        started=time.monotonic()
        check('an update waiter releases the session gate for foreground reads',
              c.call('trading/freshness',request)==first and time.monotonic()-started<3)
        c.call('trading/changes',{'context':request,**first},expected=422)
        query('UPDATE security.epoch SET generation=generation+1 WHERE id;')
        changed=waiting.result(timeout=10)
        check('committed native change notifications wake the waiter and return the durable head',
              changed!=first and changed==c.call('trading/freshness',request))
        waiting=pool.submit(c.call,'trading/changes',{'context':request,**changed},expected=403)
        time.sleep(0.2)
        c.call('profile',{'profile':'viewer'})
        waiting.result(timeout=12)
        check('a waiting update read cannot publish across an account change')
    c.call('profile',{'profile':'trader'})
