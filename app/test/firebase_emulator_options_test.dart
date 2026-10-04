import 'package:app/src/firebase_emulator_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local Firebase routing permits only a config-free debug build', () {
    expect(
      () => TonyoFirebaseEmulatorOptions.validate(
        isDebugBuild: true,
        hasFirebaseConfiguration: false,
      ),
      returnsNormally,
    );
    for (final configuration in [false, true]) {
      expect(
        () => TonyoFirebaseEmulatorOptions.validate(
          isDebugBuild: false,
          hasFirebaseConfiguration: configuration,
        ),
        throwsStateError,
      );
    }
    expect(
      () => TonyoFirebaseEmulatorOptions.validate(
        isDebugBuild: true,
        hasFirebaseConfiguration: true,
      ),
      throwsStateError,
    );
  });

  test('integration project and both services are fixed to demo loopback', () {
    expect(TonyoFirebaseEmulatorOptions.enabled, isFalse);
    expect(TonyoFirebaseEmulatorOptions.projectId, startsWith('demo-'));
    expect(TonyoFirebaseEmulatorOptions.host, '127.0.0.1');
    expect(
      TonyoFirebaseEmulatorOptions.options.projectId,
      TonyoFirebaseEmulatorOptions.projectId,
    );
    expect(TonyoFirebaseEmulatorOptions.authPort, 9099);
    expect(TonyoFirebaseEmulatorOptions.firestorePort, 8080);
    // Native Firebase Installations aborts before routing if this shape is
    // invalid, even for an otherwise valid Auth/Firestore emulator setup.
    expect(TonyoFirebaseEmulatorOptions.options.apiKey.length, 39);
    expect(TonyoFirebaseEmulatorOptions.options.apiKey.startsWith('A'), isTrue);
  });
}
