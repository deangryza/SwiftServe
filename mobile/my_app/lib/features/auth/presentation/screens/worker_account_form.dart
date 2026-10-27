import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

import '../widgets/phone_number_field.dart';

const fallbackServiceCategories = ['Electrical', 'Repair', 'Tutoring', 'Other'];

/// Active admin-managed categories, or [fallbackServiceCategories] offline.
Stream<List<String>> activeServiceCategories() async* {
  try {
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('service_categories')
            .where('status', isEqualTo: 'active')
            .snapshots()) {
      final names =
          snapshot.docs
              .map((document) => document.data()['name']?.toString().trim())
              .whereType<String>()
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      yield names.isEmpty ? fallbackServiceCategories : names;
    }
  } catch (_) {
    yield fallbackServiceCategories;
  }
}

class WorkerAccountForm extends StatefulWidget {
  const WorkerAccountForm({
    super.key,
    required this.formKey,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.password,
    required this.confirmPassword,
    required this.category,
    required this.acceptedTerms,
    required this.onTermsChanged,
    required this.loading,
    required this.profileImage,
    required this.onPickImage,
    required this.onRegister,
    this.countryCode = '+63',
    this.onCountryCodeChanged,
    this.federatedAccount = false,
    this.onChangeRole,
    this.onExit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController address;
  final TextEditingController password;
  final TextEditingController confirmPassword;
  final TextEditingController category;
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

  @override
  State<WorkerAccountForm> createState() => _WorkerAccountFormState();
}

class _WorkerAccountFormState extends State<WorkerAccountForm> {
  static const _yellow = AppTheme.yellow;
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _scrollController = ScrollController();
  var _page = 0;
  var _obscurePassword = true;
  var _obscureConfirmation = true;

  @override
  void initState() {
    super.initState();
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

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _surface => _dark ? AppTheme.ink : const Color(0xFFFFFFFF);
  Color get _field => _dark ? const Color(0xFF2C2C2C) : Colors.white;
  Color get _text => _dark ? const Color(0xFFF2F2F2) : AppTheme.ink;
  Color get _muted => _dark ? const Color(0xFFB8B8B8) : AppTheme.muted;
  Color get _border => _dark ? const Color(0xFF777777) : AppTheme.line;

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
    } else if (_page == 2 && widget.category.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a service category.')),
      );
      return;
    }

    if (_page == 6) {
      widget.onRegister();
    } else {
      _goTo(_page + 1);
    }
  }

  Widget _profileAvatar() => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        key: const ValueKey('worker-registration-profile-avatar'),
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
    final active = switch (_page) {
      <= 2 => 0,
      <= 4 => 1,
      5 => 2,
      _ => 3,
    };
    return SizedBox(
      height: 131,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: ColoredBox(color: _yellow)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 44,
            child: DecoratedBox(
              key: const ValueKey('worker-registration-curved-panel'),
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
            left: 42,
            right: 42,
            top: 30,
            child: SizedBox(
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned(
                    left: 16,
                    right: 16,
                    child: Divider(
                      height: 3,
                      thickness: 3,
                      color: AppTheme.softYellow,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: active / 3,
                        child: const SizedBox(
                          key: ValueKey('worker-registration-progress-line'),
                          height: 3,
                          child: ColoredBox(color: Color(0xFF3D4148)),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      4,
                      (index) => CircleAvatar(
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

  Widget _input(
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
          key: ValueKey('worker-$label'),
          controller: controller,
          enabled: !widget.loading,
          validator: validator ?? _required,
          keyboardType: keyboardType,
          obscureText: obscure,
          readOnly: readOnly,
          style: TextStyle(color: _text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _muted.withValues(alpha: 0.55)),
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
                    'Signing up as Worker',
                    style: TextStyle(color: _text, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed:
                  widget.onChangeRole ?? () => Navigator.maybePop(context),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      _input('First Name', '', _firstName),
      _input('Last Name', '', _lastName),
    ],
  );

  Widget _credentialsPage() => Column(
    children: [
      _input(
        'Email Address',
        'john@example.com',
        widget.email,
        keyboardType: TextInputType.emailAddress,
        readOnly: widget.federatedAccount,
      ),
      PhoneNumberField(
        fieldKey: const ValueKey('worker-Phone Number'),
        controller: widget.phone,
        dialCode: widget.countryCode,
        onDialCodeChanged: widget.onCountryCodeChanged ?? (_) {},
        enabled: !widget.loading,
        fieldColor: _field,
        textColor: _text,
        mutedColor: _muted.withValues(alpha: 0.55),
        borderColor: _border,
        focusColor: _yellow,
      ),
      _input('Address / Location', '123 Street, Tech City', widget.address),
      if (!widget.federatedAccount) ...[
        _input(
          'Password',
          'Enter your password',
          widget.password,
          obscure: _obscurePassword,
          toggle: () => setState(() => _obscurePassword = !_obscurePassword),
          validator: (value) => value == null || value.length < 6
              ? 'Use at least 6 characters.'
              : null,
        ),
        _input(
          'Confirm Password',
          'Re-enter your password',
          widget.confirmPassword,
          obscure: _obscureConfirmation,
          toggle: () =>
              setState(() => _obscureConfirmation = !_obscureConfirmation),
          validator: (value) =>
              value != widget.password.text ? 'Passwords do not match.' : null,
        ),
      ],
      Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppTheme.ink, size: 15),
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

  Widget _servicesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Service Categories',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 18),
      StreamBuilder<List<String>>(
        stream: activeServiceCategories(),
        initialData: fallbackServiceCategories,
        builder: (context, snapshot) {
          final categories = snapshot.data ?? fallbackServiceCategories;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 74,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final selected = widget.category.text == category;
              return InkWell(
                key: ValueKey('worker-category-$category'),
                onTap: () => setState(() => widget.category.text = category),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? _yellow.withValues(alpha: 0.22) : _field,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? _yellow : _border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_categoryIcon(category), color: _text, size: 21),
                      const SizedBox(height: 5),
                      Text(
                        category,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      const SizedBox(height: 34),
      Text(
        'Weekly Availability',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 32),
                for (final day in ['M', 'T', 'W', 'Th', 'F', 'S', 'Su'])
                  Expanded(
                    child: Text(
                      day,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            _availabilityRow('AM', true),
            const SizedBox(height: 6),
            _availabilityRow('PM', true),
            const SizedBox(height: 6),
            _availabilityRow('EVE', false),
          ],
        ),
      ),
    ],
  );

  IconData _categoryIcon(String category) {
    final value = category.toLowerCase();
    if (value.contains('electric')) return Icons.electrical_services_outlined;
    if (value.contains('repair')) return Icons.handyman_outlined;
    if (value.contains('tutor')) return Icons.school_outlined;
    return Icons.add;
  }

  Widget _availabilityRow(String label, bool available) => Row(
    children: [
      SizedBox(
        width: 32,
        child: Text(
          label,
          style: TextStyle(
            color: _text,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      for (var index = 0; index < 7; index++)
        Expanded(
          child: Container(
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: available
                  ? AppTheme.ink
                  : _dark
                  ? Colors.transparent
                  : const Color(0xFF999999),
              borderRadius: BorderRadius.circular(3),
              border: !available && _dark
                  ? Border.all(color: const Color(0xFF8C8C8C))
                  : null,
            ),
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
        'Your code was sent to ${normalizePhoneNumber(widget.countryCode, widget.phone.text)}',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 24),
      Row(
        children: List.generate(
          6,
          (_) => Expanded(
            child: Container(
              height: 58,
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
      const SizedBox(height: 120),
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Government ID',
                style: TextStyle(color: _text, fontWeight: FontWeight.w700),
              ),
            ),
            const Chip(
              backgroundColor: _yellow,
              label: Text('REQUIRED', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final side in ['Front Side', 'Back Side'])
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 27),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _border),
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.softYellow,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppTheme.line),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: _yellow, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your documents are encrypted and only used for identity verification.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ),
            ],
          ),
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
      const SizedBox(height: 58),
      Icon(Icons.face_retouching_natural_outlined, size: 150, color: _yellow),
      const SizedBox(height: 78),
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
        "Our admin team is reviewing your documents. This typically takes 24-48 hours. You'll receive a notification as soon as your account is verified.",
        style: TextStyle(color: _muted, height: 1.5),
      ),
      const SizedBox(height: 28),
      _reviewCard('Identity Check', 'VERIFIED', AppTheme.ink),
      const SizedBox(height: 16),
      _reviewCard('Certificates', 'REVIEWING', AppTheme.ink),
      const SizedBox(height: 86),
    ],
  );

  Widget _reviewCard(String title, String status, Color statusColor) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.badge_outlined, color: _yellow),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      status,
                      style: TextStyle(color: statusColor, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: TextStyle(color: _text)),
                  Text(
                    'COMPLETED OCT 24',
                    style: TextStyle(color: _muted, fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _pageContent() => switch (_page) {
    0 => _accountPage(),
    1 => _credentialsPage(),
    2 => _servicesPage(),
    3 => _otpPage(),
    4 => _idPage(),
    5 => _facePage(),
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
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _pageContent(),
                      const SizedBox(height: 12),
                      if (_page == 3)
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox.square(
                            dimension: 52,
                            child: FilledButton(
                              key: const ValueKey('worker-registration-next'),
                              onPressed: widget.loading ? null : _continue,
                              style: FilledButton.styleFrom(
                                backgroundColor: _yellow,
                                foregroundColor: AppTheme.ink,
                                padding: EdgeInsets.zero,
                                shape: const CircleBorder(),
                              ),
                              child: const Icon(Icons.arrow_forward_ios),
                            ),
                          ),
                        )
                      else
                        FilledButton(
                          key: const ValueKey('worker-registration-next'),
                          onPressed: widget.loading ? null : _continue,
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
                              : Text(_page == 5 ? 'Start scan' : 'Next'),
                        ),
                      if (_page == 4 || _page == 5)
                        TextButton(
                          onPressed: () => _goTo(_page + 1),
                          child: const Text('Skip for now'),
                        ),
                      if (_page == 2 || _page == 6)
                        TextButton(
                          onPressed: () {},
                          child: const Text('Help & Support'),
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
