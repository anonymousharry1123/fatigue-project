import 'dart:async';

import 'package:app/src/oura_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _endpoint = 'https://example.cloudfunctions.net/ouraIntegration';
const _redirect = 'https://example.cloudfunctions.net/ouraCallback';
final _state = 's' * 43;

Map<String, dynamic> _start() => {
  'authorizationUrl': Uri.https('cloud.ouraring.com', '/oauth/authorize', {
    'client_id': 'test-client',
    'response_type': 'code',
    'scope': 'daily',
    'redirect_uri': _redirect,
    'state': _state,
    'code_challenge': 'c' * 43,
    'code_challenge_method': 'S256',
  }).toString(),
  'redirectUri': _redirect,
  'state': _state,
};

Matcher _error(String code) =>
    isA<OuraException>().having((error) => error.code, 'code', code);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late String? uid;
  late List<String> requests;
  late List<String> nativeCalls;

  OuraService service({
    OuraRequest? request,
    OuraTokenProvider? tokenProvider,
  }) => OuraService(
    endpoint: _endpoint,
    currentUid: () => uid,
    tokenProvider: tokenProvider ?? (_) async => 'firebase-token',
    request:
        request ??
        (uri, token, body) async {
          expect(uri.toString(), _endpoint);
          expect(token, 'firebase-token');
          final action = body['action']! as String;
          requests.add(action);
          return action == 'start' ? _start() : {'connected': true};
        },
  );

  setUp(() {
    uid = 'owner';
    requests = [];
    nativeCalls = [];
    messenger.setMockMethodCallHandler(OuraService.channel, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'cancel') return null;
      expect((call.arguments as Map)['redirectUri'], _redirect);
      return {'state': _state, 'result': 'success'};
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(OuraService.channel, null));

  test('successful consent rechecks server status', () async {
    await service().connect('owner');
    expect(requests, ['start', 'status']);
    expect(nativeCalls, ['authenticate']);
  });

  test('requires a valid HTTPS configured function endpoint', () {
    for (final endpoint in [
      '',
      'http://example.cloudfunctions.net/ouraIntegration',
      'https://user@example.cloudfunctions.net/ouraIntegration',
      'https://example.cloudfunctions.net/ouraIntegration?token=x',
      'https://example.cloudfunctions.net/ouraIntegration#fragment',
      'https://example.cloudfunctions.net:8080/ouraIntegration',
      'https://example.cloudfunctions.net/otherFunction',
    ]) {
      expect(OuraService(endpoint: endpoint).configured, isFalse);
    }
    expect(service().configured, isTrue);
  });

  test('native user cancellation stays a cancellation', () async {
    messenger.setMockMethodCallHandler(OuraService.channel, (call) async {
      throw PlatformException(code: 'oura_cancelled');
    });
    await expectLater(service().connect('owner'), throwsA(_error('cancelled')));
    expect(requests, ['start']);
  });

  test('rejects another callback origin before opening browser', () async {
    final client = service(
      request: (_, _, _) async => {
        ..._start(),
        'redirectUri': 'https://other.example/ouraCallback',
      },
    );
    await expectLater(
      client.connect('owner'),
      throwsA(_error('invalid_response')),
    );
    expect(nativeCalls, isEmpty);
  });

  test('rejects callback state mismatch without querying status', () async {
    messenger.setMockMethodCallHandler(
      OuraService.channel,
      (call) async => {'state': 'another-session', 'result': 'success'},
    );
    await expectLater(
      service().connect('owner'),
      throwsA(_error('invalid_state')),
    );
    expect(requests, ['start']);
  });

  test('callback success alone does not establish a connection', () async {
    final client = service(
      request: (_, _, body) async =>
          body['action'] == 'start' ? _start() : {'connected': false},
    );
    await expectLater(
      client.connect('owner'),
      throwsA(_error('reconnect_required')),
    );
  });

  test('cancel before server start resolves never opens browser', () async {
    final start = Completer<Map<String, dynamic>>();
    final requested = Completer<void>();
    final client = service(
      request: (_, _, _) {
        requested.complete();
        return start.future;
      },
    );
    final pending = expectLater(
      client.connect('owner'),
      throwsA(_error('cancelled')),
    );
    await requested.future;
    await client.cancel();
    start.complete(_start());
    await pending;
    expect(nativeCalls, ['cancel']);
  });

  test('cancel during native callback cannot finish or check status', () async {
    final callback = Completer<Map<String, dynamic>>();
    final opened = Completer<void>();
    messenger.setMockMethodCallHandler(OuraService.channel, (call) {
      if (call.method == 'cancel') return Future.value();
      opened.complete();
      return callback.future;
    });
    final client = service();
    final pending = expectLater(
      client.connect('owner'),
      throwsA(_error('cancelled')),
    );
    await opened.future;
    await client.cancel();
    callback.complete({'state': _state, 'result': 'success'});
    await pending;
    expect(requests, ['start']);
  });

  test('cancel while server verifies connection cannot finish', () async {
    final status = Completer<Map<String, dynamic>>();
    final requested = Completer<void>();
    final client = service(
      request: (_, _, body) async {
        if (body['action'] == 'start') return _start();
        requested.complete();
        return status.future;
      },
    );
    final pending = expectLater(
      client.connect('owner'),
      throwsA(_error('cancelled')),
    );
    await requested.future;
    await client.cancel();
    status.complete({'connected': true});
    await pending;
  });

  test('account change during token refresh sends no request', () async {
    final token = Completer<String?>();
    final client = service(tokenProvider: (_) => token.future);
    final pending = expectLater(
      client.sync('owner'),
      throwsA(_error('sign_in_required')),
    );
    uid = 'another-owner';
    token.complete('old-owner-token');
    await pending;
    expect(requests, isEmpty);
  });

  test('account change during HTTP discards the response', () async {
    final response = Completer<Map<String, dynamic>>();
    final requested = Completer<void>();
    final client = service(
      request: (_, _, _) {
        requested.complete();
        return response.future;
      },
    );
    final pending = expectLater(
      client.sync('owner'),
      throwsA(_error('sign_in_required')),
    );
    await requested.future;
    uid = 'another-owner';
    response.complete({'sleep': []});
    await pending;
  });

  test('late cancelled start cannot disturb a newer authorization', () async {
    final oldStart = Completer<Map<String, dynamic>>();
    final requested = Completer<void>();
    var starts = 0;
    final client = service(
      request: (_, _, body) async {
        if (body['action'] != 'start') return {'connected': true};
        if (++starts == 1) {
          requested.complete();
          return oldStart.future;
        }
        return _start();
      },
    );
    final pending = expectLater(
      client.connect('owner'),
      throwsA(_error('cancelled')),
    );
    await requested.future;
    await client.cancel();
    await client.connect('owner');
    oldStart.complete(_start());
    await pending;
    expect(nativeCalls, ['cancel', 'authenticate']);
  });
}
