import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/theme/app_theme.dart';

typedef SendPhoneOtp = Future<void> Function(String phoneNumber);
typedef VerifyPhoneOtp =
    Future<String> Function(String phoneNumber, String code);

const _codeLength = 6;
const _resendSeconds = 60;

/// Texts a one-time code to [phoneNumber] and checks what the user types.
/// Calls [onVerified] with the backend's verification token on success.
class PhoneOtpVerifier extends StatefulWidget {
  const PhoneOtpVerifier({
    super.key,
    required this.phoneNumber,
    required this.onVerified,
    this.alreadyVerified = false,
    this.sendCode,
    this.verifyCode,
    this.textColor,
    this.mutedColor,
    this.fieldColor,
    this.borderColor,
  });

  /// E.164 Philippine mobile number, e.g. +639171234567.
  final String phoneNumber;
  final ValueChanged<String> onVerified;

  /// Shows the verified state without sending another SMS.
  final bool alreadyVerified;
  final SendPhoneOtp? sendCode;
  final VerifyPhoneOtp? verifyCode;
  final Color? textColor;
  final Color? mutedColor;
  final Color? fieldColor;
  final Color? borderColor;

  @override
  State<PhoneOtpVerifier> createState() => _PhoneOtpVerifierState();
}

class _PhoneOtpVerifierState extends State<PhoneOtpVerifier> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _cooldown = 0;
  bool _sending = false;
  bool _verifying = false;
  late bool _verified = widget.alreadyVerified;
  String? _error;
  String? _info;

  SendPhoneOtp get _send => widget.sendCode ?? ApiService().sendPhoneOtp;
  VerifyPhoneOtp get _verify =>
      widget.verifyCode ?? ApiService().verifyPhoneOtp;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
    if (!_verified) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (!mounted || _sending || _cooldown > 0) return;
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    try {
      await _send(widget.phoneNumber);
      if (!mounted) return;
      _code.clear();
      setState(() => _info = 'Code sent. It expires in 5 minutes.');
      _startCooldown(_resendSeconds);
      _focus.requestFocus();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      if (error.retryAfterSeconds != null) {
        _startCooldown(error.retryAfterSeconds!);
      }
    } on ApiConnectionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _code.text;
    if (code.length != _codeLength || _verifying || _verified) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final token = await _verify(widget.phoneNumber, code);
      if (!mounted) return;
      setState(() {
        _verified = true;
        _info = null;
      });
      _focus.unfocus();
      widget.onVerified(token);
    } on ApiException catch (error) {
      if (!mounted) return;
      _code.clear();
      setState(() => _error = error.message);
    } on ApiConnectionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not check the code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.textColor ?? theme.colorScheme.onSurface;
    final muted = widget.mutedColor ?? AppTheme.muted;
    final field = widget.fieldColor ?? theme.colorScheme.surface;
    final border = widget.borderColor ?? theme.dividerColor;
    final digits = _code.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _verified ? 'Phone verified' : 'Enter code',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _verified
              ? '${widget.phoneNumber} is confirmed.'
              : 'We sent a 6-digit code by SMS to ${widget.phoneNumber}',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        if (_verified)
          const Icon(
            Icons.verified_rounded,
            key: ValueKey('phone-otp-verified'),
            color: Color(0xFF13B981),
            size: 56,
          )
        else
          GestureDetector(
            onTap: _focus.requestFocus,
            child: Stack(
              children: [
                // Invisible field that receives the typing / SMS autofill.
                Opacity(
                  opacity: 0,
                  child: TextField(
                    key: const ValueKey('phone-otp-input'),
                    controller: _code,
                    focusNode: _focus,
                    enabled: !_verifying,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: _codeLength,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      setState(() => _error = null);
                      if (value.length == _codeLength) _verifyCode();
                    },
                  ),
                ),
                Row(
                  children: List.generate(
                    _codeLength,
                    (index) => Expanded(
                      child: Container(
                        height: 52,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: field,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: index == digits.length && _focus.hasFocus
                                ? AppTheme.yellow
                                : border,
                            width: index == digits.length && _focus.hasFocus
                                ? 1.5
                                : 1,
                          ),
                        ),
                        child: Text(
                          index < digits.length ? digits[index] : '',
                          style: TextStyle(
                            color: text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        if (_verifying || _sending)
          const Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            key: const ValueKey('phone-otp-error'),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          )
        else if (_info != null && !_verified)
          Text(
            _info!,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        if (!_verified)
          TextButton(
            key: const ValueKey('phone-otp-resend'),
            onPressed: _cooldown > 0 || _sending ? null : _sendCode,
            child: Text(
              _cooldown > 0
                  ? "Didn't get code? Resend in 0:${_cooldown.toString().padLeft(2, '0')}"
                  : "Didn't get code? Resend",
            ),
          ),
      ],
    );
  }
}

/// Full-screen verifier, used where the form has no code page (Google sign-up
/// and profile retry). Pops with the verification token, or null.
class PhoneOtpScreen extends StatelessWidget {
  const PhoneOtpScreen({super.key, required this.phoneNumber});

  final String phoneNumber;

  static Future<String?> verify(BuildContext context, String phoneNumber) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => PhoneOtpScreen(phoneNumber: phoneNumber),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify phone')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PhoneOtpVerifier(
              phoneNumber: phoneNumber,
              onVerified: (token) => Navigator.of(context).pop(token),
            ),
          ),
        ),
      ),
    ),
  );
}
