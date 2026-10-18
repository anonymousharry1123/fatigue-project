#!/usr/bin/env python3
"""Fit a private, retrospective sleep-hours -> raw Energy experiment.

Usage:
    python3 tool/experimental_sleep_model.py --input normalized.json --output run/

The caller must verify genuine source records and construct the documented
normalized envelope. A supplied ``verified_non_demo`` tag is NOT independently
authenticated here. This tool neither queries a database nor activates a model.
Only the Python standard library is required. Invalid input fails closed rather
than silently dropping observations and changing the analysis population.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import date, datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile
from typing import Any


INPUT_VERSION = "tonyo-experimental-sleep-input-v1"
MODEL_VERSION = "tonyo-experimental-sleep-ols-v1"
REPORT_VERSION = "tonyo-experimental-sleep-report-v1"
EVIDENCE_KIND = "retrospective_database_extract"
ROW_FIELDS = {
    "participant", "local_date", "sleep_hours", "energy_1_to_10",
    "sleep_source", "measurement_key", "provenance",
}
LIMITATIONS = [
    "Experimental retrospective association only; no causal, prospective, "
    "clinical, or population-generalization claims.",
    "The supplied verified_non_demo provenance tag is not independently "
    "authenticated by this trainer. Source verification remains the caller's responsibility.",
    "The chronological 80/20 split is a prespecified engineering choice, "
    "not an established sample-size or scientific sufficiency threshold.",
    "All holdout results, particularly tiny holdouts, are exploratory. "
    "Repeated evaluation can make a holdout unsuitable for future final validation.",
    "Mutable database history cannot establish original feature availability "
    "or prospective prediction timing. Missing days and selection bias are not "
    "recoverable from normalized paired rows alone.",
    "Flexible retrospective collection may include sleep saved after Energy and "
    "Energy measured at different times of day. This one-feature association "
    "does not adjust for time of day or validate a prediction made before Energy.",
    "The fitted artifact is not approved for activation or app integration.",
]


class InputError(ValueError):
    """The extract cannot be used without repairing its source/normalization."""


def _number(value: Any, field: str, index: int) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InputError(f"Row {index}: {field} must be a finite number.")
    try:
        result = float(value)
    except (OverflowError, ValueError) as error:
        raise InputError(f"Row {index}: {field} must be a finite number.") from error
    if not math.isfinite(result):
        raise InputError(f"Row {index}: {field} must be a finite number.")
    return result


def validate_input(payload: Any) -> list[dict[str, Any]]:
    """Validate normalized data without inferring missing values or provenance.

    Each row contains exactly ROW_FIELDS. Participant must be a pseudonymous
    identifier; measurement_key separates questionnaire/wording/language cohorts.
    The input sourceSnapshot may contain source metadata, but only the bounded
    safe fields in _safe_source_snapshot are reproduced in artifacts.
    """
    if not isinstance(payload, dict):
        raise InputError("Input must be a JSON object.")
    if payload.get("schemaVersion") != INPUT_VERSION:
        raise InputError(f"schemaVersion must be {INPUT_VERSION}.")
    if payload.get("evidenceKind") != EVIDENCE_KIND:
        raise InputError(f"evidenceKind must be {EVIDENCE_KIND}.")
    if not isinstance(payload.get("rows"), list):
        raise InputError("rows must be a JSON array.")
    if "sourceSnapshot" in payload and not isinstance(payload["sourceSnapshot"], dict):
        raise InputError("sourceSnapshot must be an object when supplied.")
    rows = []
    for index, raw in enumerate(payload["rows"], 1):
        if not isinstance(raw, dict) or set(raw) != ROW_FIELDS:
            raise InputError(f"Row {index}: exact normalized row fields are required.")
        participant = raw["participant"]
        if not isinstance(participant, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,63}", participant):
            raise InputError(f"Row {index}: participant must be a pseudonymous identifier.")
        local_date = raw["local_date"]
        if not isinstance(local_date, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", local_date):
            raise InputError(f"Row {index}: local_date must be YYYY-MM-DD.")
        try:
            date.fromisoformat(local_date)
        except ValueError as error:
            raise InputError(f"Row {index}: local_date is not a valid calendar date.") from error
        if raw["sleep_source"] not in ("manual", "healthKit"):
            raise InputError(f"Row {index}: sleep_source must be manual or healthKit.")
        key = raw["measurement_key"]
        if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:/-]{0,159}", key):
            raise InputError(f"Row {index}: measurement_key must be a nonempty measurement identifier.")
        if raw["provenance"] != "verified_non_demo":
            raise InputError(f"Row {index}: verified_non_demo provenance is required.")
        sleep = _number(raw["sleep_hours"], "sleep_hours", index)
        energy = _number(raw["energy_1_to_10"], "energy_1_to_10", index)
        if not 0.5 <= sleep <= 16:
            raise InputError(f"Row {index}: sleep_hours must be in [0.5, 16].")
        if not 1 <= energy <= 10 or not energy.is_integer():
            raise InputError(f"Row {index}: energy_1_to_10 must be an integer in [1, 10].")
        rows.append({**raw, "sleep_hours": sleep, "energy_1_to_10": int(energy)})
    return rows


def _safe_source_snapshot(value: dict[str, Any]) -> dict[str, Any]:
    """Copy only fixed source types, UTC times, and nonnegative integer counts.

    Unknown/free-text metadata, URLs, account IDs, database paths, and credentials
    are never echoed. This whitelist is output hygiene, not source authentication.
    """
    safe = {}
    if value.get("source_type") in ("firestore", "local_database", "account_backup"):
        safe["source_type"] = value["source_type"]
    stamp = value.get("extracted_at_utc")
    if isinstance(stamp, str) and stamp.endswith(("Z", "+00:00")):
        try:
            parsed = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
            if parsed.utcoffset() == timezone.utc.utcoffset(parsed):
                safe["extracted_at_utc"] = parsed.isoformat()
        except ValueError:
            pass
    for field in ("account_count", "signal_count", "check_in_count", "normalized_row_count"):
        item = value.get(field)
        if isinstance(item, int) and not isinstance(item, bool) and item >= 0:
            safe[field] = item
    return safe


def _clip(value: float) -> float:
    return max(1.0, min(10.0, value))


def _mae(predictions: list[float], actuals: list[int]) -> float:
    return math.fsum(abs(prediction - actual) for prediction, actual in zip(predictions, actuals)) / len(actuals)


def train(payload: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    """Return an inactive model artifact and report, including blocked cohorts.

    Each participant/source/measurement cohort is independent. Whole calendar
    dates are ordered before splitting: ceil(n/5) final rows are held out, and
    everything earlier trains OLS and both frozen baselines. Holdout targets are
    used only for scoring. Duplicate dates block their entire cohort.
    """
    rows = validate_input(payload)
    groups: dict[tuple[str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        groups[(row["participant"], row["sleep_source"], row["measurement_key"])].append(row)
    models, cohorts = [], []
    for (participant, source, measurement), group in sorted(groups.items()):
        ordered = sorted(group, key=lambda row: row["local_date"])
        count = len(ordered)
        holdout_count = max(1, (count + 4) // 5)
        training_count = count - holdout_count
        cohort: dict[str, Any] = {
            "participant": participant,
            "sleep_source": source,
            "measurement_key": measurement,
            "row_count": count,
            "training_count": training_count,
            "holdout_count": holdout_count,
            "status": "blocked",
            "reasons": [],
        }
        cohorts.append(cohort)
        if len({row["local_date"] for row in ordered}) != count:
            cohort["reasons"].append("duplicate_local_date_within_cohort")
        if training_count < 2:
            cohort["reasons"].append("fewer_than_two_training_rows")
        if cohort["reasons"]:
            continue
        training = ordered[:training_count]
        holdout = ordered[training_count:]
        x = [row["sleep_hours"] for row in training]
        y = [row["energy_1_to_10"] for row in training]
        if len(set(x)) < 2:
            cohort["reasons"].append("no_sleep_variation_in_training")
            continue
        x_mean = math.fsum(x) / training_count
        y_mean = math.fsum(y) / training_count
        ss_x = math.fsum((value - x_mean) ** 2 for value in x)
        if ss_x <= 0:
            cohort["reasons"].append("unresolvable_training_sleep_variation")
            continue
        slope = math.fsum((a - x_mean) * (b - y_mean) for a, b in zip(x, y)) / ss_x
        intercept = y_mean - slope * x_mean
        raw_predictions = [intercept + slope * row["sleep_hours"] for row in holdout]
        if not all(math.isfinite(value) for value in [slope, intercept, *raw_predictions]):
            cohort["reasons"].append("nonfinite_fit_or_prediction")
            continue
        predictions = [_clip(value) for value in raw_predictions]
        actuals = [row["energy_1_to_10"] for row in holdout]
        mean_predictions = [y_mean] * holdout_count
        last_predictions = [float(y[-1])] * holdout_count
        scores = {
            "ols_clipped_mae": _mae(predictions, actuals),
            "frozen_training_mean_mae": _mae(mean_predictions, actuals),
            "frozen_last_training_outcome_mae": _mae(last_predictions, actuals),
        }
        cohort.update({
            "status": "fitted_exploratory",
            "evaluation": "exploratory_chronological_holdout",
            "training_date_range": [training[0]["local_date"], training[-1]["local_date"]],
            "holdout_date_range": [holdout[0]["local_date"], holdout[-1]["local_date"]],
            "training_sleep_range_hours": [min(x), max(x)],
            "training_energy_range": [min(y), max(y)],
            "scores": scores,
            "holdout_predictions": [
                {
                    "holdout_index": index,
                    "ols_raw": raw,
                    "ols_clipped": clipped,
                    "frozen_training_mean": y_mean,
                    "frozen_last_training_outcome": y[-1],
                }
                for index, (raw, clipped) in enumerate(zip(raw_predictions, predictions), 1)
            ],
        })
        models.append({
            "participant": participant,
            "sleep_source": source,
            "measurement_key": measurement,
            "training_count": training_count,
            "holdout_count": holdout_count,
            "formula": "raw_energy = intercept + slope * sleep_hours; prediction = clip(raw_energy, 1, 10)",
            "intercept": intercept,
            "slope": slope,
            "training_sleep_mean_hours": x_mean,
            "training_energy_mean": y_mean,
            "last_training_outcome": y[-1],
            "training_sleep_range_hours": [min(x), max(x)],
            "training_date_range": [training[0]["local_date"], training[-1]["local_date"]],
            "holdout_date_range": [holdout[0]["local_date"], holdout[-1]["local_date"]],
            "activation_allowed": False,
        })
    common = {
        "evidenceKind": EVIDENCE_KIND,
        "status": "experimental_not_for_activation",
        "activation_allowed": False,
        "normalized_input_sha256": hashlib.sha256(json.dumps(
            sorted(rows, key=lambda row: (row["participant"], row["sleep_source"],
                                         row["measurement_key"], row["local_date"])),
            sort_keys=True, separators=(",", ":"), allow_nan=False,
        ).encode("utf-8")).hexdigest(),
        "limitations": LIMITATIONS.copy(),
        "sourceSnapshot": _safe_source_snapshot(payload.get("sourceSnapshot", {})),
    }
    artifact = {**common, "schemaVersion": MODEL_VERSION, "models": models}
    report = {
        **common,
        "schemaVersion": REPORT_VERSION,
        "split_policy": "Within each cohort, sort local_date ascending; final ceil(n/5) rows hold out; earlier rows train. No refit after holdout scoring.",
        "baseline_policy": "Training mean and final training outcome remain frozen across the identical holdout rows.",
        "row_count": len(rows),
        "cohort_count": len(cohorts),
        "fitted_cohort_count": len(models),
        "blocked_cohort_count": len(cohorts) - len(models),
        "overall_result": "exploratory_models_fitted" if models else "no_model_fitted",
        "reasons": [] if cohorts else ["no_normalized_rows"],
        "cohorts": cohorts,
    }
    return artifact, report


def _write_private_json(path: Path, payload: dict[str, Any]) -> None:
    """Replace each output atomically with mode 0600; never follow file symlinks."""
    descriptor, temporary = tempfile.mkstemp(prefix=".sleep-model-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Verified normalized JSON extract")
    parser.add_argument("--output", required=True, type=Path, help="Private output directory")
    args = parser.parse_args(argv)
    try:
        if args.input.resolve() in {
            (args.output / filename).resolve() for filename in ("model.json", "report.json")
        }:
            raise InputError("Input must not be one of the output artifact files.")
        with args.input.open(encoding="utf-8") as stream:
            artifact, report = train(json.load(stream))
        if args.output.is_symlink():
            raise InputError("Output directory must not be a symlink.")
        args.output.mkdir(mode=0o700, parents=True, exist_ok=True)
        args.output.chmod(0o700)
        _write_private_json(args.output / "model.json", artifact)
        _write_private_json(args.output / "report.json", report)
    except (OSError, ValueError, TypeError) as error:
        # Validation messages never include source values or identifiers.
        parser.exit(2, f"Experimental training failed: {error}\n")
    print(f"Rows: {report['row_count']}; fitted cohorts: {report['fitted_cohort_count']}; "
          f"blocked cohorts: {report['blocked_cohort_count']}. Experimental; activation disabled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
