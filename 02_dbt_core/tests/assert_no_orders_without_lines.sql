-- Per §4.37 Category 4: Orders with line_item_count > 0 must have at least one
-- corresponding row in fact_order_lines. Returns order_ids that violate this rule.
-- Failure means the enrichment pipeline (int_orders_enriched) is out of sync with
-- the line-item staging table.
select o.order_id
from {{ ref('fact_orders') }} o
left join {{ ref('fact_order_lines') }} l
    on l.order_id = o.order_id
where l.line_item_sk is null
  and o.line_item_count > 0
