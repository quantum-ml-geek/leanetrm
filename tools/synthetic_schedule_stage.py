"""Owned, rolled-back native negative checks start with admitted schedule authority."""
from uuid import UUID


def copy_stage(catalog, source_request, request):
    catalog,source_request,request=(str(UUID(str(value))) for value in (catalog,source_request,request))
    return f"""
      INSERT INTO trading.side_schedule_requests
       SELECT(jsonb_populate_record(NULL::trading.side_schedule_requests,to_jsonb(r)||jsonb_build_object('request_id','{request}'))).*
       FROM trading.side_schedule_requests r WHERE(catalog_id,request_id)=('{catalog}','{source_request}');
      INSERT INTO trading.side_schedule_request_items SELECT catalog_id,'{request}',slot,schedule_id
       FROM trading.side_schedule_request_items WHERE(catalog_id,request_id)=('{catalog}','{source_request}');
    """
