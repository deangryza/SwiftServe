import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../domain/registration_otp_gateway.dart';
import '../../../shared/services/profile_draft_store.dart';

abstract final class RegistrationSmsConfig {
  static const enabled = bool.fromEnvironment('REGISTRATION_SMS_ENABLED');
  static const emulatorHost = String.fromEnvironment(
    'LOCAL_FIREBASE_EMULATOR_HOST',
  );
  static void validate({
    required bool enabled,
    required String project,
    required String host,
  }) {
    if (!kDebugMode ||
        !enabled ||
        project != 'demo-swiftserve-cleanup' ||
        !['127.0.0.1', 'localhost', '10.0.2.2'].contains(host)) {
      throw const RegistrationOtpException(
        'SMS registration is prepared for a demo Firebase emulator only. Live SMS is not enabled.',
      );
    }
  }
}

/// Explicit cancellation deletes only an unfinished emulator account created by
/// this session. Disposal/process interruption retains the bound recovery draft.
class RegistrationSmsAccount {
  RegistrationSmsAccount({
    required this.auth,
    required this.project,
    this.enabled = RegistrationSmsConfig.enabled,
    this.emulatorHost = RegistrationSmsConfig.emulatorHost,
    ProfileDraftStore? store,
  }) : store = store ?? ProfileDraftStore();
  final FirebaseAuth auth;
  final String project, emulatorHost;
  final bool enabled;
  final ProfileDraftStore store;
  User? _owned;
  bool _committed = false;
  String? get ownedUid => _owned?.uid;
  String? get reservedEmail => _owned?.email;
  void guard() => RegistrationSmsConfig.validate(
    enabled: enabled,
    project: project,
    host: emulatorHost,
  );
  ProfileDraft bind(ProfileDraft draft, User user) => ProfileDraft.fromJson({
    ...draft.toJson(),
    'phoneVerificationUid': user.uid,
    'phoneVerificationProject': project,
  });
  Future<User> prepare(ProfileDraft draft, String password) async {
    guard();
    if (_owned == null) {
      if (auth.currentUser != null) {
        throw const RegistrationOtpException(
          'Sign out before starting a new account registration.',
        );
      }
      _owned = (await auth.createUserWithEmailAndPassword(
        email: draft.email,
        password: password,
      )).user;
    }
    final user = _owned;
    if (user == null ||
        auth.currentUser?.uid != user.uid ||
        user.email?.toLowerCase() != draft.email.toLowerCase()) {
      throw const RegistrationOtpException(
        'Registration account changed. Cancel or resume the original account.',
      );
    }
    await store.save(bind(draft, user));
    return user;
  }

  void commit() => _committed = true;
  Future<void> cancel() async {
    guard();
    final user = _owned;
    if (user == null || _committed) return;
    if (auth.currentUser?.uid != user.uid) {
      throw const RegistrationOtpException(
        'Account changed. No account was deleted. Resume the original registration to cancel it.',
      );
    }
    await user.delete();
    final draft = await store.load();
    if (draft?.phoneVerificationUid == user.uid &&
        draft?.phoneVerificationProject == project) {
      await store.clear();
    }
    _owned = null;
  }
}

/// Uses the existing authenticated account. Never signs in with a phone
/// credential, merges users, or creates a separate phone-only account.
class FirebaseRegistrationOtp extends RegistrationOtpGateway {
  FirebaseRegistrationOtp({
    required this.auth,
    required this.prepareAccount,
    required this.project,
    this.enabled = RegistrationSmsConfig.enabled,
    this.emulatorHost = RegistrationSmsConfig.emulatorHost,
  });
  final FirebaseAuth auth;
  final Future<User> Function() prepareAccount;
  final String project, emulatorHost;
  final bool enabled;
  String? _uid, _phone, _verificationId, _verifiedPhone, _error;
  int? _resendToken;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _linking;
  Completer<void>? _pending;
  void _cancelPending() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const RegistrationOtpException(
          'This SMS request was cancelled. Request a new code.',
        ),
      );
    }
  }

  void _guard() => RegistrationSmsConfig.validate(
    enabled: enabled,
    project: project,
    host: emulatorHost,
  );
  @override
  String? get error => _error;
  @override
  bool verifiedFor(String phone) =>
      !_disposed &&
      _verifiedPhone == phone &&
      auth.currentUser?.uid == _uid &&
      auth.currentUser?.phoneNumber == phone;

  static String message(Object error) {
    if (error is RegistrationOtpException) return error.message;
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-verification-code' =>
          'Incorrect code. Check the SMS and try again.',
        'session-expired' || 'invalid-verification-id' =>
          'This code has expired. Request a new code.',
        'credential-already-in-use' || 'phone-number-already-exists' =>
          'This phone number is already linked to another account.',
        'invalid-phone-number' =>
          'Check your mobile number, including its country code.',
        'too-many-requests' || 'quota-exceeded' =>
          'Too many requests. Please wait before trying again.',
        'network-request-failed' =>
          'Could not connect. Check your connection and try again.',
        'operation-not-allowed' =>
          'Phone authentication is not configured in this test environment.',
        _ => 'Phone verification could not finish. Please try again.',
      };
    }
    return 'Phone verification could not finish. Please try again.';
  }

  @override
  Future<void> send(String phone, {bool resend = false}) async {
    _guard();
    _cancelPending();
    final generation = ++_generation;
    final previousPhone = _phone;
    _phone = phone;
    _verifiedPhone = null;
    _verificationId = null;
    _error = null;
    final account = await prepareAccount();
    if (_disposed || generation != _generation) return;
    if (auth.currentUser?.uid != account.uid ||
        (_uid != null && _uid != account.uid)) {
      throw const RegistrationOtpException(
        'Your signed-in account changed. Restart registration.',
      );
    }
    _uid = account.uid;
    final result = Completer<void>();
    _pending = result;
    bool active() =>
        !_disposed &&
        generation == _generation &&
        _phone == phone &&
        auth.currentUser?.uid == _uid;
    void fail(Object error) {
      if (!active()) return;
      _error = message(error);
      notifyListeners();
      if (!result.isCompleted) {
        result.completeError(RegistrationOtpException(_error!));
      }
    }

    try {
      final request = auth.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: resend && previousPhone == phone
            ? _resendToken
            : null,
        verificationCompleted: (credential) async {
          if (!active()) return;
          try {
            await _link(phone, credential, generation);
            if (!result.isCompleted) result.complete();
          } catch (error) {
            fail(error);
          }
        },
        verificationFailed: fail,
        codeSent: (id, token) {
          if (!active()) return;
          _verificationId = id;
          _resendToken = token;
          if (!result.isCompleted) result.complete();
        },
        codeAutoRetrievalTimeout: (id) {
          if (active()) _verificationId ??= id;
        },
      );
      await Future.wait<void>([
        request,
        result.future,
      ]).timeout(const Duration(seconds: 90));
    } on TimeoutException {
      if (active()) invalidate();
      throw const RegistrationOtpException(
        'The SMS request timed out. Check your emulator connection and retry.',
      );
    } finally {
      if (identical(_pending, result)) _pending = null;
    }
  }

  Future<void> _link(
    String phone,
    PhoneAuthCredential credential,
    int generation,
  ) async {
    if (_linking != null) return _linking;
    final operation = () async {
      _guard();
      final user = auth.currentUser;
      if (_disposed ||
          generation != _generation ||
          _phone != phone ||
          user == null ||
          user.uid != _uid) {
        throw const RegistrationOtpException(
          'This verification request is no longer active. Request a new code.',
        );
      }
      if (user.providerData.any((provider) => provider.providerId == 'phone')) {
        await user.updatePhoneNumber(credential);
      } else {
        await user.linkWithCredential(credential);
      }
      await user.reload();
      if (_disposed ||
          generation != _generation ||
          auth.currentUser?.uid != _uid ||
          auth.currentUser?.phoneNumber != phone) {
        throw const RegistrationOtpException(
          'Your phone or account changed. Request a new code.',
        );
      }
      await auth.currentUser!.getIdToken(true);
      _verifiedPhone = phone;
      _error = null;
      notifyListeners();
    }();
    _linking = operation;
    try {
      await operation;
    } finally {
      if (identical(_linking, operation)) _linking = null;
    }
  }

  @override
  Future<void> verify(String phone, String code) async {
    _guard();
    if (_verificationId == null ||
        _phone != phone ||
        !RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const RegistrationOtpException(
        'Request a code and enter all six digits.',
      );
    }
    try {
      await _link(
        phone,
        PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: code,
        ),
        _generation,
      );
    } catch (error) {
      throw RegistrationOtpException(message(error));
    }
  }

  Future<User> requireVerified(String phone) async {
    _guard();
    if (!verifiedFor(phone)) {
      throw const RegistrationOtpException(
        'Verify your current mobile number before finishing registration.',
      );
    }
    final user = auth.currentUser!;
    await user.reload();
    if (!verifiedFor(phone)) {
      throw const RegistrationOtpException(
        'Phone verification has changed. Please verify again.',
      );
    }
    await user.getIdToken(true);
    return user;
  }

  @override
  void invalidate() {
    _cancelPending();
    _generation++;
    _phone = null;
    _verificationId = null;
    _verifiedPhone = null;
    _error = null;
  }

  @override
  void dispose() {
    _disposed = true;
    invalidate();
    super.dispose();
  }
}
