"""Run with python3 -m unittest discover -s tool -p 'test_prepare_experimental_sleep_data.py'."""

from copy import deepcopy
from contextlib import redirect_stderr
import io
import json
from pathlib import Path
import tempfile
import unittest

from experimental_sleep_model import validate_input
from prepare_experimental_sleep_data import (
    EXPORT_VERSION, ITEMS, MEASUREMENT_VERSION, PAIRING_POLICY,
    PreparationError, load_export, main, prepare,
)


def source_export():
    definition = {
        "version": MEASUREMENT_VERSION, "language": "en", "kind": "customSelfReport",
        "status": "draftNotClinicallyValidated", "recallPeriod": "right now",
        "recallPeriodText": "right now",
        "items": [{"id": item, "label": item.title(), "prompt": "",
                   "anchors": {"1": "low", "5": "middle", "10": "high"}, "optional": True}
                  for item in ITEMS],
    }
    return {
        "exportVersion": EXPORT_VERSION, "studyCode": "PersonalStudy",
        "generatedAtUtc": "2026-10-19T06:00:00Z",
        "questionnaireDefinitions": {"definition-1": definition},
        "sleepObservations": [{
            "sleep_ref": "sleep-1", "sleep_end_at_utc": "2026-10-18T15:00:00Z",
            "duration_hours": 7.5, "source": "manual", "quality": 1,
            "record_available_at_utc": "2026-10-18T16:00:00Z", "availability_known": True,
            "recorded_at_utc": "2026-10-18T16:00:00Z", "synced_at_utc": None,
        }],
        "responses": [{
            "study_code": "PersonalStudy", "response_ref": "response-1",
            "observed_at_utc": "2026-10-19T01:00:00Z", "recorded_at_utc": "2026-10-19T01:01:00Z",
            "local_date": "2026-10-18", "timezone": "America/Los_Angeles", "utc_offset_minutes": -420,
            "period": "evening", "questionnaire_version": MEASUREMENT_VERSION,
            "questionnaire_language": "en", "definition_ref": "definition-1", "source": "selfReport",
            "completion_status": "partial", "answered_item_count": 1,
            **{f"{item}_1_to_10": 7 if item == "energy" else None for item in ITEMS},
            "sleep_ref": "sleep-1", "sleep_hours": 7.5, "sleep_match_status": "matched",
            "sleep_pair_available_at_utc": "2026-10-18T16:00:00Z", "sleep_pair_availability_known": True,
        }],
    }


class PrepareExperimentalSleepDataTests(unittest.TestCase):
    def test_app_dictionary_describing_demo_exclusion_is_not_a_demo_record(self):
        payload = source_export()
        payload["dataDictionary"] = {
            "source": "selfReport; excludes legacy, demo and model-derived observations."
        }
        self.assertEqual(len(prepare(payload)[0]["rows"]), 1)

    def test_valid_app_export_is_trainer_compatible_and_pseudonymous(self):
        output, report = prepare(source_export())
        self.assertEqual(len(validate_input(output)), 1)
        row = output["rows"][0]
        self.assertEqual((row["participant"], row["sleep_hours"], row["energy_1_to_10"]), ("participant-1", 7.5, 7))
        self.assertNotIn("PersonalStudy", json.dumps([output, report]))
        self.assertIn("does not independently authenticate", report["provenance_basis"])
        self.assertEqual(report["pairing_policy_version"], PAIRING_POLICY)
        self.assertIn(f":{PAIRING_POLICY}:", row["measurement_key"])

    def test_missing_energy_on_first_compatible_response_never_falls_back(self):
        payload = source_export()
        later = deepcopy(payload["responses"][0])
        later.update(response_ref="response-2", observed_at_utc="2026-10-19T02:00:00Z", recorded_at_utc="2026-10-19T02:01:00Z")
        payload["responses"][0].update(energy_1_to_10=None, fatigue_1_to_10=5)
        payload["responses"].insert(0, later)  # Input order must not select a later answer.
        output, report = prepare(payload)
        self.assertEqual(output["rows"], [])
        self.assertEqual(report["exclusions"]["selected_first_response_missing_energy"], 1)
        self.assertEqual(report["exclusions"]["later_compatible_response_same_date"], 1)

    def test_no_morning_cutoff_including_sleep_saved_after_energy(self):
        for pair_time in ("2026-10-18T17:00:00Z", "2026-10-18T17:00:01Z", "2026-10-19T05:59:00Z"):
            with self.subTest(pair_time=pair_time):
                payload = source_export()
                payload["responses"][0]["sleep_pair_available_at_utc"] = pair_time
                payload["sleepObservations"][0].update(
                    record_available_at_utc=pair_time, recorded_at_utc=pair_time,
                )
                self.assertEqual(len(prepare(payload)[0]["rows"]), 1)

    def test_sleep_end_date_end_time_and_availability_are_all_checked(self):
        changes = [
            {"sleep_end_at_utc": "2026-10-17T15:00:00Z"},
            {"record_available_at_utc": "2026-10-18T17:01:00Z", "recorded_at_utc": "2026-10-18T17:02:00Z"},
            {"availability_known": False},
            {"recorded_at_utc": None},
        ]
        for change in changes:
            with self.subTest(change=change):
                payload = source_export()
                payload["sleepObservations"][0].update(change)
                self.assertEqual(prepare(payload)[0]["rows"], [])

    def test_evening_has_no_clock_window_and_can_be_saved_after_midnight(self):
        for observed, recorded, expected in (
            ("2026-10-19T01:00:00Z", "2026-10-19T01:00:00Z", 1),
            ("2026-10-19T00:59:59Z", "2026-10-19T01:01:00Z", 1),
            ("2026-10-19T05:00:00Z", "2026-10-19T05:00:00Z", 1),
            ("2026-10-19T04:59:00Z", "2026-10-19T05:00:00Z", 1),
            ("2026-10-18T15:00:00Z", "2026-10-18T15:01:00Z", 1),
            ("2026-10-19T06:59:00Z", "2026-10-19T07:01:00Z", 1),
        ):
            with self.subTest(observed=observed, recorded=recorded):
                payload = source_export()
                payload["generatedAtUtc"] = "2026-10-19T08:00:00Z"
                payload["responses"][0].update(observed_at_utc=observed, recorded_at_utc=recorded)
                self.assertEqual(len(prepare(payload)[0]["rows"]), expected)

    def test_sleep_can_end_after_10_but_must_end_before_energy(self):
        for ended, expected in (("2026-10-18T19:00:00Z", 1), ("2026-10-19T01:00:01Z", 0)):
            with self.subTest(ended=ended):
                payload = source_export()
                payload["sleepObservations"][0].update(
                    sleep_end_at_utc=ended, recorded_at_utc="2026-10-19T02:00:00Z",
                    record_available_at_utc="2026-10-19T02:00:00Z",
                )
                payload["responses"][0]["sleep_pair_available_at_utc"] = "2026-10-19T02:00:00Z"
                output, report = prepare(payload)
                self.assertEqual(len(output["rows"]), expected)
                if not expected:
                    self.assertEqual(report["exclusions"]["sleep_ended_after_response"], 1)

    def test_after_midnight_evening_uses_previous_sleep_and_actual_response_date(self):
        payload = source_export()
        payload["generatedAtUtc"] = "2026-10-19T08:00:00Z"
        payload["responses"][0].update(
            observed_at_utc="2026-10-19T07:15:00Z", recorded_at_utc="2026-10-19T07:16:00Z",
            local_date="2026-10-19",
        )
        output, _ = prepare(payload)
        self.assertEqual(len(output["rows"]), 1)
        self.assertEqual(output["rows"][0]["local_date"], "2026-10-19")

    def test_preceding_24_hours_includes_exact_boundary_but_not_older_sleep(self):
        for ended, expected in (("2026-10-18T01:00:00Z", 1), ("2026-10-18T00:59:59Z", 0)):
            with self.subTest(ended=ended):
                payload = source_export()
                payload["sleepObservations"][0]["sleep_end_at_utc"] = ended
                output, report = prepare(payload)
                self.assertEqual(len(output["rows"]), expected)
                if not expected:
                    self.assertEqual(report["exclusions"]["sleep_ended_more_than_24_hours_before_response"], 1)

    def test_same_sleep_cannot_be_used_on_both_sides_of_midnight(self):
        for missing_first_energy in (False, True):
            with self.subTest(missing_first_energy=missing_first_energy):
                payload = source_export()
                payload["generatedAtUtc"] = "2026-10-19T08:00:00Z"
                later = deepcopy(payload["responses"][0])
                later.update(
                    response_ref="response-2", observed_at_utc="2026-10-19T07:15:00Z",
                    recorded_at_utc="2026-10-19T07:16:00Z", local_date="2026-10-19",
                )
                if missing_first_energy:
                    payload["responses"][0].update(energy_1_to_10=None, fatigue_1_to_10=5)
                payload["responses"].insert(0, later)
                output, report = prepare(payload)
                self.assertEqual(len(output["rows"]), 0 if missing_first_energy else 1)
                self.assertEqual(report["exclusions"]["sleep_already_selected_by_earlier_response"], 1)
                if output["rows"]:
                    self.assertEqual(output["rows"][0]["local_date"], "2026-10-18")

    def test_no_future_availability_or_reversed_response_chronology(self):
        for change in (
            {"sleep_pair_available_at_utc": "2026-10-19T06:00:01Z"},
            {"recorded_at_utc": "2026-10-19T06:00:01Z"},
            {"recorded_at_utc": "2026-10-19T00:59:59Z"},
        ):
            with self.subTest(change=change):
                payload = source_export()
                payload["responses"][0].update(change)
                self.assertEqual(prepare(payload)[0]["rows"], [])

    def test_morning_energy_never_becomes_an_evening_target(self):
        payload = source_export()
        payload["responses"][0]["period"] = "morning"
        output, report = prepare(payload)
        self.assertEqual(output["rows"], [])
        self.assertEqual(report["exclusions"]["incompatible_measurement_source_or_period"], 1)

    def test_earlier_evening_outside_old_window_still_controls_selection(self):
        payload = source_export()
        earlier = deepcopy(payload["responses"][0])
        earlier.update(
            response_ref="response-earlier", observed_at_utc="2026-10-18T19:00:00Z",
            recorded_at_utc="2026-10-18T19:01:00Z", energy_1_to_10=None, fatigue_1_to_10=5,
        )
        payload["responses"].append(earlier)
        output, report = prepare(payload)
        self.assertEqual(output["rows"], [])
        self.assertEqual(report["exclusions"]["selected_first_response_missing_energy"], 1)
        self.assertEqual(report["exclusions"]["later_compatible_response_same_date"], 1)

    def test_captured_timezone_offset_and_date_must_agree(self):
        for change in ({"utc_offset_minutes": -480}, {"timezone": None}, {"local_date": "2026-10-19"}):
            payload = source_export()
            payload["responses"][0].update(change)
            self.assertEqual(prepare(payload)[0]["rows"], [])

    def test_sources_and_exact_definition_wording_remain_separate(self):
        manual, _ = prepare(source_export())
        payload = source_export()
        payload["sleepObservations"][0]["source"] = "healthKit"
        health, _ = prepare(payload)
        self.assertNotEqual(manual["rows"][0]["sleep_source"], health["rows"][0]["sleep_source"])
        payload["questionnaireDefinitions"]["definition-1"]["items"][0]["anchors"]["5"] = "usual energy"
        changed, _ = prepare(payload)
        self.assertNotEqual(health["rows"][0]["measurement_key"], changed["rows"][0]["measurement_key"])

    def test_changed_captured_zone_creates_separate_cohort_key(self):
        original, _ = prepare(source_export())
        payload = source_export()
        # Same October UTC offset, different frozen-zone identity.
        payload["responses"][0]["timezone"] = "America/Phoenix"
        changed, report = prepare(payload)
        self.assertNotEqual(original["rows"][0]["measurement_key"], changed["rows"][0]["measurement_key"])
        self.assertIn("original shared heading", " ".join(report["limitations"]))

    def test_duplicate_sleep_and_response_references_block_whole_extract(self):
        for collection in ("sleepObservations", "responses"):
            payload = source_export()
            duplicate = deepcopy(payload[collection][0])
            duplicate["duration_hours"] = 9
            payload[collection].append(duplicate)
            with self.subTest(collection=collection), self.assertRaises(PreparationError):
                prepare(payload)

    def test_conflicting_json_definition_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "input.json"
            path.write_text('{"questionnaireDefinitions":{"definition-1":{},"definition-1":{"different":true}}}')
            with self.assertRaises(PreparationError):
                load_export(path)

    def test_legacy_export_legacy_rows_and_unanchored_definitions_rejected(self):
        payload = source_export()
        payload["exportVersion"] = "legacy"
        with self.assertRaises(PreparationError):
            prepare(payload)
        payload = source_export()
        del payload["responses"][0]["questionnaire_version"]
        self.assertEqual(prepare(payload)[0]["rows"], [])
        payload = source_export()
        del payload["questionnaireDefinitions"]["definition-1"]["items"][0]["anchors"]["10"]
        self.assertEqual(prepare(payload)[0]["rows"], [])

    def test_synthetic_identity_marker_anywhere_rejects_export(self):
        for kind in ("studyCode", "response_ref", "groupId"):
            payload = source_export()
            if kind == "studyCode":
                payload[kind] = "synthetic-study"
            elif kind == "response_ref":
                payload["responses"][0][kind] = "demo-response"
            else:
                payload["sleepObservations"][0][kind] = "syn-import"
            with self.subTest(kind=kind), self.assertRaises(PreparationError):
                prepare(payload)

    def test_invalid_energy_sleep_or_completeness_is_excluded(self):
        for change in ({"energy_1_to_10": 0}, {"energy_1_to_10": 5.5}, {"energy_1_to_10": 10 ** 1000}, {"answered_item_count": 6}, {"sleep_hours": 8}):
            payload = source_export()
            payload["responses"][0].update(change)
            self.assertEqual(prepare(payload)[0]["rows"], [])

    def test_cli_never_overwrites_input_with_normalized_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            source = folder / "normalized.json"
            original = json.dumps(source_export())
            source.write_text(original, encoding="utf-8")
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
                main(["--input", str(source), "--output", str(folder)])
            self.assertEqual(caught.exception.code, 2)
            self.assertEqual(source.read_text(encoding="utf-8"), original)

    def test_private_cli_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            source = folder / "research.json"
            source.write_text(json.dumps(source_export()), encoding="utf-8")
            output = folder / "prepared"
            self.assertEqual(main(["--input", str(source), "--output", str(output)]), 0)
            self.assertEqual(output.stat().st_mode & 0o777, 0o700)
            for filename in ("normalized.json", "preparation_report.json"):
                self.assertEqual((output / filename).stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
