import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Explicit local-only integration mode. Hosts/project cannot be redirected by
/// environment values, and a release/profile build must never enable it.
abstract final class TonyoFirebaseEmulatorOptions {
  static const enabled = bool.fromEnvironment('TONYO_LOCAL_EMULATORS');
  static const appName = 'tonyo-local-emulator';
  static const projectId = 'demo-tonyo-privacy';
  static const host = '127.0.0.1';
  static const authPort = 9099;
  static const firestorePort = 8080;

  static void validate({
    required bool isDebugBuild,
    required bool hasFirebaseConfiguration,
  }) {
    if (!isDebugBuild) {
      throw StateError('Local Firebase emulators require a debug build.');
    }
    if (hasFirebaseConfiguration) {
      throw StateError(
        'Local Firebase emulators require empty firebase_secrets.dart values.',
      );
    }
  }

  static FirebaseOptions get options => FirebaseOptions(
    // Deliberately synthetic identifiers; no Firebase project is registered.
    // The iOS SDK validates the 39-character API-key shape before an emulator
    // can be selected. This all-zero placeholder is not a registered key.
    apiKey: 'AIzaSy000000000000000000000000000000000',
    appId: kIsWeb
        ? '1:1234567890:web:1234567890abcdef'
        : defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
        ? '1:1234567890:ios:1234567890abcdef'
        : '1:1234567890:android:1234567890abcdef',
    messagingSenderId: '1234567890',
    projectId: projectId,
  );
}
