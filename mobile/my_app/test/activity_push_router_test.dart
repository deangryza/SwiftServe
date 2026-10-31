import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/services/activity_push_router.dart';

void main() {
  const payload = {
    'type': 'chatMessage',
    'recipientId': 'worker',
    'conversationId': 'chat',
    'eventId': 'activity.v1.id',
  };
  test(
    'cold open waits for sign-in, loads exact conversation and deduplicates taps',
    () async {
      final opened = <String>[];
      final router = ActivityPushRouter(
        load: (collection, id) async => {
          'participantIds': ['client', 'worker'],
        },
        navigate: (type, id, data) async => opened.add(id),
        onError: () => fail('unexpected'),
      );
      await router.queue(payload);
      expect(opened, isEmpty);
      await router.ready('worker');
      await router.queue(payload);
      expect(opened, ['chat']);
    },
  );
  test('wrong account and nonmember cannot navigate', () async {
    final router = ActivityPushRouter(
      load: (_, _) async => {
        'participantIds': ['a', 'b'],
      },
      navigate: (_, _, _) async => fail('unauthorized'),
      onError: () => fail('unexpected'),
    );
    await router.ready('other');
    await router.queue(payload);
    await router.ready('worker');
    await router.queue(payload);
  });
  test('account switch fences in-flight reads', () async {
    final record = Completer<Map<String, dynamic>?>();
    final router = ActivityPushRouter(
      load: (_, _) => record.future,
      navigate: (_, _, _) async => fail('stale navigation'),
      onError: () => fail('unexpected'),
    );
    await router.ready('worker');
    final opening = router.queue(payload);
    await router.ready('client');
    record.complete({
      'participantIds': ['client', 'worker'],
    });
    await opening;
  });
  test(
    'activity opens owned saved notification and retries a failed read',
    () async {
      var failures = 0;
      var opened = 0;
      var attempts = 0;
      final router = ActivityPushRouter(
        load: (collection, id) async {
          expect(collection, 'notifications');
          expect(id, 'application');
          if (attempts++ == 0) throw StateError('offline');
          return {'recipientId': 'worker', 'requestId': 'job'};
        },
        navigate: (_, _, _) async {
          opened++;
        },
        onError: () {
          failures++;
        },
      );
      final activity = {
        ...payload,
        'type': 'activity',
        'notificationId': 'application',
      };
      await router.ready('worker');
      await router.queue(activity);
      await router.queue(activity);
      expect(failures, 1);
      expect(opened, 1);
    },
  );
}
