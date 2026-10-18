import 'package:app/src/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('TonyoFirebaseOptions platform app IDs', () {
    test('selects the web app ID for web builds', () {
      expect(
        TonyoFirebaseOptions.selectAppId(
          isWeb: true,
          platform: TargetPlatform.iOS,
          webAppId: '1:123:web:web-hash',
          iosAppId: '1:123:ios:ios-hash',
        ),
        '1:123:web:web-hash',
      );
    });

    test('selects the separate iOS app ID for iOS builds', () {
      expect(
        TonyoFirebaseOptions.selectAppId(
          isWeb: false,
          platform: TargetPlatform.iOS,
          webAppId: '1:123:web:web-hash',
          iosAppId: '1:123:ios:ios-hash',
        ),
        '1:123:ios:ios-hash',
      );
    });

    test('rejects a web app ID before native iOS initialization', () {
      expect(
        TonyoFirebaseOptions.isAppIdValidForRuntime(
          appId: '1:123:web:web-hash',
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
      expect(
        TonyoFirebaseOptions.isAppIdValidForRuntime(
          appId: '1:123:ios:ios-hash',
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
    });

    test('a missing iOS registration never falls back to the web ID', () {
      expect(
        TonyoFirebaseOptions.selectAppId(
          isWeb: false,
          platform: TargetPlatform.iOS,
          webAppId: '1:123:web:invented-web',
          iosAppId: '',
        ).isEmpty,
        isTrue,
      );
    });

    test('web runtime rejects a native iOS registration', () {
      expect(
        TonyoFirebaseOptions.isAppIdValidForRuntime(
          appId: '1:123:ios:invented-ios',
          isWeb: true,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
    });

    for (final malformed in [
      '',
      'not-an-app-id',
      '1:123:ios',
      '2:123:ios:invented',
    ]) {
      test(
        'rejects malformed synthetic app ID ${malformed.isEmpty ? '(empty)' : malformed}',
        () {
          for (final runtime in [
            (isWeb: false, platform: TargetPlatform.iOS),
            (isWeb: true, platform: TargetPlatform.linux),
            (isWeb: false, platform: TargetPlatform.android),
          ]) {
            expect(
              TonyoFirebaseOptions.isAppIdValidForRuntime(
                appId: malformed,
                isWeb: runtime.isWeb,
                platform: runtime.platform,
              ),
              isFalse,
            );
          }
        },
      );
    }

    for (final platform in TargetPlatform.values.where(
      (value) => value != TargetPlatform.iOS,
    )) {
      test(
        'preserves the existing default registration on ${platform.name}',
        () {
          expect(
            TonyoFirebaseOptions.selectAppId(
                  isWeb: false,
                  platform: platform,
                  webAppId: '1:123:web:invented-web',
                  iosAppId: '1:123:ios:invented-ios',
                ) ==
                '1:123:web:invented-web',
            isTrue,
          );
        },
      );
    }
  });

  group('TonyoFirebaseOptions installed configuration', () {
    // This suite intentionally works with either a developer's ignored local
    // configuration or the checked-in empty example. Only booleans reach
    // matchers: failure diagnostics must never print configuration values.
    test('supplied-value detection includes all public fields', () {
      final supplied = [
        TonyoFirebaseOptions.apiKey,
        TonyoFirebaseOptions.webAppId,
        TonyoFirebaseOptions.iosAppId,
        TonyoFirebaseOptions.messagingSenderId,
        TonyoFirebaseOptions.projectId,
        TonyoFirebaseOptions.authDomain,
        TonyoFirebaseOptions.storageBucket,
        TonyoFirebaseOptions.iosBundleId,
      ].any((value) => value.isNotEmpty);
      expect(TonyoFirebaseOptions.hasAnySuppliedValue == supplied, isTrue);
    });

    for (final platform in TargetPlatform.values) {
      test(
        'runtime options fail closed or map configured values on ${platform.name}',
        () {
          debugDefaultTargetPlatformOverride = platform;
          final expectedAppId = !kIsWeb && platform == TargetPlatform.iOS
              ? TonyoFirebaseOptions.iosAppId
              : TonyoFirebaseOptions.webAppId;
          expect(TonyoFirebaseOptions.appId == expectedAppId, isTrue);
          final canConfigure =
              TonyoFirebaseOptions.apiKey.isNotEmpty &&
              expectedAppId.isNotEmpty &&
              TonyoFirebaseOptions.isAppIdValidForRuntime(
                appId: expectedAppId,
                isWeb: kIsWeb,
                platform: platform,
              ) &&
              TonyoFirebaseOptions.messagingSenderId.isNotEmpty &&
              TonyoFirebaseOptions.projectId.isNotEmpty;
          expect(TonyoFirebaseOptions.isConfigured == canConfigure, isTrue);
          if (!canConfigure) {
            var rejected = false;
            try {
              TonyoFirebaseOptions.currentPlatform;
            } on StateError {
              rejected = true;
            }
            expect(rejected, isTrue);
            return;
          }
          final options = TonyoFirebaseOptions.currentPlatform;
          expect(options.apiKey == TonyoFirebaseOptions.apiKey, isTrue);
          expect(options.appId == expectedAppId, isTrue);
          expect(
            options.messagingSenderId == TonyoFirebaseOptions.messagingSenderId,
            isTrue,
          );
          expect(options.projectId == TonyoFirebaseOptions.projectId, isTrue);
          expect(
            options.authDomain ==
                (TonyoFirebaseOptions.authDomain.isEmpty
                    ? null
                    : TonyoFirebaseOptions.authDomain),
            isTrue,
          );
          expect(
            options.storageBucket ==
                (TonyoFirebaseOptions.storageBucket.isEmpty
                    ? null
                    : TonyoFirebaseOptions.storageBucket),
            isTrue,
          );
          expect(
            options.iosBundleId ==
                (!kIsWeb &&
                        platform == TargetPlatform.iOS &&
                        TonyoFirebaseOptions.iosBundleId.isNotEmpty
                    ? TonyoFirebaseOptions.iosBundleId
                    : null),
            isTrue,
          );
        },
      );
    }
  });
}
