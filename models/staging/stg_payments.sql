/*
  MODEL: stg_payments
  LAYER: Staging
  SOURCE: RAW.PAYMENTS

  PURPOSE:
    - Type cast payment amounts and dates
    - Standardize payment method and status enums
    - Flag successful payments for easy filtering in marts
*/
WITH source AS (

    SELECT * FROM {{ source('raw', 'payments') }}

),

renamed AS (

    SELECT
        -- Keys
        payment_id,
        order_id,

        -- Payment attributes
        LOWER(TRIM(payment_method))                     AS payment_method,
        LOWER(TRIM(payment_status))                     AS payment_status,

        -- Amount
        GREATEST(TRY_TO_NUMBER(amount)::NUMBER(10,2), 0) AS payment_amount,

        -- Date
        TRY_TO_DATE(payment_date, 'YYYY-MM-DD')         AS payment_date,

        -- Derived flags
        CASE
            WHEN LOWER(TRIM(payment_status)) = 'completed' THEN TRUE
            ELSE FALSE
        END                                             AS is_payment_successful,

        -- Metadata
        _loaded_at

    FROM source

),

validated AS (

    SELECT *
    FROM renamed
    WHERE
        payment_id  IS NOT NULL
        AND order_id IS NOT NULL
        AND payment_amount >= 0
        AND payment_status IN ('completed','pending','refunded','failed')

)

SELECT * FROM validated
