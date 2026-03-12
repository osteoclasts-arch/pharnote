from __future__ import annotations

import argparse
import collections
import json
import os
import shutil
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from src.pharnote.doctrine.schemas import ProblemDbSchemaProfile, ScopedProblem
from src.pharnote.utils.config_utils import load_pipeline_config
from src.pharnote.utils.json_utils import read_json, write_json
from src.pharnote.utils.text_cleaning import compact_whitespace, first_number, parse_choice_lines


def _env(name: str) -> str:
    return str(os.environ.get(name, "")).strip()


def _determine_backend(config: Dict[str, Any], backend_override: Optional[str]) -> str:
    missing_env_message = (
        "Live doctrine DB inspection requires env vars. "
        "Set DATABASE_URL with psql available, or set SUPABASE_URL/VITE_SUPABASE_URL and "
        "SUPABASE_SERVICE_ROLE_KEY (preferred) or SUPABASE_ANON_KEY/VITE_SUPABASE_ANON_KEY. "
        "Use --problem-backend fixture only when fixture mode is intentional."
    )
    if backend_override == "fixture":
        return "fixture"
    if backend_override == "supabase":
        if _env("DATABASE_URL") and shutil.which("psql"):
            return "database_url"
        if _supabase_env_ready():
            return "supabase"
        raise RuntimeError(missing_env_message)

    configured = config["problem_db"].get("backend", "auto")
    if configured == "fixture":
        return "fixture"
    if configured == "supabase":
        return _determine_backend(config, "supabase")

    if _env("DATABASE_URL") and shutil.which("psql"):
        return "database_url"
    if _supabase_env_ready():
        return "supabase"
    raise RuntimeError(missing_env_message)


def _supabase_env_ready() -> bool:
    return bool(
        (_env("SUPABASE_URL") or _env("VITE_SUPABASE_URL"))
        and (
            _env("SUPABASE_ANON_KEY")
            or _env("VITE_SUPABASE_ANON_KEY")
            or _env("SUPABASE_SERVICE_ROLE_KEY")
        )
    )


def _run_psql(query: str) -> str:
    database_url = _env("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is missing")
    result = subprocess.run(
        ["psql", database_url, "-At", "-F", "\t", "-c", query],
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout


def _fetch_rows_via_psql(table_name: str, limit: Optional[int] = None) -> List[Dict[str, Any]]:
    limit_clause = f" LIMIT {limit}" if limit is not None else ""
    sql = f"SELECT row_to_json(t) FROM (SELECT * FROM public.{table_name}{limit_clause}) t;"
    output = _run_psql(sql)
    rows: List[Dict[str, Any]] = []
    for line in output.splitlines():
        text = line.strip()
        if not text:
            continue
        rows.append(json.loads(text))
    return rows


def _introspect_columns_via_psql(table_name: str) -> List[str]:
    sql = (
        "SELECT column_name FROM information_schema.columns "
        f"WHERE table_schema = 'public' AND table_name = '{table_name}' "
        "ORDER BY ordinal_position;"
    )
    output = _run_psql(sql)
    return [line.strip() for line in output.splitlines() if line.strip()]


def _fetch_rows_via_supabase(
    config: Dict[str, Any],
    table_name: str,
    *,
    page_size: int = 1000,
    limit: Optional[int] = None,
) -> List[Dict[str, Any]]:
    base_url = _env("SUPABASE_URL") or _env("VITE_SUPABASE_URL")
    token = _env("SUPABASE_SERVICE_ROLE_KEY") or _env("SUPABASE_ANON_KEY") or _env("VITE_SUPABASE_ANON_KEY")
    rows: List[Dict[str, Any]] = []
    offset = 0
    while True:
        batch_limit = page_size if limit is None else min(page_size, max(limit - len(rows), 0))
        if batch_limit <= 0:
            break
        params = urllib.parse.urlencode({"select": "*", "limit": str(batch_limit), "offset": str(offset)})
        url = f"{base_url}/rest/v1/{table_name}?{params}"
        request = urllib.request.Request(
            url,
            headers={
                "apikey": token,
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "Prefer": "count=exact",
            },
        )
        with urllib.request.urlopen(request) as response:
            payload = response.read().decode("utf-8")
        data = json.loads(payload)
        if not isinstance(data, list):
            raise RuntimeError("Supabase REST response was not a list")
        typed_rows = [row for row in data if isinstance(row, dict)]
        rows.extend(typed_rows)
        if len(typed_rows) < batch_limit or (limit is not None and len(rows) >= limit):
            break
        offset += batch_limit
    return rows


def _load_fixture_rows(config: Dict[str, Any]) -> List[Dict[str, Any]]:
    fixture_path = Path(config["problem_db"]["fixture_path"])
    payload = read_json(fixture_path, default=[])
    return payload if isinstance(payload, list) else []


def _union_metadata_keys(rows: List[Dict[str, Any]]) -> List[str]:
    keys = set()
    for row in rows:
        metadata = row.get("metadata")
        if isinstance(metadata, dict):
            keys.update(str(key) for key in metadata.keys())
    return sorted(keys)


def _resolve_field_aliases(
    config: Dict[str, Any],
    columns: List[str],
    metadata_keys: List[str],
) -> Tuple[Dict[str, Optional[str]], Dict[str, Optional[str]], List[str], List[str]]:
    available_columns = {str(column) for column in columns}
    available_metadata = {str(key) for key in metadata_keys}
    resolved_fields: Dict[str, Optional[str]] = {}
    resolved_metadata_fields: Dict[str, Optional[str]] = {}
    warnings: List[str] = []
    excluded_capabilities: List[str] = []

    for capability, alias_group in config["field_aliases"].items():
        matched_column = next(
            (alias for alias in alias_group.get("columns", []) if alias in available_columns),
            None,
        )
        matched_metadata = next(
            (alias for alias in alias_group.get("metadata_keys", []) if alias in available_metadata),
            None,
        )
        resolved_fields[capability] = matched_column
        resolved_metadata_fields[capability] = matched_metadata
        if matched_column is None and matched_metadata is None:
            warnings.append(f"capability_unresolved:{capability}")
            excluded_capabilities.append(capability)

    return resolved_fields, resolved_metadata_fields, warnings, excluded_capabilities


def _build_schema_profile(
    *,
    backend: str,
    table_name: str,
    introspection_mode: str,
    rows: List[Dict[str, Any]],
    available_columns: List[str],
    config: Dict[str, Any],
    extra_warnings: Optional[List[str]] = None,
) -> ProblemDbSchemaProfile:
    metadata_keys = _union_metadata_keys(rows)
    resolved_fields, resolved_metadata_fields, warnings, excluded_capabilities = _resolve_field_aliases(
        config,
        available_columns,
        metadata_keys,
    )
    warnings.extend(extra_warnings or [])
    return ProblemDbSchemaProfile(
        backend=backend,  # type: ignore[arg-type]
        table_name=table_name,
        introspection_mode=introspection_mode,  # type: ignore[arg-type]
        available_columns=sorted(available_columns),
        metadata_keys=metadata_keys,
        resolved_fields=resolved_fields,
        resolved_metadata_fields=resolved_metadata_fields,
        warnings=warnings,
        excluded_capabilities=sorted(set(excluded_capabilities)),
        sample_row_count=len(rows),
    )


def _coalesce_with_source(
    row: Dict[str, Any],
    capability: str,
    profile: ProblemDbSchemaProfile,
) -> Tuple[Any, Optional[str]]:
    column_name = profile.resolved_fields.get(capability)
    if column_name and column_name in row:
        return row.get(column_name), f"column:{column_name}"

    metadata_key = profile.resolved_metadata_fields.get(capability)
    metadata = row.get(profile.resolved_fields.get("metadata") or "metadata")
    if metadata_key and isinstance(metadata, dict):
        return metadata.get(metadata_key), f"metadata:{metadata_key}"
    return None, None


def _coalesce_from_profile(
    row: Dict[str, Any],
    capability: str,
    profile: ProblemDbSchemaProfile,
) -> Any:
    value, _ = _coalesce_with_source(row, capability, profile)
    return value


def _collect_concept_tags(row: Dict[str, Any], profile: ProblemDbSchemaProfile, config: Dict[str, Any]) -> List[str]:
    tags: List[str] = []
    alias_group = config["field_aliases"]["concept_tags"]
    for column_name in alias_group.get("columns", []):
        value = row.get(column_name)
        tags.extend(_normalize_tag_value(value))

    metadata = row.get(profile.resolved_fields.get("metadata") or "metadata")
    if isinstance(metadata, dict):
        for key in alias_group.get("metadata_keys", []):
            tags.extend(_normalize_tag_value(metadata.get(key)))

    deduped: List[str] = []
    for tag in tags:
        if tag and tag not in deduped:
            deduped.append(tag)
    return deduped


def _normalize_tag_value(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [compact_whitespace(str(item)) for item in value if compact_whitespace(str(item))]
    if isinstance(value, dict):
        return [compact_whitespace(str(item)) for item in value.values() if compact_whitespace(str(item))]
    text = compact_whitespace(str(value))
    if not text:
        return []
    return [part for part in [compact_whitespace(piece) for piece in text.replace("|", ",").split(",")] if part]


def _normalize_exam_type(raw_exam_type: Any, month: Optional[int]) -> Optional[str]:
    text = compact_whitespace(str(raw_exam_type or ""))
    lowered = text.lower()
    if month == 11 or "수능" in text:
        return "수능"
    if month == 6 or "6월" in text or "6모" in lowered:
        return "6월 모의평가"
    if month == 9 or "9월" in text or "9모" in lowered:
        return "9월 모의평가"
    return None


def _is_math_subject(raw_subject: Any) -> bool:
    text = compact_whitespace(str(raw_subject or "")).lower()
    return "수학" in text or "math" in text


def _normalize_common_section(
    raw_value: Any,
    *,
    year: int,
    question_number: int,
) -> Tuple[Optional[bool], Optional[str]]:
    if isinstance(raw_value, bool):
        return raw_value, None

    text = compact_whitespace(str(raw_value or "")).lower()
    if text in {"공통", "common", "true", "1", "yes"}:
        return True, None
    if text in {"선택", "elective", "false", "0", "no"}:
        return False, None

    if year >= 2022:
        return question_number <= 22, "question_number_fallback"
    return None, None


def _normalize_points(raw_value: Any) -> Optional[int]:
    return first_number(raw_value)


def _build_problem_id(year: int, exam_type: str, question_number: int) -> str:
    session_code = {
        "수능": "csat",
        "6월 모의평가": "06_mock",
        "9월 모의평가": "09_mock",
    }[exam_type]
    return f"{year}_{session_code}_common_q{question_number:02d}"


def _load_backend_rows(config: Dict[str, Any], backend_override: Optional[str]) -> Tuple[List[Dict[str, Any]], ProblemDbSchemaProfile]:
    table_name = config["problem_db"]["table"]
    resolved_backend = _determine_backend(config, backend_override)

    if resolved_backend == "fixture":
        rows = _load_fixture_rows(config)
        columns = sorted({str(key) for row in rows for key in row.keys()})
        profile = _build_schema_profile(
            backend="fixture",
            table_name=table_name,
            introspection_mode="fixture",
            rows=rows,
            available_columns=columns,
            config=config,
        )
        return rows, profile

    if resolved_backend == "database_url":
        rows = _fetch_rows_via_psql(table_name)
        columns = _introspect_columns_via_psql(table_name)
        profile = _build_schema_profile(
            backend="database_url",
            table_name=table_name,
            introspection_mode="information_schema",
            rows=rows,
            available_columns=columns,
            config=config,
        )
        return rows, profile

    rows = _fetch_rows_via_supabase(config, table_name)
    columns = sorted({str(key) for row in rows for key in row.keys()})
    profile = _build_schema_profile(
        backend="supabase",
        table_name=table_name,
        introspection_mode="sampled_rows",
        rows=rows,
        available_columns=columns,
        config=config,
    )
    return rows, profile


def load_scoped_problems(
    config: Dict[str, Any],
    *,
    backend_override: Optional[str] = None,
) -> Tuple[ProblemDbSchemaProfile, List[ScopedProblem], List[Dict[str, Any]]]:
    rows, profile = _load_backend_rows(config, backend_override)
    scope = config["scope"]
    skipped_rows: List[Dict[str, Any]] = []
    problems: List[ScopedProblem] = []

    for row_index, row in enumerate(rows):
        year = first_number(_coalesce_from_profile(row, "year", profile))
        month = first_number(_coalesce_from_profile(row, "month", profile))
        exam_type = _normalize_exam_type(_coalesce_from_profile(row, "exam_type", profile), month)
        subject = _coalesce_from_profile(row, "subject", profile)
        question_number = first_number(_coalesce_from_profile(row, "question_number", profile))
        stem_value = _coalesce_from_profile(row, "stem", profile)
        answer_value = _coalesce_from_profile(row, "answer", profile)
        solution_outline = _coalesce_from_profile(row, "solution_outline", profile)
        raw_points, points_source = _coalesce_with_source(row, "points", profile)
        points = _normalize_points(raw_points)
        common_raw, common_source = _coalesce_with_source(row, "common_section", profile)

        skip_reason: Optional[str] = None
        fallback_reason: Optional[str] = None

        if year is None or year not in scope["years"]:
            skip_reason = "year_out_of_scope_or_unavailable"
        elif exam_type not in scope["exam_types"]:
            skip_reason = "exam_type_out_of_scope_or_unavailable"
        elif not _is_math_subject(subject):
            skip_reason = "subject_out_of_scope_or_unavailable"
        elif question_number is None:
            skip_reason = "question_number_unavailable"
        elif points not in scope["points"]:
            skip_reason = "points_unavailable_or_out_of_scope"

        common_section: Optional[bool] = None
        common_detection_method: Optional[str] = None
        if skip_reason is None and year is not None and question_number is not None:
            common_section, fallback_reason = _normalize_common_section(
                common_raw,
                year=year,
                question_number=question_number,
            )
            common_detection_method = common_source or fallback_reason or "unavailable"
            if common_section is not True:
                skip_reason = "common_section_out_of_scope_or_unavailable"

        if skip_reason:
            skipped_rows.append(
                {
                    "row_index": row_index,
                    "skip_reason": skip_reason,
                    "record_id": str(_coalesce_from_profile(row, "record_id", profile) or row.get("id") or row_index),
                    "year": year,
                    "month": month,
                    "exam_type": exam_type,
                    "question_number": question_number,
                    "points_detection_method": points_source or "unavailable",
                    "common_section_detection_method": common_detection_method or common_source or "unavailable",
                }
            )
            continue

        metadata = row.get(profile.resolved_fields.get("metadata") or "metadata")
        if not isinstance(metadata, dict):
            metadata = {}

        raw_stem_text = compact_whitespace(str(stem_value or ""))
        stem, parsed_choices = parse_choice_lines(raw_stem_text)
        choice_value = _coalesce_from_profile(row, "choices", profile)
        choices = _normalize_tag_value(choice_value) if choice_value is not None else parsed_choices

        problem = ScopedProblem(
            problem_id=_build_problem_id(year, exam_type, question_number),
            source_record_id=str(_coalesce_from_profile(row, "record_id", profile) or row.get("id") or row_index),
            year=year,
            month=month or (11 if exam_type == "수능" else 0),
            exam_type=exam_type,
            subject="수학",
            question_number=question_number,
            stem=stem or raw_stem_text,
            choices=choices,
            answer=compact_whitespace(str(answer_value)) or None,
            solution_outline=compact_whitespace(str(solution_outline)) or None,
            concept_tags=_collect_concept_tags(row, profile, config),
            points=points or 0,
            common_section=bool(common_section),
            metadata={
                **metadata,
                "common_section_resolution": fallback_reason or "direct",
                "common_section_detection_method": common_detection_method or common_source or "unavailable",
                "points_detection_method": points_source or "unavailable",
            },
        )
        problems.append(problem)

    return profile, problems, skipped_rows


def inspect_live_problem_db(
    config: Dict[str, Any],
    *,
    backend_override: Optional[str] = "supabase",
) -> Dict[str, Any]:
    rows, profile = _load_backend_rows(config, backend_override)
    scoped_profile, scoped_problems, skipped_rows = load_scoped_problems(config, backend_override=backend_override)
    assert scoped_profile == profile

    key_fields = [
        "year",
        "month",
        "exam_type",
        "subject",
        "question_number",
        "stem",
        "answer",
        "solution_outline",
        "concept_tags",
        "points",
        "common_section",
    ]
    null_rates: Dict[str, Dict[str, Any]] = {}
    for capability in key_fields:
        null_count = 0
        empty_count = 0
        for row in rows:
            value, source = _coalesce_with_source(row, capability, profile)
            if capability == "concept_tags":
                normalized = _collect_concept_tags(row, profile, config)
                if not normalized:
                    null_count += 1
            elif value is None:
                null_count += 1
            elif isinstance(value, str) and not compact_whitespace(value):
                empty_count += 1
            null_rates[capability] = {
                "resolved_from": source or profile.resolved_metadata_fields.get(capability) or profile.resolved_fields.get(capability),
            }
        total_rows = max(len(rows), 1)
        null_rates[capability]["null_rate"] = round(null_count / total_rows, 6)
        null_rates[capability]["empty_rate"] = round(empty_count / total_rows, 6)

    exam_type_distribution = collections.Counter()
    year_distribution = collections.Counter()
    points_distribution = collections.defaultdict(collections.Counter)
    common_detection_distribution = collections.Counter()
    four_point_detection_distribution = collections.Counter()
    drop_counts = collections.Counter(row["skip_reason"] for row in skipped_rows)

    for row in rows:
        month = first_number(_coalesce_from_profile(row, "month", profile))
        exam_type_distribution[_normalize_exam_type(_coalesce_from_profile(row, "exam_type", profile), month) or "unresolved"] += 1
        year_distribution[str(first_number(_coalesce_from_profile(row, "year", profile)) or "unresolved")] += 1

        for alias in config["field_aliases"]["points"]["columns"]:
            if alias in row:
                points_distribution[f"column:{alias}"][str(_normalize_points(row.get(alias)))] += 1
        metadata = row.get(profile.resolved_fields.get("metadata") or "metadata")
        if isinstance(metadata, dict):
            for alias in config["field_aliases"]["points"]["metadata_keys"]:
                if alias in metadata:
                    points_distribution[f"metadata:{alias}"][str(_normalize_points(metadata.get(alias)))] += 1

        raw_points, points_source = _coalesce_with_source(row, "points", profile)
        normalized_points = _normalize_points(raw_points)
        if normalized_points == 4:
            four_point_detection_distribution[points_source or "unavailable"] += 1
        else:
            four_point_detection_distribution[f"{points_source or 'unavailable'}:{normalized_points}"] += 1

        year = first_number(_coalesce_from_profile(row, "year", profile)) or 0
        question_number = first_number(_coalesce_from_profile(row, "question_number", profile)) or 0
        common_raw, common_source = _coalesce_with_source(row, "common_section", profile)
        _, fallback_reason = _normalize_common_section(common_raw, year=year, question_number=question_number)
        common_detection_distribution[common_source or fallback_reason or "unavailable"] += 1

    report = {
        "table_name": profile.table_name,
        "backend": profile.backend,
        "inspection_mode": profile.introspection_mode,
        "mapping_decisions": {
            "resolved_fields": profile.resolved_fields,
            "resolved_metadata_fields": profile.resolved_metadata_fields,
            "warnings": profile.warnings,
            "excluded_capabilities": profile.excluded_capabilities,
        },
        "total_rows_sampled": len(rows),
        "available_columns": profile.available_columns,
        "metadata_keys": profile.metadata_keys,
        "null_rates": null_rates,
        "exam_type_distribution": dict(sorted(exam_type_distribution.items())),
        "year_distribution": dict(sorted(year_distribution.items())),
        "points_related_distribution": {
            key: dict(sorted(counter.items()))
            for key, counter in sorted(points_distribution.items())
        },
        "common_section_detection": dict(sorted(common_detection_distribution.items())),
        "four_point_detection": dict(sorted(four_point_detection_distribution.items())),
        "row_counts_dropped_by_filter": dict(sorted(drop_counts.items())),
        "final_scoped_problem_count": len(scoped_problems),
        "final_scoped_problem_ids": [problem.problem_id for problem in scoped_problems],
    }
    return report


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Load and inspect doctrine problem DB inputs.")
    parser.add_argument("--config", default="configs/doctrine_pipeline.yaml")
    parser.add_argument("--inspect", action="store_true", help="Inspect the live problem DB and write a validation report.")
    parser.add_argument("--problem-backend", choices=["supabase", "fixture"], default=None)
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = load_pipeline_config(args.config)
    if args.inspect:
        backend = args.problem_backend or "supabase"
        report = inspect_live_problem_db(config, backend_override=backend)
        output_path = Path(config["paths"]["logs"]) / "problem_db_live_inspection.json"
        write_json(output_path, report)
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
        return

    profile, problems, skipped = load_scoped_problems(config, backend_override=args.problem_backend)
    payload = {
        "profile": profile.model_dump(),
        "scoped_problem_count": len(problems),
        "skipped_rows": len(skipped),
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
