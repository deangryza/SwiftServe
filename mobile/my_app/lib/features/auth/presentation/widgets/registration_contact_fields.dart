import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../shared/services/api_service.dart';
import 'phone_number_field.dart';

typedef ContactAvailabilityLookup =
    Future<bool> Function(String kind, String value);

class _Check {
  String value = '';
  int version = 0;
  bool? available;
  String? error;
  bool checking = false;
  Timer? timer;
  Future<void>? running;
}

class RegistrationContactFields extends StatefulWidget {
  const RegistrationContactFields({
    super.key,
    required this.email,
    required this.phone,
    required this.dialCode,
    required this.onDialCodeChanged,
    required this.enabled,
    required this.fieldColor,
    required this.textColor,
    required this.mutedColor,
    required this.borderColor,
    required this.focusColor,
    this.federatedAccount = false,
    this.lookup,
    this.emailKey = const ValueKey('Email Address'),
    this.phoneKey = const ValueKey('Phone Number'),
  });
  final TextEditingController email;
  final TextEditingController phone;
  final String dialCode;
  final ValueChanged<String> onDialCodeChanged;
  final bool enabled;
  final Color fieldColor, textColor, mutedColor, borderColor, focusColor;
  final bool federatedAccount;
  final ContactAvailabilityLookup? lookup;
  final Key emailKey, phoneKey;

  @override
  State<RegistrationContactFields> createState() =>
      RegistrationContactFieldsState();
}

class RegistrationContactFieldsState extends State<RegistrationContactFields> {
  final _checks = {'email': _Check(), 'phone': _Check()};
  final _api = ApiService();
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String _value(String kind) {
    if (kind == 'email') {
      final value = widget.email.text.trim().toLowerCase();
      return !widget.federatedAccount &&
              value.length <= 254 &&
              _emailPattern.hasMatch(value)
          ? value
          : '';
    }
    return validatePhoneNumber(widget.phone.text, widget.dialCode) == null
        ? normalizePhoneNumber(widget.dialCode, widget.phone.text)
        : '';
  }

  @override
  void initState() {
    super.initState();
    widget.email.addListener(_queue);
    widget.phone.addListener(_queue);
    _queue();
  }

  @override
  void didUpdateWidget(covariant RegistrationContactFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email) {
      oldWidget.email.removeListener(_queue);
      widget.email.addListener(_queue);
    }
    if (oldWidget.phone != widget.phone) {
      oldWidget.phone.removeListener(_queue);
      widget.phone.addListener(_queue);
    }
    _queue();
  }

  void _queue() {
    var changed = false;
    for (final entry in _checks.entries) {
      final value = _value(entry.key);
      final check = entry.value;
      if (value == check.value) continue;
      changed = true;
      check.timer?.cancel();
      check.version++;
      check.value = value;
      check.available = null;
      check.error = null;
      check.running = null;
      check.checking = value.isNotEmpty;
      if (value.isNotEmpty) {
        check.timer = Timer(
          const Duration(milliseconds: 650),
          () => _run(entry.key),
        );
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _run(String kind, {bool force = false}) {
    final check = _checks[kind]!;
    check.timer?.cancel();
    if (check.value.isEmpty || (!force && check.available != null)) {
      return Future.value();
    }
    if (check.running != null) return check.running!;
    final version = check.version;
    final value = check.value;
    check.checking = true;
    check.error = null;
    if (mounted) setState(() {});
    return check.running = () async {
      try {
        final available =
            await (widget.lookup ?? _api.registrationContactAvailable)(
              kind,
              value,
            );
        if (!mounted || check.version != version) return;
        check.available = available;
        if (!available) {
          check.error = kind == 'email'
              ? 'This email address is already in use.'
              : 'This phone number is already in use.';
        }
      } catch (error) {
        if (!mounted || check.version != version) return;
        check.available = null;
        check.error = error is ApiException && error.statusCode == 429
            ? 'Too many checks. Wait a minute and try again.'
            : 'Could not verify availability. Check your connection and try again.';
      } finally {
        if (mounted && check.version == version) {
          check.checking = false;
          check.running = null;
          setState(() {});
        }
      }
    }();
  }

  /// Flush the debounce and require verified, current values before Next.
  bool get hasCurrentAvailability {
    final kinds = widget.federatedAccount ? ['phone'] : ['email', 'phone'];
    return kinds.every(
      (kind) =>
          _value(kind).isNotEmpty &&
          _checks[kind]!.value == _value(kind) &&
          _checks[kind]!.available == true &&
          !_checks[kind]!.checking,
    );
  }

  Future<bool> checkAvailability() async {
    _queue();
    final kinds = widget.federatedAccount ? ['phone'] : ['email', 'phone'];
    if (kinds.any((kind) => _value(kind).isEmpty)) return false;
    final values = {for (final kind in kinds) kind: _value(kind)};
    await Future.wait(kinds.map((kind) => _run(kind, force: true)));
    return mounted &&
        kinds.every(
          (kind) =>
              _value(kind) == values[kind] && _checks[kind]!.available == true,
        );
  }

  @override
  void dispose() {
    widget.email.removeListener(_queue);
    widget.phone.removeListener(_queue);
    for (final check in _checks.values) {
      check.timer?.cancel();
      check.version++;
    }
    super.dispose();
  }

  Widget? _suffix(String kind) {
    final check = _checks[kind]!;
    if (check.checking) {
      return const Padding(
        padding: EdgeInsets.all(15),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (check.error != null && check.available == null) {
      return IconButton(
        tooltip: 'Check again',
        onPressed: widget.enabled ? () => _run(kind, force: true) : null,
        icon: const Icon(Icons.refresh),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Email Address',
          style: TextStyle(
            color: widget.textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          key: widget.emailKey,
          controller: widget.email,
          enabled: widget.enabled,
          readOnly: widget.federatedAccount,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          forceErrorText: _checks['email']!.error,
          validator: (value) =>
              value == null ||
                  !_emailPattern.hasMatch(value.trim()) ||
                  value.trim().length > 254
              ? 'Enter a valid email address.'
              : null,
          style: TextStyle(color: widget.textColor),
          decoration: InputDecoration(
            hintText: 'john@example.com',
            hintStyle: TextStyle(color: widget.mutedColor),
            filled: true,
            fillColor: widget.fieldColor,
            errorMaxLines: 3,
            helperText: _checks['email']!.available == true
                ? 'Email is available.'
                : null,
            border: border(widget.borderColor),
            enabledBorder: border(widget.borderColor),
            focusedBorder: border(widget.focusColor),
            suffixIcon: _suffix('email'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
          ),
        ),
        const SizedBox(height: 18),
        PhoneNumberField(
          fieldKey: widget.phoneKey,
          controller: widget.phone,
          dialCode: widget.dialCode,
          onDialCodeChanged: widget.onDialCodeChanged,
          enabled: widget.enabled,
          fieldColor: widget.fieldColor,
          textColor: widget.textColor,
          mutedColor: widget.mutedColor,
          borderColor: widget.borderColor,
          focusColor: widget.focusColor,
          errorText: _checks['phone']!.error,
          suffixIcon: _suffix('phone'),
        ),
      ],
    );
  }
}
