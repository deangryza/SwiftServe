import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client_register_screen.dart';
import 'login_screen.dart';
import 'worker_register_screen.dart';

class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  static const _ink = Color(0xFF18181B);
  static const _muted = Color(0xFF71717A);
  static const _border = Color(0xFFE4E4E7);
  static const _link = Color(0xFF2563EB);

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
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
                        const Text(
                          'SwiftServe',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _ink,
                            fontSize: 30,
                            height: 36 / 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.75,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Get help nearby. Earn with your skills.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _muted,
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
                              backgroundColor: _ink,
                              foregroundColor: Colors.white,
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
                              foregroundColor: _ink,
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: _border),
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
                            foregroundColor: _link,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 20),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Already have an account? ',
                                  style: TextStyle(
                                    color: _muted,
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
