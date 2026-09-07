import 'dart:async';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _DelayedPrivacyRepository extends MemoryCloudRepository {
  _DelayedPrivacyRepository() : super(signedInUid: 'owner');
  final reads = <Completer<AccountPrivacySnapshot>>[];

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) {
    final result = Completer<AccountPrivacySnapshot>();
    reads.add(result);
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppController controllerFor(_DelayedPrivacyRepository repository) =>
      AppController(
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: 'owner',
            email: 'owner@example.com',
          ),
        ),
        cloudRepository: repository,
        initialPrivacyConsent: testAdultPrivacyConsent,
      );

  test(
    'older foreground privacy read cannot undo a newer withdrawal',
    () async {
      final repository = _DelayedPrivacyRepository();
      final controller = controllerFor(repository);
      final first = controller.handleAppResumed();
      await Future<void>.delayed(Duration.zero);
      final second = controller.handleAppResumed();
      await Future<void>.delayed(Duration.zero);
      expect(repository.reads, hasLength(2));
      repository.reads[1].complete((
        consent: null,
        deletionPending: false,
        outcomeConsent: false,
        outcomeConsentUpdatedAt: null,
      ));
      await second;
      expect(controller.privacyFeaturesAllowed, false);
      repository.reads[0].complete((
        consent: testAdultPrivacyConsent,
        deletionPending: false,
        outcomeConsent: true,
        outcomeConsentUpdatedAt: DateTime.utc(2020),
      ));
      await first;
      expect(controller.privacyFeaturesAllowed, false);
      expect(controller.outcomeConsent, false);
      controller.dispose();
    },
  );

  test(
    'late privacy read failure cannot add an error after sign-out',
    () async {
      final repository = _DelayedPrivacyRepository();
      final controller = controllerFor(repository);
      final request = controller.handleAppResumed();
      await Future<void>.delayed(Duration.zero);
      await controller.signOut();
      repository.reads.single.completeError(StateError('old account failure'));
      await request;
      expect(controller.isSignedOut, true);
      expect(controller.privacyOperationError, isNull);
      controller.dispose();
    },
  );
}
