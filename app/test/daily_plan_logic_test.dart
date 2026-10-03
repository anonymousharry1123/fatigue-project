import 'package:app/src/daily_plan_logic.dart';
import 'package:app/src/models.dart';
import 'package:app/src/schedule_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 8, 21);
  final generatedAt = DateTime(2026, 8, 21, 6, 30);
  const score = ScoreSnapshot(
    energy: 78,
    cognitive: 80,
    confidence: .82,
    cognitiveConfidence: .78,
    inputCount: 2,
    cognitiveInputCount: 2,
    drivers: [],
  );
  List<ForecastWindow> windows({DateTime? observedAt}) => [
    ForecastWindow(
      ForecastWindowType.peak,
      DateTime(2026, 8, 21, 9),
      DateTime(2026, 8, 21, 11),
      84,
      'Experimental',
      evidence: [
        ForecastEvidence(
          id: 'check-in',
          kind: ForecastEvidenceKind.checkIn,
          label: 'Reported energy',
          detail: 'Private evidence',
          timestamp: observedAt ?? generatedAt,
        ),
      ],
    ),
  ];

  test(
    'schedule suggestions never authorize exercise or infer optimal windows',
    () {
      final plan = DailyPlanLogic.build(
        windows: windows(),
        score: score,
        profile: const UserProfile(coachPriority: CoachPriority.training),
        day: day,
        generatedAt: generatedAt,
      );
      expect(plan, hasLength(4));
      expect(plan.first.planPhase, CoachPlanPhase.morning);
      expect(plan.last.planPhase, CoachPlanPhase.evening);
      expect(plan.every(DailyPlanLogic.isCurrentPlan), isTrue);
      expect(plan.every((item) => item.isGrounded), isTrue);
      expect(plan.every((item) => item.windowType == null), isTrue);
      expect(
        plan.map((item) => item.planPhase),
        isNot(contains(CoachPlanPhase.training)),
      );
      expect(
        plan.map((item) => item.planPhase),
        isNot(contains(CoachPlanPhase.nap)),
      );
      expect(
        plan.map((item) => item.detail).join(' '),
        isNot(contains('intensity')),
      );
      expect(plan.last.scheduledAt, DateTime(2026, 8, 21, 22, 15));
    },
  );

  test(
    'score magnitude and coverage do not change suggested task intensity or duration',
    () {
      List<Recommendation> build(ScoreSnapshot value) => DailyPlanLogic.build(
        windows: windows(),
        score: value,
        profile: const UserProfile(),
        day: day,
        generatedAt: generatedAt,
      );
      final low = build(
        const ScoreSnapshot(
          energy: 20,
          cognitive: 20,
          confidence: .2,
          cognitiveConfidence: .2,
          inputCount: 1,
          cognitiveInputCount: 1,
          drivers: [],
        ),
      );
      final high = build(score);
      expect(low.map((item) => item.title), high.map((item) => item.title));
      expect(
        low.map((item) => item.durationMinutes),
        high.map((item) => item.durationMinutes),
      );
      expect(
        low.map((item) => item.scheduledAt),
        high.map((item) => item.scheduledAt),
      );
    },
  );

  test(
    'all clock schedules omit overflowing blocks and keep every block nonoverlapping',
    () {
      for (var wake = 0; wake < 24; wake++) {
        for (var bed = 0; bed < 24; bed++) {
          if (wake == bed) continue;
          final profile = UserProfile(
            wakeHour: wake.toDouble(),
            bedHour: bed.toDouble(),
          );
          final bounds = ScheduleLogic.wakingWindow(day, profile)!;
          final plan = DailyPlanLogic.build(
            windows: windows(),
            score: score,
            profile: profile,
            day: day,
            generatedAt: generatedAt,
          );
          DateTime previousEnd = bounds.wake;
          for (final item in plan) {
            expect(
              item.scheduledAt!.isBefore(previousEnd),
              isFalse,
              reason: '$wake/$bed',
            );
            final end = item.scheduledAt!.add(
              Duration(minutes: item.durationMinutes!),
            );
            expect(end.isAfter(bounds.bed), isFalse, reason: '$wake/$bed');
            previousEnd = end;
          }
        }
      }
    },
  );

  test(
    'unavailable scores, missing evidence, stale evidence and invalid schedule yield no plan',
    () {
      for (final (inputScore, inputWindows, profile) in [
        (
          const ScoreSnapshot(
            energy: 60,
            cognitive: 65,
            confidence: 0,
            drivers: [],
          ),
          windows(),
          const UserProfile(),
        ),
        (score, <ForecastWindow>[], const UserProfile()),
        (
          score,
          windows(observedAt: DateTime(2026, 8, 20, 20)),
          const UserProfile(),
        ),
        (score, windows(), const UserProfile(wakeHour: 7, bedHour: 7)),
        (score, windows(), const UserProfile(wakeHour: double.nan)),
      ]) {
        expect(
          DailyPlanLogic.build(
            windows: inputWindows,
            score: inputScore,
            profile: profile,
            day: day,
            generatedAt: generatedAt,
          ),
          isEmpty,
        );
      }
    },
  );

  test('changed schedule moves suggestions without changing observations', () {
    List<Recommendation> build(UserProfile profile) => DailyPlanLogic.build(
      windows: windows(),
      score: score,
      profile: profile,
      day: day,
      generatedAt: generatedAt,
    );
    final before = build(const UserProfile(wakeHour: 7, bedHour: 23));
    final after = build(const UserProfile(wakeHour: 9, bedHour: 1));
    expect(
      after.first.scheduledAt,
      before.first.scheduledAt!.add(const Duration(hours: 2)),
    );
    expect(after.last.scheduledAt, DateTime(2026, 8, 22, 0, 15));
    expect(after.first.evidence.single.timestamp, generatedAt);
  });

  test(
    'local clock dates preserve waking boundaries across DST transition dates',
    () {
      for (final date in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
        final bounds = ScheduleLogic.wakingWindow(
          date,
          const UserProfile(wakeHour: 7, bedHour: 1),
        )!;
        expect(bounds.wake.hour, 7);
        expect(bounds.bed.hour, 1);
        expect(bounds.bed.day, date.day + 1);
      }
    },
  );

  test('legacy goal migration is preserved', () {
    expect(
      UserProfile.fromJson(const {'goal': 'Improve focus'}).coachPriority,
      CoachPriority.focus,
    );
    expect(
      UserProfile.fromJson(const {'goal': 'Improve recovery'}).coachPriority,
      CoachPriority.recovery,
    );
  });
}
