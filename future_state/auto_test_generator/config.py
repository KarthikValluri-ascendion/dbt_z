"""
config.py — Central configuration for the DBT Test Generator.
Loads environment variables from a .env file or the shell environment.
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# ─── Load .env file BEFORE reading os.environ ────────────────────────────────
# Looks for .env in the same directory as this file
_env_path = Path(__file__).parent / ".env"
load_dotenv(dotenv_path=_env_path)

# ─── Resolve project paths relative to this file ─────────────────────────────
# File lives at: dbt_projects/future_state/auto_test_generator/config.py
# So:  .parent       = auto_test_generator/
#      .parent.parent = future_state/
#      .parent.parent.parent = dbt_projects/   ← PROJECT_ROOT
PROJECT_ROOT        = Path(__file__).parent.parent.parent
DBT_PROJECT_DIR     = PROJECT_ROOT / "current_state"
GENERATED_TESTS_DIR = PROJECT_ROOT / "future_state" / "generated_tests"
GENERATED_TESTS_DIR.mkdir(parents=True, exist_ok=True)


class AppConfig:
    """
    Simple config object — reads from environment variables.
    Using a plain class (not Pydantic) avoids version-compatibility headaches.
    """

    def __init__(self):
        # ── Claude API ────────────────────────────────────────────────────────
        self.anthropic_api_key: str = os.environ.get("ANTHROPIC_API_KEY", "")
        self.claude_model: str      = os.environ.get("CLAUDE_MODEL", "claude-sonnet-4-6")
        self.max_tokens: int        = int(os.environ.get("MAX_TOKENS", "8192"))

        # ── Snowflake (optional — for live schema introspection) ──────────────
        self.snowflake_account:   str = os.environ.get("SNOWFLAKE_ACCOUNT", "")
        self.snowflake_user:      str = os.environ.get("SNOWFLAKE_USER", "")
        self.snowflake_password:  str = os.environ.get("SNOWFLAKE_PASSWORD", "")
        self.snowflake_warehouse: str = os.environ.get("SNOWFLAKE_WAREHOUSE", "DBT_WH")
        self.snowflake_database:  str = os.environ.get("SNOWFLAKE_DATABASE", "DBT_DEMO")
        self.snowflake_role:      str = os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN")

        # ── Test generation behaviour ─────────────────────────────────────────
        self.max_unit_test_rows:      int  = 10
        self.include_edge_cases:      bool = True
        self.include_business_rules:  bool = True
        self.severity_default:        str  = "error"

    def validate(self):
        """Call this before making any API calls. Prints clear errors."""
        errors = []

        if not self.anthropic_api_key:
            errors.append(
                "  ❌  ANTHROPIC_API_KEY is not set.\n"
                "      1. Get a key at: https://console.anthropic.com/settings/api-keys\n"
                "      2. Add it to:    future_state/auto_test_generator/.env\n"
                "         ANTHROPIC_API_KEY=sk-ant-api03-..."
            )

        if not DBT_PROJECT_DIR.exists():
            errors.append(
                f"  ❌  DBT project not found at: {DBT_PROJECT_DIR}\n"
                f"      Make sure 'current_state/' exists in the project root."
            )

        if errors:
            print("\n" + "=" * 60)
            print("  Configuration errors — fix these before running:")
            print("=" * 60)
            for e in errors:
                print(e)
            print("=" * 60 + "\n")
            sys.exit(1)

        return True


# ─── Singleton: created once at import time ───────────────────────────────────
settings = AppConfig()
