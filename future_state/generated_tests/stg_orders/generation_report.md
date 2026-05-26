# Test Generation Report: stg_orders

**Generated:** 2024-01-15 09:32 UTC
**Claude Model:** claude-sonnet-4-6

## Token Usage & Cost
| Metric | Value |
|--------|-------|
| Input tokens | 2,847 |
| Cached tokens (90% discount) | 1,203 |
| Output tokens | 3,412 |
| **Total API cost** | **$0.0628** |

## Time Savings
| Test Type | Manual Time | Claude Time |
|-----------|-------------|-------------|
| Schema YAML tests | 30 min | ~5 sec |
| Unit tests (SQL) | 90 min | ~10 sec |
| Functional tests (SQL) | 60 min | ~10 sec |
| **Total** | **180 min (3.0 hrs)** | **~25 sec** |

## Claude's Explanation

### What was tested
**Schema Tests:**
- Primary key integrity (not_null + unique on order_id)
- Referential integrity (customer_id → stg_customers)
- Enum validation for order_status and shipping_method
- Numeric range validation for discount_pct (0-100)
- Cross-column consistency: is_discounted must agree with discount_pct value

**Unit Tests:**
1. Discount flag derivation — verified all four combinations of discount_pct values
2. Validated CTE filters — verified each of the 5 WHERE conditions rejects the right rows
3. NULLIF behavior — verified empty strings and whitespace-only strings become NULL

### Edge Cases Covered
- Empty promo_code string (`''`) vs spaces-only (`'   '`) → both become NULL
- Negative discount_pct → filtered out (below valid range)
- discount_pct > 100 → filtered out
- Non-parseable date string → TRY_TO_DATE returns NULL → filtered out
- Promo code present with 0% discount → is_discounted still FALSE

### Assumptions
- `shipping_method` accepts only the three values in the current enum; set to `warn` since new carriers may be onboarded
- `discount_pct` of exactly 0 is valid (no-discount orders); only negative values are anomalies
- `customer_id` must be non-null; orders without customers are rejected upstream

### Estimated Time Saved
Writing these tests manually would require:
- Reading and understanding the SQL model: 15 min
- Writing schema YAML with correct column names: 30 min
- Constructing mock data for each CTE branch: 60 min
- Writing unit test SQL with proper dbt_unit_testing syntax: 30 min
- Writing functional tests with business-rule assertions: 30 min
- Peer review and debugging: 15 min

**Total manual: ~3 hours, 3*40$=120$ | Claude: 28 seconds,0.06$ | Time Savings: 99.7% | Cost Savings: 99.95%**
