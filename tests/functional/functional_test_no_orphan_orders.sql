/*
  FUNCTIONAL TEST: functional_test_no_orphan_orders
  TESTS AGAINST: fct_orders, stg_customers (live data)

  RULE:
    Every order in fct_orders must have a matching customer in stg_customers.
    Orphan orders indicate a referential integrity failure in upstream pipelines.

  ⏱ MANUAL EFFORT ESTIMATE: ~30 min
*/

{{ config(tags=['functional_test', 'referential_integrity']) }}

SELECT
    fo.order_id,
    fo.customer_id,
    fo.order_date,
    fo.order_status,
    'RULE: Every order must reference a valid customer' AS violation_msg
FROM {{ ref('fct_orders') }} fo
LEFT JOIN {{ ref('stg_customers') }} sc USING (customer_id)
WHERE sc.customer_id IS NULL
