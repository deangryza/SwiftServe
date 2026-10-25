import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:flutter/services.dart';

import 'client_register_screen.dart';
import 'login_screen.dart';
import 'worker_register_screen.dart';

class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  static const _background = Color(0xFFFFFFFF);
  static const _yellow = AppTheme.yellow;
  static const _ink = AppTheme.ink;
  static const _muted = AppTheme.muted;
  static const _border = AppTheme.line;
  static const _link = AppTheme.muted;

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : _background;
    final surface = dark ? const Color(0xFF2C2C2C) : const Color(0xFFFFFFFF);
    final ink = dark ? const Color(0xFFF3F3F3) : _ink;
    final muted = dark ? const Color(0xFFB8B8B8) : _muted;
    final border = dark ? const Color(0xFF505050) : _border;
    final link = dark ? const Color(0xFFFFD45A) : _link;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: background,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: SizedBox(
                    width: 260,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SwiftServe',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ink,
                            fontSize: 30,
                            height: 36 / 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.75,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Get help nearby. Earn with your skills.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: muted,
                            fontSize: 15,
                            height: 22.5 / 15,
                          ),
                        ),
                        const SizedBox(height: 72),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: FilledButton(
                            onPressed: () =>
                                _open(context, const ClientRegisterScreen()),
                            style: FilledButton.styleFrom(
                              backgroundColor: _yellow,
                              foregroundColor: _ink,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                height: 22.5 / 15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            child: const Text('I need help'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 57,
                          child: OutlinedButton(
                            onPressed: () =>
                                _open(context, const WorkerRegisterScreen()),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ink,
                              backgroundColor: surface,
                              side: BorderSide(color: border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                height: 22.5 / 15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            child: const Text('I want to earn'),
                          ),
                        ),
                        const SizedBox(height: 51),
                        TextButton(
                          onPressed: () => _open(context, const LoginScreen()),
                          style: TextButton.styleFrom(
                            foregroundColor: link,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 20),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Already have an account? ',
                                  style: TextStyle(
                                    color: muted,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                Text('Sign in'),
                              ],
                            ),
                          ),
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
    );
  }
}
