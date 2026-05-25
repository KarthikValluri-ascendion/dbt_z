/*
  UNIT TEST: unit_test_stg_order_items
  MODEL UNDER TEST: stg_order_items

  PURPOSE:
    Verify that stg_order_items correctly:
      1. Computes gross_amount = quantity * unit_price
      2. Computes net_amount  = gross_amount - discount_amt
      3. Clamps negative quantities/prices to 0 (GREATEST)
      4. Filters out rows where net_amount < 0

  ⏱ MANUAL EFFORT ESTIMATE: ~1.5 hours per model
*/

{{ config(tags=['unit_test']) }}

{% call dbt_unit_testing.test('stg_order_items', 'Unit test: gross and net amount computation') %}

  {% call dbt_unit_testing.mock_source('raw', 'order_items') %}
    select * from (values
      -- order_item_id, order_id, product_id, quantity, unit_price, discount_amt, _loaded_at
      ('OI_T01', 'O001', 'P001', '2',  '100.00', '0.00',   current_timestamp),  -- gross=200, net=200
      ('OI_T02', 'O001', 'P002', '3',  '50.00',  '30.00',  current_timestamp),  -- gross=150, net=120
      ('OI_T03', 'O002', 'P003', '1',  '500.00', '50.00',  current_timestamp),  -- gross=500, net=450
      ('OI_T04', 'O003', 'P004', '-1', '100.00', '0.00',   current_timestamp),  -- negative qty → FILTERED (qty=0 after clamp → fails qty>0 check)
      ('OI_T05', 'O004', 'P005', '2',  '100.00', '999.00', current_timestamp),  -- net_amount negative → FILTERED
      ('OI_T06', 'O005', 'P006', '0',  '100.00', '0.00',   current_timestamp)   -- zero qty → FILTERED
    ) as t(order_item_id, order_id, product_id, quantity, unit_price, discount_amt, _loaded_at)
  {% endcall %}

  {% call dbt_unit_testing.expect() %}
    select * from (values
      ('OI_T01', 200.00, 200.00),
      ('OI_T02', 150.00, 120.00),
      ('OI_T03', 500.00, 450.00)
    ) as t(order_item_id, gross_amount, net_amount)
  {% endcall %}

{% endcall %}
