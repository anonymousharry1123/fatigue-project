"""Meaningful trainer checks: python3 -m unittest discover -s tool -p 'test_experimental_sleep_model.py'."""

from copy import deepcopy
from datetime import date, timedelta
import json
import math
from pathlib import Path
import tempfile
import unittest

from experimental_sleep_model import EVIDENCE_KIND, INPUT_VERSION, InputError, main, train


def envelope(xs=(2, 3, 4, 5, 6), ys=(3, 4, 5, 6, 7), **cohort):
    return {
        "schemaVersion": INPUT_VERSION,
        "evidenceKind": EVIDENCE_KIND,
        "rows": [
            {
                "participant": "person_a",
                "local_date": (date(2026, 1, 1) + timedelta(days=index)).isoformat(),
                "sleep_hours": x,
                "energy_1_to_10": y,
                "sleep_source": "manual",
                "measurement_key": "draft-v1:en",
                "provenance": "verified_non_demo",
                **cohort,
            }
            for index, (x, y) in enumerate(zip(xs, ys))
        ],
    }


class ExperimentalSleepModelTests(unittest.TestCase):
    def test_known_coefficients_and_independent_baselines(self):
        artifact, report = train(envelope())
        model = artifact["models"][0]
        self.assertAlmostEqual(model["slope"], 1)
        self.assertAlmostEqual(model["intercept"], 1)
        cohort = report["cohorts"][0]
        self.assertEqual((cohort["training_count"], cohort["holdout_count"]), (4, 1))
        self.assertEqual(cohort["scores"], {
            "ols_clipped_mae": 0.0,
            "frozen_training_mean_mae": 2.5,
            "frozen_last_training_outcome_mae": 1.0,
        })
        self.assertFalse(artifact["activation_allowed"])
        self.assertIn("not independently authenticated", " ".join(artifact["limitations"]))

    def test_holdout_outcome_changes_scores_never_model_or_baselines(self):
        original = envelope()
        changed = deepcopy(original)
        changed["rows"][-1]["energy_1_to_10"] = 1
        model_before, report_before = train(original)
        model_after, report_after = train(changed)
        self.assertEqual(model_before["models"], model_after["models"])
        self.assertNotEqual(model_before["normalized_input_sha256"],
                            model_after["normalized_input_sha256"])
        self.assertEqual(report_before["cohorts"][0]["holdout_predictions"],
                         report_after["cohorts"][0]["holdout_predictions"])
        self.assertEqual(report_after["cohorts"][0]["scores"]["ols_clipped_mae"], 6)

    def test_all_holdout_outcomes_stay_out_of_frozen_baselines(self):
        payload = envelope(xs=(2, 3, 4, 5, 6, 7), ys=(3, 4, 5, 6, 1, 10))
        _, report = train(payload)
        cohort = report["cohorts"][0]
        self.assertEqual((cohort["training_count"], cohort["holdout_count"]), (4, 2))
        self.assertEqual([r["frozen_last_training_outcome"] for r in cohort["holdout_predictions"]], [6, 6])
        self.assertEqual([r["frozen_training_mean"] for r in cohort["holdout_predictions"]], [4.5, 4.5])

    def test_constant_training_sleep_blocks_even_if_holdout_varies(self):
        artifact, report = train(envelope(xs=(4, 4, 4, 4, 6)))
        self.assertEqual(artifact["models"], [])
        self.assertEqual(report["cohorts"][0]["reasons"], ["no_sleep_variation_in_training"])

    def test_duplicate_date_blocks_entire_cohort(self):
        payload = envelope()
        payload["rows"][-1]["local_date"] = payload["rows"][0]["local_date"]
        artifact, report = train(payload)
        self.assertEqual(artifact["models"], [])
        self.assertIn("duplicate_local_date_within_cohort", report["cohorts"][0]["reasons"])

    def test_tiny_cohorts_and_empty_input_produce_no_fake_model(self):
        for count in (1, 2):
            with self.subTest(count=count):
                payload = envelope()
                payload["rows"] = payload["rows"][:count]
                artifact, report = train(payload)
                self.assertEqual(artifact["models"], [])
                self.assertIn("fewer_than_two_training_rows", report["cohorts"][0]["reasons"])
        artifact, report = train(envelope(xs=(), ys=()))
        self.assertEqual(artifact["models"], [])
        self.assertEqual(report["reasons"], ["no_normalized_rows"])

    def test_invalid_numbers_dates_fields_and_provenance_fail_closed(self):
        invalid = [
            ("sleep_hours", None), ("sleep_hours", math.inf),
            ("sleep_hours", math.nan), ("sleep_hours", 0.49),
            ("sleep_hours", 16.01), ("sleep_hours", True),
            ("energy_1_to_10", 3.5), ("energy_1_to_10", 0),
            ("energy_1_to_10", 11), ("energy_1_to_10", math.inf),
            ("energy_1_to_10", False), ("local_date", "2026-02-30"),
            ("local_date", "2026-1-01"), ("sleep_source", "model"),
            ("provenance", "synthetic"), ("measurement_key", ""),
        ]
        for field, value in invalid:
            with self.subTest(field=field, value=value):
                payload = envelope()
                payload["rows"][0][field] = value
                with self.assertRaises(InputError):
                    train(payload)
        payload = envelope()
        del payload["rows"][0]["energy_1_to_10"]
        with self.assertRaises(InputError):
            train(payload)

    def test_current_envelope_required(self):
        for field, value in (("schemaVersion", "unknown"), ("evidenceKind", "synthetic"), ("rows", None)):
            payload = envelope()
            payload[field] = value
            with self.subTest(field=field), self.assertRaises(InputError):
                train(payload)

    def test_chronology_is_deterministic_with_unsorted_input(self):
        payload = envelope()
        expected = train(payload)
        payload["rows"].reverse()
        self.assertEqual(train(payload), expected)

    def test_cohort_isolation_for_person_source_and_measurement(self):
        payload = envelope()
        payload["rows"] += envelope(ys=(7, 6, 5, 4, 3), participant="person_b")["rows"]
        payload["rows"] += envelope(sleep_source="healthKit")["rows"][:2]
        payload["rows"] += envelope(measurement_key="draft-v2:en")["rows"][:2]
        artifact, report = train(payload)
        self.assertEqual(report["cohort_count"], 4)
        self.assertEqual(report["fitted_cohort_count"], 2)
        self.assertEqual(report["blocked_cohort_count"], 2)
        slopes = {model["participant"]: model["slope"] for model in artifact["models"]}
        self.assertEqual(slopes, {"person_a": 1.0, "person_b": -1.0})

    def test_raw_predictions_preserved_but_mae_uses_clipped_prediction(self):
        artifact, report = train(envelope(xs=(1, 2, 3, 4, 16), ys=(1, 3, 5, 7, 10)))
        self.assertAlmostEqual(artifact["models"][0]["intercept"], -1)
        prediction = report["cohorts"][0]["holdout_predictions"][0]
        self.assertEqual(prediction["ols_raw"], 31)
        self.assertEqual(prediction["ols_clipped"], 10)
        self.assertEqual(report["cohorts"][0]["scores"]["ols_clipped_mae"], 0)

    def test_source_metadata_does_not_echo_account_ids_or_free_text(self):
        payload = envelope()
        payload["sourceSnapshot"] = {
            "source_type": "firestore", "account_count": 1,
            "account_id": "must-not-echo", "note": "must-not-echo",
            "extracted_at_utc": "2026-10-18T20:00:00Z",
        }
        artifact, report = train(payload)
        self.assertNotIn("must-not-echo", json.dumps([artifact, report]))
        self.assertEqual(report["sourceSnapshot"]["account_count"], 1)

    def test_cli_writes_private_inactive_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            source = folder / "input.json"
            source.write_text(json.dumps(envelope()), encoding="utf-8")
            output = folder / "result"
            self.assertEqual(main(["--input", str(source), "--output", str(output)]), 0)
            self.assertEqual(output.stat().st_mode & 0o777, 0o700)
            for filename in ("model.json", "report.json"):
                artifact = output / filename
                self.assertEqual(artifact.stat().st_mode & 0o777, 0o600)
                self.assertFalse(json.loads(artifact.read_text())["activation_allowed"])

    def test_cli_never_overwrites_its_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            source = folder / "model.json"
            original = json.dumps(envelope())
            source.write_text(original, encoding="utf-8")
            with self.assertRaises(SystemExit) as error:
                main(["--input", str(source), "--output", str(folder)])
            self.assertEqual(error.exception.code, 2)
            self.assertEqual(source.read_text(), original)


if __name__ == "__main__":
    unittest.main()
