/*
  FUNCTIONAL TEST: functional_test_revenue_integrity
  TESTS AGAINST: fct_orders (live Snowflake data)

  RULE:
    recognized_revenue must ALWAYS be 0 for non-completed orders.
    Any row returned by this query = TEST FAILURE.

  HOW TO RUN:
    dbt test --select functional_test_revenue_integrity

  ⏱ MANUAL EFFORT ESTIMATE: ~45 min to write + 30 min to verify against data
*/

{{ config(tags=['functional_test', 'revenue', 'data_quality']) }}

-- This query returns rows that VIOLATE the business rule.
-- dbt passes the test only when 0 rows are returned.

SELECT
    order_id,
    order_status,
    has_successful_payment,
    recognized_revenue,
    'RULE: Non-completed or unpaid orders must have recognized_revenue = 0' AS violation_msg
FROM {{ ref('fct_orders') }}
WHERE
    recognized_revenue > 0
    AND (
        order_status  != 'completed'
        OR has_successful_payment = FALSE
    )
