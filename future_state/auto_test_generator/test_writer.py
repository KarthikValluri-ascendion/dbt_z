"""
test_writer.py — Writes Claude-generated tests to the correct DBT directories.

Output structure:
  generated_tests/
  └── <model_name>/
      ├── schema_tests.yml          → append into models/<layer>/<model>.yml
      ├── unit_test_<model>.sql     → save to tests/unit/
      ├── functional_test_<model>.sql → save to tests/functional/
      └── generation_report.md     → audit trail with token costs, time saved
"""

import json
import shutil
from pathlib import Path
from datetime import datetime, timezone
from dataclasses import asdict
from claude_client import GeneratedTests
from config import GENERATED_TESTS_DIR, DBT_PROJECT_DIR


class TestWriter:
    """Persists generated tests and creates audit reports."""

    # Manual authoring time estimates (minutes per test type)
    MANUAL_MINUTES = {
        "schema_yaml":        30,
        "unit_test_sql":      90,
        "functional_test_sql": 60,
    }

    def __init__(self, output_dir: Path = GENERATED_TESTS_DIR):
        self.output_dir = Path(output_dir)
        self.session_stats: list[dict] = []

    def write(self, result: GeneratedTests, apply_to_project: bool = False) -> Path:
        """
        Write generated tests to output_dir/<model_name>/.
        If apply_to_project=True, also copies to the live DBT project.
        Returns the model output directory.
        """
        model_dir = self.output_dir / result.model_name
        model_dir.mkdir(parents=True, exist_ok=True)

        # ── Write the three artefacts ─────────────────────────────────────────
        schema_path = model_dir / "schema_tests.yml"
        unit_path   = model_dir / f"unit_test_{result.model_name}.sql"
        func_path   = model_dir / f"functional_test_{result.model_name}.sql"

        schema_path.write_text(
            self._add_header("yaml", result.model_name, "schema") + result.schema_yaml,
            encoding="utf-8"
        )
        unit_path.write_text(
            self._add_header("sql", result.model_name, "unit") + result.unit_test_sql,
            encoding="utf-8"
        )
        func_path.write_text(
            self._add_header("sql", result.model_name, "functional") + result.functional_test_sql,
            encoding="utf-8"
        )

        # ── Write audit report ────────────────────────────────────────────────
        report_path = model_dir / "generation_report.md"
        report_path.write_text(
            self._build_report(result),
            encoding="utf-8"
        )

        # ── Track session stats ───────────────────────────────────────────────
        self.session_stats.append({
            "model": result.model_name,
            "schema_path": str(schema_path),
            "unit_path": str(unit_path),
            "functional_path": str(func_path),
            "input_tokens": result.input_tokens,
            "output_tokens": result.output_tokens,
            "cached_tokens": result.cached_tokens,
            "cost_usd": result.total_cost_usd,
            "time_saved_minutes": sum(self.MANUAL_MINUTES.values()),
        })

        # ── Optionally apply to live project ─────────────────────────────────
        if apply_to_project:
            self._apply_to_project(result, model_dir)

        return model_dir

    def write_session_summary(self) -> Path:
        """Write a final ROI summary across all models generated this session."""
        summary_path = self.output_dir / "session_summary.md"

        total_cost  = sum(s["cost_usd"] for s in self.session_stats)
        total_saved = sum(s["time_saved_minutes"] for s in self.session_stats)
        total_models = len(self.session_stats)

        # Assume avg DBT engineer rate of $80/hr for ROI calc
        hourly_rate_usd = 80
        manual_cost_usd = (total_saved / 60) * hourly_rate_usd
        roi_ratio = round(manual_cost_usd / total_cost, 1) if total_cost > 0 else float("inf")

        lines = [
            "# 🤖 Claude DBT Test Generator — Session Summary",
            f"\nGenerated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
            "",
            "## Models Processed",
            "| Model | Input Tokens | Cached | Output | Cost ($) | Time Saved (min) |",
            "|-------|-------------|--------|--------|----------|-----------------|",
        ]

        for s in self.session_stats:
            lines.append(
                f"| {s['model']} | {s['input_tokens']:,} | {s['cached_tokens']:,} "
                f"| {s['output_tokens']:,} | ${s['cost_usd']:.4f} | {s['time_saved_minutes']} |"
            )

        lines += [
            "",
            "## ROI Summary",
            f"| Metric | Value |",
            f"|--------|-------|",
            f"| Total models processed | {total_models} |",
            f"| Total Claude API cost | **${total_cost:.4f}** |",
            f"| Manual engineer time saved | **{total_saved} minutes ({total_saved/60:.1f} hrs)** |",
            f"| Manual cost (@ ${hourly_rate_usd}/hr) | **${manual_cost_usd:.2f}** |",
            f"| **ROI Ratio** | **{roi_ratio}x** |",
            f"| Time per model (manual avg) | {sum(self.MANUAL_MINUTES.values())} minutes |",
            f"| Time per model (Claude) | ~30 seconds |",
            "",
            "## Files Generated",
        ]

        for s in self.session_stats:
            lines += [
                f"\n### {s['model']}",
                f"  - Schema YAML: `{s['schema_path']}`",
                f"  - Unit test:   `{s['unit_path']}`",
                f"  - Functional:  `{s['functional_path']}`",
            ]

        summary_path.write_text("\n".join(lines), encoding="utf-8")
        return summary_path

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _add_header(self, file_type: str, model_name: str, test_type: str) -> str:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        comment_char = "#" if file_type == "yaml" else "--"
        return (
            f"{comment_char} AUTO-GENERATED by Claude DBT Test Generator\n"
            f"{comment_char} Model: {model_name} | Type: {test_type} | Generated: {ts}\n"
            f"{comment_char} DO NOT EDIT MANUALLY — regenerate via: python main.py --model {model_name}\n\n"
        )

    def _build_report(self, result: GeneratedTests) -> str:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        time_saved = sum(self.MANUAL_MINUTES.values())
        return f"""# Test Generation Report: {result.model_name}

**Generated:** {ts}
**Claude Model:** {result.model_name}

## Token Usage & Cost
| Metric | Value |
|--------|-------|
| Input tokens | {result.input_tokens:,} |
| Cached tokens (90% discount) | {result.cached_tokens:,} |
| Output tokens | {result.output_tokens:,} |
| **Total API cost** | **${result.total_cost_usd:.6f}** |

## Time Savings
| Test Type | Manual Time | Claude Time |
|-----------|-------------|-------------|
| Schema YAML tests | {self.MANUAL_MINUTES['schema_yaml']} min | ~5 sec |
| Unit tests (SQL) | {self.MANUAL_MINUTES['unit_test_sql']} min | ~10 sec |
| Functional tests (SQL) | {self.MANUAL_MINUTES['functional_test_sql']} min | ~10 sec |
| **Total** | **{time_saved} min ({time_saved/60:.1f} hrs)** | **~25 sec** |

## Claude's Explanation
{result.explanation}
"""

    def _apply_to_project(self, result: GeneratedTests, model_dir: Path) -> None:
        """Copy generated files into the live DBT project (use with caution)."""
        unit_dest = DBT_PROJECT_DIR / "tests" / "unit" / f"unit_test_{result.model_name}.sql"
        func_dest = DBT_PROJECT_DIR / "tests" / "functional" / f"functional_test_{result.model_name}.sql"

        shutil.copy(model_dir / f"unit_test_{result.model_name}.sql", unit_dest)
        shutil.copy(model_dir / f"functional_test_{result.model_name}.sql", func_dest)
        print(f"  ✅ Applied to project: {unit_dest.name}, {func_dest.name}")
