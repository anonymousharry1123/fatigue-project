import 'models.dart';

/// Keeps explicit manual screen time authoritative for model calculations.
///
/// Device Activity report details stay in Apple's extension sandbox and are
/// never converted into app/category/domain signals. Synthetic model readings
/// remain available for the developer Cohort Lab when no manual value exists.
class ScreenTimeLogic {
  const ScreenTimeLogic._();

  static List<SignalReading> modelReadings(Iterable<SignalReading> readings) {
    final screenReadings = readings
        .where((item) => item.type == SignalType.screenTime)
        .toList();
    final manual = screenReadings
        .where((item) => item.source == SignalSource.manual)
        .toList();
    return manual.isNotEmpty ? manual : screenReadings;
  }
}
