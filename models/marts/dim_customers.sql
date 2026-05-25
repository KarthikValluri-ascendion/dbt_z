/*
  MODEL: dim_customers
  LAYER: Marts — Dimension Table
  DEPENDS ON: stg_customers, fct_orders

  PURPOSE:
    - Enrich customer records with aggregated order statistics
    - Classify customers by lifetime value (LTV) segment
    - Support 360-degree customer view for analytics / CRM

  MATERIALIZATION: table (full refresh on each run)
*/

{{
  config(
    materialized = 'table',
    tags = ['marts', 'customer', 'daily']
  )
}}

WITH customers AS (

    SELECT * FROM {{ ref('stg_customers') }}

),

-- Aggregate order history per customer
order_stats AS (

    SELECT
        customer_id,
        COUNT(order_id)                         AS total_orders,
        COUNT(CASE WHEN is_completed THEN 1 END) AS completed_orders,
        COUNT(CASE WHEN is_returned  THEN 1 END) AS returned_orders,
        COUNT(CASE WHEN is_cancelled THEN 1 END) AS cancelled_orders,
        MIN(order_date)                         AS first_order_date,
        MAX(order_date)                         AS last_order_date,
        DATEDIFF('day', MIN(order_date), MAX(order_date)) AS customer_tenure_days,
        SUM(recognized_revenue)                 AS lifetime_value,
        AVG(final_order_amount)                 AS avg_order_value,
        MAX(final_order_amount)                 AS max_order_value,
        SUM(total_quantity)                     AS total_items_purchased,
        COUNT(DISTINCT promo_code)              AS unique_promos_used
    FROM {{ ref('fct_orders') }}
    GROUP BY 1

),

final AS (

    SELECT
        -- ── Surrogate Key ──────────────────────────────────────────────
        {{ dbt_utils.generate_surrogate_key(['c.customer_id']) }} AS customer_sk,

        -- ── Natural Key ────────────────────────────────────────────────
        c.customer_id,

        -- ── Attributes ─────────────────────────────────────────────────
        c.first_name,
        c.last_name,
        c.full_name,
        c.email,
        c.phone_clean                           AS phone,
        c.city,
        c.state_code,
        c.country_code,
        c.signup_date,
        c.customer_tier,
        c.is_active,

        -- ── Order Stats ────────────────────────────────────────────────
        COALESCE(os.total_orders, 0)            AS total_orders,
        COALESCE(os.completed_orders, 0)        AS completed_orders,
        COALESCE(os.returned_orders, 0)         AS returned_orders,
        COALESCE(os.cancelled_orders, 0)        AS cancelled_orders,
        os.first_order_date,
        os.last_order_date,
        COALESCE(os.customer_tenure_days, 0)    AS customer_tenure_days,
        COALESCE(os.lifetime_value, 0)          AS lifetime_value,
        COALESCE(os.avg_order_value, 0)         AS avg_order_value,
        COALESCE(os.max_order_value, 0)         AS max_order_value,
        COALESCE(os.total_items_purchased, 0)   AS total_items_purchased,
        COALESCE(os.unique_promos_used, 0)      AS unique_promos_used,

        -- ── LTV Segment Classification ─────────────────────────────────
        CASE
            WHEN COALESCE(os.lifetime_value, 0) >= 5000  THEN 'CHAMPION'
            WHEN COALESCE(os.lifetime_value, 0) >= 2000  THEN 'LOYAL'
            WHEN COALESCE(os.lifetime_value, 0) >= 500   THEN 'POTENTIAL'
            WHEN COALESCE(os.lifetime_value, 0) > 0      THEN 'NEW'
            ELSE 'PROSPECT'
        END                                     AS ltv_segment,

        -- ── Return Rate ────────────────────────────────────────────────
        CASE
            WHEN COALESCE(os.total_orders, 0) > 0
            THEN ROUND(os.returned_orders::FLOAT / os.total_orders * 100, 2)
            ELSE 0
        END                                     AS return_rate_pct,

        -- ── Days Since Last Order ──────────────────────────────────────
        DATEDIFF('day', os.last_order_date, CURRENT_DATE()) AS days_since_last_order,

        -- ── Metadata ───────────────────────────────────────────────────
        CURRENT_TIMESTAMP()                     AS _dbt_updated_at

    FROM customers c
    LEFT JOIN order_stats os USING (customer_id)

)

SELECT * FROM final
