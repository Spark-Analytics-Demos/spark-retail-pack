# Power BI Dashboard Packs

> **Status:** Not yet developed. Awaiting Section 10 of the design document.

This folder will hold the Power BI dashboard pack files that ship with the proprietary version of the Spark Retail Pack.

## Planned dashboards (v1)

1. **Executive Summary** — top-line KPIs for leadership (revenue, growth, customer metrics, cash)
2. **Customer 360** — segmentation, behavior, lifetime value, churn risk
3. **Inventory Health** — stock levels, turnover, stockouts, sell-through

## What will go here

- `executive/SparkRetail_Executive.pbix`
- `customer_360/SparkRetail_Customer360.pbix`
- `inventory_health/SparkRetail_InventoryHealth.pbix`
- `themes/` — shared Power BI theme files (colors, fonts) for consistent branding
- `templates/` — reusable visual templates
- `docs/` — installation instructions, data source configuration, screenshots

## Distribution

Power BI files (`.pbix`) ship as part of the **proprietary** license. They will not be in the open-source repo.

## Connection

Dashboards connect to Snowflake via the Power BI Snowflake connector, using the `RETAIL_BI_READER` role defined in `../01_design_docs/02_architecture.md` Section 2.5.
