import 'dart:convert';
import 'package:crypto/crypto.dart';

bool _validDocumentId(String id) =>
    id.isNotEmpty &&
    utf8.encode(id).length <= 1500 &&
    !id.contains('/') &&
    id != '.' &&
    id != '..' &&
    !RegExp(r'^__.*__$').hasMatch(id);

bool validPushDocumentId(String id) => _validDocumentId(id);

/// Validated FCM data; a push is only a hint to reload the original owned job.
class ExpiryPushTarget {
  const ExpiryPushTarget(this.eventId, this.requestId, this.recipientId);
  final String eventId;
  final String requestId;
  final String recipientId;
  static ExpiryPushTarget? parse(Map<String, dynamic> data, String? uid) {
    final request = data['requestId'];
    final event = data['eventId'];
    if (uid == null ||
        data['recipientId'] != uid ||
        data['type'] != 'jobExpired' ||
        request is! String ||
        !_validDocumentId(request) ||
        event is! String ||
        !_validDocumentId(event)) {
      return null;
    }
    final canonical = RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(request)
        ? 'jobExpired_$request'
        : 'jobExpired.v2.${sha256.convert(utf8.encode(request))}';
    if (event != canonical && event != 'jobExpired_$request') return null;
    return ExpiryPushTarget(data['eventId'] as String, request, uid);
  }
}

/// Session-aware cold/warm-open queue, independent of FCM/plugin availability.
class ExpiryPushRouter {
  ExpiryPushRouter({
    required this.loadJob,
    required this.navigate,
    required this.onError,
  });
  final Future<Map<String, dynamic>?> Function(String id) loadJob;
  final Future<void> Function(String id) navigate;
  final void Function() onError;
  String? _uid;
  int _session = 0;
  Map<String, dynamic>? _pending;
  final Set<String> _opened = {};

  Future<void> ready(String? uid) async {
    if (_uid != uid) {
      _session++;
      _opened.clear();
    }
    _uid = uid;
    await _drain();
  }

  Future<void> queue(Map<String, dynamic> data) async {
    _pending = Map.of(data);
    await _drain();
  }

  Future<void> _drain() async {
    if (_pending == null || _uid == null) return;
    final target = ExpiryPushTarget.parse(_pending!, _uid);
    _pending = null;
    if (target == null || !_opened.add(target.eventId)) return;
    final session = _session;
    try {
      final job = await loadJob(target.requestId);
      if (session != _session || _uid != target.recipientId) return;
      if (job?['clientId'] != _uid || job?['status'] != 'expired') return;
      if (_opened.length > 100) _opened.remove(_opened.first);
      await navigate(target.requestId);
    } catch (_) {
      if (session != _session) return;
      _opened.remove(target.eventId);
      onError();
    }
  }
}
