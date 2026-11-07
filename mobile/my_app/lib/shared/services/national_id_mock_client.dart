import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

enum IdentityState {
  notStarted,
  consentRequired,
  pending,
  processing,
  governmentVerified,
  faceVerified,
  verified,
  rejected,
  manualReview,
  expired,
  failed;

  static IdentityState parse(String? value) => switch (value) {
    'NOT_STARTED' => notStarted,
    'CONSENT_REQUIRED' => consentRequired,
    'PENDING' => pending,
    'PROCESSING' => processing,
    'GOVERNMENT_VERIFIED' => governmentVerified,
    'FACE_VERIFIED' => faceVerified,
    'VERIFIED' => verified,
    'REJECTED' => rejected,
    'MANUAL_REVIEW' => manualReview,
    'EXPIRED' => expired,
    _ => failed,
  };
}

class MockIdentityResult {
  const MockIdentityResult({
    required this.reference,
    required this.state,
    this.consent = false,
    this.retryable = false,
    this.government = 'NOT_STARTED',
    this.face = 'NOT_STARTED',
    this.liveness = 'NOT_STARTED',
    this.checkSource = 'SERVER_ADAPTER',
  });
  static const label = 'MOCK / NOT OFFICIALLY VERIFIED';
  final String reference;
  final IdentityState state;
  final bool consent, retryable;
  final String government, face, liveness, checkSource;
  factory MockIdentityResult.fromJson(Map<String, dynamic> json) {
    if (json['providerType'] != 'MOCK' ||
        json['officiallyVerified'] != false ||
        !RegExp(
          r'^mock-v1-[a-f0-9]{64}$',
        ).hasMatch(json['verificationReference']?.toString() ?? '')) {
      throw const FormatException('Invalid local mock response.');
    }
    return MockIdentityResult(
      reference: json['verificationReference'],
      state: IdentityState.parse(json['verificationStatus']),
      consent: json['consentVersion'] == NationalIdMockClient.consentVersion,
      retryable: json['retryable'] == true,
      government:
          json['governmentVerificationStatus']?.toString() ?? 'NOT_STARTED',
      face: json['faceVerificationStatus']?.toString() ?? 'NOT_STARTED',
      liveness: json['livenessStatus']?.toString() ?? 'NOT_STARTED',
      checkSource: json['checkSource']?.toString() ?? 'SERVER_ADAPTER',
    );
  }
}

class NationalIdMockClient {
  NationalIdMockClient({
    http.Client? client,
    Future<String?> Function()? token,
    String Function()? project,
    String Function()? uid,
    Uri? baseUrl,
    bool enabled = buildEnabled,
  }) : _client = client ?? http.Client(),
       _token =
           token ??
           (() =>
               FirebaseAuth.instance.currentUser?.getIdToken(true) ??
               Future.value(null)),
       _project = project ?? (() => Firebase.app().options.projectId),
       _uid = uid ?? (() => FirebaseAuth.instance.currentUser?.uid ?? ''),
       _base = baseUrl ?? Uri.parse(ApiConfig.baseUrl),
       _enabled = enabled;
  static const buildEnabled = bool.fromEnvironment('ENABLE_NATIONAL_ID_MOCK');
  static const consentVersion = 'swiftserve-identity-mock-v1';
  final http.Client _client;
  final Future<String?> Function() _token;
  final String Function() _project, _uid;
  final Uri _base;
  final bool _enabled;
  String _scope() {
    if (!kDebugMode ||
        !_enabled ||
        !_project().startsWith('demo-') ||
        _uid().isEmpty ||
        _base.scheme != 'http' ||
        _base.port != 5007 ||
        !['127.0.0.1', 'localhost', '10.0.2.2'].contains(_base.host)) {
      throw StateError(
        'Use a debug demo Firebase build and the local mock backend on port 5007.',
      );
    }
    return 'identity.mock.${_project()}.${_uid()}';
  }

  Future<MockIdentityResult> _json(
    String path,
    String method, [
    Map<String, dynamic>? body,
  ]) async {
    _scope();
    final token = await _token();
    if (token == null) throw StateError('Sign in to the demo account first.');
    final request = http.Request(method, _base.resolve('/api/identity/$path'));
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 30)),
    );
    return _result(response);
  }

  MockIdentityResult _result(http.Response response) {
    if (response.statusCode >= 400) {
      throw StateError(
        'Mock verification unavailable (HTTP ${response.statusCode}). Check demo setup, birthday and consent.',
      );
    }
    return MockIdentityResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<MockIdentityResult> begin({bool fresh = false}) async {
    final key = '${_scope()}.request';
    final prefs = await SharedPreferences.getInstance();
    var id = fresh ? null : prefs.getString(key);
    id ??= base64UrlEncode(
      List.generate(24, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    await prefs.setString(key, id);
    return _json('sessions', 'POST', {'requestId': id});
  }

  String _ref(String id) {
    if (!RegExp(r'^mock-v1-[a-f0-9]{64}$').hasMatch(id)) {
      throw const FormatException('Invalid session.');
    }
    return 'sessions/$id';
  }

  Future<MockIdentityResult> accept(String id) => _json(
    '${_ref(id)}/consent',
    'POST',
    {'consent': true, 'consentVersion': consentVersion},
  );
  Future<MockIdentityResult> status(String id) => _json(_ref(id), 'GET');
  Future<MockIdentityResult> submit(
    String id,
    Uint8List document,
    Uint8List selfie, {
    required bool digital,
    void Function(double)? progress,
  }) async {
    _scope();
    MediaType type(Uint8List bytes) {
      if (bytes.length > 1536 * 1024 || bytes.length < 8) {
        throw const FormatException(
          'Each image must be JPEG/PNG and at most 1.5 MB.',
        );
      }
      if (bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
        return MediaType('image', 'jpeg');
      }
      if (listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
        return MediaType('image', 'png');
      }
      throw const FormatException('Select a JPEG or PNG image.');
    }

    final docType = type(document),
        selfieType = type(selfie),
        token = await _token();
    if (token == null) throw StateError('Sign in to the demo account first.');
    final request = _ProgressRequest(
      _base.resolve('/api/identity/${_ref(id)}/submit'),
      progress,
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['documentFormat'] = digital
        ? 'digital_image'
        : 'physical_image';
    request.files.addAll([
      http.MultipartFile.fromBytes(
        'document',
        document,
        filename: 'synthetic-document.${docType.subtype}',
        contentType: docType,
      ),
      http.MultipartFile.fromBytes(
        'selfie',
        selfie,
        filename: 'synthetic-selfie.${selfieType.subtype}',
        contentType: selfieType,
      ),
    ]);
    return _result(
      await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 120)),
      ),
    );
  }

  void close() => _client.close();
}

class _ProgressRequest extends http.MultipartRequest {
  _ProgressRequest(Uri uri, this.progress) : super('POST', uri);
  final void Function(double)? progress;
  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    var sent = 0;
    return http.ByteStream(
      stream.map((chunk) {
        sent += chunk.length;
        progress?.call(sent / contentLength);
        return chunk;
      }),
    );
  }
}
