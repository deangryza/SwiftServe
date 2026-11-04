import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Used only by the explicit, isolated staging build. Never logs request data.
class StagingApiClient extends http.BaseClient {
  StagingApiClient({
    required http.Client inner,
    String Function()? project,
    Future<String?> Function()? token,
    void Function(String)? report,
  }) : _inner = inner,
       _project = project ?? (() => Firebase.app().options.projectId),
       _token = token ?? (() => FirebaseAppCheck.instance.getToken()),
       _report = report ?? debugPrint;

  final http.Client _inner;
  final String Function() _project;
  final Future<String?> Function() _token;
  final void Function(String) _report;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_project() != 'swiftserve-staging-2026' ||
        request.url.scheme != 'http' ||
        request.url.host != '127.0.0.1' ||
        request.url.port != 5002 ||
        !request.url.path.startsWith('/api/')) {
      throw http.ClientException('Staging project or backend target mismatch.');
    }
    // Health checks must still distinguish a missing backend from App Check.
    if (request.url.path != '/api/health') {
      try {
        final token = await _token().timeout(const Duration(seconds: 15));
        if (token == null || token.isEmpty) throw StateError('Unavailable');
        request.headers['X-Firebase-AppCheck'] = token;
      } catch (_) {
        _report('SwiftServe staging: App Check token unavailable.');
        throw http.ClientException(
          'Staging App Check failed. Check debug-device registration and retry.',
        );
      }
    }
    try {
      final response = await _inner.send(request);
      _report('SwiftServe staging: backend HTTP ${response.statusCode}.');
      return response;
    } catch (_) {
      _report('SwiftServe staging: backend connection failed on port 5002.');
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}

http.Client createApiClient() {
  final client = http.Client();
  return const bool.fromEnvironment('STAGING_BACKEND')
      ? StagingApiClient(inner: client)
      : client;
}
