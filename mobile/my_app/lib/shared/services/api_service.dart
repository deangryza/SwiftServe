import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> createUserProfile({
    required String idToken,
    required String fullName,
    required String email,
    required String phoneNumber,
    required String address,
    required String role,
    String category = '',
    List<String> skills = const [],
  }) async {
    final response = await _client.post(
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
      }),
    );
    if (response.statusCode != 201) {
      throw ApiException(response.statusCode, response.body);
    }
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'Request failed ($statusCode): $body';
}
