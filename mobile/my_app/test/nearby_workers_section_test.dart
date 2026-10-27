import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/client/presentation/widgets/nearby_workers_section.dart';
import 'package:my_app/shared/models/discovered_worker.dart';
import 'package:my_app/shared/repositories/worker_discovery_repository.dart';
import 'package:my_app/shared/screens/public_profile_screen.dart';
import 'package:my_app/shared/services/worker_discovery_service.dart';

const nearby = DiscoveredWorker(
  id: 'worker-7',
  data: {
    'fullName': 'Example Worker',
    'category': 'Repair',
    'skills': ['Plumbing'],
    'verificationStatus': 'verified',
  },
  distanceMeters: 2000,
);
const suggested = DiscoveredWorker(
  id: 'worker-8',
  data: {'fullName': 'Suggested Worker', 'verificationStatus': 'verified'},
  distanceMeters: 11000,
);

class _Service extends Fake implements WorkerDiscoveryService {
  int loads = 0;
  bool fail = false;
  bool requestedGps = false;
  String? messageWorker;
  WorkerConversation? conversation = const WorkerConversation(
    'client_worker-7',
    {},
  );
  Future<WorkerRecommendations>? pending;
  @override
  Future<WorkerRecommendations> nextBatch({
    bool useCurrentLocation = false,
  }) async {
    requestedGps = useCurrentLocation;
    final call = loads++;
    if (fail) throw StateError('Firebase unavailable');
    return pending ??
        WorkerRecommendations([
          call == 0 ? nearby : suggested,
        ], 'Approximate distances from your saved address.');
  }

  @override
  Future<WorkerConversation?> conversationFor(String workerId) async {
    messageWorker = workerId;
    return conversation;
  }
}

void main() {
  late _Service service;
  setUp(() => service = _Service());
  Future<void> pump(
    WidgetTester tester, {
    ValueChanged<DiscoveredWorker>? onView,
    void Function(DiscoveredWorker, WorkerConversation)? onChat,
    String? clientId = 'client',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NearbyWorkersSection(
            clientId: clientId,
            service: service,
            onViewProfile: onView,
            onOpenChat: onChat,
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'renders nearby services and refresh labels outside workers as suggested',
    (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Nearby Workers'), findsOneWidget);
      expect(find.text('Example Worker'), findsOneWidget);
      expect(find.text('Repair · Plumbing'), findsOneWidget);
      expect(find.text('Nearby · ~2 km away'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('refresh-worker-recommendations')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Suggested Workers'), findsOneWidget);
      expect(find.text('Suggested · ~11 km away'), findsOneWidget);
      expect(find.text('Example Worker'), findsNothing);
    },
  );

  testWidgets(
    'card opens the selected worker; message uses the same worker and existing chat',
    (tester) async {
      String? viewed;
      String? messaged;
      String? chatId;
      await pump(
        tester,
        onView: (worker) => viewed = worker.id,
        onChat: (worker, conversation) {
          messaged = worker.id;
          chatId = conversation.id;
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example Worker'));
      expect(viewed, 'worker-7');
      final button = find.byKey(
        const ValueKey('message-recommended-worker-worker-7'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(service.messageWorker, 'worker-7');
      expect(messaged, 'worker-7');
      expect(chatId, 'client_worker-7');
    },
  );

  test(
    'navigation reuses the existing profile and chat screen with correct IDs',
    () {
      final profile = discoveredWorkerProfile(nearby);
      expect(profile.userId, 'worker-7');
      expect(profile.role, PublicProfileRole.worker);
      expect(profile.initialData, same(nearby.data));
      final chat = discoveredWorkerChat(
        nearby,
        const WorkerConversation('legacy-request', {}),
      );
      expect(chat.conversationId, 'legacy-request');
      expect(chat.otherPersonName, 'Example Worker');
    },
  );

  testWidgets(
    'no existing chat explains accepted-job restriction without opening another chat',
    (tester) async {
      service.conversation = null;
      var opened = false;
      await pump(tester, onChat: (_, _) => opened = true);
      await tester.pumpAndSettle();
      final button = find.byKey(
        const ValueKey('message-recommended-worker-worker-7'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(opened, isFalse);
      expect(
        find.textContaining('Messaging is available after'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Firebase failure shows retry feedback and recovers on refresh', (
    tester,
  ) async {
    service.fail = true;
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load workers.'), findsOneWidget);
    service.fail = false;
    await tester.tap(
      find.byKey(const ValueKey('refresh-worker-recommendations')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Suggested Worker'), findsOneWidget);
  });

  testWidgets('empty results and guest state are explicit', (tester) async {
    service.pending = Future.value(
      const WorkerRecommendations([], 'Location unavailable.'),
    );
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('No eligible workers found'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    service.loads = 0;
    await pump(tester, clientId: null);
    await tester.pumpAndSettle();
    expect(service.loads, 0);
    expect(
      find.text('Sign in as a client to discover workers.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'loading prevents duplicate refreshes and completion after disposal is safe',
    (tester) async {
      final pending = Completer<WorkerRecommendations>();
      service.pending = pending.future;
      await pump(tester);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('refresh-worker-recommendations')),
      );
      expect(button.onPressed, isNull);
      expect(service.loads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(const WorkerRecommendations([], 'No location'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('GPS is opt-in; controls fit narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: NearbyWorkersSection(clientId: 'client', service: service),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.requestedGps, isFalse);
    await tester.tap(find.text('Use current location'));
    await tester.pumpAndSettle();
    expect(service.requestedGps, isTrue);
    expect(tester.takeException(), isNull);
  });
}
