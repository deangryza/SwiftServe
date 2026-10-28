import '../models/app_user.dart';

enum NotificationAudience { client, worker, account }

bool isVerificationNotification(Map<String, dynamic> data) {
  final title = data['title']?.toString().trim().toLowerCase();
  return data['type'] == 'verificationUpdated' ||
      title == 'verification updated' ||
      title == 'verification update';
}

/// Uses the event's recipient relationship, never the recipient's active role.
NotificationAudience? notificationAudience(
  Map<String, dynamic> data,
  String uid, {
  Map<String, dynamic>? request,
}) {
  if (uid.isEmpty || data['recipientId'] != uid) return null;
  if (data.containsKey('recipientRole')) {
    return switch (data['recipientRole']) {
      'client' => NotificationAudience.client,
      'worker' => NotificationAudience.worker,
      'account' => NotificationAudience.account,
      _ => null,
    };
  }
  if (isVerificationNotification(data)) return NotificationAudience.account;
  switch (data['type']) {
    case 'workerApplication':
    case 'requestAccepted':
      return NotificationAudience.client;
    case 'applicationAccepted':
      return NotificationAudience.worker;
  }
  // Legacy reviews/updates have no unambiguous type. Only a saved job
  // relationship can classify them; missing/deleted jobs remain unclassified.
  if (request == null) return null;
  final client = request['clientId'] == uid;
  final worker = request['workerId'] == uid;
  if (client == worker) return null;
  return client ? NotificationAudience.client : NotificationAudience.worker;
}

bool audienceMatchesRole(NotificationAudience? audience, UserRole role) =>
    role != UserRole.admin &&
    (audience == NotificationAudience.account ||
        (role == UserRole.client && audience == NotificationAudience.client) ||
        (role == UserRole.worker && audience == NotificationAudience.worker));

bool conversationMatchesRole(
  Map<String, dynamic> data,
  String uid,
  UserRole role,
) {
  final participants = data['participantIds'];
  final client = data['clientId'];
  final worker = data['workerId'];
  return uid.isNotEmpty &&
      participants is List &&
      participants.length == 2 &&
      participants.contains(uid) &&
      client is String &&
      client.isNotEmpty &&
      worker is String &&
      worker.isNotEmpty &&
      client != worker &&
      participants.contains(client) &&
      participants.contains(worker) &&
      switch (role) {
        UserRole.client => client == uid,
        UserRole.worker => worker == uid,
        UserRole.admin => false,
      };
}
