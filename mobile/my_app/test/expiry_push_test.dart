import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/services/expiry_push_service.dart';

void main() {
  const valid = {
    'type': 'jobExpired',
    'recipientId': 'owner',
    'requestId': 'job-1',
    'eventId': 'jobExpired_job-1',
  };
  test('expiry payload preserves exact original request and account', () {
    final target = ExpiryPushTarget.parse(valid, 'owner')!;
    expect(target.requestId, 'job-1');
    expect(target.recipientId, 'owner');
    expect(target.eventId, 'jobExpired_job-1');
  });
  test('other account and signed-out opens are rejected', () {
    expect(ExpiryPushTarget.parse(valid, 'other'), isNull);
    expect(ExpiryPushTarget.parse(valid, null), isNull);
  });
  test('dotted legacy IDs preserve the exact original job', () {
    final dotted = {
      ...valid,
      'requestId': 'a.place',
      'eventId': 'jobExpired_a.place',
    };
    expect(ExpiryPushTarget.parse(dotted, 'owner')?.requestId, 'a.place');
  });
  test(
    'hashed event IDs match the backend SHA-256 contract and reject mismatches',
    () {
      final hashed = {
        ...valid,
        'requestId': 'a.place',
        'eventId':
            'jobExpired.v2.d0c87c1daf9371e098c822afcd2d911dfa86b99eaa29df7eaa69cf548466591a',
      };
      expect(ExpiryPushTarget.parse(hashed, 'owner')?.requestId, 'a.place');
      expect(
        ExpiryPushTarget.parse({
          ...hashed,
          'requestId': 'other.place',
        }, 'owner'),
        isNull,
      );
      final long = 'a' * 1495;
      expect(
        ExpiryPushTarget.parse({
          ...valid,
          'requestId': long,
          'eventId':
              'jobExpired.v2.7e87e79026abc918ad51eafea1d57550bc590fc1dcb8135bcaaffef94077adc3',
        }, 'owner')?.requestId,
        long,
      );
    },
  );
  test('unknown types, mismatched events and path injection cannot route', () {
    for (final change in [
      {'type': 'verification'},
      {'eventId': 'different'},
      {'requestId': '../users/private'},
      {'requestId': ''},
      {'requestId': 2},
    ]) {
      expect(ExpiryPushTarget.parse({...valid, ...change}, 'owner'), isNull);
    }
  });
  test('push is disabled unless explicitly enabled at build time', () {
    expect(ExpiryPushService.enabled, isFalse);
  });

  test(
    'cold open waits for profile; duplicate warm open navigates only once',
    () async {
      final opened = <String>[];
      final router = ExpiryPushRouter(
        loadJob: (_) async => {'clientId': 'owner', 'status': 'expired'},
        navigate: (id) async {
          opened.add(id);
        },
        onError: () => fail('Unexpected error'),
      );
      await router.queue(valid);
      expect(opened, isEmpty);
      await router.ready('owner');
      await router.queue(valid);
      expect(opened, ['job-1']);
    },
  );
  test('server ownership and current expired status are required', () async {
    for (final job in [
      null,
      {'clientId': 'other', 'status': 'expired'},
      {'clientId': 'owner', 'status': 'pending'},
    ]) {
      final opened = <String>[];
      final router = ExpiryPushRouter(
        loadJob: (_) async => job,
        navigate: (id) async {
          opened.add(id);
        },
        onError: () => fail('Unexpected error'),
      );
      await router.ready('owner');
      await router.queue(valid);
      expect(opened, isEmpty);
    }
  });
  test('sign-out during request load prevents stale navigation', () async {
    final loading = Completer<Map<String, dynamic>?>();
    final opened = <String>[];
    final router = ExpiryPushRouter(
      loadJob: (_) => loading.future,
      navigate: (id) async {
        opened.add(id);
      },
      onError: () => fail('Unexpected error'),
    );
    await router.ready('owner');
    final pending = router.queue(valid);
    await router.ready(null);
    loading.complete({'clientId': 'owner', 'status': 'expired'});
    await pending;
    expect(opened, isEmpty);
  });
  test(
    'network failures allow retry without inventing a job or navigation',
    () async {
      var calls = 0;
      var errors = 0;
      final opened = <String>[];
      final router = ExpiryPushRouter(
        loadJob: (_) async {
          if (calls++ == 0) throw Exception('offline');
          return {'clientId': 'owner', 'status': 'expired'};
        },
        navigate: (id) async {
          opened.add(id);
        },
        onError: () {
          errors++;
        },
      );
      await router.ready('owner');
      await router.queue(valid);
      await router.queue(valid);
      expect(errors, 1);
      expect(opened, ['job-1']);
    },
  );
}
