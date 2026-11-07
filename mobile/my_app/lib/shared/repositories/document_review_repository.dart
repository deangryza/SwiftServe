import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:crypto/crypto.dart';
import '../config/api_config.dart';

class DocumentReviewException implements Exception {
  const DocumentReviewException(this.message, this.code);
  final String message;
  final String? code;
  @override
  String toString() => message;
}

abstract class DocumentReviewGateway {
  void close() {}
  Future<Map<String, dynamic>> get();
  Future<Map<String, dynamic>> submit(
    File file,
    String type,
    Map<String, dynamic> previous,
  );
  Future<File> restore(Map<String, dynamic> record);
}

class DocumentReviewRepository implements DocumentReviewGateway {
  final _client = http.Client();
  @override
  void close() => _client.close();
  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in again before document review.');
    return {'Authorization': 'Bearer ${await user.getIdToken(true)}'};
  }

  String get _url => '${ApiConfig.baseUrl}/api/verification/document';
  Map<String, dynamic> _parse(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw DocumentReviewException(
        body['message'] ?? 'Document review failed. Refresh and try again.',
        body['code'],
      );
    }
    return Map<String, dynamic>.from(body['item']);
  }

  @override
  Future<Map<String, dynamic>> get() async => _parse(
    await _client
        .get(Uri.parse(_url), headers: await _headers())
        .timeout(const Duration(seconds: 30)),
  );
  @override
  Future<Map<String, dynamic>> submit(
    File file,
    String type,
    Map<String, dynamic> previous,
  ) async {
    final request = http.MultipartRequest('POST', Uri.parse(_url));
    request.headers.addAll(await _headers());
    request.fields['idType'] = type;
    for (final key in ['sessionId', 'attemptId']) {
      if (previous[key] is String) request.fields[key] = previous[key];
    }
    request.files.add(
      await http.MultipartFile.fromPath(
        'document',
        file.path,
        contentType: MediaType(
          'image',
          file.path.endsWith('.png') ? 'png' : 'jpeg',
        ),
      ),
    );
    return _parse(
      await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 60)),
      ),
    );
  }

  @override
  Future<File> restore(Map<String, dynamic> record) async {
    final response = await _client
        .get(
          Uri.parse(
            '$_url/image?attemptId=${Uri.encodeQueryComponent(record['attemptId'])}',
          ),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError(
        'Could not restore the document. Refresh or upload a replacement.',
      );
    }
    final suffix = response.headers['content-type']?.contains('png') == true
        ? 'png'
        : 'jpg';
    if (sha256.convert(response.bodyBytes).toString() !=
        record['imageDigest']) {
      throw StateError(
        'Document attempt changed. Refresh before restoring the image.',
      );
    }
    final file = File(
      '${Directory.systemTemp.path}/swiftserve-reviewed-${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }
}
