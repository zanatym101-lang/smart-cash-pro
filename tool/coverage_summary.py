#!/usr/bin/env python3
"""Generate a compact coverage report from LCOV data."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


ACCOUNTING_CORE_FILES = [
    "lib/data/app_db_transactions.dart",
    "lib/data/app_db_claims.dart",
    "lib/data/app_db_wallets.dart",
    "lib/data/app_db_reports.dart",
    "lib/data/app_db_admin.dart",
    "lib/data/app_db_internal.dart",
    "lib/data/app_db_audit.dart",
    "lib/data/reporting.dart",
]

PREFIX_GROUPS = [
    "lib/data/",
    "lib/services/",
    "lib/screens/",
    "lib/widgets/",
    "lib/",
]


@dataclass
class FileCoverage:
    path: str
    hit: int = 0
    found: int = 0

    @property
    def percent(self) -> float:
        if self.found == 0:
            return 100.0
        return (self.hit / self.found) * 100.0


def _normalize_path(value: str) -> str:
    return value.replace("\\", "/")


def parse_lcov(lines: Iterable[str]) -> list[FileCoverage]:
    results: list[FileCoverage] = []
    current: FileCoverage | None = None

    for raw in lines:
        line = raw.strip()
        if line.startswith("SF:"):
            current = FileCoverage(path=_normalize_path(line[3:]))
            results.append(current)
            continue

        if line.startswith("DA:") and current is not None:
            payload = line[3:]
            parts = payload.split(",")
            if len(parts) < 2:
                continue
            try:
                hits = int(parts[1])
            except ValueError:
                continue
            current.found += 1
            if hits > 0:
                current.hit += 1
            continue

        if line == "end_of_record":
            current = None

    return results


def aggregate(items: Iterable[FileCoverage]) -> tuple[int, int, float]:
    hit = sum(i.hit for i in items)
    found = sum(i.found for i in items)
    pct = 100.0 if found == 0 else (hit / found) * 100.0
    return hit, found, pct


def format_ratio(hit: int, found: int, pct: float) -> str:
    return f"{hit}/{found} ({pct:.2f}%)"


def build_report(files: list[FileCoverage]) -> tuple[str, dict]:
    overall_hit, overall_found, overall_pct = aggregate(files)

    by_prefix: dict[str, dict] = {}
    for prefix in PREFIX_GROUPS:
        matched = [f for f in files if f.path.startswith(prefix)]
        hit, found, pct = aggregate(matched)
        by_prefix[prefix] = {"hit": hit, "found": found, "percent": pct}

    core_items: list[FileCoverage] = []
    by_path = {f.path: f for f in files}
    for path in ACCOUNTING_CORE_FILES:
        core_items.append(by_path.get(path, FileCoverage(path=path, hit=0, found=0)))

    core_hit, core_found, core_pct = aggregate(core_items)
    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")

    low_files = sorted(
        [f for f in files if f.found > 0],
        key=lambda item: (item.percent, item.found),
    )[:12]

    lines: list[str] = []
    lines.append("Coverage Summary")
    lines.append(f"Generated (UTC): {generated_at}")
    lines.append("")
    lines.append(f"Overall: {format_ratio(overall_hit, overall_found, overall_pct)}")
    lines.append("")
    lines.append("By area:")
    for prefix in PREFIX_GROUPS:
        entry = by_prefix[prefix]
        lines.append(f"- {prefix}: {format_ratio(entry['hit'], entry['found'], entry['percent'])}")

    lines.append("")
    lines.append(f"Accounting core: {format_ratio(core_hit, core_found, core_pct)}")
    for item in core_items:
        lines.append(f"  - {item.path}: {format_ratio(item.hit, item.found, item.percent)}")

    lines.append("")
    lines.append("Lowest-covered files:")
    for item in low_files:
        lines.append(f"- {item.path}: {format_ratio(item.hit, item.found, item.percent)}")

    payload = {
        "generated_at_utc": generated_at,
        "overall": {"hit": overall_hit, "found": overall_found, "percent": overall_pct},
        "by_prefix": by_prefix,
        "accounting_core": {
            "hit": core_hit,
            "found": core_found,
            "percent": core_pct,
            "files": [
                {
                    "path": i.path,
                    "hit": i.hit,
                    "found": i.found,
                    "percent": i.percent,
                }
                for i in core_items
            ],
        },
        "lowest_covered_files": [
            {
                "path": i.path,
                "hit": i.hit,
                "found": i.found,
                "percent": i.percent,
            }
            for i in low_files
        ],
    }
    return "\n".join(lines) + "\n", payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize LCOV coverage.")
    parser.add_argument(
        "--input",
        default="coverage/lcov.info",
        help="Path to lcov.info file",
    )
    parser.add_argument(
        "--out",
        default="coverage/summary.txt",
        help="Path to text summary output",
    )
    parser.add_argument(
        "--json",
        default="coverage/summary.json",
        help="Path to JSON summary output",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Coverage input not found: {input_path}")

    files = parse_lcov(input_path.read_text(encoding="utf-8", errors="ignore").splitlines())
    report_text, report_json = build_report(files)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(report_text, encoding="utf-8")

    json_path = Path(args.json)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report_json, ensure_ascii=False, indent=2), encoding="utf-8")

    print(report_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
