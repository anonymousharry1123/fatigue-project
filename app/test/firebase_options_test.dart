import 'package:app/src/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const webAppId = '1:123:web:web-hash';
  const androidAppId = '1:123:android:android-hash';
  const iosAppId = '1:123:ios:ios-hash';

  group('TonyoFirebaseOptions platform app IDs', () {
    test('selects the web app ID for web builds', () {
      expect(
        TonyoFirebaseOptions.selectAppId(
          isWeb: true,
          platform: TargetPlatform.iOS,
          webAppId: webAppId,
          androidAppId: androidAppId,
          iosAppId: iosAppId,
        ),
        webAppId,
      );
    });

    test('selects the separate iOS app ID for iOS builds', () {
      expect(
        TonyoFirebaseOptions.selectAppId(
          isWeb: false,
          platform: TargetPlatform.iOS,
          webAppId: webAppId,
          androidAppId: androidAppId,
          iosAppId: iosAppId,
        ),
        iosAppId,
      );
    });

    test('selects the Android app ID for Android builds', () {
      expect(
        TonyoFirebaseOptions.selectAppId(
          isWeb: false,
          platform: TargetPlatform.android,
          webAppId: webAppId,
          androidAppId: androidAppId,
          iosAppId: iosAppId,
        ),
        androidAppId,
      );
    });

    test('rejects a web app ID before native iOS initialization', () {
      expect(
        TonyoFirebaseOptions.isAppIdValidForRuntime(
          appId: webAppId,
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
      expect(
        TonyoFirebaseOptions.isAppIdValidForRuntime(
          appId: iosAppId,
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
    });

    test('rejects a web app ID before native Android initialization', () {
      expect(
        TonyoFirebaseOptions.isAppIdValidForRuntime(
          appId: webAppId,
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        TonyoFirebaseOptions.isAppIdValidForRuntime(
          appId: androidAppId,
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });
  });
}
