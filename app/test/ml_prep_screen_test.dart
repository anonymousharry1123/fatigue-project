import 'privacy_test_support.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/ml_prep_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PrepSource implements PrepDataSource {
  _PrepSource(this.auth);

  final MemoryAccountAuth auth;
  int metadataReads = 0;
  int collectionQueries = 0;
  final List<int> limits = [];

  @override
  String? get currentUid => auth.currentSession?.uid;

  @override
  Future<PrepAccountMetadata> readAccount(String uid) async {
    metadataReads++;
    return const PrepAccountMetadata(
      consent: PrepConsent(collection: false, trainingUse: false, version: 0),
      schemaVersion: 7,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> readCollection(
    String uid,
    PrepCollection collection,
    PrepWindow window, {
    required int limit,
  }) async {
    collectionQueries++;
    limits.add(limit);
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, AppController controller) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildTonyoTheme(),
          home: MlPrepScreen(controller: controller),
        ),
      );

  testWidgets(
    'unconfigured build explains Firebase blocker and disables reads',
    (tester) async {
      await open(
        tester,
        AppController(initialPrivacyConsent: testAdultPrivacyConsent),
      );
      expect(find.textContaining('Firebase is not configured'), findsOneWidget);
      final prepare = tester.widget<FilledButton>(
        find.byKey(const Key('prepare-model-snapshot')),
      );
      expect(prepare.onPressed, isNull);
    },
  );

  testWidgets('signed-out configured build explains the account sign-in gate', (
    tester,
  ) async {
    final auth = MemoryAccountAuth();
    final source = _PrepSource(auth);
    await open(
      tester,
      AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        accountAuth: auth,
        cloudRepository: MemoryCloudRepository(signedInUid: null),
        prepDataSource: source,
      ),
    );
    expect(find.textContaining('Sign in through Profile'), findsOneWidget);
    expect(source.metadataReads, 0);
    expect(source.collectionQueries, 0);
  });

  testWidgets('navigation does not read, explicit prep caches without writes', (
    tester,
  ) async {
    final auth = MemoryAccountAuth(
      session: const AccountSession(
        uid: 'prep-user',
        email: 'prep@example.com',
      ),
    );
    final source = _PrepSource(auth);
    final repository = MemoryCloudRepository(signedInUid: 'prep-user');
    final controller = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
      accountAuth: auth,
      cloudRepository: repository,
      prepDataSource: source,
    );
    await open(tester, controller);
    expect(source.metadataReads, 0);
    expect(source.collectionQueries, 0);

    await tester.ensureVisible(find.byKey(const Key('prepare-model-snapshot')));
    await tester.tap(find.byKey(const Key('prepare-model-snapshot')));
    await tester.pumpAndSettle();
    expect(source.metadataReads, 1);
    expect(source.collectionQueries, 3);
    expect(source.limits, unorderedEquals([1500, 100, 100]));
    expect(repository.replaceUserCallCount, 0);
    expect(controller.outcomeConsent, isFalse);

    await tester.pumpWidget(const SizedBox());
    await open(tester, controller);
    expect(source.collectionQueries, 3);
    await tester.ensureVisible(find.byKey(const Key('prepare-model-snapshot')));
    await tester.tap(find.byKey(const Key('prepare-model-snapshot')));
    await tester.pumpAndSettle();
    expect(source.metadataReads, 1);
    expect(source.collectionQueries, 3);
    expect(repository.replaceUserCallCount, 0);

    await tester.ensureVisible(find.byKey(const Key('refresh-model-snapshot')));
    await tester.tap(find.byKey(const Key('refresh-model-snapshot')));
    await tester.pumpAndSettle();
    expect(source.metadataReads, 2);
    expect(source.collectionQueries, 6);
    expect(repository.replaceUserCallCount, 0);
  });

  test(
    'controller returns persisted snapshot without a second account read',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'prep-user',
          email: 'prep@example.com',
        ),
      );
      final source = _PrepSource(auth);
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        accountAuth: auth,
        cloudRepository: MemoryCloudRepository(signedInUid: 'prep-user'),
        prepDataSource: source,
      );
      final window = PrepWindow.endingOn(
        DateTime(2026, 7, 31),
        timezone: 'America/Los_Angeles',
      );
      final first = await controller.prepareModelSnapshot(window: window);
      expect(
        PrepSnapshot.fromJson(
          first.snapshot.toJson(),
          uid: 'prep-user',
        ).fingerprint,
        first.snapshot.fingerprint,
      );
      final next = await controller.prepareModelSnapshot(window: window);
      expect(next.cacheHit, isTrue);
      expect(next.snapshot.fingerprint, first.snapshot.fingerprint);
      expect(source.metadataReads, 1);
      expect(source.collectionQueries, 3);
    },
  );

  test(
    'nondefault window survives screen reopen and app restart without prep reads',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'prep-user',
          email: 'prep@example.com',
        ),
      );
      final source = _PrepSource(auth);
      final repository = MemoryCloudRepository(signedInUid: 'prep-user');
      repository.seed(
        'prep-user',
        CloudUserState(
          privacyConsent: testAdultPrivacyConsent,
          profile: const UserProfile(),
          accountEmail: 'prep@example.com',
          onboardingComplete: false,
          notificationsEnabled: false,
          outcomeConsent: false,
          healthAuthorized: false,
          migrationVersion: localMigrationVersion,
          signals: const [],
          checkIns: const [],
        ),
      );
      final original = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        accountAuth: auth,
        cloudRepository: repository,
        prepDataSource: source,
      );
      final window = PrepWindow.endingOn(
        DateTime(2026, 7, 31),
        timezone: 'UTC',
      );
      await original.prepareModelSnapshot(window: window);
      expect(original.lastModelPreparationWindow?.toJson(), window.toJson());

      final restored = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        accountAuth: auth,
        cloudRepository: repository,
        prepDataSource: source,
      );
      await restored.load();
      expect(restored.lastModelPreparationWindow?.toJson(), window.toJson());
      expect(source.metadataReads, 1);
      expect(source.collectionQueries, 3);
      final repeated = await restored.prepareModelSnapshot(
        window: restored.lastModelPreparationWindow!,
      );
      expect(repeated.cacheHit, isTrue);
      expect(source.metadataReads, 1);
      expect(source.collectionQueries, 3);

      final otherAccount = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: 'other-user',
            email: 'other@example.com',
          ),
        ),
        cloudRepository: MemoryCloudRepository(signedInUid: 'other-user'),
      );
      await otherAccount.load();
      expect(otherAccount.lastModelPreparationWindow, isNull);
    },
  );

  testWidgets('reopened page retains July window and reuses the snapshot', (
    tester,
  ) async {
    final auth = MemoryAccountAuth(
      session: const AccountSession(
        uid: 'prep-user',
        email: 'prep@example.com',
      ),
    );
    final source = _PrepSource(auth);
    final controller = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
      accountAuth: auth,
      cloudRepository: MemoryCloudRepository(signedInUid: 'prep-user'),
      prepDataSource: source,
    );
    await controller.prepareModelSnapshot(
      window: PrepWindow.endingOn(DateTime(2026, 7, 31), timezone: 'UTC'),
    );
    await open(tester, controller);
    expect(find.text('Window ends 2026-07-31'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('prep-timezone')))
          .controller
          ?.text,
      'Etc/UTC',
    );
    expect(source.collectionQueries, 3);
    await tester.pumpWidget(const SizedBox());
    await open(tester, controller);
    expect(find.text('Window ends 2026-07-31'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('prepare-model-snapshot')));
    await tester.tap(find.byKey(const Key('prepare-model-snapshot')));
    await tester.pumpAndSettle();
    expect(source.metadataReads, 1);
    expect(source.collectionQueries, 3);
  });

  test(
    'sign-out clears prep cache and prevents further account reads',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'prep-user',
          email: 'prep@example.com',
        ),
      );
      final source = _PrepSource(auth);
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        accountAuth: auth,
        cloudRepository: MemoryCloudRepository(signedInUid: 'prep-user'),
        prepDataSource: source,
      );
      final window = PrepWindow.endingOn(
        DateTime(2026, 7, 31),
        timezone: 'UTC',
      );
      await controller.prepareModelSnapshot(window: window);
      await controller.signOut();
      expect(controller.lastModelPreparationWindow, isNull);
      expect(source.collectionQueries, 3);
      expect(
        (await SharedPreferences.getInstance()).getKeys().where(
          (key) => key.startsWith('tonyo_ml_prep_'),
        ),
        isEmpty,
      );
      await expectLater(
        controller.prepareModelSnapshot(window: window),
        throwsStateError,
      );
      expect(source.collectionQueries, 3);
    },
  );

  test(
    'controller edit invalidates prep without launching automatic reads',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'prep-user',
          email: 'prep@example.com',
        ),
      );
      final source = _PrepSource(auth);
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        accountAuth: auth,
        cloudRepository: MemoryCloudRepository(signedInUid: 'prep-user'),
        prepDataSource: source,
      );
      final window = PrepWindow.endingOn(
        DateTime(2026, 7, 31),
        timezone: 'UTC',
      );
      await controller.prepareModelSnapshot(window: window);
      await controller.updateProfile(const UserProfile(name: 'Edited'));
      expect(source.collectionQueries, 3);
      await controller.prepareModelSnapshot(window: window);
      expect(source.collectionQueries, 6);
    },
  );
}
