#!/usr/bin/env python3
"""Generate a compact coverage report from LCOV data."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
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

DEFAULT_EXCLUDE_GLOBS = [
    "**/*.g.dart",
    "**/*.freezed.dart",
    "**/*.mocks.dart",
]


@dataclass
class FileCoverage:
    path: str
    hit: int = 0
    found: int = 0

    @property
    def percent(self) -> float | None:
        if self.found == 0:
            return None
        return (self.hit / self.found) * 100.0


def _normalize_path(value: str) -> str:
    normalized = value.replace("\\", "/").strip()
    while "//" in normalized:
        normalized = normalized.replace("//", "/")
    lower = normalized.lower()

    if lower.startswith("lib/"):
        return normalized

    lib_segment_idx = lower.find("/lib/")
    if lib_segment_idx >= 0:
        return normalized[lib_segment_idx + 1 :]

    return normalized


def parse_lcov(lines: Iterable[str]) -> list[FileCoverage]:
    results: list[FileCoverage] = []
    current_path: str | None = None
    da_found = 0
    da_hit = 0
    lf_found: int | None = None
    lh_hit: int | None = None

    def flush_record() -> None:
        nonlocal current_path, da_found, da_hit, lf_found, lh_hit
        if current_path is None:
            return

        found = lf_found if lf_found is not None else da_found
        hit = lh_hit if lh_hit is not None else da_hit
        if found < 0:
            found = 0
        if hit < 0:
            hit = 0
        if hit > found:
            hit = found

        results.append(FileCoverage(path=current_path, hit=hit, found=found))

        current_path = None
        da_found = 0
        da_hit = 0
        lf_found = None
        lh_hit = None

    for raw in lines:
        line = raw.strip()
        if line.startswith("SF:"):
            flush_record()
            current_path = _normalize_path(line[3:])
            da_found = 0
            da_hit = 0
            lf_found = None
            lh_hit = None
            continue

        if line.startswith("DA:") and current_path is not None:
            payload = line[3:]
            parts = payload.split(",")
            if len(parts) < 2:
                continue
            try:
                hits = int(parts[1])
            except ValueError:
                continue
            da_found += 1
            if hits > 0:
                da_hit += 1
            continue

        if line.startswith("LF:") and current_path is not None:
            try:
                lf_found = int(line[3:])
            except ValueError:
                pass
            continue

        if line.startswith("LH:") and current_path is not None:
            try:
                lh_hit = int(line[3:])
            except ValueError:
                pass
            continue

        if line == "end_of_record":
            flush_record()

    flush_record()
    return results


def aggregate(items: Iterable[FileCoverage]) -> tuple[int, int, float | None]:
    hit = sum(i.hit for i in items)
    found = sum(i.found for i in items)
    pct = None if found == 0 else (hit / found) * 100.0
    return hit, found, pct


def format_ratio(hit: int, found: int, pct: float | None) -> str:
    if found == 0 or pct is None:
        return f"{hit}/{found} (N/A)"
    return f"{hit}/{found} ({pct:.2f}%)"


def _matches_any_glob(path: str, globs: list[str]) -> bool:
    pure = PurePosixPath(path)
    for pattern in globs:
        if pure.match(pattern):
            return True
    return False


def _aggregate_by_prefix(files: list[FileCoverage]) -> dict[str, dict]:
    by_prefix: dict[str, dict] = {}
    for prefix in PREFIX_GROUPS:
        matched = [f for f in files if f.path.startswith(prefix)]
        hit, found, pct = aggregate(matched)
        by_prefix[prefix] = {"hit": hit, "found": found, "percent": pct}
    return by_prefix


def build_report(
    files: list[FileCoverage],
    exclude_globs: list[str],
) -> tuple[str, dict]:
    merged_by_path: dict[str, FileCoverage] = {}
    for file_cov in files:
        existing = merged_by_path.get(file_cov.path)
        if existing is None:
            merged_by_path[file_cov.path] = FileCoverage(
                path=file_cov.path,
                hit=file_cov.hit,
                found=file_cov.found,
            )
        else:
            existing.hit += file_cov.hit
            existing.found += file_cov.found

    raw_files = list(merged_by_path.values())
    excluded_files = [f for f in raw_files if _matches_any_glob(f.path, exclude_globs)]
    effective_files = [f for f in raw_files if not _matches_any_glob(f.path, exclude_globs)]

    overall_hit_raw, overall_found_raw, overall_pct_raw = aggregate(raw_files)
    overall_hit, overall_found, overall_pct = aggregate(effective_files)
    excluded_hit, excluded_found, excluded_pct = aggregate(excluded_files)

    by_prefix_raw = _aggregate_by_prefix(raw_files)
    by_prefix = _aggregate_by_prefix(effective_files)

    core_items: list[FileCoverage] = []
    by_path = {f.path: f for f in effective_files}
    for path in ACCOUNTING_CORE_FILES:
        core_items.append(by_path.get(path, FileCoverage(path=path, hit=0, found=0)))

    core_hit, core_found, core_pct = aggregate(core_items)
    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")

    low_files = sorted(
        [f for f in effective_files if f.found > 0],
        key=lambda item: ((item.percent if item.percent is not None else 101.0), -item.found),
    )[:12]

    riskiest_files = sorted(
        [f for f in effective_files if f.found > 0],
        key=lambda item: ((item.found - item.hit), item.found),
        reverse=True,
    )[:12]

    lines: list[str] = []
    lines.append("Coverage Summary")
    lines.append(f"Generated (UTC): {generated_at}")
    lines.append("")
    lines.append(f"Overall (raw): {format_ratio(overall_hit_raw, overall_found_raw, overall_pct_raw)}")
    lines.append(f"Overall (effective): {format_ratio(overall_hit, overall_found, overall_pct)}")
    lines.append(
        f"Excluded generated files: {len(excluded_files)} "
        f"({format_ratio(excluded_hit, excluded_found, excluded_pct)})"
    )
    lines.append("")
    lines.append("By area (effective):")
    for prefix in PREFIX_GROUPS:
        entry = by_prefix[prefix]
        lines.append(f"- {prefix}: {format_ratio(entry['hit'], entry['found'], entry['percent'])}")
    lines.append("Note: lib/ includes all subfolders.")

    lines.append("")
    lines.append(f"Accounting core: {format_ratio(core_hit, core_found, core_pct)}")
    for item in core_items:
        lines.append(f"  - {item.path}: {format_ratio(item.hit, item.found, item.percent)}")

    lines.append("")
    lines.append("Top riskiest files (lost lines):")
    for item in riskiest_files:
        lost_lines = item.found - item.hit
        lines.append(
            f"- {item.path}: lost={lost_lines}, {format_ratio(item.hit, item.found, item.percent)}"
        )

    lines.append("")
    lines.append("Lowest-covered files:")
    for item in low_files:
        lines.append(f"- {item.path}: {format_ratio(item.hit, item.found, item.percent)}")

    payload = {
        "generated_at_utc": generated_at,
        "overall": {"hit": overall_hit_raw, "found": overall_found_raw, "percent": overall_pct_raw},
        "overall_effective": {"hit": overall_hit, "found": overall_found, "percent": overall_pct},
        "excluded_generated": {
            "files": len(excluded_files),
            "hit": excluded_hit,
            "found": excluded_found,
            "percent": excluded_pct,
            "globs": exclude_globs,
        },
        "by_prefix": by_prefix,
        "by_prefix_raw": by_prefix_raw,
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
        "riskiest_files": [
            {
                "path": i.path,
                "hit": i.hit,
                "found": i.found,
                "lost_lines": i.found - i.hit,
                "percent": i.percent,
            }
            for i in riskiest_files
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
    parser.add_argument(
        "--exclude-glob",
        action="append",
        default=None,
        help="Glob pattern to exclude from effective coverage (repeatable)",
    )
    parser.add_argument(
        "--min-effective",
        type=float,
        default=None,
        help="Fail with non-zero exit if effective coverage %% is below this threshold",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Coverage input not found: {input_path}")

    files = parse_lcov(input_path.read_text(encoding="utf-8", errors="ignore").splitlines())
    exclude_globs = args.exclude_glob if args.exclude_glob else DEFAULT_EXCLUDE_GLOBS
    report_text, report_json = build_report(files, exclude_globs)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(report_text, encoding="utf-8")

    json_path = Path(args.json)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report_json, ensure_ascii=False, indent=2), encoding="utf-8")

    print(report_text)
    if args.min_effective is not None:
        effective_pct = report_json.get("overall_effective", {}).get("percent")
        if effective_pct is None or effective_pct < args.min_effective:
            print(
                (
                    "Coverage gate failed: effective coverage "
                    f"{effective_pct if effective_pct is not None else 'N/A'}% "
                    f"is below required {args.min_effective:.2f}%"
                ),
                file=sys.stderr,
            )
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
