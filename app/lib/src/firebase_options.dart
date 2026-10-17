import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_secrets.dart' as secrets;

/// Local Firebase configuration compiled into ordinary Flutter/Xcode builds.
///
/// Copy firebase_secrets.example.dart to firebase_secrets.dart before the first
/// build. Empty constants keep Firebase offline; the filled file stays ignored.
abstract final class TonyoFirebaseOptions {
  static const apiKey = secrets.apiKey;
  static const webAppId = secrets.webAppId;
  static const iosAppId = secrets.iosAppId;
  static const messagingSenderId = secrets.messagingSenderId;
  static const projectId = secrets.projectId;
  static const authDomain = secrets.authDomain;
  static const storageBucket = secrets.storageBucket;
  static const iosBundleId = secrets.iosBundleId;

  static bool get hasAnySuppliedValue => [
    apiKey,
    webAppId,
    iosAppId,
    messagingSenderId,
    projectId,
    authDomain,
    storageBucket,
    iosBundleId,
  ].any((value) => value.isNotEmpty);

  static String get appId => selectAppId(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    webAppId: webAppId,
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

  /// Keeps the web and iOS Firebase registrations separate while retaining
  /// webAppId as the existing web/default value for other platforms.
  static String selectAppId({
    required bool isWeb,
    required TargetPlatform platform,
    required String webAppId,
    required String iosAppId,
  }) => !isWeb && platform == TargetPlatform.iOS ? iosAppId : webAppId;

  /// Rejects a web app ID on iOS before the native Firebase SDK can abort the
  /// process. Firebase app IDs use `1:<sender>:<platform>:<hash>`.
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
    return true;
  }

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError(
        'Firebase configuration is missing or invalid. Fill the local '
        'lib/src/firebase_secrets.dart file and rebuild.',
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
