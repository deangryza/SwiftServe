import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _requestTimeout = Duration(seconds: 8);

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
        'The SwiftServe server did not respond. Make sure the backend is running and try again.',
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
