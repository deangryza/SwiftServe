import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../domain/registration_otp_gateway.dart';

class RegistrationOtpScreen extends StatefulWidget {
  const RegistrationOtpScreen({
    super.key,
    required this.phone,
    required this.onVerified,
    required this.onEditPhone,
    required this.onBack,
    required this.verifyButtonKey,
    this.gateway,
    this.now = DateTime.now,
  });
  final String phone;
  final VoidCallback onVerified, onEditPhone, onBack;
  final Key verifyButtonKey;
  final RegistrationOtpGateway? gateway;
  final DateTime Function() now;
  @override
  State<RegistrationOtpScreen> createState() => _RegistrationOtpScreenState();
}

class _RegistrationOtpScreenState extends State<RegistrationOtpScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  DateTime? _resendAt;
  bool _busy = false, _sent = false, _continued = false;
  String? _error;
  int get _remaining => _resendAt == null
      ? 0
      : ((_resendAt!.difference(widget.now()).inMilliseconds / 1000).ceil())
            .clamp(0, 180);
  @override
  void initState() {
    super.initState();
    _code.addListener(_redraw);
    _focus.addListener(_redraw);
    widget.gateway?.addListener(_gatewayChanged);
    if (widget.gateway != null && !widget.gateway!.verifiedFor(widget.phone)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send();
      });
    }
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _gatewayChanged() {
    if (!mounted) return;
    if (widget.gateway!.verifiedFor(widget.phone)) {
      _finish();
    } else {
      setState(() => _error = widget.gateway!.error);
    }
  }

  void _finish() {
    if (_continued || !mounted) return;
    _continued = true;
    FocusScope.of(context).unfocus();
    widget.onVerified();
  }

  Future<void> _send({bool resend = false}) async {
    if (_busy || widget.gateway == null || (resend && _remaining > 0)) return;
    setState(() {
      _busy = true;
      _error = null;
      _sent = false;
    });
    try {
      await widget.gateway!.send(widget.phone, resend: resend);
      if (!mounted) return;
      if (widget.gateway!.verifiedFor(widget.phone)) {
        _finish();
        return;
      }
      setState(() {
        _sent = true;
        _code.clear();
        _resendAt = widget.now().add(const Duration(minutes: 3));
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _remaining == 0) _timer?.cancel();
        if (mounted) setState(() {});
      });
      _focus.requestFocus();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is RegistrationOtpException
              ? error.message
              : 'Could not send the code. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (widget.gateway == null || widget.gateway!.verifiedFor(widget.phone)) {
      _finish();
      return;
    }
    if (!_sent || _code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway!.verify(widget.phone, _code.text);
      if (!mounted) return;
      if (!widget.gateway!.verifiedFor(widget.phone)) {
        throw const RegistrationOtpException(
          'Verification was not confirmed. Please retry.',
        );
      }
      _finish();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is RegistrationOtpException
              ? error.message
              : 'Could not verify this code. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.gateway?.removeListener(_gatewayChanged);
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active =
        (_code.selection.isValid
                ? _code.selection.baseOffset
                : _code.text.length)
            .clamp(0, 5);
    final verified = widget.gateway?.verifiedFor(widget.phone) ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) {
          widget.gateway?.invalidate();
          widget.onBack();
        }
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Column(
            children: [
              Container(height: 8, color: AppTheme.yellow),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Enter One-Time-Password',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          text: _sent
                              ? 'Please enter the one-time password (OTP) sent to '
                              : 'Verify your mobile number ',
                          children: [
                            TextSpan(
                              text: widget.phone,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'OTP',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _code.clear();
                                    setState(() => _error = null);
                                    _focus.requestFocus();
                                  },
                            child: const Text(
                              'Clear',
                              style: TextStyle(
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 56,
                        child: Stack(
                          children: [
                            ExcludeSemantics(
                              child: Row(
                                children: List.generate(
                                  6,
                                  (index) => Expanded(
                                    child: Container(
                                      margin: EdgeInsets.only(
                                        right: index == 5 ? 0 : 6,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: colors.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _error != null
                                              ? const Color(0xFFB3261E)
                                              : index == active
                                              ? colors.onSurface
                                              : colors.outlineVariant,
                                          width: index == active ? 2 : 1,
                                        ),
                                      ),
                                      child: Text(
                                        index < _code.text.length
                                            ? _code.text[index]
                                            : '',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: TextField(
                                key: const ValueKey('registration-otp-input'),
                                controller: _code,
                                focusNode: _focus,
                                enabled:
                                    !_busy && (_sent || widget.gateway == null),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.oneTimeCode,
                                ],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                style: const TextStyle(
                                  color: Colors.transparent,
                                ),
                                showCursor: false,
                                decoration: const InputDecoration(
                                  labelText: null,
                                  hintText: null,
                                  semanticCounterText:
                                      'Six-digit one-time password',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) => _verify(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_busy)
                        const Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (verified)
                        const Text(
                          'Mobile number verified',
                          textAlign: TextAlign.center,
                        ),
                      if (widget.gateway != null && !_busy && !verified)
                        if (_remaining > 0)
                          Text(
                            'Resend code in ${_remaining ~/ 60} minutes ${_remaining % 60} seconds',
                            textAlign: TextAlign.center,
                          )
                        else
                          TextButton(
                            onPressed: () => _send(resend: _sent),
                            child: Text(_sent ? 'Resend code' : 'Send code'),
                          ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.softYellow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: AppTheme.ink,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.gateway == null
                                    ? 'SMS verification is not enabled in this build. Continuing does not verify your phone number.'
                                    : 'SMS delivery may take a few minutes. You can request another code when the 3-minute timer ends.',
                                style: const TextStyle(
                                  color: AppTheme.ink,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFB3261E)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Not ${widget.phone}?'),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  widget.gateway?.invalidate();
                                  widget.onEditPhone();
                                },
                          child: const Text(
                            'Edit mobile number',
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    FilledButton(
                      key: widget.verifyButtonKey,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.yellow,
                        foregroundColor: AppTheme.ink,
                        minimumSize: const Size.fromHeight(52),
                        shape: const StadiumBorder(),
                      ),
                      onPressed:
                          _busy ||
                              (widget.gateway != null &&
                                  !verified &&
                                  (!_sent || _code.text.length != 6))
                          ? null
                          : _verify,
                      child: Text(
                        widget.gateway == null || verified
                            ? 'Continue'
                            : 'Verify',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
