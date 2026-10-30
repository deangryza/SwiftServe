import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Future<bool> registrationContactAvailable(
    String kind,
    String value, {
    String? idToken,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(
              '${ApiConfig.baseUrl}/api/users/registration-availability',
            ),
            headers: {
              'Content-Type': 'application/json',
              if (idToken != null) 'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'kind': kind, 'value': value}),
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const ApiConnectionException(
        'Availability check timed out. Please try again.',
      );
    } on http.ClientException {
      throw const ApiConnectionException(
        'Could not check availability. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['available'] is! bool) {
      throw const ApiConnectionException(
        'Could not verify availability. Please try again.',
      );
    }
    return body['available'] as bool;
  }

  static const _requestTimeout = Duration(seconds: 30);

  /// Throws [ApiConnectionException] when the backend cannot be reached, so
  /// sign-up can stop before creating a Firebase account without a profile.
  Future<void> checkReachable() async {
    late final http.Response response;
    try {
      response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/health'))
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiConnectionException(
        'The SwiftServe server did not respond. Make sure the backend is running and try again.',
      );
    } on http.ClientException {
      throw const ApiConnectionException(
        'The SwiftServe server could not be reached. Check the backend connection and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw const ApiConnectionException(
        'The SwiftServe server is not ready. Try again in a moment.',
      );
    }
  }

  Future<void> createUserProfile({
    required String idToken,
    required String fullName,
    required String email,
    required String phoneNumber,
    required String address,
    required String role,
    String category = '',
    List<String> skills = const [],
    String photoBase64 = '',
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/users/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'fullName': fullName,
              'email': email,
              'phoneNumber': phoneNumber,
              'address': address,
              'role': role,
              if (category.isNotEmpty) 'category': category,
              if (skills.isNotEmpty) 'skills': skills,
              if (photoBase64.isNotEmpty) 'photoBase64': photoBase64,
            }),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiConnectionException(
        'The SwiftServe server did not respond within 30 seconds. Keep the backend and USB connection active, then try again.',
      );
    } on http.ClientException {
      throw const ApiConnectionException(
        'The SwiftServe server could not be reached. Check the backend connection and try again.',
      );
    }
    if (response.statusCode != 201) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<void> updateProfilePhoto({
    required String idToken,
    required String photoBase64,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/api/users/profile/photo'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'photoBase64': photoBase64}),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiConnectionException(
        'The server did not respond. Try again.',
      );
    } on http.ClientException {
      throw const ApiConnectionException(
        'The server could not be reached. Try again.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Atomically saves the private address and its public locality projection.
  Future<void> updateProfileAddress({
    required String idToken,
    required String fullName,
    required String address,
  }) => _postJson('/api/users/profile/address', idToken, {
    'fullName': fullName,
    'address': address,
  });

  /// Saves About and/or address changes together with their public projections.
  Future<void> updateProfileDetails({
    required String idToken,
    required String fullName,
    String? address,
    String? description,
    List<String>? services,
  }) => _postJson('/api/users/profile/details', idToken, {
    'fullName': fullName,
    'address': ?address,
    'description': ?description,
    'services': ?services,
  });

  /// Adds the client or worker role to an existing account, keeping its data.
  Future<void> addRole({
    required String idToken,
    required String role,
    String category = '',
    String description = '',
  }) => _postJson('/api/users/roles', idToken, {
    'role': role,
    if (category.isNotEmpty) 'category': category,
    if (description.isNotEmpty) 'description': description,
  });

  /// Makes [role] the active role; AuthGate then shows that role's home.
  Future<void> switchRole({required String idToken, required String role}) =>
      _postJson('/api/users/role', idToken, {'role': role});

  /// Alerts SwiftServe admins about an emergency on [requestId]. Pressing
  /// again refreshes the same alert, so this returns its id.
  Future<String> raiseSos({
    required String idToken,
    required String requestId,
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    final body = await _postJson('/api/sos', idToken, {
      'requestId': requestId,
      if (latitude != null && longitude != null)
        'position': {'lat': latitude, 'lng': longitude, 'accuracy': ?accuracy},
    }, timeout: _sosTimeout);
    return body['id'].toString();
  }

  Future<void> markSosSafe({
    required String idToken,
    required String alertId,
  }) => _postJson('/api/sos/$alertId/safe', idToken, const {});

  static const _sosTimeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> _postJson(
    String path,
    String idToken,
    Map<String, Object> body, {
    Duration timeout = _requestTimeout,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiConnectionException(
        'The server did not respond. Try again.',
      );
    } on http.ClientException {
      throw const ApiConnectionException(
        'The server could not be reached. Try again.',
      );
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException(response.statusCode, response.body);
    }
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}

class ApiConnectionException implements Exception {
  const ApiConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  Map<String, dynamic> get _payload {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } catch (_) {
      return const {};
    }
  }

  String? get code => _payload['code']?.toString();

  String get message =>
      _payload['message']?.toString() ?? 'The request could not be completed.';

  @override
  String toString() => 'Request failed ($statusCode): $body';
}
