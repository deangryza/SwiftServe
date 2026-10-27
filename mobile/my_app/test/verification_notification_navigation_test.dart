import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/screens/worker_home_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_verification_screen.dart';
import 'package:my_app/shared/models/app_user.dart';

const worker = AppUser(
  id: 'worker-1',
  fullName: 'Worker One',
  email: 'worker@example.com',
  role: UserRole.worker,
  verificationStatus: VerificationStatus.verified,
);

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  late BuildContext context;
  late _Routes routes;

  Future<void> pumpSubject(WidgetTester tester) async {
    routes = _Routes();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: Text('Notifications'));
          },
        ),
      ),
    );
  }

  for (final title in ['Verification updated', ' Verification Update ']) {
    testWidgets(
      '$title opens verification without a request ID after marking read',
      (tester) async {
        await pumpSubject(tester);
        final read = Completer<void>();
        var readCalled = false;
        final opened = openWorkerVerificationNotification(
          context: context,
          notification: {'title': title, 'read': false},
          worker: worker,
          markAsRead: () {
            readCalled = true;
            return read.future;
          },
        );
        expect(readCalled, isTrue);
        expect(routes.pushed, hasLength(1));
        read.complete();
        expect(await opened, isTrue);
        expect(routes.pushed, hasLength(2));

        // Inspect the real route destination without starting its live Firebase
        // status stream. Screen status rendering has its own widget tests.
        final route = routes.pushed.last as MaterialPageRoute<void>;
        final screen = route.builder(context) as WorkerVerificationScreen;
        expect(screen.profile, same(worker));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'job and review notifications are left to their existing routes',
    (tester) async {
      await pumpSubject(tester);
      var markedRead = false;
      for (final data in [
        {'title': 'Application accepted', 'requestId': 'request-1'},
        {'title': 'New review received', 'type': 'reviewReceived'},
      ]) {
        expect(
          await openWorkerVerificationNotification(
            context: context,
            notification: data,
            worker: worker,
            markAsRead: () async => markedRead = true,
          ),
          isFalse,
        );
      }
      expect(markedRead, isFalse);
      expect(routes.pushed, hasLength(1));
    },
  );

  testWidgets(
    'read failure does not navigate and remains available to the error handler',
    (tester) async {
      await pumpSubject(tester);
      await expectLater(
        openWorkerVerificationNotification(
          context: context,
          notification: {'title': 'Verification updated'},
          worker: worker,
          markAsRead: () async => throw StateError('Read update failed'),
        ),
        throwsStateError,
      );
      expect(routes.pushed, hasLength(1));
    },
  );

  testWidgets(
    'leaving notifications during the read update does not open a new screen',
    (tester) async {
      await pumpSubject(tester);
      final read = Completer<void>();
      final opened = openWorkerVerificationNotification(
        context: context,
        notification: {'title': 'Verification updated'},
        worker: worker,
        markAsRead: () => read.future,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      read.complete();
      expect(await opened, isTrue);
      expect(routes.pushed, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
