// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/client/presentation/widgets/conversation_ui.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/repositories/notification_repository.dart';
import 'package:my_app/shared/utils/role_context.dart';
import 'package:my_app/shared/widgets/role_notification_feed.dart';

class _Document extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Document(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
}

class _Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class _Notifications implements RoleNotificationSource {
  final client = StreamController<List<NotificationDocument>>.broadcast();
  final worker = StreamController<List<NotificationDocument>>.broadcast();
  @override
  Stream<List<NotificationDocument>> watch(String uid, UserRole role) =>
      role == UserRole.client ? client.stream : worker.stream;
}

Map<String, dynamic> _conversation(String client, String worker) => {
  'clientId': client,
  'workerId': worker,
  'participantIds': [client, worker],
  'clientName': 'Client $client',
  'workerName': 'Worker $worker',
  'lastMessage': 'Saved message history',
  'unreadFor': ['me'],
  'updatedAt': Timestamp.fromDate(DateTime(2026)),
};

void main() {
  test(
    'legacy notification event types follow recipient interaction, not active role',
    () {
      for (final entry in {
        'workerApplication': NotificationAudience.client,
        'requestAccepted': NotificationAudience.client,
        'applicationAccepted': NotificationAudience.worker,
      }.entries) {
        final data = {'recipientId': 'me', 'type': entry.key, 'read': false};
        expect(notificationAudience(data, 'me'), entry.value);
        expect(notificationAudience(data, 'other'), isNull);
        expect(data['read'], isFalse);
      }
    },
  );

  test(
    'reviews and untyped legacy events use job relationships and fail closed if unknown',
    () {
      final data = {'recipientId': 'me', 'type': 'reviewReceived'};
      expect(notificationAudience(data, 'me'), isNull);
      expect(
        notificationAudience(
          data,
          'me',
          request: {'clientId': 'me', 'workerId': 'other'},
        ),
        NotificationAudience.client,
      );
      expect(
        notificationAudience(
          data,
          'me',
          request: {'clientId': 'other', 'workerId': 'me'},
        ),
        NotificationAudience.worker,
      );
      expect(
        notificationAudience(
          data,
          'me',
          request: {'clientId': 'me', 'workerId': 'me'},
        ),
        isNull,
      );
      expect(notificationAudience({'recipientId': 'me'}, 'me'), isNull);
    },
  );

  test(
    'new audiences are explicit; account verification updates appear in both roles',
    () {
      for (final role in [UserRole.client, UserRole.worker]) {
        expect(
          audienceMatchesRole(
            notificationAudience({
              'recipientId': 'me',
              'title': 'Verification updated',
            }, 'me'),
            role,
          ),
          isTrue,
        );
        expect(
          audienceMatchesRole(
            notificationAudience({
              'recipientId': 'me',
              'recipientRole': 'account',
              'type': 'verificationUpdated',
            }, 'me'),
            role,
          ),
          isTrue,
        );
      }
      final data = {
        'recipientId': 'me',
        'recipientRole': 'worker',
        'read': true,
      };
      expect(
        audienceMatchesRole(notificationAudience(data, 'me'), UserRole.client),
        isFalse,
      );
      expect(
        audienceMatchesRole(notificationAudience(data, 'me'), UserRole.worker),
        isTrue,
      );
      expect(data['read'], isTrue);
      expect(
        notificationAudience({
          'recipientId': 'me',
          'recipientRole': 'invalid',
          'type': 'workerApplication',
        }, 'me'),
        isNull,
      );
    },
  );

  test(
    'conversation roles require explicit identity and participant access',
    () {
      final client = _conversation('me', 'other');
      final worker = _conversation('other', 'me');
      expect(conversationMatchesRole(client, 'me', UserRole.client), isTrue);
      expect(conversationMatchesRole(client, 'me', UserRole.worker), isFalse);
      expect(conversationMatchesRole(worker, 'me', UserRole.worker), isTrue);
      expect(
        conversationMatchesRole(worker, 'stranger', UserRole.worker),
        isFalse,
      );
      expect(
        conversationMatchesRole(
          {
            'participantIds': ['me', 'other'],
          },
          'me',
          UserRole.client,
        ),
        isFalse,
      );
      expect(
        conversationMatchesRole(
          {
            ...client,
            'participantIds': ['me', 'stranger'],
          },
          'me',
          UserRole.client,
        ),
        isFalse,
      );
      expect(
        conversationMatchesRole(
          _conversation('me', 'me'),
          'me',
          UserRole.client,
        ),
        isFalse,
      );
      expect(
        conversationUnreadCount([
          _Document('client', client),
          _Document('worker', worker),
        ], 'me'),
        1,
      );
      expect(
        conversationUnreadCount(
          [_Document('client', client), _Document('worker', worker)],
          'me',
          role: UserRole.worker,
        ),
        1,
      );
      expect(
        conversationUnreadCount([
          _Document('client', {
            ...client,
            'hiddenFor': ['me'],
          }),
        ], 'me'),
        0,
      );
    },
  );

  testWidgets(
    'role notification feed replaces subscriptions and clears stale snapshots',
    (tester) async {
      final source = _Notifications();
      addTearDown(source.client.close);
      addTearDown(source.worker.close);
      Future<void> pump(UserRole role) => tester.pumpWidget(
        MaterialApp(
          home: RoleNotificationFeed(
            uid: 'me',
            role: role,
            source: source,
            builder: (_, snapshot) => Text(
              snapshot.data?.map((doc) => doc.id).join(',') ?? 'Loading',
            ),
          ),
        ),
      );
      final client = _Document('client-notice', {
        'recipientId': 'me',
        'read': false,
      });
      await pump(UserRole.client);
      source.client.add([client]);
      await tester.pumpAndSettle();
      expect(find.text('client-notice'), findsOneWidget);
      await pump(UserRole.worker);
      expect(source.client.hasListener, isFalse);
      expect(find.text('client-notice'), findsNothing);
      source.worker.add([
        _Document('worker-notice', {'read': true}),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('worker-notice'), findsOneWidget);
      source.client.add([client]);
      await tester.pumpAndSettle();
      expect(find.text('client-notice'), findsNothing);
      await pump(UserRole.client);
      source.client.add([client]);
      await tester.pumpAndSettle();
      expect(find.text('client-notice'), findsOneWidget);
      expect(client.data()['read'], isFalse);
      expect(source.worker.hasListener, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(source.client.hasListener, isFalse);
    },
  );

  testWidgets(
    'inbox changes roles without reusing stale rows or changing chat IDs',
    (tester) async {
      final client = _Document('me_other', _conversation('me', 'other'));
      final worker = _Document('other_me', _conversation('other', 'me'));
      final streams = [
        StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(),
        StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(),
      ];
      for (final stream in streams) {
        addTearDown(stream.close);
      }
      final opened = <String>[];
      Future<void> pump(UserRole role) => tester.pumpWidget(
        MaterialApp(
          home: ConversationInboxScreen(
            userId: 'me',
            role: role,
            counterpartIdField: role == UserRole.client
                ? 'workerId'
                : 'clientId',
            counterpartNameField: role == UserRole.client
                ? 'workerName'
                : 'clientName',
            conversationStream: streams[role == UserRole.client ? 0 : 1].stream,
            onOpenConversation: (id, name) => opened.add(id),
          ),
        ),
      );
      await pump(UserRole.client);
      streams[0].add(_Snapshot([client, worker]));
      await tester.pumpAndSettle();
      expect(find.text('Worker other'), findsOneWidget);
      expect(find.text('Client other'), findsNothing);
      await tester.tap(find.text('Worker other'));
      expect(opened, ['me_other']);
      await pump(UserRole.worker);
      expect(find.text('Worker other'), findsNothing);
      expect(streams[0].hasListener, isFalse);
      streams[1].add(_Snapshot([client, worker]));
      await tester.pumpAndSettle();
      expect(find.text('Client other'), findsOneWidget);
      await tester.tap(find.text('Client other'));
      expect(opened, ['me_other', 'other_me']);
      await pump(UserRole.client);
      streams[0].add(_Snapshot([client, worker]));
      await tester.pumpAndSettle();
      expect(find.text('Worker other'), findsOneWidget);
      expect(client.data()['lastMessage'], 'Saved message history');
      expect(client.data()['unreadFor'], ['me']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(streams.every((stream) => !stream.hasListener), isTrue);
    },
  );
}
