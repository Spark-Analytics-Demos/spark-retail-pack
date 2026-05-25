"""
Spark Retail Pack — Snowflake Provisioning Runner
==================================================
Executes the SQL setup scripts in order against your Snowflake account.

Usage (from your terminal):
    python setup/snowflake/run_provisioning.py

Required environment variables (copy .env.example → .env and fill in):
    SF_ACCOUNT        Snowflake account identifier (e.g. myorg-myaccount)
    SF_ADMIN_USER     Admin username with ACCOUNTADMIN role
    SF_ADMIN_PASSWORD Admin password

The script stops on the first error. Fix it, then re-run — every statement
uses CREATE IF NOT EXISTS / GRANT so re-runs are safe.
"""

import os
import sys
from pathlib import Path
import snowflake.connector

ROLE = "ACCOUNTADMIN"

SCRIPTS = [
    "01_databases_and_schemas.sql",
    "02_warehouses.sql",
    "03_roles.sql",
    "04_grants.sql",
    "06_resource_monitors.sql",
    # 05_service_accounts.sql excluded: replace <REPLACE_WITH_STRONG_PASSWORD>
    # placeholders first, then run it manually in Snowsight.
]

SCRIPT_DIR = Path(__file__).parent


def get_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        print(f"ERROR: required environment variable {name!r} is not set.")
        print("  Copy .env.example to .env, fill in your values, then run:")
        print("  $env:SF_ACCOUNT='...'; $env:SF_ADMIN_USER='...'; $env:SF_ADMIN_PASSWORD='...'")
        sys.exit(1)
    return value


def split_statements(sql: str) -> list[str]:
    """Split a SQL file into individual statements, stripping comment-only lines."""
    statements = []
    current: list[str] = []
    for line in sql.splitlines():
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        current.append(line)
        if stripped.endswith(";"):
            stmt = "\n".join(current).strip().rstrip(";").strip()
            if stmt:
                statements.append(stmt)
            current = []
    return statements


def run():
    account  = get_env("SF_ACCOUNT")
    user     = get_env("SF_ADMIN_USER")
    password = get_env("SF_ADMIN_PASSWORD")

    print(f"Connecting to Snowflake account {account} as {user} ({ROLE})...")
    conn = snowflake.connector.connect(
        account=account,
        user=user,
        password=password,
        role=ROLE,
    )
    cur = conn.cursor()

    cur.execute("SELECT CURRENT_ACCOUNT(), CURRENT_USER(), CURRENT_ROLE(), CURRENT_REGION()")
    row = cur.fetchone()
    print(f"  Account : {row[0]}")
    print(f"  User    : {row[1]}")
    print(f"  Role    : {row[2]}")
    print(f"  Region  : {row[3]}")
    print()

    for script_name in SCRIPTS:
        script_path = SCRIPT_DIR / script_name
        print(f"Running {script_name} ...")
        sql = script_path.read_text(encoding="utf-8")
        statements = split_statements(sql)
        for i, stmt in enumerate(statements, 1):
            try:
                cur.execute(stmt)
                status = cur.fetchone()
                msg = status[0] if status else "OK"
                print(f"  [{i}/{len(statements)}] {msg}")
            except snowflake.connector.errors.ProgrammingError as e:
                print(f"  [{i}/{len(statements)}] ERROR: {e}")
                print(f"  Failed statement:\n    {stmt[:200]}")
                cur.close()
                conn.close()
                sys.exit(1)
        print(f"  {script_name} complete ({len(statements)} statements)\n")

    cur.close()
    conn.close()
    print("=" * 60)
    print("Provisioning complete.")
    print()
    print("Next: edit 05_service_accounts.sql, replace the")
    print("<REPLACE_WITH_STRONG_PASSWORD> placeholders, run it")
    print("manually in Snowsight, then tick off PHASE_0_CHECKLIST §0.2.")


if __name__ == "__main__":
    run()
