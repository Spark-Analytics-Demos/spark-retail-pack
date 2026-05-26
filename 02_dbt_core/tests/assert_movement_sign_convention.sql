-- Business rule: sale movements must have negative quantity_change (stock decreases
-- on sale) and return movements must have positive quantity_change (stock increases
-- on return). Returns movement_ids that violate the sign convention.
select movement_id, movement_type, quantity_change
from {{ ref('fact_inventory_movements') }}
where
    (movement_type = 'sale'   and quantity_change >= 0)
    or (movement_type = 'return' and quantity_change <= 0)
