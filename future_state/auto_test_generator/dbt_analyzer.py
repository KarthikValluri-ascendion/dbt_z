"""
dbt_analyzer.py — Parses DBT project artifacts to extract model metadata.

Reads:
  - SQL model files         → extracts SQL logic, CTEs, column references
  - schema YAML files       → extracts column descriptions, existing tests
  - dbt_project.yml         → extracts materialization, tags
  - manifest.json (if built) → extracts column-level lineage

This metadata is fed into the Claude prompt for intelligent test generation.
"""

import re
import json
import yaml
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ColumnInfo:
    name: str
    description: str = ""
    data_type: str = ""
    existing_tests: list[str] = field(default_factory=list)
    is_nullable: bool = True


@dataclass
class ModelInfo:
    """All metadata Claude needs to generate tests for a single model."""
    model_name: str
    layer: str                   # staging | intermediate | marts
    sql_content: str             # raw SQL
    description: str = ""
    materialization: str = "view"
    tags: list[str] = field(default_factory=list)
    columns: list[ColumnInfo] = field(default_factory=list)
    upstream_models: list[str] = field(default_factory=list)   # ref() calls
    upstream_sources: list[tuple] = field(default_factory=list) # source() calls
    business_rules: list[str] = field(default_factory=list)    # extracted from comments
    existing_tests: list[str] = field(default_factory=list)


class DBTProjectAnalyzer:
    """
    Scans a DBT project directory and extracts model metadata.
    Works from SQL + YAML files alone — no dbt CLI required.
    """

    def __init__(self, project_dir: Path):
        self.project_dir = Path(project_dir)
        self.models_dir = self.project_dir / "models"
        self.tests_dir  = self.project_dir / "tests"

    # ─── Public API ───────────────────────────────────────────────────────────

    def list_models(self) -> list[str]:
        """Return all model names in the project."""
        return [
            p.stem
            for p in self.models_dir.rglob("*.sql")
            if not p.name.startswith("_")
        ]

    def analyze_model(self, model_name: str) -> Optional[ModelInfo]:
        """Return full ModelInfo for a given model name."""
        sql_path = self._find_sql_file(model_name)
        if not sql_path:
            return None

        sql_content = sql_path.read_text(encoding="utf-8")
        layer = self._detect_layer(sql_path)

        info = ModelInfo(
            model_name=model_name,
            layer=layer,
            sql_content=sql_content,
            materialization=self._detect_materialization(sql_content),
            tags=self._extract_tags(sql_content),
            upstream_models=self._extract_refs(sql_content),
            upstream_sources=self._extract_sources(sql_content),
            business_rules=self._extract_business_rules(sql_content),
        )

        # Merge YAML schema if available
        yaml_info = self._find_yaml_schema(model_name)
        if yaml_info:
            info.description = yaml_info.get("description", "")
            info.columns = self._parse_yaml_columns(yaml_info.get("columns", []))

        # Collect existing test files
        info.existing_tests = self._find_existing_tests(model_name)

        return info

    def analyze_all_models(self) -> list[ModelInfo]:
        """Analyze every model in the project."""
        results = []
        for name in self.list_models():
            mi = self.analyze_model(name)
            if mi:
                results.append(mi)
        return results

    # ─── Private helpers ──────────────────────────────────────────────────────

    def _find_sql_file(self, model_name: str) -> Optional[Path]:
        matches = list(self.models_dir.rglob(f"{model_name}.sql"))
        return matches[0] if matches else None

    def _detect_layer(self, sql_path: Path) -> str:
        parts = sql_path.parts
        for layer in ("staging", "intermediate", "marts"):
            if layer in parts:
                return layer
        return "unknown"

    def _detect_materialization(self, sql: str) -> str:
        m = re.search(r"materialized\s*=\s*['\"](\w+)['\"]", sql)
        return m.group(1) if m else "view"

    def _extract_tags(self, sql: str) -> list[str]:
        m = re.search(r"tags\s*=\s*\[([^\]]+)\]", sql)
        if not m:
            return []
        return [t.strip().strip("'\"") for t in m.group(1).split(",")]

    def _extract_refs(self, sql: str) -> list[str]:
        """Extract ref('model_name') calls."""
        return list(set(re.findall(r"{{\s*ref\(['\"](\w+)['\"]\)\s*}}", sql)))

    def _extract_sources(self, sql: str) -> list[tuple]:
        """Extract source('schema', 'table') calls."""
        return list(set(
            re.findall(r"{{\s*source\(['\"](\w+)['\"],\s*['\"](\w+)['\"]\)\s*}}", sql)
        ))

    def _extract_business_rules(self, sql: str) -> list[str]:
        """
        Pull business rule comments from SQL.
        Looks for lines with RULE:, NOTE:, BUSINESS:, or PURPOSE: markers.
        """
        rules = []
        for line in sql.splitlines():
            stripped = line.strip().lstrip("-").lstrip("/").lstrip("*").strip()
            if any(stripped.upper().startswith(kw) for kw in
                   ("RULE:", "BUSINESS RULE:", "NOTE:", "PURPOSE:", "INVARIANT:")):
                rules.append(stripped)
        return rules

    def _find_yaml_schema(self, model_name: str) -> Optional[dict]:
        """Search all YAML files in models dir for this model's definition."""
        for yaml_path in self.models_dir.rglob("*.yml"):
            try:
                data = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
                if not data or "models" not in data:
                    continue
                for m in data["models"]:
                    if m.get("name") == model_name:
                        return m
            except Exception:
                continue
        return None

    def _parse_yaml_columns(self, columns_yaml: list) -> list[ColumnInfo]:
        result = []
        for col in columns_yaml:
            tests = []
            for t in col.get("tests", []):
                if isinstance(t, str):
                    tests.append(t)
                elif isinstance(t, dict):
                    tests.extend(list(t.keys()))
            result.append(ColumnInfo(
                name=col.get("name", ""),
                description=col.get("description", ""),
                existing_tests=tests,
            ))
        return result

    def _find_existing_tests(self, model_name: str) -> list[str]:
        """Return paths of existing test SQL files for this model."""
        found = []
        if self.tests_dir.exists():
            for p in self.tests_dir.rglob(f"*{model_name}*.sql"):
                found.append(str(p.relative_to(self.project_dir)))
        return found
