import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models_worker/job.dart';

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:3000/api';

  Future<List<Job>> getAvailableJobs() async {
    final response = await http.get(
      Uri.parse('$baseUrl/jobs?status=available'),
    );

    if (response.statusCode != 200) {
      throw Exception('Unable to load jobs');
    }

    final data = jsonDecode(response.body) as List;

    return data
        .map((item) => Job.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> acceptJob(String jobId, String workerId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/jobs/$jobId/accept'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'workerId': workerId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Unable to accept job');
    }
  }

  Future<void> updateJobStatus(
    String jobId,
    String status,
    String workerId,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/jobs/$jobId/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'workerId': workerId, 'status': status}),
    );

    if (response.statusCode != 200) {
      throw Exception('Unable to update status');
    }
  }

  Future<void> sendMessage(
    String conversationId,
    String senderId,
    String receiverId,
    String message,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'conversationId': conversationId,
        'senderId': senderId,
        'receiverId': receiverId,
        'text': message,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Unable to send message');
    }
  }
}
