import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:5000';

  static Future<void> createUserProfile({
    required String idToken,
    required String fullName,
    required String email,
    required String phoneNumber,
    required String address,
    required String role,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/users/profile'),
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
      }),
    );

    if (response.statusCode != 201) {
      throw Exception(
        'Failed to create profile: ${response.body}',
      );
    }
  }
}