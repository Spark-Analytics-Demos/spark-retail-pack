# Snowflake Provisioning Scripts

Provisions the Spark Retail Pack Snowflake environment from scratch.
Run once per account. Re-runs are safe — all statements use `IF NOT EXISTS`.

## Prerequisites

- Snowflake account in **AWS us-west-2** (locked in `PHASE_0_DECISIONS.md`)
- A user with `ACCOUNTADMIN` role
- Python with `snowflake-connector-python` installed (`pip install snowflake-connector-python`)

## Execution order

| Script | What it does |
|---|---|
| `01_databases_and_schemas.sql` | 4 databases, 11 schemas per environment |
| `02_warehouses.sql` | 4 compute warehouses with auto-suspend |
| `03_roles.sql` | 7 custom roles + hierarchy |
| `04_grants.sql` | All privilege grants (warehouse, database, schema, future) |
| `05_service_accounts.sql` | 3 service account users — **edit passwords first** |
| `06_resource_monitors.sql` | Monthly credit caps per warehouse |

## Automated run (scripts 01–04, 06)

Set your admin password as an environment variable, then run:

```powershell
$env:SF_ADMIN_PASSWORD = "your-password"
python setup/snowflake/run_provisioning.py
```

Or from the Claude Code terminal:
```
! python setup/snowflake/run_provisioning.py
```

## Service accounts (script 05 — manual)

`05_service_accounts.sql` is excluded from the automated runner because it
contains password placeholders. Before running it:

1. Open `05_service_accounts.sql`
2. Replace each `<REPLACE_WITH_STRONG_PASSWORD>` with a strong generated password
3. Run it in Snowsight or via `snowsql`
4. Store the credentials in your secrets manager (AWS Secrets Manager / Azure Key Vault)
5. **Never commit the passwords to this repo**

## Design notes

**Schema naming.** Checklist §0.2 refers to BRONZE/SILVER/GOLD as layer labels.
Actual Snowflake schema names follow `dbt_project.yml`:
- Bronze layer → schemas in `RAW_RETAIL` (one per source connector)
- Silver layer → `STAGING` schema in analytics databases
- Gold layer → `GOLD` schema in analytics databases

**Warehouse naming.** Section 2.5 uses `WH_LOADING`; checklist uses `WH_LOAD`.
Scripts use `WH_LOAD` (consistent with `profiles.yml.template`).
Section 2.5 `WH_ADHOC` is included — `RETAIL_ANALYST` needs it.

**Schema generation in dbt.** The `generate_schema_name` macro in
`02_dbt_core/macros/` controls how dbt names schemas:
- `prod` / `staging` targets → clean names (`GOLD`, `MART_SALES`, etc.)
- `dev` / `ci` targets → prefixed (`dev_denis_gold`, `ci_42_mart_sales`)

## After provisioning

Check off all items in `PHASE_0_CHECKLIST.md §0.2`, then proceed to §0.3
(dbt project scaffold — already done) and §0.4 (CI/CD pipeline).
