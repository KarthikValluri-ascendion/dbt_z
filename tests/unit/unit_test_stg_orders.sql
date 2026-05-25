/*
  UNIT TEST: unit_test_stg_orders
  MODEL UNDER TEST: stg_orders

  PURPOSE:
    Verify that stg_orders correctly:
      1. Casts discount_pct from string to numeric
      2. Sets is_discounted = TRUE when discount_pct > 0
      3. Filters out rows with invalid status values
      4. Filters out rows where discount_pct is out of range

  PATTERN: Uses dbt_unit_testing package — mock the source, compare output.

  HOW TO RUN:
    dbt test --select unit_test_stg_orders

  ⏱ MANUAL EFFORT ESTIMATE: ~1.5 hours to write, review, and maintain per model.
  (This is what Claude will automate in future state.)
*/

{{ config(tags=['unit_test']) }}

{% call dbt_unit_testing.test('stg_orders', 'Unit test: discount flag and status filter') %}

  {% call dbt_unit_testing.mock_source('raw', 'orders') %}
    select * from (values
      -- order_id, customer_id, order_date, status, shipping_method, promo_code, discount_pct, _loaded_at
      ('O_TEST_001', 'C001', '2023-11-15', 'completed',  'standard',  null,     '10',  current_timestamp),   -- should be discounted
      ('O_TEST_002', 'C002', '2023-11-16', 'completed',  'express',   'SAVE5',  '5',   current_timestamp),   -- should be discounted
      ('O_TEST_003', 'C003', '2023-11-17', 'shipped',    'standard',  null,     '0',   current_timestamp),   -- NOT discounted
      ('O_TEST_004', 'C004', '2023-11-18', 'INVALID',   'standard',  null,     '0',   current_timestamp),   -- FILTERED OUT (bad status)
      ('O_TEST_005', 'C005', '2023-11-19', 'completed',  'standard',  null,     '150', current_timestamp),   -- FILTERED OUT (discount > 100)
      ('O_TEST_006', null,   '2023-11-20', 'completed',  'standard',  null,     '0',   current_timestamp)    -- FILTERED OUT (null customer_id)
    ) as t(order_id, customer_id, order_date, status, shipping_method, promo_code, discount_pct, _loaded_at)
  {% endcall %}

  {% call dbt_unit_testing.expect() %}
    select * from (values
      -- Only 3 rows should pass through the validated CTE
      ('O_TEST_001', 'C001', true,  10.0),
      ('O_TEST_002', 'C002', true,   5.0),
      ('O_TEST_003', 'C003', false,  0.0)
    ) as t(order_id, customer_id, is_discounted, discount_pct)
  {% endcall %}

{% endcall %}
