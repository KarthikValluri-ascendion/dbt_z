/*
  MODEL: int_order_enriched
  LAYER: Intermediate (ephemeral)
  DEPENDS ON: stg_orders, stg_order_items, stg_payments

  PURPOSE:
    - Join orders → order_items → payments
    - Aggregate line-item totals up to order level
    - Compute payment status at order level
    - Feed into both fct_orders and dim_customers downstream

  NOTE: Materialized as ephemeral — runs as a CTE inside mart queries.
*/
WITH orders AS (

    SELECT * FROM {{ ref('stg_orders') }}

),

order_items_agg AS (

    SELECT
        order_id,
        COUNT(order_item_id)            AS line_item_count,
        SUM(quantity)                   AS total_quantity,
        SUM(gross_amount)               AS order_gross_amount,
        SUM(net_amount)                 AS order_net_amount,
        SUM(discount_amt)               AS order_total_discount
    FROM {{ ref('stg_order_items') }}
    GROUP BY 1

),

payments AS (

    SELECT
        order_id,
        -- Take the latest payment record per order
        MAX(payment_date)               AS payment_date,
        SUM(CASE WHEN is_payment_successful THEN payment_amount ELSE 0 END)
                                        AS collected_amount,
        MAX(payment_method)             AS payment_method,  -- last method used
        BOOL_OR(is_payment_successful)  AS has_successful_payment
    FROM {{ ref('stg_payments') }}
    GROUP BY 1

),

joined AS (

    SELECT
        -- Order identity
        o.order_id,
        o.customer_id,
        o.order_date,
        o.order_status,
        o.shipping_method,
        o.promo_code,
        o.discount_pct              AS header_discount_pct,
        o.is_discounted,

        -- Item aggregates
        COALESCE(oi.line_item_count, 0)     AS line_item_count,
        COALESCE(oi.total_quantity, 0)      AS total_quantity,
        COALESCE(oi.order_gross_amount, 0)  AS order_gross_amount,
        COALESCE(oi.order_net_amount, 0)    AS order_net_amount,
        COALESCE(oi.order_total_discount, 0) AS order_total_discount,

        -- Apply header-level discount on top of line-level discounts
        ROUND(
            COALESCE(oi.order_net_amount, 0)
            * (1 - o.discount_pct / 100.0),
            2
        )                                   AS final_order_amount,

        -- Payment info
        p.payment_date,
        p.payment_method,
        COALESCE(p.collected_amount, 0)     AS collected_amount,
        COALESCE(p.has_successful_payment, FALSE) AS has_successful_payment,

        -- Days to payment
        DATEDIFF(
            'day',
            o.order_date,
            COALESCE(p.payment_date, CURRENT_DATE())
        )                                   AS days_to_payment

    FROM orders o
    LEFT JOIN order_items_agg oi USING (order_id)
    LEFT JOIN payments p USING (order_id)

)

SELECT * FROM joined
