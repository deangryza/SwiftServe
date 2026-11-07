import 'package:flutter/foundation.dart';

abstract class RegistrationOtpGateway extends ChangeNotifier {
  bool verifiedFor(String phone);
  String? get error => null;
  Future<void> send(String phone, {bool resend = false});
  Future<void> verify(String phone, String code);
  void invalidate();
}

class RegistrationOtpException implements Exception {
  const RegistrationOtpException(this.message);
  final String message;
  @override
  String toString() => message;
}
