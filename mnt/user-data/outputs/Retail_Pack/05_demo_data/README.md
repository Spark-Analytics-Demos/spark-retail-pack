# Demo Data

> **Status:** Not yet developed. Awaiting Section 9 of the design document.

This folder will hold the synthetic data generators and pre-built demo datasets used for client demos, internal testing, and the public demo environment.

## What will go here

- `generators/` — Python scripts that produce realistic synthetic data
- `datasets/` — pre-generated CSV/JSON files in the source-system formats (Shopify export shape, Stripe export shape, etc.)
- `scenarios/` — story-arc definitions (fraud spike, seasonal demand, inventory shortage, customer churn cohort)
- `loaders/` — scripts to load demo data into Snowflake bronze tables
- `docs/` — narrative descriptions of each scenario for sales use

## Design principles

- **Realistic, not random.** Demo data must tell a coherent business story. Random data is forgettable.
- **One company, 12 months.** v1 ships with a single fictional retailer ("Northwind Co.") with 12 months of activity.
- **Multiple scales.** Small (1K orders), Medium (50K orders), Large (500K orders) variants for different demo contexts.

## Reference

See `../01_design_docs/09_demo_data.md` (pending) for the full design.
