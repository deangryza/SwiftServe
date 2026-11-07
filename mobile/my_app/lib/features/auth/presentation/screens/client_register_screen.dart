import '../../domain/registration_identity_draft.dart';
import '../../../../shared/models/app_user.dart';
import '../../../worker/presentation/screens/worker_verification_screen.dart';
import '../../data/firebase_registration_otp.dart';
import '../../data/iprog_registration_otp.dart';
import '../../domain/registration_otp_gateway.dart';
import '../../../../shared/utils/registration_birthday.dart';
import 'dart:typed_data';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/policy_consent.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../shared/services/profile_photo_picker.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/profile_draft_store.dart';
import '../../../../shared/services/client_theme_controller.dart';
import '../../../../shared/models/worker_service_selection.dart';
import 'profile_completion_screen.dart';
import 'client_account_form.dart';
import 'worker_account_form.dart';
import '../widgets/phone_number_field.dart';
import '../widgets/registration_contact_fields.dart';

class ClientRegisterScreen extends StatelessWidget {
  const ClientRegisterScreen({
    super.key,
    this.contactAvailability,
    this.smsGateway,
  });
  final ContactAvailabilityLookup? contactAvailability;
  final IprogRegistrationOtp? smsGateway;

  @override
  Widget build(BuildContext context) => AccountRegistrationScreen(
    role: 'client',
    contactAvailability: contactAvailability,
    smsGateway: smsGateway,
  );
}

class AccountRegistrationScreen extends StatefulWidget {
  const AccountRegistrationScreen({
    super.key,
    required this.role,
    this.contactAvailability,
    this.smsGateway,
  });

  final String role;
  final ContactAvailabilityLookup? contactAvailability;

  /// Live SMS codes (IPROG SMS via the backend). Tests can inject one.
  final IprogRegistrationOtp? smsGateway;

  @override
  State<AccountRegistrationScreen> createState() =>
      _AccountRegistrationScreenState();
}

class _AccountRegistrationScreenState extends State<AccountRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _birthday = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _category = TextEditingController();
  final _services = WorkerServiceSelection();
  final _identity = RegistrationIdentityDraft();
  bool _acceptedTerms = false;
  bool _loading = false;
  String _countryCode = '+63';
  Uint8List? _profileImageBytes;
  RegistrationSmsAccount? _smsAccount;
  FirebaseRegistrationOtp? _otp;

  /// Used whenever the emulator-only Firebase SMS flow is off (the real app).
  late final IprogRegistrationOtp? _iprogOtp = RegistrationSmsConfig.enabled
      ? null
      : (widget.smsGateway ?? IprogRegistrationOtp());

  @override
  void initState() {
    super.initState();
    if (RegistrationSmsConfig.enabled) {
      final auth = FirebaseAuth.instance;
      final project = auth.app.options.projectId;
      _smsAccount = RegistrationSmsAccount(auth: auth, project: project);
      _otp = FirebaseRegistrationOtp(
        auth: auth,
        project: project,
        prepareAccount: () async {
          final birthdayError = RegistrationBirthday.validate(_birthday.text);
          if (birthdayError != null || !_acceptedTerms) {
            throw RegistrationOtpException(
              birthdayError ?? PolicyConsent.requiredMessage,
            );
          }
          await ApiService().checkReachable();
          final user = await _smsAccount!.prepare(
            _registrationDraft(),
            _password.text,
          );
          if (mounted) setState(() {});
          return user;
        },
      );
    }
  }

  Future<bool> _smsAvailability(String kind, String value) {
    if (kind == 'email' &&
        _smsAccount?.ownedUid != null &&
        FirebaseAuth.instance.currentUser?.uid == _smsAccount!.ownedUid &&
        value.toLowerCase() == _smsAccount!.reservedEmail?.toLowerCase()) {
      return Future.value(true);
    }
    return (widget.contactAvailability ??
        ApiService().registrationContactAvailable)(kind, value);
  }

  Future<void> _leaveSmsRegistration() async {
    if (_smsAccount?.ownedUid != null) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cancel registration?'),
              content: const Text(
                'This removes only the unfinished test account created for this registration.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep editing'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cancel registration'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      try {
        _otp?.invalidate();
        await _smsAccount!.cancel();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not cancel the unfinished account. Your recovery draft was retained. Retry before leaving.',
              ),
            ),
          );
        }
        return;
      }
    }
    if (mounted) Navigator.maybePop(context);
  }

  ProfileDraft _registrationDraft() => ProfileDraft(
    dateOfBirth: _birthday.text,
    fullName: _name.text.trim(),
    email: _email.text.trim(),
    phoneNumber: normalizePhoneNumber(_countryCode, _phone.text),
    address: _address.text.trim(),
    role: widget.role,
    category: _category.text.trim(),
    photoBase64: _profileImageBytes == null
        ? ''
        : base64Encode(_profileImageBytes!),
    skills: widget.role == 'worker'
        ? _services.services
        : _category.text.trim().isEmpty
        ? const []
        : [_category.text.trim()],
    phoneVerificationToken: _iprogOtp?.tokenFor(
      normalizePhoneNumber(_countryCode, _phone.text),
    ),
  );

  Future<void> _register() async {
    if (widget.role == 'worker' && _services.validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_services.validationError!)));
      return;
    }
    if (!_formKey.currentState!.validate() || !_acceptedTerms) {
      if (!_acceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(PolicyConsent.requiredMessage)),
        );
      }
      return;
    }
    final birthdayError = RegistrationBirthday.validate(_birthday.text);
    if (birthdayError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(birthdayError)));
      return;
    }
    final phone = normalizePhoneNumber(_countryCode, _phone.text);
    if (_iprogOtp != null && !_iprogOtp.verifiedFor(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verify your mobile number with the SMS code first.'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    var draft = _registrationDraft();
    if (_smsAccount?.ownedUid != null &&
        FirebaseAuth.instance.currentUser != null) {
      draft = _smsAccount!.bind(draft, FirebaseAuth.instance.currentUser!);
    }
    try {
      await ApiService().checkReachable();
    } on ApiConnectionException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    UserCredential? credential;
    try {
      User user;
      if (_otp != null) {
        user = await _otp!.requireVerified(draft.phoneNumber);
      } else {
        credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: draft.email,
          password: _password.text,
        );
        user = credential.user!;
      }
      await user.updateDisplayName(draft.fullName);
      await ProfileDraftStore().save(draft);
      final token = await user.getIdToken(true);
      await ApiService().createUserProfile(
        idToken: token!,
        dateOfBirth: draft.dateOfBirth,
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
      _smsAccount?.commit();
      await ProfileDraftStore().clear();
      if (mounted && _identity.hasId) {
        final files = await _identity.takeForVerification();
        if (mounted && files != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WorkerVerificationScreen(
                profile: AppUser(
                  id: user.uid,
                  fullName: draft.fullName,
                  email: draft.email,
                  role: draft.role == 'worker'
                      ? UserRole.worker
                      : UserRole.client,
                  verificationStatus: VerificationStatus.pending,
                ),
                initialDocument: files.document,
                initialSelfie: files.selfie,
              ),
            ),
          );
        } else if (files != null) {
          await RegistrationIdentityDraft.deleteTemporary(files.document);
          await RegistrationIdentityDraft.deleteTemporary(files.selfie);
        }
      }
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on RegistrationOtpException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not create the account.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'PHONE_NUMBER_IN_USE') {
        try {
          if (_otp == null) {
            await credential?.user?.delete();
            await ProfileDraftStore().clear();
          }
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileCompletionScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account created. ${error.message}')),
      );
    } on ApiConnectionException catch (error) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileCompletionScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account created. ${error.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileCompletionScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account created, but the profile could not be saved. Please retry profile setup.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _birthday,
      _name,
      _email,
      _phone,
      _address,
      _password,
      _confirmPassword,
      _category,
    ]) {
      controller.dispose();
    }
    _identity.dispose();
    _otp?.dispose();
    if (widget.smsGateway == null) _iprogOtp?.dispose();
    _services.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  Future<void> _pickProfileImage() async {
    try {
      final bytes = await pickProfilePhoto();
      if (mounted && bytes != null) setState(() => _profileImageBytes = bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not select photo. Try a smaller image.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => _buildRegistrationScreen(context);

  Widget _buildRegistrationScreen(BuildContext context) {
    if (widget.role == 'client') {
      return ClientThemeScope(
        child: ClientAccountForm(
          otpGateway: _otp ?? _iprogOtp,
          identityDraft: _identity,
          credentialsLocked: _smsAccount?.ownedUid != null,
          onExit: _otp == null ? null : _leaveSmsRegistration,
          contactAvailability: _otp == null
              ? widget.contactAvailability
              : _smsAvailability,
          birthday: _birthday,
          formKey: _formKey,
          name: _name,
          email: _email,
          phone: _phone,
          address: _address,
          password: _password,
          confirmPassword: _confirmPassword,
          acceptedTerms: _acceptedTerms,
          onTermsChanged: (value) => setState(() => _acceptedTerms = value),
          loading: _loading,
          profileImage: _profileImageBytes,
          onPickImage: _pickProfileImage,
          onRegister: _register,
          countryCode: _countryCode,
          onCountryCodeChanged: (value) => setState(() => _countryCode = value),
        ),
      );
    }
    if (widget.role == 'worker') {
      return ClientThemeScope(
        child: WorkerAccountForm(
          otpGateway: _otp ?? _iprogOtp,
          identityDraft: _identity,
          credentialsLocked: _smsAccount?.ownedUid != null,
          onExit: _otp == null ? null : _leaveSmsRegistration,
          contactAvailability: _otp == null
              ? widget.contactAvailability
              : _smsAvailability,
          birthday: _birthday,
          formKey: _formKey,
          name: _name,
          email: _email,
          phone: _phone,
          address: _address,
          password: _password,
          confirmPassword: _confirmPassword,
          category: _category,
          services: _services,
          acceptedTerms: _acceptedTerms,
          onTermsChanged: (value) => setState(() => _acceptedTerms = value),
          loading: _loading,
          profileImage: _profileImageBytes,
          onPickImage: _pickProfileImage,
          onRegister: _register,
          countryCode: _countryCode,
          onCountryCodeChanged: (value) => setState(() => _countryCode = value),
        ),
      );
    }
    final isWorker = widget.role == 'worker';
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 64,
        leadingWidth: 44,
        shape: const Border(bottom: BorderSide(color: AppTheme.line)),
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: SvgPicture.asset('assets/registration/back.svg'),
        ),
        titleSpacing: 0,
        title: const Text(
          'SwiftServe',
          style: TextStyle(
            color: AppTheme.ink,
            fontSize: 16,
            height: 24 / 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 128),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 416),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Create Account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 24,
                        height: 32 / 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Join our professional service network',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF44474C),
                        fontSize: 14,
                        height: 20 / 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppTheme.softYellow,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.line,
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0D000000),
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _profileImageBytes == null
                                  ? Center(
                                      child: SvgPicture.asset(
                                        'assets/registration/profile.svg',
                                      ),
                                    )
                                  : Image.memory(
                                      _profileImageBytes!,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: SizedBox.square(
                              dimension: 32,
                              child: FilledButton(
                                onPressed: _pickProfileImage,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.all(8),
                                  backgroundColor: AppTheme.ink,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: SvgPicture.asset(
                                  'assets/registration/camera.svg',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.softYellow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.line),
                      ),
                      child: Row(
                        children: [
                          SvgPicture.asset('assets/registration/role.svg'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CURRENT ROLE',
                                  style: TextStyle(
                                    color: Color(0xFF44474C),
                                    fontSize: 12,
                                    height: 16 / 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                Text(
                                  'Signing up as ${isWorker ? 'Worker' : 'Client'}',
                                  style: const TextStyle(
                                    color: AppTheme.ink,
                                    fontSize: 14,
                                    height: 20 / 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.maybePop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.ink,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 16,
                                height: 24 / 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.ink,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.line),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SvgPicture.asset('assets/registration/shield.svg'),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'To ensure community safety, all users must verify their identity.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 20 / 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _RegistrationField(
                      label: 'Full Name',
                      hintText: 'John Doe',
                      controller: _name,
                      validator: _required,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                    ),
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Email Address',
                      hintText: 'john@example.com',
                      controller: _email,
                      validator: _required,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Phone Number',
                      hintText: '+1 (555) 000-0000',
                      controller: _phone,
                      validator: _required,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                    ),
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Address / Location',
                      hintText: '123 Service Lane, Tech City',
                      controller: _address,
                      validator: _required,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.fullStreetAddress],
                    ),
                    if (isWorker) ...[
                      const SizedBox(height: 16),
                      _RegistrationField(
                        label: 'Primary Service Category',
                        hintText: 'e.g. Plumbing',
                        controller: _category,
                        validator: _required,
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Password',
                      hintText: '••••••••',
                      controller: _password,
                      obscureText: true,
                      validator: (value) => (value?.length ?? 0) < 6
                          ? 'Use at least 6 characters.'
                          : null,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Confirm Password',
                      hintText: '••••••••',
                      controller: _confirmPassword,
                      obscureText: true,
                      validator: (value) => value != _password.text
                          ? 'Passwords do not match.'
                          : null,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _register(),
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          SvgPicture.asset('assets/registration/security.svg'),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Your data is encrypted and stored securely.',
                              style: TextStyle(
                                color: Color(0xFF44474C),
                                fontSize: 14,
                                height: 20 / 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    PolicyConsent(
                      value: _acceptedTerms,
                      onChanged: (value) =>
                          setState(() => _acceptedTerms = value),
                      enabled: !_loading,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 60,
                      child: FilledButton(
                        onPressed: _loading ? null : _register,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.yellow,
                          foregroundColor: AppTheme.ink,
                          disabledBackgroundColor: AppTheme.softYellow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            height: 28 / 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  color: AppTheme.ink,
                                  strokeWidth: 2,
                                ),
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Create Account'),
                                    const SizedBox(width: 8),
                                    SvgPicture.asset(
                                      'assets/registration/arrow.svg',
                                      colorFilter: const ColorFilter.mode(
                                        AppTheme.ink,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: () => Navigator.maybePop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.ink,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 20),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      child: const Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Already have an account? ',
                              style: TextStyle(color: Color(0xFF44474C)),
                            ),
                            TextSpan(text: 'Log In'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationField extends StatelessWidget {
  const _RegistrationField({
    required this.label,
    required this.hintText,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          autofillHints: autofillHints,
          style: const TextStyle(color: AppTheme.ink, fontSize: 16),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              color: AppTheme.line,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(16, 15, 17, 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.ink, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.ink),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.ink, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
