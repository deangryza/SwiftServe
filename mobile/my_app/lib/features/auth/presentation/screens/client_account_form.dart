import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../shared/services/client_theme_controller.dart';
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
  });

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

  @override
  State<ClientAccountForm> createState() => _ClientAccountFormState();
}

class _ClientAccountFormState extends State<ClientAccountForm> {
  static const _yellow = Color(0xFFFFC72C);
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _scrollController = ScrollController();
  var _page = 0;
  var _obscurePassword = true;
  var _obscureConfirmation = true;

  bool get _dark => ClientThemeController.darkMode.value;
  Color get _surface =>
      _dark ? const Color(0xFF242424) : const Color(0xFFFFF9E9);
  Color get _field => _dark ? const Color(0xFF2C2C2C) : const Color(0xFFFFFEFB);
  Color get _text => _dark ? const Color(0xFFF2F2F2) : const Color(0xFF07182A);
  Color get _muted => _dark ? const Color(0xFFB8B8B8) : const Color(0xFF555960);
  Color get _border =>
      _dark ? const Color(0xFF777777) : const Color(0xFFC4C6CD);

  @override
  void dispose() {
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

  void _continue() {
    if (_page == 0) {
      if (!widget.formKey.currentState!.validate()) return;
      widget.name.text = '${_firstName.text.trim()} ${_lastName.text.trim()}';
    } else if (_page == 1) {
      if (!widget.formKey.currentState!.validate()) return;
      if (!widget.acceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please accept the terms and privacy policy.'),
          ),
        );
        return;
      }
    }
    if (_page == 5) {
      widget.onRegister();
    } else {
      _goTo(_page + 1);
    }
  }

  Widget _inputField(
    String label,
    String hint,
    TextEditingController controller, {
    TextInputType? keyboardType,
    bool obscure = false,
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

  Widget _header() {
    const labels = ['Account', 'Verification', 'Review'];
    const progress = [0.18, 0.30, 0.50, 0.70, 0.78, 1.0];
    final active = _page < 2 ? 0 : (_page < 5 ? 1 : 2);
    return SizedBox(
      height: 124,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: _yellow)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 46,
            child: DecoratedBox(
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
                    child: ColoredBox(color: Color(0xFFFFF4D0)),
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
                                  : const Color(0xFFFFF9E9),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: index <= active
                                      ? Colors.white
                                      : const Color(0xFF555960),
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
          Positioned(
            left: 0,
            right: 0,
            top: 54,
            child: Row(
              children: labels
                  .map(
                    (label) => Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF3D4148),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
      const SizedBox(height: 24),
      Center(
        child: Stack(
          children: [
            CircleAvatar(
              radius: 46,
              backgroundColor: _field,
              foregroundImage: widget.profileImage == null
                  ? null
                  : MemoryImage(widget.profileImage!),
              child: widget.profileImage == null
                  ? Icon(Icons.person_outline, color: _muted, size: 32)
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: IconButton.filled(
                onPressed: widget.onPickImage,
                style: IconButton.styleFrom(backgroundColor: _yellow),
                icon: const Icon(Icons.camera_alt_outlined, size: 17),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_outline, color: _yellow),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT ROLE',
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                  Text(
                    'Signing up as Client',
                    style: TextStyle(color: _text, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      _inputField('First Name', 'First name', _firstName),
      _inputField('Last Name', 'Last name', _lastName),
    ],
  );

  Widget _credentialsPage() => Column(
    children: [
      _inputField(
        'Email Address',
        'john@example.com',
        widget.email,
        keyboardType: TextInputType.emailAddress,
      ),
      _inputField(
        'Phone Number',
        '+63 000-000-0000',
        widget.phone,
        keyboardType: TextInputType.phone,
      ),
      _inputField(
        'Address / Location',
        '123 Street, Tech City',
        widget.address,
      ),
      _inputField(
        'Password',
        'Enter your password',
        widget.password,
        obscure: _obscurePassword,
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
        toggle: () =>
            setState(() => _obscureConfirmation = !_obscureConfirmation),
        validator: (value) =>
            value != widget.password.text ? 'Passwords do not match.' : null,
      ),
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
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: widget.acceptedTerms,
        onChanged: (value) => widget.onTermsChanged(value ?? false),
        title: Text(
          'I agree to the Terms and Conditions and Privacy Policy.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ),
    ],
  );

  Widget _otpPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Enter code',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Your code was sent to ${widget.phone.text}',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 24),
      Row(
        children: List.generate(
          6,
          (_) => Expanded(
            child: Container(
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _field,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text("Didn't get code?", style: TextStyle(color: _muted)),
    ],
  );

  Widget _idPage() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _field,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Government ID',
            style: TextStyle(color: _text, fontWeight: FontWeight.w700),
          ),
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Chip(label: Text('REQUIRED')),
        ),
        const SizedBox(height: 12),
        for (final side in ['Front Side', 'Back Side'])
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 27),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _border, style: BorderStyle.solid),
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file_outlined, color: _muted),
                const SizedBox(height: 7),
                Text(
                  side,
                  style: TextStyle(color: _text, fontWeight: FontWeight.w600),
                ),
                Text(
                  'PNG, JPG up to 5MB',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        Text(
          'Your documents are encrypted and only used for identity verification.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _facePage() => Column(
    children: [
      Text(
        'Face Recognition',
        style: TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        'Scan your face to verify your identity',
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 60),
      Icon(Icons.face_retouching_natural_outlined, size: 150, color: _yellow),
      const SizedBox(height: 55),
    ],
  );

  Widget _reviewPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Verification in Progress',
        style: TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        "Our admin team is reviewing your documents. This typically takes 24–48 hours. You'll receive a notification as soon as your account is verified.",
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
            const Text('PENDING', style: TextStyle(color: Color(0xFFBD8500))),
            const SizedBox(height: 14),
            Text('Identity Check', style: TextStyle(color: _text)),
            Text(
              'COMPLETED OCT 24',
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
    1 => _credentialsPage(),
    2 => _otpPage(),
    3 => _idPage(),
    4 => _facePage(),
    _ => _reviewPage(),
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _page == 0 && !widget.loading,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _page > 0 && !widget.loading) _goTo(_page - 1);
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
              : () =>
                    _page > 0 ? _goTo(_page - 1) : Navigator.maybePop(context),
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
                        onPressed: widget.loading ? null : _continue,
                        style: FilledButton.styleFrom(
                          backgroundColor: _yellow,
                          foregroundColor: const Color(0xFF161616),
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
                                _page == 4
                                    ? 'Start scan'
                                    : _page == 5
                                    ? 'Go to Dashboard'
                                    : 'Next',
                              ),
                      ),
                      if (_page == 3 || _page == 4)
                        TextButton(
                          onPressed: () => _goTo(_page + 1),
                          child: const Text('Skip for now'),
                        ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        ),
                        child: const Text('Already have an account? Log In'),
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
  );
}
