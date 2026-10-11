import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../shared/services/google_auth_service.dart';

import 'entry_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _background = Color(0xFFF8F9FF);
  static const _ink = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _label = Color(0xFF374151);
  static const _button = Color(0xFF0058BE);

  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _resettingPassword = false;

  Future<void> _loginWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await GoogleAuthService().signIn();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on GoogleSignInException catch (error) {
      if (mounted && error.code != GoogleSignInExceptionCode.canceled) {
        _showMessage(
          error.description ??
              'Google sign-in could not finish. Check the app configuration.',
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted &&
          ![
            'popup-closed-by-user',
            'cancelled-popup-request',
          ].contains(error.code)) {
        _showMessage(
          error.code == 'operation-not-allowed'
              ? 'Enable Google sign-in in Firebase Authentication first.'
              : error.message ?? 'Unable to sign in with Google.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Unable to sign in with Google: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      _showMessage('Enter your email and password.');
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _password.text,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(error.message ?? 'Unable to sign in.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showMessage('Enter your email to reset your password.');
      return;
    }

    setState(() => _resettingPassword = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) _showMessage('Password reset email sent.');
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(error.message ?? 'Unable to send a reset email.');
      }
    } finally {
      if (mounted) setState(() => _resettingPassword = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _background,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: _background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth < 360 ? 20 : 28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 440,
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: constraints.maxHeight > 650 ? 100 : 48,
                      bottom: 32,
                    ),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Welcome back',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to continue to your account',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 40),
                          const _FieldLabel('Email Address'),
                          const SizedBox(height: 8),
                          _LoginField(
                            key: const ValueKey('login-email'),
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            hintText: 'john@example.com',
                          ),
                          const SizedBox(height: 20),
                          const _FieldLabel('Password'),
                          const SizedBox(height: 8),
                          _LoginField(
                            key: const ValueKey('login-password'),
                            controller: _password,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                            hintText: '????????',
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _resettingPassword || _loading
                                  ? null
                                  : _resetPassword,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF737780),
                              ),
                              child: Text(
                                _resettingPassword
                                    ? 'Sending...'
                                    : 'Forgot Password?',
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _loading ? null : _login,
                            style: FilledButton.styleFrom(
                              backgroundColor: _button,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Log in',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 32),
                          const Row(
                            children: [
                              Expanded(
                                child: Divider(color: Color(0xFFAAADB4)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'or',
                                  style: TextStyle(
                                    color: Color(0xFF737780),
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: Color(0xFFAAADB4)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          OutlinedButton(
                            key: const ValueKey('google-login-preview'),
                            onPressed: _loading || _resettingPassword
                                ? null
                                : _loginWithGoogle,
                            style: OutlinedButton.styleFrom(
                              disabledForegroundColor: const Color(0xFF62666E),
                              side: const BorderSide(color: Color(0xFFAAADB4)),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) =>
                                      const SweepGradient(
                                        colors: [
                                          Color(0xFF4285F4),
                                          Color(0xFF34A853),
                                          Color(0xFFFBBC05),
                                          Color(0xFFEA4335),
                                          Color(0xFF4285F4),
                                        ],
                                      ).createShader(bounds),
                                  child: const Text(
                                    'G',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Flexible(
                                  child: Text(
                                    'Continue with Google',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                "Don't have an account?",
                                style: TextStyle(color: _muted, fontSize: 14),
                              ),
                              TextButton(
                                key: const ValueKey('login-sign-up'),
                                onPressed: _loading
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const EntryScreen(),
                                        ),
                                      ),
                                style: TextButton.styleFrom(
                                  foregroundColor: _button,
                                ),
                                child: const Text(
                                  'Sign up',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _LoginScreenState._label,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    super.key,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.hintText,
  });

  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? hintText;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    obscureText: obscureText,
    autofillHints: autofillHints,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    style: const TextStyle(
      color: _LoginScreenState._ink,
      fontSize: 14,
      height: 20 / 14,
    ),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFFBCC0C9)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFC4C6CD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _LoginScreenState._button,
          width: 1.5,
        ),
      ),
    ),
  );
}
