/// Calendar operations follow the device region; elapsed durations still use
/// DateTime.difference. A local day is not necessarily 24 hours across DST.
DateTime localDay(DateTime instant, [int dayOffset = 0]) {
  final local = instant.toUtc().toLocal();
  return DateTime(local.year, local.month, local.day + dayOffset);
}

String localDayKey(DateTime instant) {
  final local = instant.toUtc().toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

bool sameLocalDay(DateTime a, DateTime b) => localDay(a) == localDay(b);
