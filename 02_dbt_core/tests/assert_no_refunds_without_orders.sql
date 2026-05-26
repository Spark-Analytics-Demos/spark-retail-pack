-- Every refund in fact_refunds must reference an order that exists in fact_orders.
-- Returns refund_ids whose order_id has no match — indicates a data gap in the
-- ingestion pipeline (refund arrived before the parent order was loaded).
select r.refund_id
from {{ ref('fact_refunds') }} r
left join {{ ref('fact_orders') }} o
    on o.order_id = r.order_id
where o.order_sk is null
