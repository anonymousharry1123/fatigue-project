import 'package:timezone/timezone.dart' as timezone;

import 'device_timezone_platform.dart'
    if (dart.library.js_interop) 'device_timezone_web.dart'
    as platform;
import 'timezone_database.dart';

/// Reads the system's region without requesting location access. Refresh when
/// the app starts or resumes so travel and daylight-saving changes invalidate
/// forecasts generated for an earlier local clock.
class DeviceTimezoneService {
  DeviceTimezoneService({
    Future<String?> Function()? readIdentifier,
    DateTime Function()? clock,
  }) : _readIdentifier = readIdentifier ?? platform.readDeviceTimezone,
       _clock = clock ?? DateTime.now;

  final Future<String?> Function() _readIdentifier;
  final DateTime Function() _clock;
  timezone.Location? _location;
  Duration _utcOffset = Duration.zero;
  bool _initialized = false;
  Future<bool>? _pendingRefresh;

  /// Null means the host did not provide a usable IANA region. Never infer a
  /// region from an abbreviation or the current offset: neither identifies its
  /// historical daylight-saving rules.
  String? get identifier => _location?.name;
  Duration get utcOffset => _utcOffset;
  bool get isInitialized => _initialized;

  String get label {
    final minutes = _utcOffset.inMinutes.abs();
    final offset =
        'UTC${_utcOffset.isNegative ? '-' : '+'}'
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
    return '${identifier ?? 'Device local time'} · $offset';
  }

  DateTime localTime(DateTime instant) => _location == null
      ? instant.toLocal()
      : timezone.TZDateTime.from(instant, _location!);

  Future<bool> refresh() => _pendingRefresh ??= _refresh().whenComplete(() {
    _pendingRefresh = null;
  });

  Future<bool> _refresh() async {
    initializeTimezoneDatabase();
    String? candidate;
    try {
      candidate = (await _readIdentifier())?.trim();
    } on Object {
      // Reading a system setting must never prevent startup or foreground work.
    }
    if (candidate == 'UTC' || candidate == 'GMT') candidate = 'Etc/UTC';
    timezone.Location? location;
    if (candidate != null && candidate.isNotEmpty) {
      try {
        location = timezone.getLocation(candidate);
      } on timezone.LocationNotFoundException {
        // Preserve the device's local clock; explicit historical preparation
        // will ask for a region instead of silently using the wrong one.
      }
    }
    final now = _clock();
    final offset = location == null
        ? now.toLocal().timeZoneOffset
        : timezone.TZDateTime.from(now, location).timeZoneOffset;
    final changed =
        !_initialized || location?.name != identifier || offset != _utcOffset;
    _location = location;
    _utcOffset = offset;
    _initialized = true;
    return changed;
  }
}
