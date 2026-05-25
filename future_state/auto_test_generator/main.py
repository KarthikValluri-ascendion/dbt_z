#!/usr/bin/env python3
"""
main.py -- CLI entry point for the Claude DBT Test Generator.

USAGE:
  # Generate tests for a single model
  python main.py --model stg_orders

  # Generate tests for all models in the project
  python main.py --all

  # Generate and auto-copy tests into the live dbt project
  python main.py --model fct_orders --apply

  # Dry-run: print what Claude would receive, no API call
  python main.py --model stg_customers --dry-run

  # Filter to one layer
  python main.py --all --layer staging
"""

import sys
import time
import click
from pathlib import Path

# Force UTF-8 output so Rich works on Windows without emoji issues
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

# ── Local imports ─────────────────────────────────────────────────────────────
from config import settings, DBT_PROJECT_DIR, GENERATED_TESTS_DIR
from dbt_analyzer import DBTProjectAnalyzer
from claude_client import ClaudeTestGenerator
from test_writer import TestWriter

# Force Rich to use a basic console that works on all Windows terminals
console = Console(highlight=False, emoji=False)


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

@click.command()
@click.option("--model",    "-m", default=None,  help="Generate tests for one specific model")
@click.option("--all",      "-a", is_flag=True,  help="Generate tests for ALL models in the project")
@click.option("--apply",          is_flag=True,  help="Also copy generated tests into the live DBT project")
@click.option("--dry-run",        is_flag=True,  help="Show what Claude would receive -- no API call made")
@click.option("--types",    "-t", default="schema,unit,functional",
              help="Comma-separated test types to generate: schema, unit, functional")
@click.option("--output",   "-o", default=str(GENERATED_TESTS_DIR),
              help="Output directory for generated test files")
@click.option("--layer",    "-l", default=None,
              help="Filter by layer when using --all: staging | intermediate | marts")
def generate(model, all, apply, dry_run, types, output, layer):
    """
    Claude DBT Test Generator

    Reads your DBT models, sends them to Claude Sonnet, and writes back
    schema YAML tests, unit tests (dbt_unit_testing), and functional tests.
    """

    console.print(Panel(
        "[bold cyan]Claude DBT Test Generator[/bold cyan]\n"
        f"Project : {DBT_PROJECT_DIR}\n"
        f"Output  : {output}",
        border_style="cyan",
        padding=(0, 2),
    ))

    # ── Setup ─────────────────────────────────────────────────────────────────
    analyzer = DBTProjectAnalyzer(DBT_PROJECT_DIR)
    writer   = TestWriter(Path(output))

    if not dry_run:
        generator = ClaudeTestGenerator()   # validates API key here

    # ── Decide which models to process ────────────────────────────────────────
    if model:
        info = analyzer.analyze_model(model)
        if not info:
            console.print(f"[red]ERROR: Model '{model}' not found under {DBT_PROJECT_DIR / 'models'}[/red]")
            sys.exit(1)
        model_infos = [info]

    elif all:
        model_infos = analyzer.analyze_all_models()
        if layer:
            model_infos = [m for m in model_infos if m.layer == layer]
        if not model_infos:
            console.print(f"[yellow]No models found for layer='{layer}'[/yellow]")
            sys.exit(0)

    else:
        console.print("[yellow]Nothing to do. Use --model <name>  or  --all[/yellow]")
        sys.exit(0)

    console.print(f"\n[green]Found {len(model_infos)} model(s) to process[/green]\n")

    # ── Process each model ────────────────────────────────────────────────────
    for model_info in model_infos:
        console.rule(f"[bold]{model_info.model_name}[/bold]  ({model_info.layer})")

        if dry_run:
            # ---------- DRY RUN: show metadata only, no API call ----------
            console.print("[yellow]DRY RUN -- no API call will be made[/yellow]")
            _print_model_info(model_info)
            console.print()
            continue

        # ---------- REAL RUN: call Claude API ----------
        start = time.time()

        console.print(f"  Sending [bold]{model_info.model_name}[/bold] to Claude ({settings.claude_model})...")

        result = generator.generate_tests(
            model_sql         = model_info.sql_content,
            model_name        = model_info.model_name,
            model_description = model_info.description,
            upstream_models   = model_info.upstream_models,
            business_rules    = model_info.business_rules,
            existing_columns  = [
                {"name": c.name, "description": c.description}
                for c in model_info.columns
            ],
        )

        elapsed = time.time() - start

        # Write output files
        output_dir = writer.write(result, apply_to_project=apply)

        _print_result_summary(result, output_dir, elapsed)
        console.print()

    # ── Session summary (only when processing more than one model) ────────────
    if not dry_run and len(model_infos) > 1:
        summary_path = writer.write_session_summary()
        console.print(f"[bold green]Session complete![/bold green]")
        console.print(f"  ROI summary written to: [cyan]{summary_path}[/cyan]\n")

    if not dry_run:
        _print_roi_panel(writer.session_stats)


# ─────────────────────────────────────────────────────────────────────────────
# Pretty-print helpers
# ─────────────────────────────────────────────────────────────────────────────

def _print_model_info(info) -> None:
    t = Table(show_header=False, box=None, padding=(0, 2))
    t.add_column("key",  style="dim", width=22)
    t.add_column("val")
    t.add_row("Layer",            info.layer)
    t.add_row("Materialization",  info.materialization)
    t.add_row("Upstream ref()s",  ", ".join(info.upstream_models) or "none")
    t.add_row("Upstream sources", str(info.upstream_sources) if info.upstream_sources else "none")
    t.add_row("Business rules",   f"{len(info.business_rules)} extracted from comments")
    t.add_row("Existing tests",   f"{len(info.existing_tests)} test file(s) found")
    t.add_row("Columns in YAML",  f"{len(info.columns)} defined")
    console.print(t)


def _print_result_summary(result, output_dir: Path, elapsed: float) -> None:
    t = Table(title=f"[green]DONE[/green]  {result.model_name}", show_header=True)
    t.add_column("Artefact",    style="cyan",  width=22)
    t.add_column("File",        style="white")
    t.add_column("Tokens",      justify="right", style="dim")

    t.add_row("Schema YAML",    str(output_dir / "schema_tests.yml"),
              f"in:{result.input_tokens:,}")
    t.add_row("Unit test SQL",  str(output_dir / f"unit_test_{result.model_name}.sql"),
              f"out:{result.output_tokens:,}")
    t.add_row("Functional SQL", str(output_dir / f"functional_test_{result.model_name}.sql"),
              f"cache:{result.cached_tokens:,}")

    console.print(t)

    time_saved = sum(TestWriter.MANUAL_MINUTES.values())
    console.print(
        f"  Cost: [red]${result.total_cost_usd:.6f}[/red]  |  "
        f"Elapsed: {elapsed:.1f}s  |  "
        f"Manual time saved: [green]~{time_saved} min[/green]"
    )


def _print_roi_panel(stats: list) -> None:
    if not stats:
        return

    total_cost  = sum(s["cost_usd"]           for s in stats)
    total_saved = sum(s["time_saved_minutes"]  for s in stats)
    manual_cost = (total_saved / 60) * 80   # $80/hr engineer rate

    roi = f"{manual_cost / total_cost:.0f}x" if total_cost > 0 else "infinite"

    console.print(Panel(
        f"[bold]ROI Summary -- Leadership Report[/bold]\n\n"
        f"  Models processed       : [cyan]{len(stats)}[/cyan]\n"
        f"  Total Claude API cost  : [red]${total_cost:.4f}[/red]\n"
        f"  Engineer time saved    : [green]{total_saved} min  ({total_saved/60:.1f} hrs)[/green]\n"
        f"  Manual cost (@ $80/hr) : [green]${manual_cost:.2f}[/green]\n"
        f"  ROI ratio              : [bold yellow]{roi} cheaper than manual[/bold yellow]",
        border_style="green",
        padding=(0, 2),
    ))


if __name__ == "__main__":
    generate()
