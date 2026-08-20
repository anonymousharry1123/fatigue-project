import 'package:app/src/continuous_refresh_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Version 0.26 refreshes on launch and after the foreground interval',
    () {
      final now = DateTime(2026, 8, 20, 12);

      expect(
        ContinuousRefreshLogic.shouldRefresh(now: now, lastAttempt: null),
        isTrue,
      );
      expect(
        ContinuousRefreshLogic.shouldRefresh(
          now: now,
          lastAttempt: now.subtract(const Duration(minutes: 14)),
        ),
        isFalse,
      );
      expect(
        ContinuousRefreshLogic.shouldRefresh(
          now: now,
          lastAttempt: now.subtract(const Duration(minutes: 15)),
        ),
        isTrue,
      );
    },
  );

  test('Version 0.26 ignores sync-only metadata changes', () {
    final observedAt = DateTime(2026, 8, 20, 8);
    final before = [
      SignalReading(
        id: 'healthkit-hrv',
        type: SignalType.hrv,
        value: 54,
        timestamp: observedAt,
        source: SignalSource.healthKit,
        syncedAt: DateTime.utc(2026, 8, 20, 9),
      ),
    ];
    final after = [
      SignalReading(
        id: 'healthkit-hrv',
        type: SignalType.hrv,
        value: 54,
        timestamp: observedAt,
        source: SignalSource.healthKit,
        syncedAt: DateTime.utc(2026, 8, 20, 10),
      ),
    ];

    expect(
      ContinuousRefreshLogic.hasMeaningfulModelChange(before, after),
      isFalse,
    );
  });

  test('Version 0.26 detects effective activity changes', () {
    final day = DateTime(2026, 8, 20);
    SignalReading steps(double value) => SignalReading(
      id: 'healthkit-steps-2026-08-20',
      type: SignalType.steps,
      value: value,
      timestamp: day.add(const Duration(hours: 12)),
      source: SignalSource.healthKit,
    );

    expect(
      ContinuousRefreshLogic.hasMeaningfulModelChange(
        [steps(4200)],
        [steps(6100)],
      ),
      isTrue,
    );
  });
}
