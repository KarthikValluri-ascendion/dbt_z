"""
claude_client.py — Anthropic Claude API client with prompt caching.

Key features:
  - Prompt caching on the system prompt → 90% cost reduction on the 2nd+ model
  - Structured output parsing: pulls yaml/sql blocks from Claude's response
  - Token + cost tracking for the ROI report
"""

import re
import anthropic
from dataclasses import dataclass
from config import settings


# ─────────────────────────────────────────────────────────────────────────────
# Data container — one per model processed
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class GeneratedTests:
    """Everything Claude produces for a single DBT model."""
    model_name:          str
    schema_yaml:         str   # YAML schema tests
    unit_test_sql:       str   # dbt_unit_testing SQL
    functional_test_sql: str   # business-rule SQL
    explanation:         str   # plain-English summary from Claude
    input_tokens:        int = 0
    output_tokens:       int = 0
    cached_tokens:       int = 0

    @property
    def total_cost_usd(self) -> float:
        """
        Claude Sonnet 4.6 pricing (2025):
          Input  tokens : $3.00  / 1M
          Cached tokens : $0.30  / 1M  (cache READ — 90% cheaper)
          Output tokens : $15.00 / 1M
        """
        input_cost  = (self.input_tokens  / 1_000_000) * 3.00
        cached_cost = (self.cached_tokens / 1_000_000) * 0.30
        output_cost = (self.output_tokens / 1_000_000) * 15.00
        return round(input_cost + cached_cost + output_cost, 6)


# ─────────────────────────────────────────────────────────────────────────────
# Claude client
# ─────────────────────────────────────────────────────────────────────────────

class ClaudeTestGenerator:
    """
    Wraps the Anthropic SDK.

    HOW PROMPT CACHING WORKS HERE
    ──────────────────────────────
    The system prompt (~1,400 tokens) is identical for every model.
    By marking it with  cache_control: {type: ephemeral}  Claude caches it
    server-side for 5 minutes.  When you run --all (8 models), only the
    FIRST call pays full input price; the remaining 7 use the cached copy
    at 10% of the cost.  That alone cuts your bill by ~60% on a full run.
    """

    # ── System prompt ─────────────────────────────────────────────────────────
    # This is the part that gets cached. Keep it detailed — the cache amortises
    # the cost across every model in the session.
    SYSTEM_PROMPT = """You are a senior DBT and Snowflake data engineer specializing in data quality and automated test generation.

Your job is to generate comprehensive, production-ready test cases for DBT models.

CONTEXT:
  - Platform: Snowflake + DBT Core
  - Pattern: staging (views) → intermediate (ephemeral CTEs) → marts (tables/incremental)
  - Test packages available: dbt_utils, dbt_expectations, EqualExperts/dbt_unit_testing
  - Domain: e-commerce analytics (customers, orders, order_items, products, payments)

═══════════════════════════════════════════════════════════════════════════════
CATEGORY 1 — SCHEMA TESTS  (output as ```yaml)
═══════════════════════════════════════════════════════════════════════════════
Format:
  version: 2
  models:
    - name: <model>
      tests: [...]          ← model-level tests (row count, uniqueness combos)
      columns:
        - name: <col>
          tests: [...]      ← column-level tests

Rules:
  • Every primary key  → not_null + unique
  • Every foreign key  → not_null + relationships: to: ref('...') field: ...
  • Enum columns       → accepted_values (error severity)
  • Numeric columns    → dbt_expectations.expect_column_values_to_be_between
  • Date columns       → range check between '2020-01-01' and CURRENT_DATE()
  • Derived booleans   → dbt_utils.expression_is_true to cross-check the source column
  • Use severity: warn for soft constraints (new enum values likely), error for hard ones

═══════════════════════════════════════════════════════════════════════════════
CATEGORY 2 — UNIT TESTS  (output as ```sql)
═══════════════════════════════════════════════════════════════════════════════
Use the EqualExperts dbt_unit_testing package.

Structure (one {% call %} block per business rule being tested):
  {{ config(tags=['unit_test', 'auto_generated']) }}

  {% call dbt_unit_testing.test('model_name', 'descriptive test name') %}
    {% call dbt_unit_testing.mock_source('schema', 'table') %}
      select * from (values (...)) as t(col1, col2, ...)
    {% endcall %}
    -- OR for ref() dependencies:
    {% call dbt_unit_testing.mock_ref('upstream_model_name') %}
      select * from (values (...)) as t(col1, col2, ...)
    {% endcall %}

    {% call dbt_unit_testing.expect() %}
      select * from (values (...)) as t(col1, col2, ...)
    {% endcall %}
  {% endcall %}

Rules:
  • Write ONE test block per distinct business rule or CASE statement
  • Include 4-6 rows per mock: happy path + edge cases (NULL, zero, boundary, invalid)
  • Add a comment on each row explaining what it tests
  • The expect() block only lists columns being asserted (not all columns)
  • NEVER reference real Snowflake tables inside mock blocks

═══════════════════════════════════════════════════════════════════════════════
CATEGORY 3 — FUNCTIONAL TESTS  (output as ```sql)
═══════════════════════════════════════════════════════════════════════════════
Plain SQL files run against live Snowflake data.
DBT passes the test when the query returns 0 rows (violations = failures).

Structure:
  {{ config(tags=['functional_test', 'auto_generated']) }}

  WITH violations AS (
    SELECT ..., 'RULE N: description' AS violation_msg
    FROM {{ ref('model') }}
    WHERE <condition that breaks the rule>

    UNION ALL
    SELECT ..., 'RULE N+1: ...' AS violation_msg
    ...
  )
  SELECT * FROM violations

Rules:
  • Write 3-5 separate UNION ALL blocks, one per business rule
  • Include cross-model joins where the rule spans multiple models
  • Each block must have a violation_msg column describing the broken rule
  • Use ref() — never hardcode schema names

═══════════════════════════════════════════════════════════════════════════════
RESPONSE FORMAT — follow exactly
═══════════════════════════════════════════════════════════════════════════════
Output THREE fenced code blocks in this exact order:
  1. ```yaml   (schema tests)
  2. ```sql    (unit tests)
  3. ```sql    (functional tests)

After the third block, write an EXPLANATION section covering:
  • What business rules were tested
  • Which edge cases are covered and why
  • Any assumptions made about the data
  • Estimated time saved vs manual authoring (be specific: X hrs → Y sec)

QUALITY REQUIREMENTS:
  • Column names must exactly match the SELECT list in the provided SQL
  • All Jinja syntax must be valid ({% %} for logic, {{ }} for expressions)
  • Snowflake SQL only (use BOOL_OR, TRY_TO_DATE, TRY_TO_NUMBER, GREATEST, etc.)
  • Mock data values must be realistic (match the sample data provided)"""

    # ── Constructor ───────────────────────────────────────────────────────────

    def __init__(self):
        # validate() prints helpful errors and exits if key is missing
        settings.validate()
        self.client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    # ── Public: generate tests for one model ──────────────────────────────────

    def generate_tests(
        self,
        model_sql:        str,
        model_name:       str,
        model_description: str = "",
        upstream_models:  list = None,
        business_rules:   list = None,
        existing_columns: list = None,
        sample_data:      str  = "",
    ) -> GeneratedTests:
        """
        Send one model's SQL + metadata to Claude and get back three test artefacts.
        The system prompt is cached → fast and cheap from the 2nd call onwards.
        """
        upstream_models  = upstream_models  or []
        business_rules   = business_rules   or []
        existing_columns = existing_columns or []

        user_prompt = self._build_user_prompt(
            model_name, model_sql, model_description,
            upstream_models, business_rules, existing_columns, sample_data
        )

        # ── API call ──────────────────────────────────────────────────────────
        # system is a LIST (not a string) so we can attach cache_control.
        # The SDK sends  anthropic-beta: prompt-caching-2024-07-31  automatically
        # when it detects cache_control blocks.
        response = self.client.messages.create(
            model=settings.claude_model,
            max_tokens=settings.max_tokens,
            system=[
                {
                    "type": "text",
                    "text": self.SYSTEM_PROMPT,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            messages=[
                {"role": "user", "content": user_prompt}
            ],
        )

        raw_text = response.content[0].text

        # ── Parse the three code blocks ───────────────────────────────────────
        schema_yaml, unit_sql, functional_sql, explanation = self._parse_response(raw_text)

        # ── Token tracking ────────────────────────────────────────────────────
        usage  = response.usage
        cached = getattr(usage, "cache_read_input_tokens", 0)

        return GeneratedTests(
            model_name          = model_name,
            schema_yaml         = schema_yaml,
            unit_test_sql       = unit_sql,
            functional_test_sql = functional_sql,
            explanation         = explanation,
            input_tokens        = usage.input_tokens,
            output_tokens       = usage.output_tokens,
            cached_tokens       = cached,
        )

    # ── Private helpers ───────────────────────────────────────────────────────

    def _build_user_prompt(
        self, model_name, sql, description, upstream, rules, columns, sample_data
    ) -> str:
        lines = [
            f"Generate all three test categories for the DBT model below.",
            f"",
            f"MODEL NAME        : {model_name}",
            f"LAYER             : {'staging' if 'stg_' in model_name else 'intermediate' if 'int_' in model_name else 'marts'}",
            f"DESCRIPTION       : {description or '(not provided — derive from SQL)'}",
            f"UPSTREAM REF()s   : {', '.join(upstream) or 'none'}",
            f"",
            f"BUSINESS RULES EXTRACTED FROM SQL COMMENTS:",
        ]
        if rules:
            for r in rules:
                lines.append(f"  • {r}")
        else:
            lines.append("  (none found — infer all rules from the SQL logic)")

        lines += ["", "COLUMNS (from schema YAML, use these exact names):"]
        if columns:
            for c in columns:
                desc = c.get("description", "")
                lines.append(f"  - {c['name']}" + (f": {desc}" if desc else ""))
        else:
            lines.append("  (no YAML found — derive column list from SQL SELECT)")

        if sample_data:
            lines += ["", "SAMPLE DATA (for realistic mock values):", sample_data]

        lines += [
            "",
            "SQL MODEL:",
            "```sql",
            sql,
            "```",
            "",
            "Now generate the yaml, unit test sql, and functional test sql blocks.",
        ]
        return "\n".join(lines)

    def _parse_response(self, text: str) -> tuple:
        """
        Extract the three fenced code blocks from Claude's response.
        Returns (schema_yaml, unit_sql, functional_sql, explanation).
        """
        # Match both ```yaml and ```sql blocks
        blocks = re.findall(r"```(?:yaml|sql)\s*\n(.*?)```", text, re.DOTALL)

        schema_yaml    = blocks[0].strip() if len(blocks) > 0 else "# Claude did not produce a schema block"
        unit_sql       = blocks[1].strip() if len(blocks) > 1 else "-- Claude did not produce a unit test block"
        functional_sql = blocks[2].strip() if len(blocks) > 2 else "-- Claude did not produce a functional test block"

        # Explanation = text after the last closing ```
        last_fence = text.rfind("```")
        explanation = text[last_fence + 3:].strip() if last_fence != -1 else ""

        return schema_yaml, unit_sql, functional_sql, explanation
