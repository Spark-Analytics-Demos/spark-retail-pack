{{ config(materialized='ephemeral') }}

-- Order-level enrichment per §4.19 (fact_orders source mapping).
-- Adds is_first_order, is_repeat_order, line_item_count, total_quantity.
-- Output grain: one row per order_id — joins to stg_shopify__orders in fact_orders.
-- Anonymous orders (null shopify_customer_id) default is_first_order/is_repeat_order to false.

with orders as (
    select
        order_id,
        shopify_customer_id,
        order_date,
        order_timestamp
    from {{ ref('stg_shopify__orders') }}
),

line_item_agg as (
    select
        order_id,
        count(*)      as line_item_count,
        sum(quantity) as total_quantity
    from {{ ref('stg_shopify__order_line_items') }}
    group by order_id
),

-- Row_number within each customer's orders to detect first purchase.
-- Partition only over non-null customers; anonymous orders excluded.
order_rank as (
    select
        order_id,
        row_number() over (
            partition by shopify_customer_id
            order by order_date asc, order_timestamp asc
        ) as order_rank
    from orders
    where shopify_customer_id is not null
)

select
    o.order_id,
    coalesce(li.line_item_count, 0)    as line_item_count,
    coalesce(li.total_quantity,  0)    as total_quantity,
    -- coalesce with false for anonymous orders where order_rank is NULL
    coalesce(r.order_rank = 1,  false) as is_first_order,
    coalesce(r.order_rank > 1,  false) as is_repeat_order
from orders o
left join line_item_agg li on o.order_id = li.order_id
left join order_rank     r  on o.order_id  = r.order_id
