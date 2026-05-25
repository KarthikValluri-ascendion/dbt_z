/*
  MODEL: stg_orders
  LAYER: Staging
  SOURCE: RAW.ORDERS

  PURPOSE:
    - Cast raw columns to correct types
    - Standardize order status values
    - Calculate derived flag: is_discounted
    - No joins yet — pure column-level transformation

  OWNER: data-engineering@company.com
*/
WITH source AS (

    SELECT * FROM {{ source('raw', 'orders') }}

),

renamed AS (

    SELECT
        -- Keys
        order_id,
        customer_id,

        -- Dates
        TRY_TO_DATE(order_date, 'YYYY-MM-DD')   AS order_date,

        -- Status standardization
        LOWER(TRIM(status))                     AS order_status,
        -- Allowed: completed, shipped, processing, returned, cancelled

        -- Shipping
        LOWER(TRIM(shipping_method))            AS shipping_method,
        -- Allowed: standard, express, overnight

        -- Promotions
        NULLIF(TRIM(promo_code), '')            AS promo_code,
        COALESCE(
            TRY_TO_NUMBER(discount_pct), 0
        )::NUMBER(5,2)                          AS discount_pct,

        -- Derived flags
        CASE
            WHEN TRY_TO_NUMBER(discount_pct) > 0 THEN TRUE
            ELSE FALSE
        END                                     AS is_discounted,

        -- Metadata
        _loaded_at

    FROM source

),

validated AS (

    SELECT *
    FROM renamed
    WHERE
        order_id IS NOT NULL
        AND customer_id IS NOT NULL
        AND order_date IS NOT NULL
        AND order_status IN ('completed','shipped','processing','returned','cancelled')
        AND discount_pct BETWEEN 0 AND 100

)

SELECT * FROM validated
