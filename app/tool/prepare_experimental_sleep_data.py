#!/usr/bin/env python3
"""Prepare an existing Tonyo ResearchExport for the inactive experimental trainer.

Usage: python3 tool/prepare_experimental_sleep_data.py --input export.json --output private-run/

Only app-produced tonyo-measurement-export-v1 JSON is supported. The caller is
trusting the supplied file to be an actual app export: its non-demo filtering is
the provenance basis, not independent authentication by this adapter. These are
mutable retrospective observations, never reconstructed prospective snapshots.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


EXPORT_VERSION = "tonyo-measurement-export-v1"
MEASUREMENT_VERSION = "tonyo-self-report-draft-v1"
PAIRING_POLICY = "flexible-evening-retrospective-v1"
ITEMS = ("energy", "fatigue", "sleepiness", "focus", "mood", "stress")
DEMO = re.compile(r"(^|[^a-z])(seed(?:ed)?|synthetic|fake|demo|fixture|cohort)([^a-z]|$)", re.I)
IDENTITY_KEYS = {
    "studycode", "study_code", "id", "uid", "sourceid", "source_id",
    "sourcekey", "source_key", "groupid", "group_id", "participant",
    "participantid", "participant_id", "source", "origin", "provenance",
    "note", "response_ref", "sleep_ref", "definition_ref",
}
PROVENANCE_BASIS = (
    "The caller supplies this file as an actual Tonyo ResearchExport produced by "
    "the app's non-demo filter. verified_non_demo is carried forward on that "
    "source-format trust; this adapter does not independently authenticate the "
    "file or infer genuineness merely from absence of synthetic markers."
)


class PreparationError(ValueError):
    """Unsupported or ambiguous source data; do not guess its interpretation."""


def _unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PreparationError("Duplicate JSON object keys, including definitions, are not supported.")
        result[key] = value
    return result


def load_export(path: Path) -> Any:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream, object_pairs_hook=_unique_keys)


def _check_markers(value: Any) -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            if str(key).lower() in IDENTITY_KEYS and isinstance(item, str):
                if DEMO.search(item) or item.lower().startswith("syn-"):
                    raise PreparationError("Synthetic/demo marker in source identity metadata.")
            _check_markers(item)
    elif isinstance(value, list):
        for item in value:
            _check_markers(item)


def _utc(value: Any) -> datetime:
    if not isinstance(value, str):
        raise ValueError("time_missing")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        raise ValueError("time_not_utc")
    return parsed.astimezone(timezone.utc)


def _finite(value: Any) -> bool:
    try:
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
    except OverflowError:
        return False


def _definition(value: Any) -> str | None:
    """Return hash of the exact valid English definition, preserving wording."""
    if not isinstance(value, dict) or set(value) != {
        "version", "language", "kind", "status", "recallPeriod", "recallPeriodText", "items"
    }:
        return None
    if (value["version"] != MEASUREMENT_VERSION or value["language"] != "en"
            or value["kind"] != "customSelfReport"
            or value["status"] != "draftNotClinicallyValidated"
            or value["recallPeriod"] != "right now"
            or value["recallPeriodText"] != "right now"):
        return None
    items = value["items"]
    if not isinstance(items, list) or len(items) != 6:
        return None
    for expected, item in zip(ITEMS, items):
        if not isinstance(item, dict) or set(item) != {"id", "label", "prompt", "anchors", "optional"}:
            return None
        if item["id"] != expected or item["optional"] is not True:
            return None
        if not isinstance(item["label"], str) or not 1 <= len(item["label"]) <= 100:
            return None
        if not isinstance(item["prompt"], str) or len(item["prompt"]) > 500:
            return None
        anchors = item["anchors"]
        if not isinstance(anchors, dict) or set(anchors) != {"1", "5", "10"}:
            return None
        if any(not isinstance(text, str) or not 1 <= len(text) <= 300 for text in anchors.values()):
            return None
    canonical = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _indexed(rows: Any, field: str) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list):
        raise PreparationError("Expected an array of source records.")
    result = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get(field), str) or not row[field]:
            raise PreparationError("Source record reference is missing or invalid.")
        if row[field] in result:
            raise PreparationError("Duplicate source references are ambiguous; no records were prepared.")
        result[row[field]] = row
    return result


def prepare(payload: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    """Select first compatible evening response per date BEFORE inspecting Energy.

    Invalid/missing Energy or unavailable sleep on the selected row never causes
    fallback to a later response. Sources and exact definition hashes remain
    separate trainer cohorts. A trusted app export excludes demo/legacy records;
    this adapter still validates its format, chronology, bounds, and references.
    Evening is a participant-selected period, with no wall-clock window. Sleep
    may be saved later, but must have ended within 24 hours before the response.
    Each sleep record is reserved for its first selected response before Energy
    is inspected, preventing repeated sleep from crossing train/holdout dates.
    """
    if not isinstance(payload, dict) or payload.get("exportVersion") != EXPORT_VERSION:
        raise PreparationError("Only tonyo-measurement-export-v1 ResearchExport JSON is supported.")
    # Scan actual record metadata, not explanatory dictionaries. The genuine
    # app dictionary itself says that its source excludes "demo" observations.
    _check_markers({
        "studyCode": payload.get("studyCode"),
        "responses": payload.get("responses"),
        "sleepObservations": payload.get("sleepObservations"),
    })
    study_code = payload.get("studyCode")
    if not isinstance(study_code, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,31}", study_code):
        raise PreparationError("A valid app export study code is required.")
    try:
        generated = _utc(payload.get("generatedAtUtc"))
    except (ValueError, TypeError, OverflowError) as error:
        raise PreparationError("A valid UTC export generation time is required.") from error
    definitions = payload.get("questionnaireDefinitions")
    if not isinstance(definitions, dict):
        raise PreparationError("Saved questionnaire definitions are required.")
    definition_hashes = {key: _definition(value) for key, value in definitions.items()}
    sleeps = _indexed(payload.get("sleepObservations"), "sleep_ref")
    responses = _indexed(payload.get("responses"), "response_ref")
    excluded: Counter[str] = Counter()
    candidates = defaultdict(list)
    for row in responses.values():
        if (row.get("questionnaire_version") != MEASUREMENT_VERSION
                or row.get("questionnaire_language") != "en"
                or row.get("source") != "selfReport" or row.get("period") != "evening"):
            excluded["incompatible_measurement_source_or_period"] += 1
            continue
        definition_hash = definition_hashes.get(row.get("definition_ref"))
        if definition_hash is None:
            excluded["missing_or_invalid_definition"] += 1
            continue
        if row.get("study_code") != study_code:
            excluded["study_code_mismatch"] += 1
            continue
        try:
            local_date = row["local_date"]
            if not isinstance(local_date, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", local_date):
                raise ValueError("invalid_date")
            day = date.fromisoformat(local_date)
            zone_name = row["timezone"]
            if not isinstance(zone_name, str):
                raise ValueError("timezone_missing")
            zone = ZoneInfo(zone_name)
            offset = row["utc_offset_minutes"]
            if not isinstance(offset, int) or isinstance(offset, bool):
                raise ValueError("invalid_offset")
            observed, recorded = _utc(row["observed_at_utc"]), _utc(row["recorded_at_utc"])
            local_observed = observed.astimezone(zone)
            if (local_observed.date() != day
                    or int(local_observed.utcoffset().total_seconds() // 60) != offset
                    or not observed <= recorded <= generated):
                raise ValueError("invalid_response_timing")
        except (KeyError, ValueError, TypeError, OverflowError, ZoneInfoNotFoundError):
            excluded["invalid_response_date_timezone_or_timing"] += 1
            continue
        candidates[local_date].append((observed, recorded, row["response_ref"], row, definition_hash, zone))
    selected_responses = []
    for options in candidates.values():
        selected_responses.append(min(options, key=lambda item: item[:3]))
        excluded["later_compatible_response_same_date"] += len(options) - 1
    normalized = []
    selected_sleep_refs = set()
    for selected in sorted(selected_responses, key=lambda item: item[:3]):
        observed, _, _, row, definition_hash, zone = selected
        local_date = row["local_date"]
        sleep_ref = row.get("sleep_ref")
        sleep = sleeps.get(sleep_ref) if isinstance(sleep_ref, str) else None
        if row.get("sleep_match_status") == "matched" and sleep is not None:
            if sleep_ref in selected_sleep_refs:
                excluded["sleep_already_selected_by_earlier_response"] += 1
                continue
            selected_sleep_refs.add(sleep_ref)
        # The selection above deliberately does not read any rating value.
        energy = row.get("energy_1_to_10")
        if energy is None:
            excluded["selected_first_response_missing_energy"] += 1
            continue
        ratings = [row.get(f"{item}_1_to_10") for item in ITEMS]
        answered = [rating for rating in ratings if rating is not None]
        if (any(not _finite(rating) or not 1 <= rating <= 10 or int(rating) != rating for rating in answered)
                or isinstance(row.get("answered_item_count"), bool)
                or row.get("answered_item_count") != len(answered)
                or row.get("completion_status") != ("complete" if len(answered) == 6 else "partial")):
            excluded["selected_response_invalid_ratings_or_completeness"] += 1
            continue
        if row.get("sleep_match_status") != "matched" or sleep is None:
            excluded["selected_response_sleep_unmatched"] += 1
            continue
        duration = sleep.get("duration_hours")
        row_duration = row.get("sleep_hours")
        quality = sleep.get("quality")
        source = sleep.get("source")
        if (source not in ("manual", "healthKit") or not _finite(duration)
                or not 0.5 <= duration <= 16 or not _finite(row_duration)
                or abs(row_duration - duration) > 1e-9
                or not _finite(quality) or not 0 < quality <= 1):
            excluded["selected_response_invalid_sleep"] += 1
            continue
        if sleep.get("availability_known") is not True or row.get("sleep_pair_availability_known") is not True:
            excluded["sleep_availability_unknown"] += 1
            continue
        try:
            ended = _utc(sleep["sleep_end_at_utc"])
            available = _utc(sleep["record_available_at_utc"])
            pair_available = _utc(row["sleep_pair_available_at_utc"])
            availability_parts = [_utc(sleep[key]) for key in ("recorded_at_utc", "synced_at_utc") if sleep.get(key) is not None]
            if (not availability_parts or available != max(availability_parts)
                    or any(value < ended for value in availability_parts)
                    or not available <= pair_available <= generated):
                raise ValueError("invalid_availability")
            if ended > observed:
                excluded["sleep_ended_after_response"] += 1
                continue
            if observed - ended > timedelta(hours=24):
                excluded["sleep_ended_more_than_24_hours_before_response"] += 1
                continue
        except (KeyError, ValueError, TypeError, OverflowError):
            excluded["invalid_sleep_availability_metadata"] += 1
            continue
        # Separate captured zones as well as exact definitions. A prospective
        # plan's frozen zone and full heading are not available in this export.
        cohort_hash = hashlib.sha256(f"{definition_hash}|{zone.key}".encode("utf-8")).hexdigest()
        normalized.append({
            "participant": "participant-1",
            "local_date": local_date,
            "sleep_hours": float(duration),
            "energy_1_to_10": int(energy),
            "sleep_source": source,
            "measurement_key": f"{MEASUREMENT_VERSION}:en:{PAIRING_POLICY}:{cohort_hash}",
            "provenance": "verified_non_demo",
        })
    output = {
        "schemaVersion": "tonyo-experimental-sleep-input-v1",
        "evidenceKind": "retrospective_database_extract",
        "sourceSnapshot": {"extracted_at_utc": generated.isoformat(), "account_count": 1,
                           "check_in_count": len(responses), "normalized_row_count": len(normalized)},
        "rows": sorted(normalized, key=lambda row: row["local_date"]),
    }
    report = {
        "schemaVersion": "tonyo-experimental-sleep-preparation-v1",
        "source_export_version": EXPORT_VERSION,
        "pairing_policy_version": PAIRING_POLICY,
        "evidenceKind": "retrospective_database_extract",
        "provenance_basis": PROVENANCE_BASIS,
        "input_response_count": len(responses),
        "input_sleep_observation_count": len(sleeps),
        "candidate_local_date_count": len(candidates),
        "normalized_row_count": len(normalized),
        "exclusions": dict(sorted((key, value) for key, value in excluded.items() if value)),
        "selection_policy": "First compatible English Evening-labelled response per local date, at any time, ordered by observation time, save time, then export-local response reference. Each matched sleep reference is reserved for its earliest selected response. Selection precedes checking Energy; no later-row fallback. Morning responses remain separate and are not targets.",
        "sleep_pairing_policy": "Main sleep must end within the 24 hours before the response, including the boundary. The actual response local date is retained, including after-midnight entries. There is no morning save cutoff or evening response window. Known sleep and pair availability may be after the response but must be no later than export generation.",
        "limitations": [
            PROVENANCE_BASIS,
            "Retrospective database-derived observations only. Exported mutable save times do not prove initial save, immutable morning snapshots, or original issuing-device availability.",
            "This adapter cannot recover omitted days, edits, deletions, or missing source records. A late upload is not independently distinguishable from a later original save.",
            "Clock-free retrospective policy: participant-selected Evening responses are accepted at any time; save times can cross midnight. Sleep may be saved after Energy, so these pairs are not evidence that sleep was available to a prediction made before Energy. Raw ratings remain 1–10.",
            "Pairing policy version, exact saved definition, captured timezone and sleep source separate cohorts. Flexible collection can change the time of day at which Energy is measured; time-of-day variation is not adjusted by this one-feature experiment.",
            "Captured IANA timezone is included with the exact definition hash in the cohort key; changed zones are not pooled. ResearchExport does not capture the original shared heading or a plan's frozen timezone, so exact AI-1 presentation/prospective compatibility is not asserted.",
            "No model activation or scientific sufficiency determination is performed.",
        ],
        "activation_allowed": False,
    }
    return output, report


def _write(path: Path, value: Any) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=".sleep-preparation-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream, sort_keys=True, indent=2, allow_nan=False)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.input.resolve() in {(args.output / name).resolve() for name in ("normalized.json", "preparation_report.json")}:
            raise PreparationError("An output artifact must not overwrite the source export.")
        output, report = prepare(load_export(args.input))
        if args.output.is_symlink():
            raise PreparationError("Output directory must not be a symlink.")
        args.output.mkdir(mode=0o700, parents=True, exist_ok=True)
        args.output.chmod(0o700)
        _write(args.output / "normalized.json", output)
        _write(args.output / "preparation_report.json", report)
    except (OSError, ValueError, TypeError) as error:
        parser.exit(2, f"Preparation failed: {error}\n")
    print(f"Prepared {len(output['rows'])} retrospective rows from {report['input_response_count']} responses. Activation disabled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
