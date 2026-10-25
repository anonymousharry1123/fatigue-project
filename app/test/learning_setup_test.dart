import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_capture_store.dart';
import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The preference platform injects a failed durable prompt-receipt write.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'privacy_test_support.dart';

final _now = DateTime.utc(2026, 10, 25, 20);

class _FailingChoicePreferences extends InMemorySharedPreferencesStore {
  _FailingChoicePreferences() : super.empty();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.startsWith('flutter.tonyo_learning_setup_v1_')) return false;
    return super.setValue(type, key, value);
  }
}

class _CaptureStore implements Ai1CaptureStore {
  bool available = true;
  bool failWrites = false;
  Completer<void>? writeStarted;
  Completer<void>? releaseWrite;
  final values = <String, String>{};
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<String?> read(String owner) async => values[owner];
  @override
  Future<DateTime> write(String owner, String value) async {
    writeStarted?.complete();
    await releaseWrite?.future;
    if (failWrites) throw StateError('Device storage unavailable');
    values[owner] = value;
    return _now;
  }

  @override
  Future<void> clear(String owner) async => values.remove(owner);
  @override
  Future<void> clearAll() async => values.clear();
}

class _Repository extends MemoryCloudRepository {
  _Repository(String owner) : super(signedInUid: owner);
  bool failConsent = false;
  int consentWrites = 0;
  @override
  Future<DateTime> saveOutcomeConsent(String uid, bool enabled) {
    consentWrites++;
    if (failConsent) throw StateError('Offline');
    return super.saveOutcomeConsent(uid, enabled);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppController> local(_CaptureStore store) async {
    final controller = AppController(
      captureStore: store,
      initialPrivacyConsent: testAdultPrivacyConsent,
      clock: () => _now,
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.onboardingComplete = true;
    return controller;
  }

  Future<({AppController controller, _Repository repository})> cloud(
    _CaptureStore store,
    String owner,
  ) async {
    final repository = _Repository(owner)
      ..seed(
        owner,
        CloudUserState(
          profile: const UserProfile(),
          accountEmail: '$owner@example.test',
          privacyConsent: testAdultPrivacyConsent,
          onboardingComplete: true,
          notificationsEnabled: false,
          outcomeConsent: false,
          healthAuthorized: false,
          signals: [],
          checkIns: [],
          migrationVersion: localMigrationVersion,
        ),
      );
    final controller = AppController(
      captureStore: store,
      clock: () => _now,
      cloudRepository: repository,
      accountAuth: MemoryAccountAuth(
        session: AccountSession(uid: owner, email: '$owner@example.test'),
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();
    return (controller: controller, repository: repository);
  }

  test('first offer is opt-in and declining persists across restart', () async {
    final store = _CaptureStore();
    final controller = await local(store);
    expect(await controller.shouldOfferLearningSetup(), isTrue);
    expect(controller.ai1CaptureEnabled, isFalse);
    expect(controller.outcomeConsent, isFalse);
    expect(store.values, isEmpty);
    await controller.completeLearningSetup(enable: false);
    final restarted = await local(store);
    expect(await restarted.shouldOfferLearningSetup(), isFalse);
    expect(restarted.ai1CaptureEnabled, isFalse);
    expect(restarted.outcomeConsent, isFalse);
    expect(store.values, isEmpty);
  });

  test(
    'accepting enables both; later opt-outs stay off after restart',
    () async {
      final store = _CaptureStore();
      final controller = await local(store);
      await controller.completeLearningSetup(enable: true);
      expect(controller.ai1CaptureEnabled, isTrue);
      expect(controller.outcomeConsent, isTrue);
      final journal = jsonDecode(store.values['local']!) as Map;
      expect(journal['entries'], isEmpty);
      expect(journal['trainingEligible'], isFalse);
      expect(controller.outcomes, isEmpty);
      final restored = await local(store);
      expect(await restored.shouldOfferLearningSetup(), isFalse);
      expect(restored.ai1CaptureEnabled, isTrue);
      expect(restored.outcomeConsent, isTrue);
      await restored.setAi1CaptureEnabled(false);
      await restored.setOutcomeConsent(false);
      final optedOut = await local(store);
      expect(await optedOut.shouldOfferLearningSetup(), isFalse);
      expect(optedOut.ai1CaptureEnabled, isFalse);
      expect(optedOut.outcomeConsent, isFalse);
    },
  );

  test(
    'already enabled settings are not prompted or re-enabled after opt-out',
    () async {
      final controller = await local(_CaptureStore());
      await controller.setAi1CaptureEnabled(true);
      await controller.setOutcomeConsent(true);
      expect(await controller.shouldOfferLearningSetup(), isFalse);
      await controller.setAi1CaptureEnabled(false);
      expect(await controller.shouldOfferLearningSetup(), isFalse);
      expect(controller.ai1CaptureEnabled, isFalse);
    },
  );

  test(
    'local and different cloud owners never inherit a setup choice',
    () async {
      final store = _CaptureStore();
      final device = await local(store);
      await device.completeLearningSetup(enable: false);
      final first = await cloud(store, 'first-owner');
      expect(await first.controller.shouldOfferLearningSetup(), isTrue);
      await first.controller.completeLearningSetup(enable: false);
      final second = await cloud(store, 'second-owner');
      expect(await second.controller.shouldOfferLearningSetup(), isTrue);
      expect(second.controller.ai1CaptureEnabled, isFalse);
      expect(second.controller.outcomeConsent, isFalse);
      expect(first.repository.consentWrites, 0);
      expect(second.repository.consentWrites, 0);
    },
  );

  test(
    'failed cloud consent shows partial state and remains retryable',
    () async {
      final store = _CaptureStore();
      final account = await cloud(store, 'owner');
      account.repository.failConsent = true;
      await expectLater(
        account.controller.completeLearningSetup(enable: true),
        throwsStateError,
      );
      expect(account.controller.ai1CaptureEnabled, isTrue);
      expect(account.controller.outcomeConsent, isFalse);
      expect(await account.controller.shouldOfferLearningSetup(), isTrue);
      account.repository.failConsent = false;
      await account.controller.completeLearningSetup(enable: true);
      expect(account.controller.outcomeConsent, isTrue);
      expect(await account.controller.shouldOfferLearningSetup(), isFalse);
      expect(account.repository.consentWrites, 2);
    },
  );

  test('a local save failure cannot enable cloud outcome collection', () async {
    final store = _CaptureStore();
    final account = await cloud(store, 'owner');
    store.failWrites = true;
    await expectLater(
      account.controller.completeLearningSetup(enable: true),
      throwsStateError,
    );
    expect(account.controller.ai1CaptureEnabled, isFalse);
    expect(account.controller.outcomeConsent, isFalse);
    expect(account.repository.consentWrites, 0);
    expect(await account.controller.shouldOfferLearningSetup(), isTrue);
    await account.controller.completeLearningSetup(enable: false);
    expect(await account.controller.shouldOfferLearningSetup(), isFalse);
  });

  test(
    'sign-out during local activation cannot enable the next account',
    () async {
      final store = _CaptureStore();
      final controller = await local(store);
      store.writeStarted = Completer<void>();
      store.releaseWrite = Completer<void>();
      final pending = controller.completeLearningSetup(enable: true);
      final rejected = expectLater(pending, throwsStateError);
      await store.writeStarted!.future;
      await controller.signOut();
      store.releaseWrite!.complete();
      await rejected;
      expect(controller.outcomeConsent, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().where(
          (key) => key.startsWith('tonyo_learning_setup_v1_'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'unsupported platforms and missing privacy cannot auto-enroll',
    () async {
      final unsupported = await local(_CaptureStore()..available = false);
      expect(await unsupported.shouldOfferLearningSetup(), isFalse);
      await expectLater(
        unsupported.completeLearningSetup(enable: true),
        throwsStateError,
      );
      SharedPreferences.setMockInitialValues({});
      final minor = AppController(
        captureStore: _CaptureStore(),
        initialPrivacyConsent: PrivacyConsent(
          ageBand: PrivacyAgeBand.age16to17,
          region: PrivacyRegion.us,
          acceptedAt: _now,
        ),
        clock: () => _now,
      )..onboardingComplete = true;
      addTearDown(minor.dispose);
      await minor.load();
      expect(await minor.shouldOfferLearningSetup(), isFalse);
      await expectLater(
        minor.completeLearningSetup(enable: true),
        throwsStateError,
      );
      expect(minor.outcomeConsent, isFalse);
    },
  );

  testWidgets('first eligible launch asks consent before enabling both', (
    tester,
  ) async {
    final controller = (await tester.runAsync(() => local(_CaptureStore())))!;
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('learning-setup-prompt')), findsOneWidget);
    expect(controller.outcomeConsent, isFalse);
    expect(controller.ai1CaptureEnabled, isFalse);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('learning-setup-allow')),
      250,
    );
    await tester.tap(find.byKey(const Key('learning-setup-allow')));
    await tester.pumpAndSettle();
    expect(controller.outcomeConsent, isTrue);
    expect(controller.ai1CaptureEnabled, isTrue);
    expect(find.byKey(const Key('learning-setup-prompt')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a failed decline receipt never enables learning or blocks the app',
    (tester) async {
      SharedPreferencesStorePlatform.instance = _FailingChoicePreferences();
      final controller = (await tester.runAsync(() => local(_CaptureStore())))!;
      await tester.pumpWidget(TonyoApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('learning-setup-decline')),
        250,
      );
      await tester.tap(find.byKey(const Key('learning-setup-decline')));
      await tester.pumpAndSettle();
      expect(controller.ai1CaptureEnabled, isFalse);
      expect(controller.outcomeConsent, isFalse);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.textContaining('you may be asked again'), findsOneWidget);
      expect(await controller.shouldOfferLearningSetup(), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('decline remains usable at large text size and opens the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = (await tester.runAsync(() => local(_CaptureStore())))!;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('learning-setup-decline')),
      250,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('learning-setup-decline')));
    await tester.pumpAndSettle();
    expect(controller.ai1CaptureEnabled, isFalse);
    expect(controller.outcomeConsent, isFalse);
    expect(await controller.shouldOfferLearningSetup(), isFalse);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
