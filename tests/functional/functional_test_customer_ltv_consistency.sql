/*
  FUNCTIONAL TEST: functional_test_customer_ltv_consistency
  TESTS AGAINST: dim_customers vs fct_orders (live data)

  RULES:
    1. A customer with 0 total_orders must have lifetime_value = 0
    2. A CHAMPION customer must have lifetime_value >= 5000
    3. No customer can have a negative return rate

  ⏱ MANUAL EFFORT ESTIMATE: ~1 hour (multiple rules, complex joins)
*/

{{ config(tags=['functional_test', 'customer', 'data_quality']) }}

WITH violations AS (

    -- Rule 1: Zero orders → zero LTV
    SELECT
        customer_id,
        ltv_segment,
        total_orders,
        lifetime_value,
        return_rate_pct,
        'RULE 1: Customer with 0 orders must have lifetime_value = 0' AS violation_msg
    FROM {{ ref('dim_customers') }}
    WHERE total_orders = 0 AND lifetime_value != 0

    UNION ALL

    -- Rule 2: CHAMPION tier requires LTV >= 5000
    SELECT
        customer_id,
        ltv_segment,
        total_orders,
        lifetime_value,
        return_rate_pct,
        'RULE 2: CHAMPION customers must have lifetime_value >= 5000'
    FROM {{ ref('dim_customers') }}
    WHERE ltv_segment = 'CHAMPION' AND lifetime_value < 5000

    UNION ALL

    -- Rule 3: Return rate cannot be negative
    SELECT
        customer_id,
        ltv_segment,
        total_orders,
        lifetime_value,
        return_rate_pct,
        'RULE 3: Return rate cannot be negative'
    FROM {{ ref('dim_customers') }}
    WHERE return_rate_pct < 0

    UNION ALL

    -- Rule 4: dim_customers.lifetime_value must match SUM from fct_orders
    SELECT
        dc.customer_id,
        dc.ltv_segment,
        dc.total_orders,
        dc.lifetime_value,
        dc.return_rate_pct,
        'RULE 4: lifetime_value in dim_customers must match sum of recognized_revenue in fct_orders'
    FROM {{ ref('dim_customers') }} dc
    LEFT JOIN (
        SELECT customer_id, SUM(recognized_revenue) AS total_recognized
        FROM {{ ref('fct_orders') }}
        GROUP BY 1
    ) fo USING (customer_id)
    WHERE ABS(dc.lifetime_value - COALESCE(fo.total_recognized, 0)) > 0.01

)

SELECT * FROM violations
