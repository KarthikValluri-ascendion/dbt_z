/*
  MACROS: test_helpers.sql
  Reusable Jinja macros to reduce boilerplate in custom data tests.
*/

-- ─────────────────────────────────────────────────────────────────────────────
-- assert_row_count: Fail if the model row count is not within [min, max]
-- Usage: {{ assert_row_count(ref('stg_orders'), 1, 1000000) }}
-- ─────────────────────────────────────────────────────────────────────────────
{% macro assert_row_count(model, min_count=1, max_count=none) %}

    WITH model_count AS (
        SELECT COUNT(*) AS cnt FROM {{ model }}
    )
    SELECT cnt
    FROM model_count
    WHERE cnt < {{ min_count }}
    {% if max_count is not none %}
        OR cnt > {{ max_count }}
    {% endif %}

{% endmacro %}


-- ─────────────────────────────────────────────────────────────────────────────
-- assert_no_duplicates: Fail if the model has duplicate values in given columns
-- Usage: {{ assert_no_duplicates(ref('fct_orders'), ['order_id']) }}
-- ─────────────────────────────────────────────────────────────────────────────
{% macro assert_no_duplicates(model, columns) %}

    WITH dupes AS (
        SELECT
            {{ columns | join(', ') }},
            COUNT(*) AS cnt
        FROM {{ model }}
        GROUP BY {{ columns | join(', ') }}
        HAVING COUNT(*) > 1
    )
    SELECT * FROM dupes

{% endmacro %}


-- ─────────────────────────────────────────────────────────────────────────────
-- assert_column_sum_equals: Check that SUM of a column matches expected value
-- Useful for reconciliation tests
-- ─────────────────────────────────────────────────────────────────────────────
{% macro assert_column_sum_equals(model, column_name, expected_value, tolerance=0.01) %}

    WITH agg AS (
        SELECT SUM({{ column_name }}) AS actual_sum
        FROM {{ model }}
    )
    SELECT actual_sum
    FROM agg
    WHERE ABS(actual_sum - {{ expected_value }}) > {{ tolerance }}

{% endmacro %}


-- ─────────────────────────────────────────────────────────────────────────────
-- generate_test_data: Helper to build mock CTE rows for unit tests
-- ─────────────────────────────────────────────────────────────────────────────
{% macro generate_test_data(column_names, rows) %}
    SELECT * FROM (VALUES
        {% for row in rows %}
        ({{ row | join(', ') }}){% if not loop.last %},{% endif %}
        {% endfor %}
    ) AS t({{ column_names | join(', ') }})
{% endmacro %}
