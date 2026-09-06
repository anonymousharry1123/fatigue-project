# Read-only coverage inspection of a Tonyo local-cache JSON object.
# Usage: jq --arg start YYYY-MM-DD --arg end YYYY-MM-DD \
#   -f tool/inspect_prep_cache.jq
# Bounds are inclusive/exclusive LOCAL calendar dates. This cache stores local
# ISO timestamps. Offset-bearing exports need timezone normalization first.
# This reports ingestion coverage; it does not create labels or fit a model.

def seeded:
  ((.id // "") | test("(^|-)seed-|^demo-"; "i")) or
  ((.note // "") | test("synthetic|demo fixture"; "i"));

def date_key($field): (.[$field] // "")[:10];
def in_window($field): date_key($field) >= $start and date_key($field) < $end;
def day_count($field): map(date_key($field)) | unique | length;
def duplicates: length - (map(.id) | unique | length);
def summary($field): {
  records: length,
  distinctDays: day_count($field),
  duplicateIds: duplicates,
  syntheticRecords: (map(select(seeded)) | length),
  firstTimestamp: (map(.[$field]) | min),
  lastTimestamp: (map(.[$field]) | max)
};

if ((($end | strptime("%Y-%m-%d") | mktime) -
     ($start | strptime("%Y-%m-%d") | mktime)) / 86400) != 30
then error("Prep inspection requires exactly 30 local calendar dates")
else . end |
((.signals // []) | map(select(in_window("timestamp")))) as $signals |
((.checkIns // []) | map(select(in_window("timestamp")))) as $checkins |
((.outcomes // []) | map(select(in_window("observedAt")))) as $outcomes |
{
  window: {startInclusive: $start, endExclusive: $end,
    timezone: "America/Los_Angeles", calendarDays: 30},
  source: "Existing on-device cache; not a refreshed Firestore export",
  cachedOutcomeConsent: .outcomeConsent,
  outcomeFieldPresent: has("outcomes"),
  signals: ($signals | summary("timestamp")),
  checkIns: ($checkins | summary("timestamp")),
  outcomes: ($outcomes | summary("observedAt")),
  sourceCounts: ($signals | group_by(.source) |
    map({source: .[0].source, records: length})),
  signalCoverage: (["sleep", "bedtime", "hydration", "exercise", "steps",
    "study", "screenTime", "caffeine", "reactionTime", "hrv",
    "restingHeartRate"] | map(. as $type |
      ($signals | map(select(.type == $type))) as $matches |
      {type: $type, records: ($matches | length),
       daysPresent: ($matches | day_count("timestamp")),
       daysMissing: (30 - ($matches | day_count("timestamp"))),
       explicitZeroRecords: ($matches | map(select(.value == 0)) | length),
       syntheticRecords: ($matches | map(select(seeded)) | length)})),
  capReached: (($signals | length) >= 1500 or
    ($checkins | length) >= 100 or ($outcomes | length) >= 100),
  trainingPerformed: false,
  interpretation: "Coverage only. Synthetic rows are pipeline fixtures; cached ratings/signals must not be backfilled into real training outcomes."
}
