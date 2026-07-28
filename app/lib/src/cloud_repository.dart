import 'cloud_schema.dart';
import 'models.dart';

class AccountSession {
  const AccountSession({required this.uid, required this.email});

  final String uid;
  final String email;
}

abstract interface class AccountAuth {
  bool get isConfigured;
  AccountSession? get currentSession;

  Future<AccountSession> register({
    required String email,
    required String password,
  });

  Future<AccountSession> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();
  Future<void> deleteCurrentAccount();
}

/// Used when Firebase environment values have not been supplied.
class LocalOnlyAccountAuth implements AccountAuth {
  const LocalOnlyAccountAuth();

  @override
  bool get isConfigured => false;

  @override
  AccountSession? get currentSession => null;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) => throw StateError('Firebase is not configured.');

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => throw StateError('Firebase is not configured.');

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteCurrentAccount() async {}
}

class MemoryAccountAuth implements AccountAuth {
  MemoryAccountAuth({this.session, this.configured = true});

  AccountSession? session;
  final bool configured;

  @override
  bool get isConfigured => configured;

  @override
  AccountSession? get currentSession => session;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    if (!configured) throw StateError('Firebase is not configured.');
    session = AccountSession(
      uid: 'test-uid',
      email: email.trim().toLowerCase(),
    );
    return session!;
  }

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => register(email: email, password: password);

  @override
  Future<void> signOut() async {
    session = null;
  }

  @override
  Future<void> deleteCurrentAccount() async {
    session = null;
  }
}

abstract interface class CloudRepository {
  Future<CloudUserState?> readUser(String uid);

  /// Replaces the user profile, signals, and check-ins with a single logical
  /// snapshot. Implementations must reject a uid other than the signed-in uid.
  Future<void> replaceUser(String uid, CloudUserState state);

  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
  });

  Future<DailyCheckIn?> latestCheckIn(String uid);

  Future<List<SignalReading>> reactionBaselineWindow(
    String uid, {
    int limit = 14,
  });

  Future<Map<String, Object?>> exportUser(String uid);
  Future<void> deleteUserTree(String uid);
}

/// A uid-enforcing repository for deterministic unit tests and offline demos.
class MemoryCloudRepository implements CloudRepository {
  MemoryCloudRepository({required this.signedInUid});

  String? signedInUid;
  final Map<String, CloudUserState> _users = {};

  void seed(String uid, CloudUserState state) {
    _users[uid] = state;
  }

  void _authorize(String uid) {
    if (signedInUid == null || signedInUid != uid) {
      throw StateError('Cross-user repository access denied.');
    }
  }

  @override
  Future<CloudUserState?> readUser(String uid) async {
    _authorize(uid);
    return _users[uid];
  }

  @override
  Future<void> replaceUser(String uid, CloudUserState state) async {
    _authorize(uid);
    _users[uid] = state;
  }

  @override
  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
  }) async {
    _authorize(uid);
    final matches = (_users[uid]?.signals ?? const <SignalReading>[])
        .where(
          (reading) =>
              !reading.timestamp.isBefore(start) &&
              reading.timestamp.isBefore(end) &&
              (type == null || reading.type == type),
        )
        .toList();
    return matches..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<DailyCheckIn?> latestCheckIn(String uid) async {
    _authorize(uid);
    final values = [...?_users[uid]?.checkIns]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return values.firstOrNull;
  }

  @override
  Future<List<SignalReading>> reactionBaselineWindow(
    String uid, {
    int limit = 14,
  }) async {
    _authorize(uid);
    final values =
        (_users[uid]?.signals ?? const <SignalReading>[])
            .where((reading) => reading.type == SignalType.reactionTime)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return values.take(limit).toList();
  }

  @override
  Future<Map<String, Object?>> exportUser(String uid) async {
    _authorize(uid);
    return {
      'uid': uid,
      if (_users[uid] case final state?) ...state.toExportJson(),
    };
  }

  @override
  Future<void> deleteUserTree(String uid) async {
    _authorize(uid);
    _users.remove(uid);
  }
}
