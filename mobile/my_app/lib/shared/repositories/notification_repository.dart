import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../utils/role_context.dart';

typedef NotificationDocument = QueryDocumentSnapshot<Map<String, dynamic>>;

abstract interface class RoleNotificationSource {
  Stream<List<NotificationDocument>> watch(String uid, UserRole role);
}

class NotificationRepository implements RoleNotificationSource {
  NotificationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  @override
  Stream<List<NotificationDocument>> watch(String uid, UserRole role) {
    if (uid.isEmpty) return Stream.value(const []);
    // Only ambiguous legacy events need an extra read. Cache by job for this
    // subscription; do not fetch profiles or guess from names/participant order.
    final requests = <String, Future<Map<String, dynamic>?>>{};
    return _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .snapshots()
        .asyncMap((snapshot) async {
          final visible = await Future.wait(
            snapshot.docs.map((document) async {
              final data = document.data();
              var audience = notificationAudience(data, uid);
              final id = data['requestId'];
              if (audience == null &&
                  !data.containsKey('recipientRole') &&
                  id is String &&
                  id.isNotEmpty) {
                final request = await requests.putIfAbsent(id, () async {
                  try {
                    return (await _firestore
                            .collection('service_requests')
                            .doc(id)
                            .get())
                        .data();
                  } catch (_) {
                    return null;
                  }
                });
                audience = notificationAudience(data, uid, request: request);
              }
              return audienceMatchesRole(audience, role) ? document : null;
            }),
          );
          final result = visible.whereType<NotificationDocument>().toList();
          result.sort((a, b) {
            int time(NotificationDocument doc) =>
                switch (doc.data()['createdAt']) {
                  Timestamp value => value.millisecondsSinceEpoch,
                  _ => 0,
                };
            return time(b).compareTo(time(a));
          });
          return result;
        });
  }
}
