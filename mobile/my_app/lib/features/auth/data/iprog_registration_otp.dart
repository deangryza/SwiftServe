import '../../../shared/services/api_service.dart';
import '../domain/registration_otp_gateway.dart';

typedef SendPhoneOtp = Future<void> Function(String phoneNumber);
typedef VerifyPhoneOtp =
    Future<String> Function(String phoneNumber, String code);

/// Live SMS codes through the SwiftServe backend, which sends them with
/// IPROG SMS. A verified number yields a signed token that the backend
/// requires when the account profile is created.
class IprogRegistrationOtp extends RegistrationOtpGateway {
  IprogRegistrationOtp({SendPhoneOtp? send, VerifyPhoneOtp? verify})
    : _sendCode = send ?? ApiService().sendPhoneOtp,
      _verifyCode = verify ?? ApiService().verifyPhoneOtp;

  final SendPhoneOtp _sendCode;
  final VerifyPhoneOtp _verifyCode;
  String? _verifiedPhone;
  String? _token;
  String? _error;

  @override
  String? get error => _error;

  @override
  bool verifiedFor(String phone) => _token != null && _verifiedPhone == phone;

  /// The backend's proof for [phone], or null when it is not verified.
  String? tokenFor(String phone) => verifiedFor(phone) ? _token : null;

  /// Restores a proof saved in a recovery draft.
  void restore(String phone, String token) {
    _verifiedPhone = phone;
    _token = token;
    notifyListeners();
  }

  @override
  Future<void> send(String phone, {bool resend = false}) async {
    if (verifiedFor(phone)) return;
    _error = null;
    try {
      await _sendCode(phone);
    } on ApiException catch (error) {
      throw RegistrationOtpException(error.message);
    } on ApiConnectionException catch (error) {
      throw RegistrationOtpException(error.message);
    }
  }

  @override
  Future<void> verify(String phone, String code) async {
    _error = null;
    try {
      final token = await _verifyCode(phone, code);
      _verifiedPhone = phone;
      _token = token;
      notifyListeners();
    } on ApiException catch (error) {
      throw RegistrationOtpException(error.message);
    } on ApiConnectionException catch (error) {
      throw RegistrationOtpException(error.message);
    }
  }

  @override
  void invalidate() {
    if (_token == null && _verifiedPhone == null) return;
    _token = null;
    _verifiedPhone = null;
    notifyListeners();
  }
}
