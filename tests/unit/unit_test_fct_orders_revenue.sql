/*
  UNIT TEST: unit_test_fct_orders_revenue
  MODEL UNDER TEST: fct_orders

  PURPOSE:
    Verify the recognized_revenue business rule:
      - recognized_revenue = final_order_amount  ONLY when:
          order_status = 'completed' AND has_successful_payment = TRUE
      - recognized_revenue = 0 for all other combinations

    Also verify final_order_amount applies header discount on top of net_amount:
      final_order_amount = order_net_amount * (1 - header_discount_pct/100)

  ⏱ MANUAL EFFORT ESTIMATE: ~2 hours (complex model, multiple rules)
*/

{{ config(tags=['unit_test']) }}

{% call dbt_unit_testing.test('fct_orders', 'Unit test: recognized revenue rule') %}

  {% call dbt_unit_testing.mock_ref('int_order_enriched') %}
    select * from (values
      -- order_id, customer_id, order_date, order_status, shipping_method, promo_code,
      -- header_discount_pct, is_discounted, line_item_count, total_quantity,
      -- order_gross_amount, order_total_discount, order_net_amount, final_order_amount,
      -- payment_date, payment_method, collected_amount, has_successful_payment, days_to_payment
      ('O_A', 'C001', '2023-11-01'::date, 'completed',   'standard', null,    0,  false, 1, 1, 1000.00, 0,   1000.00, 1000.00, '2023-11-01'::date, 'credit_card', 1000.00, true,  0),
      ('O_B', 'C002', '2023-11-02'::date, 'completed',   'express',  'S10',   10, true,  1, 2, 2000.00, 200, 1800.00, 1620.00, '2023-11-02'::date, 'paypal',       1620.00, true,  0),
      ('O_C', 'C003', '2023-11-03'::date, 'shipped',     'standard', null,    0,  false, 1, 1, 500.00,  0,    500.00,  500.00, null,               null,              0.00, false, 10),
      ('O_D', 'C004', '2023-11-04'::date, 'completed',   'standard', null,    0,  false, 1, 1, 750.00,  0,    750.00,  750.00, '2023-11-04'::date, 'debit_card',      0.00, false, 0),  -- completed but payment FAILED
      ('O_E', 'C005', '2023-11-05'::date, 'cancelled',   'standard', null,    0,  false, 0, 0,   0.00,  0,      0.00,    0.00, null,               null,              0.00, false, 0)
    ) as t(order_id, customer_id, order_date, order_status, shipping_method, promo_code,
           header_discount_pct, is_discounted, line_item_count, total_quantity,
           order_gross_amount, order_total_discount, order_net_amount, final_order_amount,
           payment_date, payment_method, collected_amount, has_successful_payment, days_to_payment)
  {% endcall %}

  {% call dbt_unit_testing.mock_ref('stg_customers') %}
    select * from (values
      ('C001','John','Smith','John Smith','john@test.com','5550101','NY','NY','USA','2022-01-01'::date,'GOLD',true,current_timestamp),
      ('C002','Jane','Doe','Jane Doe','jane@test.com','5550102','LA','CA','USA','2022-01-01'::date,'SILVER',true,current_timestamp),
      ('C003','Bob','J','Bob J','bob@test.com','5550103','CHI','IL','USA','2022-01-01'::date,'BRONZE',true,current_timestamp),
      ('C004','Alice','W','Alice W','alice@test.com','5550104','HOU','TX','USA','2022-01-01'::date,'GOLD',true,current_timestamp),
      ('C005','Charlie','B','Charlie B','charlie@test.com','5550105','PHX','AZ','USA','2022-01-01'::date,'SILVER',false,current_timestamp)
    ) as t(customer_id,first_name,last_name,full_name,email,phone_clean,city,state_code,country_code,signup_date,customer_tier,is_active,_loaded_at)
  {% endcall %}

  {% call dbt_unit_testing.expect() %}
    select * from (values
      ('O_A', 1000.00, 1000.00),   -- completed + paid → recognized
      ('O_B', 1620.00, 1620.00),   -- completed + paid → recognized (after 10% header discount)
      ('O_C',  500.00,    0.00),   -- shipped, not paid → NOT recognized
      ('O_D',  750.00,    0.00),   -- completed but payment FAILED → NOT recognized
      ('O_E',    0.00,    0.00)    -- cancelled → NOT recognized
    ) as t(order_id, final_order_amount, recognized_revenue)
  {% endcall %}

{% endcall %}
