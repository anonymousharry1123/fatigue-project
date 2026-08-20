import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Environment-safe Firebase configuration.
///
/// Run with:
/// flutter run --dart-define-from-file=config/firebase_options.json
abstract final class TonyoFirebaseOptions {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const webAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static String get appId => selectAppId(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    webAppId: webAppId,
    androidAppId: androidAppId,
    iosAppId: iosAppId,
  );

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      isAppIdValidForRuntime(
        appId: appId,
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      ) &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  /// Picks the Firebase app registration for the current runtime.
  /// `FIREBASE_APP_ID` stays the web/default value.
  static String selectAppId({
    required bool isWeb,
    required TargetPlatform platform,
    required String webAppId,
    required String androidAppId,
    required String iosAppId,
  }) {
    if (!isWeb && platform == TargetPlatform.iOS) return iosAppId;
    if (!isWeb && platform == TargetPlatform.android) return androidAppId;
    return webAppId;
  }

  /// Rejects a web app ID on iOS/Android before the native Firebase SDK can
  /// abort. Firebase app IDs use `1:<sender>:<platform>:<hash>`.
  static bool isAppIdValidForRuntime({
    required String appId,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    final parts = appId.split(':');
    if (parts.length < 4 || parts.first != '1') return false;
    final registeredPlatform = parts[2];
    if (isWeb) return registeredPlatform == 'web';
    if (platform == TargetPlatform.iOS) return registeredPlatform == 'ios';
    if (platform == TargetPlatform.android) {
      return registeredPlatform == 'android';
    }
    return true;
  }

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError(
        'Firebase configuration is missing. Supply config/firebase_options.json '
        'with --dart-define-from-file.',
      );
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      iosBundleId: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
          ? (iosBundleId.isEmpty ? null : iosBundleId)
          : null,
    );
  }
}
