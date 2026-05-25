# Governance

> **Status:** Not yet developed. Awaiting Section 8 of the design document.

This folder will hold governance artifacts that ship with the Spark Retail Pack: data ownership definitions, classification rules, PII inventory, and lineage scaffolding.

## What will go here

- `ownership.yml` — domain ownership matrix (who owns Sales, Customer, Inventory, etc.)
- `classification.yml` — column-level data classification (Public, Internal, Confidential, Restricted, PII)
- `pii_inventory.md` — full list of fields containing personally identifiable information
- `data_quality_rules.yml` — DQ rules beyond what dbt tests cover
- `retention_policies.yml` — how long each data type is kept and where
- `access_matrix.md` — which role sees which data

## Why governance ships with the pack

For enterprise and mid-market clients, "governance" is a question they will ask in week 1. Shipping a working baseline — even if generic — removes a major adoption blocker. Clients customize from there rather than starting from zero.

## Reference

See `../01_design_docs/08_governance.md` (pending) for the full design.
