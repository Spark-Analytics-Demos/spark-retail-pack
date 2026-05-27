"""
Generate Shopify product catalog tables.

Produces:
  shopify/products.csv
  shopify/product_variants.csv
  shopify/inventory_items.csv
  shopify/inventory_levels.csv  (initial stock snapshot)
  shopify/locations.csv
"""

import pandas as pd
import numpy as np
import math
import re
from datetime import datetime, timezone


def _make_handle(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def generate_products(rng: np.random.Generator, cfg: dict, catalog: dict, company: dict) -> dict:
    """
    Returns dict with DataFrames: products, product_variants, inventory_items,
    inventory_levels, locations.
    """
    sku_count_target = cfg["sku_count"]
    categories = catalog["categories"]
    special_skus = catalog["special_skus"]
    resort_wear_cfg = catalog["resort_wear"]
    locations = company["shopify"]["locations"]
    store_launch = datetime(2022, 6, 1, tzinfo=timezone.utc)
    sync_ts = datetime(2026, 12, 31, 23, 59, 0, tzinfo=timezone.utc)

    total_design_skus = sum(c["sku_count"] for c in categories)
    scale = sku_count_target / total_design_skus

    products_rows = []
    variants_rows = []
    inv_items_rows = []
    inv_levels_rows = []

    product_id = 1000010   # starts at 10; 1–2 reserved for special SKUs
    variant_id = 2000010
    inventory_item_id = 3000010

    location_id = locations[0]["id"]

    # Inject special SKUs first
    for sp in special_skus:
        pid = int(sp["product_id"])
        vid = int(sp["variant_id"])
        iid = int(sp["inventory_item_id"])
        sku = sp["sku"]
        name = sp["name"]
        handle = _make_handle(name)
        created_ts = datetime(2022, 9, 1, tzinfo=timezone.utc)
        updated_ts = datetime(2026, 1, 1, tzinfo=timezone.utc)

        products_rows.append({
            "id": pid,
            "title": name,
            "handle": handle,
            "product_type": sp["product_type"],
            "vendor": "Northwind Co.",
            "status": "active",
            "published_at": created_ts.isoformat(),
            "image_url": f"https://cdn.northwindco.com/products/{handle}.jpg",
            "tags": f"{sp['category'].lower()},{sp['subcategory'].lower()}",
            "body_html": f"<p>The {name} — a Northwind staple.</p>",
            "created_at": created_ts.isoformat(),
            "updated_at": updated_ts.isoformat(),
        })
        variants_rows.append({
            "id": vid,
            "product_id": pid,
            "title": f"{sp['size']} / {sp['color']}",
            "sku": sku,
            "price": sp["price"],
            "compare_at_price": None,
            "option1": sp["size"],
            "option2": sp["color"],
            "option3": None,
            "inventory_item_id": iid,
            "inventory_quantity": 47,
            "requires_shipping": True,
            "taxable": True,
            "barcode": f"NW{pid}{vid}",
            "weight": 0.6,
            "weight_unit": "kg",
            "created_at": created_ts.isoformat(),
            "updated_at": updated_ts.isoformat(),
        })
        inv_items_rows.append({
            "id": iid,
            "sku": sku,
            "cost": sp["cost"],
            "tracked": True,
            "country_code_of_origin": "PT",
            "created_at": created_ts.isoformat(),
            "updated_at": updated_ts.isoformat(),
        })
        inv_levels_rows.append({
            "inventory_item_id": iid,
            "location_id": location_id,
            "available": 47,
            "updated_at": updated_ts.isoformat(),
        })

    # Resort Wear line (18 SKUs) — Story 5
    rw = resort_wear_cfg
    rw_launch_ts = datetime(2026, 3, 1, tzinfo=timezone.utc)
    for i in range(rw["sku_count"]):
        pid = product_id; product_id += 1
        vid = variant_id; variant_id += 1
        iid = inventory_item_id; inventory_item_id += 1
        price = float(rng.uniform(rw["price_min"], rw["price_max"]))
        price = round(math.floor(price * 100) / 100, 2)
        cost = round(price * 0.40, 2)
        name = f"Resort {['Linen Shirt', 'Swim Short', 'Cover-Up Dress', 'Sun Hat', 'Sandal Slide',\
 'Wrap Skirt', 'Tank Top', 'Midi Dress', 'Pool Tee', 'Crochet Bag',\
 'Raffia Hat', 'Terry Short', 'Breezy Blouse', 'Sarong Wrap', 'Palazzo Pant',\
 'Espadrille', 'Bikini Top', 'Beach Towel'][i % 18]}"
        sku = f"RW-{i+1:03d}"
        handle = _make_handle(name) + f"-{i+1}"
        updated_ts = datetime(2026, 3, 1, tzinfo=timezone.utc)

        products_rows.append({
            "id": pid, "title": name, "handle": handle,
            "product_type": rw["product_type"], "vendor": "Northwind Co.",
            "status": "active", "published_at": rw_launch_ts.isoformat(),
            "image_url": f"https://cdn.northwindco.com/products/{handle}.jpg",
            "tags": "resort-wear,limited,spring-2026",
            "body_html": f"<p>{name} — part of the Northwind Resort Wear capsule collection.</p>",
            "created_at": rw_launch_ts.isoformat(), "updated_at": updated_ts.isoformat(),
        })
        size = ["XS", "S", "M", "L", "XL"][i % 5]
        color = ["White", "Sand", "Terracotta", "Sage", "Navy"][i % 5]
        variants_rows.append({
            "id": vid, "product_id": pid, "title": f"{size} / {color}", "sku": sku,
            "price": price, "compare_at_price": None, "option1": size, "option2": color,
            "option3": None, "inventory_item_id": iid, "inventory_quantity": 80,
            "requires_shipping": True, "taxable": True, "barcode": f"NW{pid}{vid}",
            "weight": 0.4, "weight_unit": "kg",
            "created_at": rw_launch_ts.isoformat(), "updated_at": updated_ts.isoformat(),
        })
        inv_items_rows.append({
            "id": iid, "sku": sku, "cost": cost, "tracked": True,
            "country_code_of_origin": "PT", "created_at": rw_launch_ts.isoformat(),
            "updated_at": updated_ts.isoformat(),
        })
        inv_levels_rows.append({
            "inventory_item_id": iid, "location_id": location_id,
            "available": 80, "updated_at": updated_ts.isoformat(),
        })

    # Regular catalog products
    for cat in categories:
        cat_sku_count = max(1, round(cat["sku_count"] * scale))
        adj_list = cat["adjectives"]
        sizes = cat["variants"]["sizes"]
        colors = cat["variants"]["colors"]
        prefix = cat["sku_prefix"]
        cat_name = cat["category"]
        sub_name = cat["subcategory"]
        prod_type = cat["product_type"]
        price_min = cat["price_min"]
        price_max = cat["price_max"]
        cost_margin = cat["cost_margin"]

        for j in range(cat_sku_count):
            pid = product_id; product_id += 1
            adj = adj_list[j % len(adj_list)]
            name = f"{adj} {sub_name.rstrip('s')}"
            if j > 0:
                name = f"{adj} {sub_name.rstrip('s')} {j+1}"
            handle = _make_handle(name)

            # Stagger creation dates over the store's history
            days_offset = int(rng.integers(0, 365 * 3))
            created_ts = store_launch.replace(tzinfo=timezone.utc)
            created_ts = datetime(
                created_ts.year + days_offset // 365,
                ((created_ts.month - 1 + days_offset // 30) % 12) + 1,
                max(1, days_offset % 28),
                tzinfo=timezone.utc,
            )
            # Clamp to store_launch .. 2025-12-01
            created_ts = max(created_ts, store_launch.replace(tzinfo=timezone.utc))

            products_rows.append({
                "id": pid,
                "title": name,
                "handle": handle,
                "product_type": prod_type,
                "vendor": "Northwind Co.",
                "status": "active",
                "published_at": created_ts.isoformat(),
                "image_url": f"https://cdn.northwindco.com/products/{handle}.jpg",
                "tags": f"{cat_name.lower()},{sub_name.lower().replace(' ', '-')}",
                "body_html": f"<p>The {name} by Northwind Co.</p>",
                "created_at": created_ts.isoformat(),
                "updated_at": sync_ts.isoformat(),
            })

            # Generate 1–4 variants (size × color combos, capped)
            if len(sizes) <= 1:
                n_sizes = len(sizes)
            else:
                n_sizes = min(len(sizes), int(rng.integers(1, len(sizes) + 1)))
            n_colors = min(len(colors), int(rng.integers(1, min(3, len(colors)) + 1)))
            chosen_sizes = sizes[:n_sizes]
            chosen_colors = list(rng.choice(colors, size=n_colors, replace=False))

            for size in chosen_sizes:
                for color in chosen_colors:
                    vid = variant_id; variant_id += 1
                    iid = inventory_item_id; inventory_item_id += 1

                    price = float(rng.uniform(price_min, price_max))
                    price = round(math.floor(price * 100) / 100, 2)
                    cost = round(price * cost_margin, 2)
                    sku = f"{prefix}-{pid % 10000:04d}-{size[:3].upper()}-{color[:3].upper()}"
                    init_qty = int(rng.integers(20, 200))

                    variants_rows.append({
                        "id": vid,
                        "product_id": pid,
                        "title": f"{size} / {color}",
                        "sku": sku,
                        "price": price,
                        "compare_at_price": None,
                        "option1": size,
                        "option2": color,
                        "option3": None,
                        "inventory_item_id": iid,
                        "inventory_quantity": init_qty,
                        "requires_shipping": True,
                        "taxable": True,
                        "barcode": f"NW{pid}{vid}",
                        "weight": round(float(rng.uniform(0.2, 1.5)), 2),
                        "weight_unit": "kg",
                        "created_at": created_ts.isoformat(),
                        "updated_at": sync_ts.isoformat(),
                    })
                    inv_items_rows.append({
                        "id": iid,
                        "sku": sku,
                        "cost": cost,
                        "tracked": True,
                        "country_code_of_origin": str(rng.choice(["CN", "PT", "IN", "BD", "VN"])),
                        "created_at": created_ts.isoformat(),
                        "updated_at": sync_ts.isoformat(),
                    })
                    inv_levels_rows.append({
                        "inventory_item_id": iid,
                        "location_id": location_id,
                        "available": init_qty,
                        "updated_at": sync_ts.isoformat(),
                    })

    # Locations table
    location_rows = []
    for loc in locations:
        location_rows.append({
            "id": loc["id"],
            "name": loc["name"],
            "active": loc["active"],
            "address1": loc["address1"],
            "city": loc["city"],
            "province": loc["province"],
            "province_code": loc["province_code"],
            "country_code": loc["country_code"],
            "zip": loc["zip"],
            "phone": loc["phone"],
            "updated_at": sync_ts.isoformat(),
        })

    return {
        "products": pd.DataFrame(products_rows),
        "product_variants": pd.DataFrame(variants_rows),
        "inventory_items": pd.DataFrame(inv_items_rows),
        "inventory_levels": pd.DataFrame(inv_levels_rows),
        "locations": pd.DataFrame(location_rows),
    }
