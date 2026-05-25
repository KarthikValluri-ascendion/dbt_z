/*
  MODEL: stg_customers
  LAYER: Staging
  SOURCE: RAW.CUSTOMERS (Snowflake) or seeds/raw_customers.csv

  PURPOSE:
    - Cast raw VARCHAR columns to correct types
    - Standardize column naming (snake_case)
    - Apply basic data quality filters
    - No business logic here — just clean and rename

  OWNER: data-engineering@company.com
  TESTS: models/staging/stg_customers.yml
*/
WITH source AS (

    SELECT * FROM {{ source('raw', 'customers') }}

),

renamed AS (

    SELECT
        -- Primary key
        customer_id,

        -- Name fields: trim whitespace
        TRIM(first_name)                        AS first_name,
        TRIM(last_name)                         AS last_name,
        TRIM(first_name) || ' ' || TRIM(last_name) AS full_name,

        -- Contact
        LOWER(TRIM(email))                      AS email,
        REPLACE(REPLACE(phone, '-', ''), ' ', '') AS phone_clean,

        -- Geography
        TRIM(city)                              AS city,
        UPPER(TRIM(state))                      AS state_code,
        UPPER(TRIM(country))                    AS country_code,

        -- Dates
        TRY_TO_DATE(signup_date, 'YYYY-MM-DD')  AS signup_date,

        -- Segmentation
        UPPER(TRIM(customer_tier))              AS customer_tier,  -- GOLD, SILVER, BRONZE

        -- Boolean cast from raw string
        CASE
            WHEN LOWER(TRIM(is_active)) IN ('true', '1', 'yes') THEN TRUE
            ELSE FALSE
        END                                     AS is_active,

        -- Metadata
        _loaded_at

    FROM source

),

validated AS (

    SELECT *
    FROM renamed
    WHERE
        customer_id IS NOT NULL           -- PK must exist
        AND email IS NOT NULL             -- email required
        AND email LIKE '%@%'              -- basic email format check
        AND signup_date IS NOT NULL       -- date must parse

)

SELECT * FROM validated
