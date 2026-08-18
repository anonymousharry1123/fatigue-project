import 'package:app/src/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
