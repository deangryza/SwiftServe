import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../features/auth/presentation/screens/profile_completion_screen.dart';
import '../features/client/presentation/screens/client_home_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../features/worker/presentation/screens/worker_home_screen.dart';
import '../shared/models/app_user.dart';
import '../shared/repositories/profile_repository.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        final firebaseUser = authSnapshot.data;
        if (firebaseUser == null) return const OnboardingScreen();

        return StreamBuilder<AppUser?>(
          stream: ProfileRepository().watch(firebaseUser.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }
            if (profileSnapshot.hasError) {
              return _GateError(error: profileSnapshot.error);
            }
            final profile = profileSnapshot.data;
            if (profile == null) return const ProfileCompletionScreen();
            if (profile.role == UserRole.worker) {
              return WorkerHomeScreen(profile: profile);
            }
            return const ClientHomeScreen();
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _GateError extends StatelessWidget {
  const _GateError({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load your profile.\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
