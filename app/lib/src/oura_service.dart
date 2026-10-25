import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'oura_http_stub.dart' if (dart.library.io) 'oura_http_io.dart' as http;

class OuraException implements Exception {
  const OuraException(this.code);
  final String code;

  String get message => switch (code) {
    'cancelled' => 'Oura connection was cancelled.',
    'not_configured' => 'Oura connection is not available in this build yet.',
    'sign_in_required' ||
    'unauthenticated' => 'Sign in to your Tonyo account to connect Oura.',
    'privacy_required' => 'Review your privacy choices before connecting Oura.',
    'not_connected' ||
    'reconnect_required' => 'Reconnect Oura to resume syncing.',
    'busy' => 'Oura is already syncing. Try again shortly.',
    _ => 'Oura could not finish syncing. Please retry.',
  };
}

typedef OuraRequest =
    Future<Map<String, dynamic>> Function(
      Uri uri,
      String token,
      Map<String, Object?> body,
    );
typedef OuraTokenProvider = Future<String?> Function(String uid);

/// Oura access/refresh tokens and the client secret stay on the server. Only a
/// short-lived Firebase ID token authenticates requests from this installation.
class OuraService {
  OuraService({
    String? endpoint,
    OuraRequest? request,
    OuraTokenProvider? tokenProvider,
    String? Function()? currentUid,
  }) : endpoint = endpoint ?? const String.fromEnvironment('OURA_API_BASE_URL'),
       _request = request ?? http.postOura,
       _tokenProvider = tokenProvider ?? _firebaseToken,
       _currentUid = currentUid ?? _firebaseUid;

  final String endpoint;
  final OuraRequest _request;
  final OuraTokenProvider _tokenProvider;
  final String? Function() _currentUid;
  int _authorizationGeneration = 0;
  static const channel = MethodChannel('tonyo/oura');

  static String? _firebaseUid() => FirebaseAuth.instance.currentUser?.uid;
  static Future<String?> _firebaseToken(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid == uid ? await user!.getIdToken() : null;
  }

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get configured {
    final uri = Uri.tryParse(endpoint);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (!uri.hasPort || uri.port == 443) &&
        uri.pathSegments.lastOrNull == 'ouraIntegration';
  }

  Future<Map<String, dynamic>> _call(String uid, String action) async {
    if (!configured) throw const OuraException('not_configured');
    try {
      if (_currentUid() != uid) {
        throw const OuraException('sign_in_required');
      }
      final token = await _tokenProvider(uid);
      if (token == null || _currentUid() != uid) {
        throw const OuraException('sign_in_required');
      }
      final result = await _request(Uri.parse(endpoint), token, {
        'action': action,
      });
      if (_currentUid() != uid) {
        throw const OuraException('sign_in_required');
      }
      final error = result['error'];
      if (error != null) {
        throw OuraException(
          error is Map ? '${error['code']}' : 'provider_unavailable',
        );
      }
      return result;
    } on OuraException {
      rethrow;
    } on Object {
      throw const OuraException('provider_unavailable');
    }
  }

  Future<bool> status(String uid) async =>
      (await _call(uid, 'status'))['connected'] == true;

  Future<void> connect(String uid) async {
    final generation = ++_authorizationGeneration;
    final start = await _call(uid, 'start');
    _ensureAuthorizationCurrent(uid, generation);
    final expectedRedirect = Uri.parse(endpoint)
        .replace(
          path: Uri.parse(
            endpoint,
          ).path.replaceFirst(RegExp(r'ouraIntegration$'), 'ouraCallback'),
        )
        .toString();
    if (start['redirectUri'] != expectedRedirect ||
        start['state'] is! String ||
        start['authorizationUrl'] is! String) {
      throw const OuraException('invalid_response');
    }
    try {
      final result = await channel
          .invokeMapMethod<String, dynamic>('authenticate', {
            'authorizationUrl': start['authorizationUrl'],
            'redirectUri': expectedRedirect,
          });
      _ensureAuthorizationCurrent(uid, generation);
      if (result?['state'] != start['state']) {
        throw const OuraException('invalid_state');
      }
      if (result?['result'] != 'success') {
        throw OuraException(
          result?['result'] == 'cancelled' ? 'cancelled' : 'reconnect_required',
        );
      }
      final connected = await status(uid);
      _ensureAuthorizationCurrent(uid, generation);
      if (!connected) throw const OuraException('reconnect_required');
    } on PlatformException catch (error) {
      throw OuraException(switch (error.code) {
        'oura_cancelled' || 'cancelled' => 'cancelled',
        'oura_busy' => 'busy',
        _ => 'provider_unavailable',
      });
    } on MissingPluginException {
      throw const OuraException('not_configured');
    }
  }

  void _ensureAuthorizationCurrent(String uid, int generation) {
    if (generation != _authorizationGeneration) {
      throw const OuraException('cancelled');
    }
    if (_currentUid() != uid) {
      throw const OuraException('sign_in_required');
    }
  }

  Future<Map<String, dynamic>> sync(String uid) => _call(uid, 'sync');
  Future<void> disconnect(String uid) async {
    await _call(uid, 'disconnect');
  }

  Future<void> cancel() async {
    // Invalidate even before the native session exists: a pending server start
    // must not reopen sign-in after logout, deletion or a privacy pause.
    _authorizationGeneration++;
    try {
      await channel.invokeMethod<void>('cancel');
    } on Object {
      /* No active native session. */
    }
  }
}
