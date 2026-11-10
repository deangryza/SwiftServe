import '../../domain/registration_identity_draft.dart';
import '../widgets/registration_identity_capture.dart';
import '../../domain/registration_otp_gateway.dart';
import '../widgets/registration_otp_screen.dart';
import '../widgets/registration_birthday_field.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../widgets/policy_consent.dart';
import '../../../../shared/theme/app_theme.dart';

import '../../../../shared/services/client_theme_controller.dart';
import '../widgets/phone_number_field.dart';
import '../widgets/registration_contact_fields.dart';
import '../widgets/registration_validation_theme.dart';
import '../widgets/registration_address_fields.dart';
import 'login_screen.dart';

class ClientAccountForm extends StatefulWidget {
  const ClientAccountForm({
    super.key,
    required this.formKey,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.password,
    required this.confirmPassword,
    required this.acceptedTerms,
    required this.onTermsChanged,
    required this.loading,
    required this.profileImage,
    required this.onPickImage,
    required this.onRegister,
    this.otpGateway,
    this.identityDraft,
    this.credentialsLocked = false,
    this.birthday,
    this.countryCode = '+63',
    this.onCountryCodeChanged,
    this.federatedAccount = false,
    this.onChangeRole,
    this.onExit,
    this.contactAvailability,
  });

  final RegistrationIdentityDraft? identityDraft;
  final RegistrationOtpGateway? otpGateway;
  final bool credentialsLocked;
  final TextEditingController? birthday;
  final GlobalKey<FormState> formKey;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController address;
  final TextEditingController password;
  final TextEditingController confirmPassword;
  final bool acceptedTerms;
  final ValueChanged<bool> onTermsChanged;
  final bool loading;
  final Uint8List? profileImage;
  final VoidCallback onPickImage;
  final VoidCallback onRegister;
  final String countryCode;
  final ValueChanged<String>? onCountryCodeChanged;
  final bool federatedAccount;
  final VoidCallback? onChangeRole;
  final VoidCallback? onExit;
  final ContactAvailabilityLookup? contactAvailability;

  @override
  State<ClientAccountForm> createState() => _ClientAccountFormState();
}

class _ClientAccountFormState extends State<ClientAccountForm> {
  static const _yellow = AppTheme.yellow;
  final _localBirthday = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _scrollController = ScrollController();
  var _page = 0;
  late final RegistrationIdentityDraft _identity =
      widget.identityDraft ?? RegistrationIdentityDraft();
  void _identityChanged() {
    if (mounted) setState(() {});
  }

  final _contactKey = GlobalKey<RegistrationContactFieldsState>();
  var _continuing = false;
  var _obscurePassword = true;
  var _obscureConfirmation = true;

  @override
  void initState() {
    super.initState();
    _identity.addListener(_identityChanged);
    final parts = widget.name.text.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      _firstName.text = parts.first;
      _lastName.text = parts.skip(1).join(' ');
    }
    _firstName.addListener(_syncName);
    _lastName.addListener(_syncName);
  }

  void _syncName() {
    widget.name.text = '${_firstName.text.trim()} ${_lastName.text.trim()}'
        .trim();
  }

  bool get _dark => ClientThemeController.darkMode.value;
  Color get _surface => _dark ? AppTheme.ink : const Color(0xFFFFFFFF);
  Color get _field => _dark ? const Color(0xFF2C2C2C) : const Color(0xFFFFFFFF);
  Color get _text => _dark ? const Color(0xFFF2F2F2) : AppTheme.ink;
  Color get _muted => _dark ? const Color(0xFFB8B8B8) : AppTheme.muted;
  Color get _border => _dark ? const Color(0xFF777777) : AppTheme.line;

  @override
  void dispose() {
    _identity.removeListener(_identityChanged);
    if (widget.identityDraft == null) _identity.dispose();
    _localBirthday.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  void _goTo(int page) {
    FocusScope.of(context).unfocus();
    setState(() => _page = page);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _continue() async {
    if (_continuing || _identity.busy || _identity.capturing) return;
    if ((_page == 4 && !_identity.hasId) ||
        (_page == 5 && _identity.selfie == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete this check, or choose Skip for now.'),
        ),
      );
      return;
    }
    _continuing = true;
    try {
      if (_page == 0) {
        if (!widget.formKey.currentState!.validate()) return;
        widget.name.text = '${_firstName.text.trim()} ${_lastName.text.trim()}';
      } else if (_page == 1) {
        if (!widget.formKey.currentState!.validate()) return;
      } else if (_page == 2) {
        final available =
            await _contactKey.currentState?.checkAvailability() ?? false;
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (!widget.formKey.currentState!.validate() ||
            !available ||
            _contactKey.currentState?.hasCurrentAvailability != true) {
          return;
        }
        if (!widget.acceptedTerms) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(PolicyConsent.requiredMessage)),
          );
          return;
        }
      }
      if (_page == 6) {
        widget.onRegister();
      } else {
        _goTo(_page + 1);
      }
    } finally {
      _continuing = false;
    }
  }

  Widget _inputField(
    String label,
    String hint,
    TextEditingController controller, {
    TextInputType? keyboardType,
    bool obscure = false,
    bool readOnly = false,
    VoidCallback? toggle,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          key: ValueKey(label),
          controller: controller,
          enabled: !widget.loading,
          validator: validator ?? _required,
          keyboardType: keyboardType,
          obscureText: obscure,
          readOnly: readOnly,
          style: TextStyle(color: _text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _muted),
            filled: true,
            fillColor: _field,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            suffixIcon: toggle == null
                ? null
                : IconButton(
                    onPressed: toggle,
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: _muted,
                    ),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _yellow, width: 1.5),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _profileAvatar() => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        key: const ValueKey('client-registration-profile-avatar'),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: _field,
          shape: BoxShape.circle,
          border: Border.all(color: _border, width: 1.5),
          boxShadow: const [],
          image: widget.profileImage == null
              ? null
              : DecorationImage(
                  image: MemoryImage(widget.profileImage!),
                  fit: BoxFit.cover,
                ),
        ),
        alignment: Alignment.center,
        child: widget.profileImage == null
            ? Icon(Icons.person_outline, color: _muted, size: 27)
            : null,
      ),
      Positioned(
        right: -1,
        bottom: 1,
        child: SizedBox.square(
          dimension: 22,
          child: IconButton.filled(
            onPressed: widget.loading ? null : widget.onPickImage,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: _yellow,
              foregroundColor: AppTheme.ink,
            ),
            icon: const Icon(Icons.camera_alt_outlined, size: 12),
          ),
        ),
      ),
    ],
  );

  Widget _header() {
    const progress = [0.18, 0.24, 0.30, 0.50, 0.70, 0.78, 1.0];
    final active = _page < 3 ? 0 : (_page < 6 ? 1 : 2);
    return SizedBox(
      height: 124,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: ColoredBox(color: _yellow)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 46,
            child: DecoratedBox(
              key: const ValueKey('client-registration-curved-panel'),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(46),
                  topRight: Radius.circular(46),
                ),
              ),
            ),
          ),
          Positioned(
            left: 54,
            right: 54,
            top: 27,
            child: SizedBox(
              height: 25,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(
                    width: double.infinity,
                    height: 3,
                    child: ColoredBox(color: AppTheme.softYellow),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress[_page],
                      child: const SizedBox(
                        key: ValueKey('registration-progress-line'),
                        height: 3,
                        child: ColoredBox(color: Color(0xFF3D4148)),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(
                      3,
                      (index) => Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 11,
                              backgroundColor: index <= active
                                  ? const Color(0xFF3D4148)
                                  : const Color(0xFFFFFFFF),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: index <= active
                                      ? Colors.white
                                      : AppTheme.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_page == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: -4,
              child: Center(child: _profileAvatar()),
            ),
        ],
      ),
    );
  }

  Widget _nameField(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey(label),
          controller: controller,
          enabled: !widget.loading,
          validator: _required,
          style: TextStyle(color: _text, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: _field,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _yellow, width: 1.5),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _accountPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      Text(
        'Create Account',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Join our professional service network',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 13),
      ),
      const SizedBox(height: 26),
      Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _yellow,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(
                Icons.badge_outlined,
                color: AppTheme.ink,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT ROLE',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Signing up as Client',
                    style: TextStyle(
                      color: _text,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed:
                  widget.onChangeRole ?? () => Navigator.maybePop(context),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.ink,
                backgroundColor: _yellow,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Change',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _nameField('First Name', _firstName),
      _nameField('Last Name', _lastName),

      const SizedBox(height: 22),
    ],
  );

  Widget _birthdayLocationPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RegistrationBirthdayField(
        controller: widget.birthday ?? _localBirthday,
        enabled: !widget.loading,
      ),
      RegistrationAddressFields(
        address: widget.address,
        enabled: !widget.loading,
        fieldColor: _field,
        textColor: _text,
        mutedColor: _muted,
        borderColor: _border,
        focusColor: _yellow,
      ),
    ],
  );

  Widget _credentialsPage() => Column(
    children: [
      RegistrationContactFields(
        key: _contactKey,
        email: widget.email,
        phone: widget.phone,
        emailKey: const ValueKey('Email Address'),
        phoneKey: const ValueKey('Phone Number'),
        dialCode: widget.countryCode,
        onDialCodeChanged: widget.onCountryCodeChanged ?? (_) {},
        enabled: !widget.loading,
        fieldColor: _field,
        textColor: _text,
        mutedColor: _muted,
        borderColor: _border,
        focusColor: _yellow,
        federatedAccount: widget.federatedAccount,
        emailReadOnly: widget.credentialsLocked,
        lookup: widget.contactAvailability,
      ),

      if (!widget.federatedAccount) ...[
        _inputField(
          'Password',
          'Enter your password',
          widget.password,
          obscure: _obscurePassword,
          readOnly: widget.credentialsLocked,
          toggle: () => setState(() => _obscurePassword = !_obscurePassword),
          validator: (value) => value == null || value.length < 6
              ? 'Use at least 6 characters.'
              : null,
        ),
        _inputField(
          'Confirm Password',
          'Re-enter your password',
          widget.confirmPassword,
          obscure: _obscureConfirmation,
          readOnly: widget.credentialsLocked,
          toggle: () =>
              setState(() => _obscureConfirmation = !_obscureConfirmation),
          validator: (value) =>
              value != widget.password.text ? 'Passwords do not match.' : null,
        ),
      ],
      Row(
        children: [
          Icon(Icons.lock_outline, color: _muted, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your data is encrypted and stored securely.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ),
      PolicyConsent(
        value: widget.acceptedTerms,
        onChanged: widget.onTermsChanged,
        enabled: !widget.loading,
      ),
    ],
  );

  Widget _otpPage() => RegistrationOtpScreen(
    phone: normalizePhoneNumber(widget.countryCode, widget.phone.text),
    gateway: widget.otpGateway,
    verifyButtonKey: const ValueKey('client-registration-next'),
    onVerified: () => _goTo(4),
    onEditPhone: () => _goTo(2),
    onBack: () => _goTo(2),
  );

  Widget _idPage() => RegistrationIdentityCapture(draft: _identity);
  Widget _facePage() => RegistrationIdentityCapture(
    draft: _identity,
    face: true,
    onRequestId: () => _goTo(4),
  );

  Widget _reviewPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Verification after registration',
        style: TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Finish creating your account. Accepted photos will open in Verification checks for consent, ID details and document review before face comparison. Skipped checks can be completed later in Settings.',
        style: TextStyle(color: _muted, height: 1.5),
      ),
      const SizedBox(height: 30),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.badge_outlined, color: _yellow),
            const SizedBox(height: 8),
            Text('PENDING', style: TextStyle(color: _text)),
            const SizedBox(height: 14),
            Text('Identity Check', style: TextStyle(color: _text)),
            Text(
              'AFTER ACCOUNT CREATION',
              style: TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
      ),
      const SizedBox(height: 90),
    ],
  );

  Widget _pageContent() => switch (_page) {
    0 => _accountPage(),
    1 => _birthdayLocationPage(),
    2 => _credentialsPage(),
    3 => _otpPage(),
    4 => _idPage(),
    5 => _facePage(),
    _ => _reviewPage(),
  };

  @override
  Widget build(BuildContext context) => RegistrationValidationTheme(
    child: _page == 3
        ? _otpPage()
        : PopScope(
            canPop: _page == 0 && !widget.loading && !widget.credentialsLocked,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && !widget.loading) {
                if (_page > 0) {
                  _goTo(_page - 1);
                } else {
                  widget.onExit?.call();
                }
              }
            },
            child: Scaffold(
              backgroundColor: _surface,
              appBar: AppBar(
                backgroundColor: _surface,
                foregroundColor: _text,
                surfaceTintColor: Colors.transparent,
                title: const Text('SwiftServe'),
                leading: IconButton(
                  onPressed: widget.loading
                      ? null
                      : () {
                          if (_page > 0) {
                            _goTo(_page - 1);
                          } else if (widget.onExit != null) {
                            widget.onExit!();
                          } else {
                            Navigator.maybePop(context);
                          }
                        },
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              body: SafeArea(
                top: false,
                child: Column(
                  children: [
                    _header(),
                    Expanded(
                      child: Form(
                        key: widget.formKey,
                        autovalidateMode: AutovalidateMode.onUnfocus,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _pageContent(),
                              const SizedBox(height: 12),
                              FilledButton(
                                key: const ValueKey('client-registration-next'),
                                onPressed:
                                    widget.loading ||
                                        _identity.busy ||
                                        _identity.capturing
                                    ? null
                                    : _continue,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _yellow,
                                  foregroundColor: AppTheme.ink,
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: widget.loading
                                    ? const SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        _page == 6 ? 'Go to Dashboard' : 'Next',
                                      ),
                              ),
                              if (_page == 4 || _page == 5)
                                TextButton(
                                  onPressed:
                                      widget.loading ||
                                          _identity.busy ||
                                          _identity.capturing
                                      ? null
                                      : () async {
                                          await _identity.skip(id: _page == 4);
                                          if (mounted) _goTo(_page + 1);
                                        },
                                  child: const Text('Skip for now'),
                                ),
                              const SizedBox(height: 8),
                              if (!widget.federatedAccount)
                                TextButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  ),
                                  child: const Text(
                                    'Already have an account? Log In',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
