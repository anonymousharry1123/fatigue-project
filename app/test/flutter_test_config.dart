import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // Native platform channels have no engine implementation in widget tests.
    // Individual timezone tests override this with a region or injected reader.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('tonyo/timezone'),
          (_) async => null,
        );
  });
  await testMain();
}
