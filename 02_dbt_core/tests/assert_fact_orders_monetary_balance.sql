-- Monetary integrity check: net_amount should equal
-- gross_amount - discount_amount + tax_amount + shipping_amount + tip_amount.
-- FX conversion is applied uniformly so the relationship holds after conversion.
-- A discrepancy > $1.00 indicates a staging mapping error (wrong column mapped).
-- Returns order_ids where the imbalance exceeds the $1.00 tolerance.
select
    order_id,
    net_amount,
    gross_amount - discount_amount + tax_amount + shipping_amount + tip_amount as computed_net,
    abs(net_amount - (gross_amount - discount_amount + tax_amount + shipping_amount + tip_amount)) as discrepancy
from {{ ref('fact_orders') }}
where abs(net_amount - (gross_amount - discount_amount + tax_amount + shipping_amount + tip_amount)) > 1.0
