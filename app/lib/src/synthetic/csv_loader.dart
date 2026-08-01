import 'package:flutter/services.dart';

import 'cohort_mapper.dart';
import 'synthetic_person.dart';

const syntheticStudentsAssetPath = 'assets/data/synthetic_students.csv';

/// Loads and scores the bundled synthetic CSV.
///
/// ~3000 rows parse quickly on the UI isolate; no background isolate is
/// required for this dataset size.
abstract final class SyntheticCsvLoader {
  static Future<List<SyntheticPerson>> loadAsset({
    String assetPath = syntheticStudentsAssetPath,
    DateTime? now,
  }) async {
    final csv = await rootBundle.loadString(assetPath);
    return parseCsv(csv, now: now);
  }

  static List<SyntheticPerson> parseCsv(String csv, {DateTime? now}) =>
      SyntheticCohortMapper.mapCsv(csv, now: now ?? DateTime.now());
}
