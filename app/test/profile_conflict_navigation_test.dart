import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/screens/sync_conflict_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

CloudUserState _state(String name) => CloudUserState(
  profile: UserProfile(name: name),
  accountEmail: 'owner@example.com',
  onboardingComplete: false,
  notificationsEnabled: false,
  outcomeConsent: false,
  healthAuthorized: false,
  signals: const [],
  checkIns: const [],
  migrationVersion: localMigrationVersion,
  notificationPrefsVersion: notificationPreferencesVersion,
  privacyConsent: testAdultPrivacyConsent,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Profile shows sync details and opens per-field conflict review',
    (tester) async {
      final repo = MemoryCloudRepository(signedInUid: 'owner')
        ..seed('owner', _state('Original'));
      final controller = AppController(
        cloudRepository: repo,
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: 'owner',
            email: 'owner@example.com',
          ),
        ),
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => DateTime(2026, 9, 19, 12),
      );
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await controller.load();
        repo.seed('owner', _state('Cloud name'));
        await controller.updateProfile(
          controller.profile.copyWith(name: 'Phone name'),
        );
      });
      expect(controller.cloudSyncConflict, true);
      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: MaterialApp(
            theme: buildTonyoTheme(),
            home: const Scaffold(body: ProfileScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloud-sync-status')), findsOneWidget);
      expect(find.text(controller.cloudSyncStatusMessage), findsOneWidget);
      expect(find.text('1 pending changes'), findsOneWidget);
      expect(find.byKey(const Key('cloud-sync-last-success')), findsOneWidget);
      final review = find.byKey(const Key('cloud-sync-review-conflicts'));
      await tester.scrollUntilVisible(review, 200);
      await tester.ensureVisible(review);
      await tester.pumpAndSettle();
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.byType(SyncConflictScreen), findsOneWidget);
      expect(find.text('Phone name'), findsOneWidget);
      expect(find.text('Cloud name'), findsOneWidget);
      expect(controller.profile.name, 'Phone name');
      expect((await repo.readUser('owner'))!.profile.name, 'Cloud name');
      expect(tester.takeException(), isNull);
    },
  );
}
