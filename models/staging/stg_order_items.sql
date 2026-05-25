/*
  MODEL: stg_order_items
  LAYER: Staging
  SOURCE: RAW.ORDER_ITEMS

  PURPOSE:
    - Cast numeric strings to proper decimal types
    - Compute line-level revenue (gross_amount, net_amount)
    - Guard against negative quantities / prices
*/
WITH source AS (

    SELECT * FROM {{ source('raw', 'order_items') }}

),

renamed AS (

    SELECT
        -- Keys
        order_item_id,
        order_id,
        product_id,

        -- Numeric casts with safety
        GREATEST(TRY_TO_NUMBER(quantity)::INT, 0)          AS quantity,
        GREATEST(TRY_TO_NUMBER(unit_price)::NUMBER(10,2), 0) AS unit_price,
        GREATEST(TRY_TO_NUMBER(discount_amt)::NUMBER(10,2), 0) AS discount_amt,

        -- Derived revenue metrics
        GREATEST(TRY_TO_NUMBER(quantity), 0)
            * GREATEST(TRY_TO_NUMBER(unit_price)::NUMBER(10,2), 0)
                                                           AS gross_amount,

        (GREATEST(TRY_TO_NUMBER(quantity), 0)
            * GREATEST(TRY_TO_NUMBER(unit_price)::NUMBER(10,2), 0))
            - GREATEST(TRY_TO_NUMBER(discount_amt)::NUMBER(10,2), 0)
                                                           AS net_amount,

        -- Metadata
        _loaded_at

    FROM source

),

validated AS (

    SELECT *
    FROM renamed
    WHERE
        order_item_id IS NOT NULL
        AND order_id   IS NOT NULL
        AND product_id IS NOT NULL
        AND quantity   > 0
        AND unit_price >= 0
        AND net_amount >= 0

)

SELECT * FROM validated
