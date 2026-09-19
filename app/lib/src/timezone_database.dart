import 'package:timezone/data/latest_all.dart' as timezone_data;

bool _initialized = false;

/// One shared initialization preserves the aliases returned by system APIs
/// (for example Asia/Calcutta) when preparation or notifications start later.
void initializeTimezoneDatabase() {
  if (_initialized) return;
  timezone_data.initializeTimeZones();
  _initialized = true;
}
