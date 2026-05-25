/*
  FUNCTIONAL TEST: functional_test_order_item_totals
  TESTS AGAINST: fct_orders vs stg_order_items (live data)

  RULE:
    order_gross_amount in fct_orders must equal the SUM of
    gross_amount from stg_order_items for the same order_id.

    Tolerance: ±$0.01 for floating point rounding.

  ⏱ MANUAL EFFORT ESTIMATE: ~1 hour (cross-model join logic)
*/

{{ config(tags=['functional_test', 'revenue', 'referential_integrity']) }}

WITH item_totals AS (

    SELECT
        order_id,
        SUM(gross_amount)   AS sum_gross_amount,
        SUM(net_amount)     AS sum_net_amount
    FROM {{ ref('stg_order_items') }}
    GROUP BY 1

),

order_totals AS (

    SELECT
        order_id,
        order_gross_amount,
        order_net_amount
    FROM {{ ref('fct_orders') }}

),

mismatches AS (

    SELECT
        o.order_id,
        i.sum_gross_amount           AS expected_gross,
        o.order_gross_amount         AS actual_gross,
        ABS(i.sum_gross_amount - o.order_gross_amount) AS gross_diff,
        i.sum_net_amount             AS expected_net,
        o.order_net_amount           AS actual_net,
        ABS(i.sum_net_amount - o.order_net_amount) AS net_diff
    FROM order_totals o
    INNER JOIN item_totals i USING (order_id)
    WHERE
        ABS(i.sum_gross_amount - o.order_gross_amount) > 0.01
        OR ABS(i.sum_net_amount - o.order_net_amount) > 0.01

)

SELECT
    *,
    'RULE: fct_orders amounts must match sum of stg_order_items' AS violation_msg
FROM mismatches
