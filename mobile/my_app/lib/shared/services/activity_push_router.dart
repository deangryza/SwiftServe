import 'expiry_push_router.dart' show validPushDocumentId;

/// Push data is a hint. Only an authenticated reload authorizes navigation.
class ActivityPushRouter {
  ActivityPushRouter({
    required this.load,
    required this.navigate,
    required this.onError,
  });
  final Future<Map<String, dynamic>?> Function(String collection, String id)
  load;
  final Future<void> Function(
    String type,
    String id,
    Map<String, dynamic> record,
  )
  navigate;
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
    if (_uid == null || _pending == null) return;
    final data = _pending!;
    _pending = null;
    final type = data['type'];
    final id =
        data[type == 'chatMessage' ? 'conversationId' : 'notificationId'];
    final event = data['eventId'];
    if (!['chatMessage', 'activity'].contains(type) ||
        data['recipientId'] != _uid ||
        id is! String ||
        !validPushDocumentId(id) ||
        event is! String ||
        !validPushDocumentId(event) ||
        !_opened.add(event)) {
      return;
    }
    final session = _session;
    try {
      final record = await load(
        type == 'chatMessage' ? 'conversations' : 'notifications',
        id,
      );
      if (session != _session || record == null) return;
      if (type == 'chatMessage') {
        final ids = record['participantIds'];
        if (ids is! List || ids.length != 2 || !ids.contains(_uid)) return;
      } else if (record['recipientId'] != _uid) {
        return;
      }
      if (_opened.length > 100) _opened.remove(_opened.first);
      await navigate(type as String, id, record);
    } catch (_) {
      if (session != _session) return;
      _opened.remove(event);
      onError();
    }
  }
}
