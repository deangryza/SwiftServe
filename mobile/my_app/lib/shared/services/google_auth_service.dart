import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  static Future<void>? _initialization;

  Future<UserCredential> signIn() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      return FirebaseAuth.instance.signInWithPopup(provider);
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      throw UnsupportedError(
        'Google sign-in is available on Android, iOS, macOS, and web.',
      );
    }
    try {
      await (_initialization ??= GoogleSignIn.instance.initialize());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null) {
      throw FirebaseAuthException(
        code: 'missing-google-token',
        message:
            'Google did not return an identity token. Check your Google sign-in configuration.',
      );
    }
    return FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: token),
    );
  }
}
