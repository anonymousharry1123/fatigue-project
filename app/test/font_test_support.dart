import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Use production font metrics in layout tests and optional visual artifacts.
Future<void> loadAppearanceFonts() async {
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final flutter = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((package) => package['name'] == 'flutter');
  final sdk = Directory.fromUri(
    configFile.uri.resolve(flutter['rootUri'] as String),
  ).parent.parent;
  final system = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    system.addFont(
      File(
        '${sdk.path}/bin/cache/artifacts/material_fonts/$name',
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await system.load();
}
