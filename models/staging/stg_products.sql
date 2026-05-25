/*
  MODEL: stg_products
  LAYER: Staging
  SOURCE: RAW.PRODUCTS

  PURPOSE:
    - Cast types, standardize categories
    - Compute margin percentage
    - Filter out deleted products (soft-delete pattern)
*/
WITH source AS (

    SELECT * FROM {{ source('raw', 'products') }}

),

renamed AS (

    SELECT
        -- Keys
        product_id,
        supplier_id,

        -- Descriptions
        TRIM(product_name)                  AS product_name,
        UPPER(TRIM(category))               AS category,
        UPPER(TRIM(subcategory))            AS subcategory,

        -- Pricing
        TRY_TO_NUMBER(cost_price)::NUMBER(10,2)  AS cost_price,
        TRY_TO_NUMBER(list_price)::NUMBER(10,2)  AS list_price,

        -- Derived: gross margin %
        CASE
            WHEN TRY_TO_NUMBER(list_price) > 0
            THEN ROUND(
                (TRY_TO_NUMBER(list_price) - TRY_TO_NUMBER(cost_price))
                / TRY_TO_NUMBER(list_price) * 100,
                2
            )
            ELSE NULL
        END                                 AS gross_margin_pct,

        -- Flags
        CASE
            WHEN LOWER(TRIM(is_active)) IN ('true','1','yes') THEN TRUE
            ELSE FALSE
        END                                 AS is_active,

        TRY_TO_DATE(launch_date, 'YYYY-MM-DD') AS launch_date,

        -- Metadata
        _loaded_at

    FROM source

),

validated AS (

    SELECT *
    FROM renamed
    WHERE
        product_id IS NOT NULL
        AND list_price > 0
        AND cost_price >= 0
        AND cost_price <= list_price   -- margin must not be negative

)

SELECT * FROM validated
