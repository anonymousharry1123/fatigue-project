import 'package:app/src/models.dart';
import 'package:app/src/screen_time_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Version 0.28 keeps manual screen time authoritative', () {
    final readings = ScreenTimeLogic.modelReadings([
      SignalReading(
        id: 'synthetic',
        type: SignalType.screenTime,
        value: 12,
        timestamp: DateTime(2026, 8, 20, 8),
        source: SignalSource.model,
      ),
      SignalReading(
        id: 'manual',
        type: SignalType.screenTime,
        value: 3.5,
        timestamp: DateTime(2026, 8, 20, 9),
      ),
    ]);

    expect(readings.map((item) => item.id), ['manual']);
  });

  test('Version 0.28 retains synthetic fallback for Cohort Lab', () {
    final readings = ScreenTimeLogic.modelReadings([
      SignalReading(
        id: 'synthetic',
        type: SignalType.screenTime,
        value: 6,
        timestamp: DateTime(2026, 8, 20, 8),
        source: SignalSource.model,
      ),
    ]);

    expect(readings.single.id, 'synthetic');
  });
}
