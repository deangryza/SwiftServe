import '../widgets/registration_birthday_field.dart';
import '../../../../shared/utils/registration_birthday.dart';
import 'package:my_app/shared/services/expiry_push_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/profile_draft_store.dart';
import '../../data/firebase_registration_otp.dart';
import '../../data/iprog_registration_otp.dart';
import '../../domain/registration_otp_gateway.dart';
import '../widgets/registration_otp_screen.dart';

class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  State<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final _birthday = TextEditingController();
  ProfileDraft? _draft;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final draft = await ProfileDraftStore().load();
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _birthday.text = draft?.dateOfBirth ?? '';
      _loading = false;
    });
  }

  Future<void> _retry() async {
    final user = FirebaseAuth.instance.currentUser;
    var draft = _draft;
    if (user == null || draft == null) return;
    if (!RegistrationSmsConfig.enabled &&
        draft.phoneVerificationToken == null) {
      draft = await _verifyWithSms(draft);
      if (draft == null) return;
    }
    final birthdayError = RegistrationBirthday.validate(_birthday.text);
    if (birthdayError != null) {
      setState(() => _error = birthdayError);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (draft.phoneVerificationUid.isNotEmpty &&
          !await _verifyRecoveredPhone(draft)) {
        return;
      }
      await ProfileDraftStore().save(
        ProfileDraft.fromJson({
          ...draft.toJson(),
          'dateOfBirth': _birthday.text,
        }),
      );
      final token = await user.getIdToken(true);
      await ApiService().createUserProfile(
        idToken: token!,
        dateOfBirth: _birthday.text,
        fullName: draft.fullName,
        email: draft.email,
        phoneNumber: draft.phoneNumber,
        address: draft.address,
        role: draft.role,
        category: draft.category,
        skills: draft.skills,
        photoBase64: draft.photoBase64,
        phoneVerificationToken: draft.phoneVerificationToken,
      );
      await ProfileDraftStore().clear();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on RegistrationOtpException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on ApiException catch (error) {
      if (error.code == 'PHONE_VERIFICATION_REQUIRED') {
        // The saved SMS proof expired; the next retry asks for a new code.
        final cleared = draft.withPhoneVerificationToken(null);
        await ProfileDraftStore().save(cleared);
        _draft = cleared;
      }
      if (mounted) setState(() => _error = error.message);
    } on ApiConnectionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The profile could not be saved. Check the backend and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Live SMS (IPROG via the backend): asks for a code and saves the proof.
  Future<ProfileDraft?> _verifyWithSms(ProfileDraft draft) async {
    final gateway = IprogRegistrationOtp();
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => RegistrationOtpScreen(
            phone: draft.phoneNumber,
            gateway: gateway,
            verifyButtonKey: const ValueKey('recovery-sms-verify'),
            onVerified: () => Navigator.pop(context, 'verified'),
            onEditPhone: () => Navigator.pop(context, 'edit'),
            onBack: () => Navigator.pop(context, 'back'),
          ),
        ),
      );
      final token = gateway.tokenFor(draft.phoneNumber);
      if (result != 'verified' || token == null) return null;
      final updated = draft.withPhoneVerificationToken(token);
      await ProfileDraftStore().save(updated);
      _draft = updated;
      return updated;
    } finally {
      gateway.dispose();
    }
  }

  Future<bool> _verifyRecoveredPhone(ProfileDraft draft) async {
    final auth = FirebaseAuth.instance;
    final project = auth.app.options.projectId;
    RegistrationSmsConfig.validate(
      enabled: RegistrationSmsConfig.enabled,
      project: project,
      host: RegistrationSmsConfig.emulatorHost,
    );
    if (draft.phoneVerificationUid != auth.currentUser?.uid ||
        draft.phoneVerificationProject != project) {
      throw const RegistrationOtpException(
        'This recovery draft belongs to another account or Firebase project. No profile was saved.',
      );
    }
    await auth.currentUser!.reload();
    if (auth.currentUser?.phoneNumber == draft.phoneNumber) return true;
    if (!mounted) return false;
    final gateway = FirebaseRegistrationOtp(
      auth: auth,
      project: project,
      prepareAccount: () async {
        final user = auth.currentUser;
        if (user == null || user.uid != draft.phoneVerificationUid) {
          throw const RegistrationOtpException(
            'Your signed-in account changed.',
          );
        }
        return user;
      },
    );
    String? result;
    try {
      result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => RegistrationOtpScreen(
            phone: draft.phoneNumber,
            gateway: gateway,
            verifyButtonKey: const ValueKey('recovery-otp-verify'),
            onVerified: () => Navigator.pop(context, 'verified'),
            onEditPhone: () => Navigator.pop(context, 'edit'),
            onBack: () => Navigator.pop(context, 'back'),
          ),
        ),
      );
    } finally {
      gateway.dispose();
    }
    if (result == 'edit' && mounted) {
      final number = await showDialog<String>(
        context: context,
        builder: (_) => _RecoveryPhoneDialog(phone: draft.phoneNumber),
      );
      if (number != null) {
        final updated = ProfileDraft.fromJson({
          ...draft.toJson(),
          'phoneNumber': number,
        });
        await ProfileDraftStore().save(updated);
        if (mounted) setState(() => _draft = updated);
      }
      return false;
    }
    return result == 'verified' &&
        auth.currentUser?.uid == draft.phoneVerificationUid &&
        auth.currentUser?.phoneNumber == draft.phoneNumber;
  }

  @override
  void dispose() {
    _birthday.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    await ExpiryPushService.instance.beforeSignOut();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Complete profile')),
    body: Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 52),
                    const SizedBox(height: 16),
                    Text(
                      _draft == null
                          ? 'No saved profile draft was found. Sign out and register again.'
                          : 'Your account exists, but the SwiftServe profile has not been saved yet.',
                      textAlign: TextAlign.center,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.ink),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_draft != null)
                      RegistrationBirthdayField(
                        controller: _birthday,
                        enabled: !_loading,
                      ),
                    if (_draft != null)
                      FilledButton(
                        onPressed: _retry,
                        child: const Text('Retry profile setup'),
                      ),
                    TextButton(
                      onPressed: _signOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class _RecoveryPhoneDialog extends StatefulWidget {
  const _RecoveryPhoneDialog({required this.phone});
  final String phone;
  @override
  State<_RecoveryPhoneDialog> createState() => _RecoveryPhoneDialogState();
}

class _RecoveryPhoneDialogState extends State<_RecoveryPhoneDialog> {
  late final _controller = TextEditingController(text: widget.phone);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit mobile number'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Mobile number',
          hintText: '+639171234567',
        ),
        validator: (value) =>
            RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value?.trim() ?? '')
            ? null
            : 'Include + and your country code.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: const Text('Save number'),
      ),
    ],
  );
}
