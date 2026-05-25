/*
  UNIT TEST: unit_test_dim_customers_ltv
  MODEL UNDER TEST: dim_customers

  PURPOSE:
    Verify LTV segment classification thresholds:
      lifetime_value >= 5000 → CHAMPION
      lifetime_value >= 2000 → LOYAL
      lifetime_value >= 500  → POTENTIAL
      lifetime_value > 0     → NEW
      lifetime_value = 0     → PROSPECT (never ordered)

    Also verify return_rate_pct calculation.

  ⏱ MANUAL EFFORT ESTIMATE: ~2 hours
*/

{{ config(tags=['unit_test']) }}

{% call dbt_unit_testing.test('dim_customers', 'Unit test: LTV segmentation and return rate') %}

  {% call dbt_unit_testing.mock_ref('stg_customers') %}
    select * from (values
      ('C001','John','Smith','John Smith','john@test.com','5550101','NY','NY','USA','2022-01-01'::date,'GOLD',true,current_timestamp),
      ('C002','Jane','Doe','Jane Doe','jane@test.com','5550102','LA','CA','USA','2022-01-01'::date,'SILVER',true,current_timestamp),
      ('C003','Bob','J','Bob J','bob@test.com','5550103','CHI','IL','USA','2022-01-01'::date,'BRONZE',true,current_timestamp),
      ('C004','Alice','W','Alice W','alice@test.com','5550104','HOU','TX','USA','2022-01-01'::date,'GOLD',true,current_timestamp),
      ('C005','Charlie','B','Charlie B','charlie@test.com','5550105','PHX','AZ','USA','2022-01-01'::date,'SILVER',false,current_timestamp)
    ) as t(customer_id,first_name,last_name,full_name,email,phone_clean,city,state_code,country_code,signup_date,customer_tier,is_active,_loaded_at)
  {% endcall %}

  {% call dbt_unit_testing.mock_ref('fct_orders') %}
    select * from (values
      -- customer_id, order_id, is_completed, is_returned, is_cancelled, final_order_amount, recognized_revenue, promo_code, total_quantity, order_date
      ('C001','O001',true, false,false, 6000.00, 6000.00, null, 2, '2023-01-01'::date),  -- CHAMPION (6000 LTV)
      ('C002','O002',true, false,false, 2500.00, 2500.00, null, 3, '2023-02-01'::date),  -- LOYAL (2500 LTV)
      ('C003','O003',true, false,false,  700.00,  700.00, null, 1, '2023-03-01'::date),  -- POTENTIAL (700 LTV)
      ('C003','O004',true, true, false,   80.00,    0.00, null, 1, '2023-04-01'::date),  -- same C003, returned → return rate = 50%
      ('C004','O005',true, false,false,  100.00,  100.00, null, 1, '2023-05-01'::date)   -- NEW (100 LTV); C005 has no orders → PROSPECT
    ) as t(customer_id,order_id,is_completed,is_returned,is_cancelled,final_order_amount,recognized_revenue,promo_code,total_quantity,order_date)
  {% endcall %}

  {% call dbt_unit_testing.expect() %}
    select * from (values
      ('C001', 6000.00, 'CHAMPION',  0.00),
      ('C002', 2500.00, 'LOYAL',     0.00),
      ('C003',  700.00, 'POTENTIAL', 50.00),
      ('C004',  100.00, 'NEW',       0.00),
      ('C005',    0.00, 'PROSPECT',  0.00)
    ) as t(customer_id, lifetime_value, ltv_segment, return_rate_pct)
  {% endcall %}

{% endcall %}
