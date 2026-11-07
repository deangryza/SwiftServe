import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/data/firebase_registration_otp.dart';
import 'package:my_app/features/auth/domain/registration_otp_gateway.dart';
import 'package:my_app/shared/services/profile_draft_store.dart';

class MemoryDrafts extends ProfileDraftStore {
  ProfileDraft? value;
  @override
  Future<ProfileDraft?> load() async => value;
  @override
  Future<void> save(ProfileDraft draft) async {
    value = draft;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FakeCredential extends Fake implements UserCredential {
  FakeCredential(this.value);
  final User value;
  @override
  User get user => value;
}

class PhoneProvider extends Fake implements UserInfo {
  @override
  String get providerId => 'phone';
}

class FakeUser extends Fake implements User {
  FakeUser(this.auth, {this.id = 'synthetic-new-user'});
  final FakeAuth auth;
  final String id;
  String? number;
  int links = 0, updates = 0, deletes = 0;
  bool rejectCode = false, rejectDelete = false;
  @override
  String get uid => id;
  @override
  String get email => 'synthetic@example.test';
  @override
  String? get phoneNumber => number;
  @override
  List<UserInfo> get providerData => number == null ? [] : [PhoneProvider()];
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    if (rejectCode || (credential as PhoneAuthCredential).smsCode != '123456') {
      throw FirebaseAuthException(code: 'invalid-verification-code');
    }
    links++;
    number = auth.requestedPhone;
    return FakeCredential(this);
  }

  @override
  Future<void> updatePhoneNumber(PhoneAuthCredential credential) async {
    if (rejectCode) {
      throw FirebaseAuthException(code: 'invalid-verification-code');
    }
    updates++;
    number = auth.requestedPhone;
  }

  @override
  Future<void> reload() async {}
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'synthetic-test-token';
  @override
  Future<void> delete() async {
    if (rejectDelete) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    deletes++;
    auth.user = null;
  }
}

class FakeAuth extends Fake implements FirebaseAuth {
  FakeUser? user;
  int creates = 0, sends = 0;
  String? requestedPhone;
  int? lastResend;
  bool failSend = false, deferCode = false, instant = false;
  final List<PhoneCodeSent> callbacks = [];
  PhoneVerificationCompleted? lastAutomaticCallback;
  @override
  User? get currentUser => user;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creates++;
    user = FakeUser(this);
    return FakeCredential(user!);
  }

  @override
  Future<void> verifyPhoneNumber({
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    String? autoRetrievedSmsCodeForTesting,
    Duration timeout = const Duration(seconds: 30),
    int? forceResendingToken,
    MultiFactorSession? multiFactorSession,
  }) async {
    sends++;
    lastAutomaticCallback = verificationCompleted;
    requestedPhone = phoneNumber;
    lastResend = forceResendingToken;
    callbacks.add(codeSent);
    if (failSend) {
      verificationFailed(FirebaseAuthException(code: 'network-request-failed'));
      return;
    }
    if (instant) {
      verificationCompleted(
        PhoneAuthProvider.credential(
          verificationId: 'synthetic',
          smsCode: '123456',
        ),
      );
      return;
    }
    if (!deferCode) codeSent('synthetic-session-$sends', 42);
  }
}

const draft = ProfileDraft(
  fullName: 'Synthetic User',
  email: 'synthetic@example.test',
  phoneNumber: '+639171111111',
  address: 'Synthetic Barangay, Test City, Test Province',
  role: 'client',
  dateOfBirth: '2000-01-01',
);
const project = 'demo-swiftserve-cleanup';
FirebaseRegistrationOtp gateway(FakeAuth auth) => FirebaseRegistrationOtp(
  auth: auth,
  enabled: true,
  project: project,
  emulatorHost: '127.0.0.1',
  prepareAccount: () async => auth.user!,
);

void main() {
  test(
    'disabled mode, production, staging, unknown projects and remote hosts fail closed',
    () {
      for (final entry in [
        (false, project, '127.0.0.1'),
        (true, 'swiftserve-production', '127.0.0.1'),
        (true, 'swiftserve-staging-2026', '127.0.0.1'),
        (true, 'demo-unknown', '127.0.0.1'),
        (true, project, ''),
        (true, project, 'example.com'),
      ]) {
        expect(
          () => RegistrationSmsConfig.validate(
            enabled: entry.$1,
            project: entry.$2,
            host: entry.$3,
          ),
          throwsA(isA<RegistrationOtpException>()),
        );
      }
      RegistrationSmsConfig.validate(
        enabled: true,
        project: project,
        host: '127.0.0.1',
      );
    },
  );
  test('wrong project cannot create an Auth account or send SMS', () async {
    final auth = FakeAuth();
    var prepared = false;
    final otp = FirebaseRegistrationOtp(
      auth: auth,
      enabled: true,
      project: 'swiftserve-production',
      emulatorHost: '127.0.0.1',
      prepareAccount: () async {
        prepared = true;
        return auth.user!;
      },
    );
    await expectLater(
      otp.send(draft.phoneNumber),
      throwsA(isA<RegistrationOtpException>()),
    );
    expect(prepared, isFalse);
    expect(auth.creates, 0);
    expect(auth.sends, 0);
    otp.dispose();
  });
  test(
    'code confirmation links the same email account, not a new phone account',
    () async {
      final auth = FakeAuth();
      final user = FakeUser(auth);
      auth.user = user;
      final otp = gateway(auth);
      await otp.send(draft.phoneNumber);
      expect(otp.verifiedFor(draft.phoneNumber), isFalse);
      await otp.verify(draft.phoneNumber, '123456');
      expect(otp.verifiedFor(draft.phoneNumber), isTrue);
      expect(user.uid, 'synthetic-new-user');
      expect(user.links, 1);
      expect(auth.creates, 0);
      expect(await otp.requireVerified(draft.phoneNumber), same(user));
      otp.dispose();
    },
  );
  test(
    'invalid codes, incomplete codes and account changes never verify',
    () async {
      final auth = FakeAuth();
      final user = FakeUser(auth);
      auth.user = user;
      final otp = gateway(auth);
      await otp.send(draft.phoneNumber);
      for (final code in ['123', '000000']) {
        await expectLater(
          otp.verify(draft.phoneNumber, code),
          throwsA(isA<RegistrationOtpException>()),
        );
        expect(otp.verifiedFor(draft.phoneNumber), isFalse);
      }
      auth.user = FakeUser(auth, id: 'another-user');
      await expectLater(
        otp.verify(draft.phoneNumber, '123456'),
        throwsA(isA<RegistrationOtpException>()),
      );
      expect(user.links, 0);
      otp.dispose();
    },
  );
  test(
    'changing phone invalidates old proof and uses update on the same UID',
    () async {
      final auth = FakeAuth();
      final user = FakeUser(auth);
      auth.user = user;
      final otp = gateway(auth);
      await otp.send(draft.phoneNumber);
      await otp.verify(draft.phoneNumber, '123456');
      otp.invalidate();
      expect(otp.verifiedFor(draft.phoneNumber), isFalse);
      const changed = '+639172222222';
      await otp.send(changed);
      await otp.verify(changed, '123456');
      expect(user.links, 1);
      expect(user.updates, 1);
      expect(otp.verifiedFor(changed), isTrue);
      expect(otp.verifiedFor(draft.phoneNumber), isFalse);
      otp.dispose();
    },
  );
  test('resend passes its SDK token only for the same phone', () async {
    final auth = FakeAuth()..user = null;
    auth.user = FakeUser(auth);
    final otp = gateway(auth);
    await otp.send(draft.phoneNumber);
    await otp.send(draft.phoneNumber, resend: true);
    expect(auth.lastResend, 42);
    await otp.send('+639172222222', resend: true);
    expect(auth.lastResend, isNull);
    otp.dispose();
  });
  test('automatic verification confirms the same account once', () async {
    final auth = FakeAuth()..instant = true;
    auth.user = FakeUser(auth);
    final otp = gateway(auth);
    await otp.send(draft.phoneNumber);
    expect(otp.verifiedFor(draft.phoneNumber), isTrue);
    expect(auth.user!.links, 1);
    otp.dispose();
  });
  test(
    'SDK send failure is handled without unhandled errors or false success',
    () async {
      final auth = FakeAuth()..failSend = true;
      auth.user = FakeUser(auth);
      final otp = gateway(auth);
      await expectLater(
        otp.send(draft.phoneNumber),
        throwsA(isA<RegistrationOtpException>()),
      );
      expect(otp.verifiedFor(draft.phoneNumber), isFalse);
      otp.dispose();
    },
  );
  test(
    'unfinished account and recovery draft are reused; explicit cancel removes only owned account',
    () async {
      final auth = FakeAuth();
      final store = MemoryDrafts();
      final account = RegistrationSmsAccount(
        auth: auth,
        project: project,
        enabled: true,
        emulatorHost: '127.0.0.1',
        store: store,
      );
      final user = await account.prepare(draft, 'synthetic-password');
      await account.prepare(draft, 'synthetic-password');
      expect(auth.creates, 1);
      expect(store.value!.phoneVerificationUid, user.uid);
      expect(store.value!.phoneVerificationProject, project);
      final roundtrip = ProfileDraft.fromJson(store.value!.toJson());
      expect(roundtrip.phoneVerificationUid, user.uid);
      await account.cancel();
      expect(auth.user, isNull);
      expect(store.value, isNull);
    },
  );
  test(
    'existing and committed accounts cannot be deleted by cancellation',
    () async {
      final auth = FakeAuth();
      final existing = FakeUser(auth, id: 'existing');
      auth.user = existing;
      final account = RegistrationSmsAccount(
        auth: auth,
        project: project,
        enabled: true,
        emulatorHost: '127.0.0.1',
        store: MemoryDrafts(),
      );
      await expectLater(
        account.prepare(draft, 'synthetic-password'),
        throwsA(isA<RegistrationOtpException>()),
      );
      await account.cancel();
      expect(existing.deletes, 0);
      auth.user = null;
      final created =
          await account.prepare(draft, 'synthetic-password') as FakeUser;
      account.commit();
      await account.cancel();
      expect(created.deletes, 0);
    },
  );
  test(
    'failed cancellation retains account and recovery draft for retry',
    () async {
      final auth = FakeAuth();
      final store = MemoryDrafts();
      final account = RegistrationSmsAccount(
        auth: auth,
        project: project,
        enabled: true,
        emulatorHost: '127.0.0.1',
        store: store,
      );
      final created =
          await account.prepare(draft, 'synthetic-password') as FakeUser;
      created.rejectDelete = true;
      await expectLater(
        account.cancel(),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(store.value, isNotNull);
      expect(auth.user, same(created));
      created.rejectDelete = false;
      await account.cancel();
      expect(store.value, isNull);
    },
  );
  test(
    'legacy profile drafts remain readable without changing existing verification state',
    () {
      final decoded = ProfileDraft.fromJson(draft.toJson());
      expect(decoded.phoneVerificationUid, isEmpty);
      expect(decoded.phoneVerificationProject, isEmpty);
    },
  );
  test(
    'cancelled requests ignore late callbacks and never link a phone',
    () async {
      final auth = FakeAuth()..deferCode = true;
      final user = FakeUser(auth);
      auth.user = user;
      final otp = gateway(auth);
      final request = otp.send(draft.phoneNumber);
      final cancelled = expectLater(
        request,
        throwsA(isA<RegistrationOtpException>()),
      );
      await Future<void>.delayed(Duration.zero);
      otp.invalidate();
      auth.callbacks.single('obsolete-session', 1);
      auth.lastAutomaticCallback!(
        PhoneAuthProvider.credential(
          verificationId: 'obsolete-session',
          smsCode: '123456',
        ),
      );
      await cancelled;
      await Future<void>.delayed(Duration.zero);
      expect(user.links, 0);
      expect(otp.verifiedFor(draft.phoneNumber), isFalse);
      otp.dispose();
    },
  );
  test(
    'cancellation refuses an account switch and preserves both accounts',
    () async {
      final auth = FakeAuth();
      final store = MemoryDrafts();
      final account = RegistrationSmsAccount(
        auth: auth,
        project: project,
        enabled: true,
        emulatorHost: '127.0.0.1',
        store: store,
      );
      final original =
          await account.prepare(draft, 'synthetic-password') as FakeUser;
      final other = FakeUser(auth, id: 'another-account');
      auth.user = other;
      await expectLater(
        account.cancel(),
        throwsA(isA<RegistrationOtpException>()),
      );
      expect(original.deletes, 0);
      expect(other.deletes, 0);
      expect(store.value, isNotNull);
    },
  );
}
