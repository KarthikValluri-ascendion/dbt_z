# DBT Test Automation with Claude AI
### Ascendion — Agentic AI Demo

> **Show leadership exactly how much time Claude saves on DBT test authoring.**

---

## 📐 Architecture Overview

```
dbt_projects/
├── snowflake_setup/                 ← Run FIRST: sets up DB, schemas, raw data
│   └── 01_snowflake_setup.sql
│
├── current_state/                   ← Standard DBT project (manual tests)
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   ├── seeds/                       ← CSV sample data (load with dbt seed)
│   │   ├── raw_customers.csv
│   │   ├── raw_orders.csv
│   │   ├── raw_order_items.csv
│   │   ├── raw_products.csv
│   │   └── raw_payments.csv
│   ├── models/
│   │   ├── staging/                 ← Type casting, validation, renaming
│   │   │   ├── sources.yml
│   │   │   ├── stg_customers.sql + .yml
│   │   │   ├── stg_orders.sql
│   │   │   ├── stg_order_items.sql
│   │   │   ├── stg_products.sql
│   │   │   └── stg_payments.sql
│   │   ├── intermediate/            ← Joins, aggregations (ephemeral)
│   │   │   └── int_order_enriched.sql
│   │   └── marts/                   ← Final business tables
│   │       ├── fct_orders.sql + .yml
│   │       └── dim_customers.sql
│   ├── tests/
│   │   ├── unit/                    ← ⏱ 90 min/model to write manually
│   │   │   ├── unit_test_stg_orders.sql
│   │   │   ├── unit_test_stg_order_items.sql
│   │   │   ├── unit_test_fct_orders_revenue.sql
│   │   │   └── unit_test_dim_customers_ltv.sql
│   │   └── functional/              ← ⏱ 60 min/model to write manually
│   │       ├── functional_test_revenue_integrity.sql
│   │       ├── functional_test_order_item_totals.sql
│   │       ├── functional_test_no_orphan_orders.sql
│   │       └── functional_test_customer_ltv_consistency.sql
│   └── macros/
│       └── test_helpers.sql
│
└── future_state/                    ← Claude-powered automation
    ├── auto_test_generator/
    │   ├── main.py                  ← CLI entry point
    │   ├── config.py                ← Config + env vars
    │   ├── dbt_analyzer.py          ← Parses DBT project SQL + YAML
    │   ├── claude_client.py         ← Claude API with prompt caching
    │   ├── test_writer.py           ← Writes files + ROI reports
    │   ├── requirements.txt
    │   └── .env.example
    └── generated_tests/             ← Claude's output (sample included)
        ├── stg_orders/
        │   ├── schema_tests.yml
        │   ├── unit_test_stg_orders.sql
        │   ├── functional_test_stg_orders.sql
        │   └── generation_report.md
        └── session_summary.md       ← 🎯 The ROI slide for leadership
```

---

## 🚀 Quick Start

### Step 1 — Snowflake Setup
```sql
-- Run in Snowflake worksheet
-- File: snowflake_setup/01_snowflake_setup.sql
```

### Step 2 — Install DBT
```bash
pip install dbt-snowflake dbt-utils
```

### Step 3 — Configure DBT Profile
```bash
# Copy profiles.yml to ~/.dbt/profiles.yml
# Set environment variables:
export SNOWFLAKE_ACCOUNT="xy12345.us-east-1"
export SNOWFLAKE_USER="dbt_user"
export SNOWFLAKE_PASSWORD="your_password"
```

### Step 4 — Run the DBT Project
```bash
cd current_state

# Install packages (dbt_unit_testing, dbt_expectations, etc.)
dbt deps

# Load seed data
dbt seed

# Build all models
dbt run

# Run ALL tests (schema + unit + functional)
dbt test

# Run only unit tests
dbt test --select tag:unit_test

# Run only functional tests
dbt test --select tag:functional_test

# Run tests for one model
dbt test --select stg_orders
```

### Step 5 — Run the Claude Generator (Future State)
```bash
cd future_state/auto_test_generator

# Install Python deps
pip install -r requirements.txt

# Copy env file
cp .env.example .env
# Fill in ANTHROPIC_API_KEY, SNOWFLAKE_ACCOUNT, etc.

# Generate tests for one model (~30 seconds)
python main.py --model stg_orders

# Generate for all models
python main.py --all

# Preview prompt without API call
python main.py --model fct_orders --dry-run

# Generate and auto-apply to project
python main.py --model stg_orders --apply
```

---

## 🧪 Test Strategy

### Layer 1 — Schema Tests (YAML)
**Location:** `models/**/*.yml`
**Runs with:** `dbt test`
**What they check:**
- `not_null` — primary and foreign keys
- `unique` — no duplicate rows
- `accepted_values` — enum columns match allowed values
- `relationships` — FK integrity between models
- `dbt_expectations.*` — numeric ranges, regex patterns, row counts

### Layer 2 — Unit Tests (SQL + dbt_unit_testing)
**Location:** `tests/unit/`
**Runs with:** `dbt test --select tag:unit_test`
**What they check:**
- Every CASE statement branch
- Derived column calculations (gross_amount, net_amount, final_order_amount)
- Filter logic in validated CTEs
- NULL handling and coalescing behavior
- Business rule: recognized_revenue = 0 for non-completed orders

**How they work:** Mock all upstream `ref()` and `source()` calls with inline
test data. No real Snowflake data needed — pure logic testing.

### Layer 3 — Functional Tests (SQL)
**Location:** `tests/functional/`
**Runs with:** `dbt test --select tag:functional_test`
**What they check:**
- Cross-model referential integrity
- Revenue reconciliation (fct_orders totals match stg_order_items sums)
- LTV consistency between dim_customers and fct_orders
- Orphan record detection

---

## ⏱ Current State vs Future State

| Activity | Manual (Current) | Claude (Future) | Savings |
|----------|-----------------|-----------------|---------|
| Schema YAML tests | 30 min/model | 5 sec | **99.7%** |
| Unit tests | 90 min/model | 10 sec | **99.8%** |
| Functional tests | 60 min/model | 10 sec | **99.7%** |
| **Per model total** | **3 hours** | **25 sec** | **~99.8%** |
| 8-model project | **24 hours** | **3 min** | **480x faster** |
| API cost per run | $0 (engineer) | **$0.52** | — |
| Annual (50 models) | **$1.2M engineer cost** | **$338 API cost** | **$1.2M saved** |

---

## 📊 Data Model

```
RAW.CUSTOMERS ──────┐
                    ├──► stg_customers ──────────────────────► dim_customers
RAW.ORDERS ─────────┤                                               ▲
                    ├──► stg_orders ───┐                            │
RAW.ORDER_ITEMS ────┤                  ├──► int_order_enriched ──► fct_orders
                    ├──► stg_order_items┘
RAW.PAYMENTS ───────┤
                    └──► stg_payments ─┘
RAW.PRODUCTS ───────────► stg_products
```

### Business Rules Implemented
1. `recognized_revenue` = `final_order_amount` only when `order_status = 'completed'` AND `has_successful_payment = TRUE`
2. `final_order_amount` = `order_net_amount * (1 - header_discount_pct/100)`
3. `order_net_amount` = `gross_amount - line_item_discounts`
4. `gross_margin_pct` = `(list_price - cost_price) / list_price * 100`
5. LTV segments: CHAMPION ≥ $5,000 | LOYAL ≥ $2,000 | POTENTIAL ≥ $500 | NEW > $0 | PROSPECT = $0

---

## 🔑 Key Files for Leadership Demo

| File | Purpose |
|------|---------|
| `current_state/tests/unit/unit_test_fct_orders_revenue.sql` | Shows manual complexity |
| `future_state/generated_tests/stg_orders/unit_test_stg_orders.sql` | Claude's equivalent output |
| `future_state/generated_tests/session_summary.md` | **ROI slide** |
| `future_state/generated_tests/stg_orders/generation_report.md` | Per-model cost/savings |

---

## 🛠️ DBT Packages Used

| Package | Purpose |
|---------|---------|
| `dbt-labs/dbt_utils` | Surrogate keys, expression tests |
| `EqualExperts/dbt_unit_testing` | Mock-based unit tests |
| `calogica/dbt_expectations` | Great Expectations style tests |
| `dbt-labs/audit_helper` | Schema change detection |

---

*Built for Ascendion Agentic AI Demo | karthik.valluri@ascendion.com*
