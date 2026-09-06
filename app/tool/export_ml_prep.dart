import 'dart:convert';
import 'dart:io';

import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';

/// Local-only reproduction of the app's last bounded snapshot. Feed the JSON
/// conversion of the simulator preferences on stdin; no credentials or network.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: plutil -convert json -o - <preferences.plist> | '
      'dart run tool/export_ml_prep.dart <output-directory>',
    );
    exitCode = 64;
    return;
  }
  final preferences =
      jsonDecode(await stdin.transform(utf8.decoder).join())
          as Map<String, dynamic>;
  final entries = preferences.entries
      .where((entry) => entry.key.contains('tonyo_ml_prep_v1_'))
      .toList();
  if (entries.length != 1) {
    throw StateError(
      'Expected exactly one bounded prep snapshot; found ${entries.length}.',
    );
  }
  final envelope =
      jsonDecode(entries.single.value as String) as Map<String, dynamic>;
  final snapshot = PrepSnapshot.fromJson(
    Map<String, dynamic>.from(envelope['snapshot'] as Map),
    uid: 'local-export', // Snapshot storage deliberately excludes account IDs.
  );
  final report = MlPrepBuilder.build(snapshot).toJson();
  final directory = Directory(arguments.single);
  await directory.create(recursive: true);
  await File(
    '${directory.path}/coverage.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  final counts = report['counts'] as Map;
  final readiness = report['readiness'] as Map;
  final provenance = report['provenance'] as Map;
  final content = StringBuffer()
    ..writeln('# Version 0.32 preparation — account coverage')
    ..writeln()
    ..writeln(
      'The preparation pipeline is implemented. Training readiness remains '
      'a separate gate; this export does not fit or upload a model.',
    )
    ..writeln()
    ..writeln('## Snapshot and grain')
    ..writeln()
    ..writeln(
      '- Window: ${snapshot.window.dayKey(snapshot.window.start)} through '
      '${snapshot.window.dayKey(snapshot.window.end.subtract(const Duration(seconds: 1)))} '
      'inclusive, ${snapshot.window.timezone}.',
    )
    ..writeln(
      '- UTC bounds: [${snapshot.window.start.toIso8601String()}, '
      '${snapshot.window.end.toIso8601String()}).',
    )
    ..writeln('- Fetched at: ${snapshot.fetchedAt.toUtc().toIso8601String()}.')
    ..writeln(
      '- Content fingerprint: `${snapshot.fingerprint}`; schema ${snapshot.schemaVersion}.',
    )
    ..writeln(
      '- Grain: source documents, then one eligible linked outcome per local example.',
    )
    ..writeln(
      '- Provenance: the app’s authenticated, owner-scoped bounded Firebase '
      'snapshot, copied from its local prep cache. This command performs zero network reads/writes.',
    )
    ..writeln()
    ..writeln('## Coverage and readiness')
    ..writeln()
    ..writeln('| Check | Result |')
    ..writeln('| --- | --- |');
  for (final entry in counts.entries) {
    content.writeln('| ${entry.key} | ${entry.value} |');
  }
  for (final entry in readiness.entries) {
    final head = entry.value as Map;
    content.writeln('| ${entry.key} ready | ${head['ready']} |');
  }
  content
    ..writeln()
    ..writeln('## Data-quality findings')
    ..writeln()
    ..writeln(
      '- Consent: collection=${snapshot.consent.collection}, '
      'training use=${snapshot.consent.trainingUse}, version=${snapshot.consent.version}.',
    )
    ..writeln('- Source provenance: `${jsonEncode(provenance)}`.')
    ..writeln(
      '- High-severity training blockers: '
      '${readiness.entries.map((e) => '${e.key}: ${(e.value as Map)['reasons']}').join('; ')}.',
    )
    ..writeln(
      '- Synthetic and uncertain records cannot establish personal effects, '
      'accuracy, or training readiness. Missing data is not a zero measurement.',
    )
    ..writeln(
      '- This is one selected historical month, not a current-month trend or '
      'an analysis of changes in wellness. No claim of model accuracy is made.',
    )
    ..writeln()
    ..writeln('## Checks and limits')
    ..writeln()
    ..writeln(
      'Owner scope; exact calendar bounds; 1,500/100/100 server document '
      'caps; dual consent; IDs and source joins; synthetic/uncertain provenance; '
      'label ranges and units; temporal availability; prior-only baselines; '
      'nullable fixed-normalized features; whole-day chronological holdout.',
    )
    ..writeln()
    ..writeln(
      'Detailed missingness, rejected rows, split dates, fixed normalization '
      'and limitations are in [coverage.json](./coverage.json). Empty eligible '
      'feature denominators mean “not evaluable,” not complete coverage.',
    )
    ..writeln()
    ..writeln('## Next step')
    ..writeln()
    ..writeln(
      'Keep FatigueEngine active. Collect genuine consented future outcomes; '
      'do not backfill seeded rows into labels. Reopen the cached report without '
      'reads; refresh explicitly only when remote changes are needed. Request '
      'counts are distinct from billed document/rules/index reads.',
    )
    ..writeln()
    ..writeln(
      'Reproduce from the simulator preferences with '
      '`tool/export_ml_prep.dart`. Keep these private outputs out of Git.',
    );
  await File('${directory.path}/REPORT.md').writeAsString(content.toString());
  stdout.writeln(
    jsonEncode({
      'output': directory.path,
      'fingerprint': snapshot.fingerprint,
      'counts': counts,
      'energyReady': (readiness['energy'] as Map)['ready'],
      'cognitiveReady': (readiness['cognitive'] as Map)['ready'],
    }),
  );
}
