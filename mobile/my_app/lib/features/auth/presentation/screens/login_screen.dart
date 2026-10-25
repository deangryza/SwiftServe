import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/services/client_theme_controller.dart';
import '../../../../shared/services/google_auth_service.dart';

import 'entry_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _signedInBeforeKey = 'has_signed_in_before';
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _resettingPassword = false;
  bool _hasSignedInBefore = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _loadGreetingState();
  }

  Future<void> _loadGreetingState() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () =>
          _hasSignedInBefore = preferences.getBool(_signedInBeforeKey) ?? false,
    );
  }

  Future<void> _rememberSuccessfulLogin() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_signedInBeforeKey, true);
  }

  Future<void> _loginWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await GoogleAuthService().signIn();
      await _rememberSuccessfulLogin();
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
      await _rememberSuccessfulLogin();
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
    return ClientThemeScope(
      child: Builder(
        builder: (context) {
          final palette = _LoginPalette(
            dark: Theme.of(context).brightness == Brightness.dark,
          );
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: palette.accent,
              statusBarIconBrightness: Brightness.dark,
              systemNavigationBarColor: palette.background,
              systemNavigationBarIconBrightness: palette.dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: Scaffold(
              backgroundColor: palette.background,
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: palette.accent)),
                      Positioned(
                        top: constraints.maxHeight > 700 ? 22 : 8,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 430),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Image.asset(
                                  'assets/dashboard/mascot_waving.png',
                                  width: constraints.maxHeight > 700
                                      ? 172
                                      : 145,
                                  height: constraints.maxHeight > 700
                                      ? 172
                                      : 145,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: constraints.maxHeight > 700 ? 145 : 120,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.background,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(54),
                            ),
                          ),
                        ),
                      ),
                      SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth < 360 ? 24 : 32,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: 430,
                              minHeight: constraints.maxHeight,
                            ),
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: constraints.maxHeight > 700 ? 72 : 44,
                                bottom: 32,
                              ),
                              child: AutofillGroup(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _hasSignedInBefore
                                          ? 'Welcome back'
                                          : 'Welcome',
                                      style: TextStyle(
                                        color: AppTheme.ink,
                                        fontSize: 28,
                                        height: 34 / 28,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Sign in to continue to your account',
                                      style: TextStyle(
                                        color: const Color(0xFF686868),
                                        fontSize: 13,
                                        height: 18 / 13,
                                      ),
                                    ),
                                    const SizedBox(height: 50),
                                    _FieldLabel(
                                      'Email Address',
                                      palette: palette,
                                    ),
                                    const SizedBox(height: 8),
                                    _LoginField(
                                      key: const ValueKey('login-email'),
                                      controller: _email,
                                      palette: palette,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email,
                                      ],
                                      textInputAction: TextInputAction.next,
                                    ),
                                    const SizedBox(height: 18),
                                    _FieldLabel('Password', palette: palette),
                                    const SizedBox(height: 8),
                                    _LoginField(
                                      key: const ValueKey('login-password'),
                                      controller: _password,
                                      palette: palette,
                                      obscureText: !_showPassword,
                                      suffixIcon: IconButton(
                                        key: const ValueKey(
                                          'login-password-toggle',
                                        ),
                                        tooltip: _showPassword
                                            ? 'Hide password'
                                            : 'Show password',
                                        onPressed: () => setState(
                                          () => _showPassword = !_showPassword,
                                        ),
                                        icon: Icon(
                                          _showPassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: palette.subtle,
                                        ),
                                      ),
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _login(),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed:
                                            _resettingPassword || _loading
                                            ? null
                                            : _resetPassword,
                                        style: TextButton.styleFrom(
                                          foregroundColor: palette.subtle,
                                          disabledForegroundColor:
                                              palette.subtle,
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                            bottom: 6,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          textStyle: const TextStyle(
                                            fontSize: 13,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        child: Text(
                                          _resettingPassword
                                              ? 'Sending...'
                                              : 'Forgot Password?',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 30),
                                    FilledButton(
                                      onPressed: _loading ? null : _login,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: palette.accent,
                                        disabledBackgroundColor: palette.accent
                                            .withValues(alpha: 0.65),
                                        foregroundColor: const Color(
                                          0xFF171717,
                                        ),
                                        disabledForegroundColor: const Color(
                                          0xFF171717,
                                        ),
                                        minimumSize: const Size.fromHeight(52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _loading
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                color: Color(0xFF171717),
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text(
                                              'Log in',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 26),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Divider(
                                            color: palette.divider,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Text(
                                            'or',
                                            style: TextStyle(
                                              color: palette.subtle,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Divider(
                                            color: palette.divider,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    OutlinedButton(
                                      key: const ValueKey(
                                        'google-login-preview',
                                      ),
                                      onPressed: _loading || _resettingPassword
                                          ? null
                                          : _loginWithGoogle,
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: const Color(
                                          0xFF565A63,
                                        ),
                                        disabledBackgroundColor: Colors.white,
                                        disabledForegroundColor: const Color(
                                          0xFF8B8E95,
                                        ),
                                        side: BorderSide(
                                          color: palette.googleBorder,
                                        ),
                                        minimumSize: const Size.fromHeight(52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
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
                                                fontSize: 24,
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
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          "Don't have an account?",
                                          style: TextStyle(
                                            color: palette.muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                        TextButton(
                                          key: const ValueKey('login-sign-up'),
                                          onPressed: _loading
                                              ? null
                                              : () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const EntryScreen(),
                                                  ),
                                                ),
                                          style: TextButton.styleFrom(
                                            foregroundColor: palette.link,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          child: const Text(
                                            'Sign up',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
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
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoginPalette {
  const _LoginPalette({required this.dark});

  final bool dark;

  Color get background => dark ? AppTheme.ink : Colors.white;
  Color get ink => dark ? const Color(0xFFF7F7F7) : AppTheme.ink;
  Color get muted => dark ? const Color(0xFF9A9A9A) : AppTheme.muted;
  Color get subtle => dark ? const Color(0xFF858585) : AppTheme.muted;
  Color get label => dark ? const Color(0xFF969696) : AppTheme.ink;
  Color get field => dark ? const Color(0xFF2C2C2C) : const Color(0xFFFFFFFF);
  Color get fieldBorder => dark ? const Color(0xFF8C8C8C) : AppTheme.line;
  Color get divider => dark ? const Color(0xFF777777) : const Color(0xFFAAADB4);
  Color get googleBorder =>
      dark ? const Color(0xFFD7D8DC) : const Color(0xFFAAADB4);
  Color get accent => AppTheme.yellow;
  Color get link => AppTheme.muted;
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.palette});

  final String text;
  final _LoginPalette palette;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: palette.label,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    super.key,
    required this.controller,
    required this.palette,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final _LoginPalette palette;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    obscureText: obscureText,
    autofillHints: autofillHints,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    style: TextStyle(color: palette.ink, fontSize: 14, height: 20 / 14),
    decoration: InputDecoration(
      filled: true,
      fillColor: palette.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      suffixIcon: suffixIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.yellow, width: 1.5),
      ),
    ),
  );
}
