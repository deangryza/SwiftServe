// ignore_for_file: subtype_of_sealed_class
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/repositories/service_request_repository.dart';
import 'package:my_app/shared/utils/role_context.dart';
import 'package:my_app/features/client/presentation/screens/client_request_details_screen.dart';
import 'package:my_app/features/client/presentation/screens/client_notifications_screen.dart';
import 'package:my_app/features/client/presentation/screens/client_booking_flow.dart';
import 'package:my_app/features/client/presentation/screens/post_request_screen.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(String? uid) : user = uid == null ? null : _User(uid);
  User? user;
  @override
  User? get currentUser => user;
}

class _Firestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final writes = <String, Map<String, dynamic>>{};
  int transactions = 0;
  void Function()? onRead;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactions++;
    final transaction = _Transaction(this);
    final result = await handler(transaction);
    writes.addAll(transaction.writes);
    return result;
  }
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(db, '${this.path}/${path ?? 'new'}');
  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => _Query(db, field, isEqualTo);
}

class _Query extends Fake implements Query<Map<String, dynamic>> {
  _Query(this.db, this.field, this.value);
  final _Firestore db;
  final Object field;
  final Object? value;
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => Stream.value(
    _QuerySnapshot([
      for (final entry in db.documents.entries)
        if (entry.key.split('/').length == 2 && entry.value[field] == value)
          _QueryDocument(entry.value, entry.key.split('/').last),
    ]),
  );
}

class _QuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(db, '${this.path}/$path');
}

class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value;
}

class _QueryDocument extends _Snapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(super.value, this.id);
  @override
  final String id;
  @override
  Map<String, dynamic> data() => value!;
}

class _Transaction extends Fake implements Transaction {
  _Transaction(this.db);
  final _Firestore db;
  final writes = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async {
    db.onRead?.call();
    return _Snapshot(db.documents[ref.path]) as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    writes[ref.path] = Map.of(data as Map<String, dynamic>);
    return this;
  }
}

ServiceRequest oldJob() => ServiceRequest.fromMap('old', {
  'clientId': 'client',
  'clientName': 'Client',
  'title': 'Original task',
  'description': 'Original description',
  'category': 'Other',
  'budget': 250,
  'modality': 'online',
  'status': 'expired',
  'scheduleFrom': Timestamp.fromDate(DateTime.utc(2025, 1, 1, 4)),
  'expiredAt': Timestamp.fromDate(DateTime.utc(2025, 1, 1, 5)),
});
Future<String> _repost(
  _Firestore db, {
  String? uid = 'client',
  DateTime? date,
  JobModality modality = JobModality.online,
  JobLocationSelection? location,
  ErrandDetails? errand,
}) => ServiceRequestRepository(firestore: db, auth: _Auth(uid)).createRequest(
  clientId: uid ?? 'client',
  clientName: 'Client',
  title: 'Original task',
  category: 'Other',
  budget: 250,
  description: 'Original description',
  scheduleFrom: date ?? DateTime.now().add(const Duration(days: 2)),
  scheduleTo: date ?? DateTime.now().add(const Duration(days: 3)),
  modality: modality,
  location: location,
  errand: errand,
  repostSourceId: 'old',
);
Future<void> loadFont(WidgetTester tester) async {
  await tester.runAsync(() async {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final bytes = await File(
      '${artifacts.path}/material_fonts/roboto-regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      'ExpiryTestFont',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
}

void main() {
  test(
    'expired status is retained, unavailable, and routes to details in the client role',
    () {
      final job = oldJob();
      expect(job.status, ServiceRequestStatus.expired);
      expect(job.expiredAt!.toUtc(), DateTime.utc(2025, 1, 1, 5));
      expect(job.isAvailableToWorker('worker'), isFalse);
      expect(bookingStatusLabel(job.status), 'Expired');
      for (final type in ['jobExpired', 'workerApplication', null]) {
        final destination = clientNotificationDestination(type, job);
        expect(destination, isA<ClientRequestDetailsScreen>());
        expect((destination as ClientRequestDetailsScreen).requestId, 'old');
      }
      final pending = ServiceRequest.fromMap('different-id', {
        'status': 'pending',
      });
      final pendingDestination = clientNotificationDestination(
        'workerApplication',
        pending,
      );
      expect(pendingDestination, isA<ClientWorkersFoundScreen>());
      expect(
        (pendingDestination as ClientWorkersFoundScreen).requestId,
        'different-id',
      );
      final accepted = ServiceRequest.fromMap('accepted-id', {
        'status': 'accepted',
        'workerId': 'chosen-worker',
      });
      final acceptedDestination =
          clientNotificationDestination('requestAccepted', accepted)
              as ClientBookingDetailsScreen;
      expect(acceptedDestination.requestId, 'accepted-id');
      expect(acceptedDestination.workerId, 'chosen-worker');
      final audience = notificationAudience({
        'recipientId': 'client',
        'recipientRole': 'client',
        'type': 'jobExpired',
        'requestId': job.id,
      }, 'client');
      expect(audienceMatchesRole(audience, UserRole.client), isTrue);
      expect(audienceMatchesRole(audience, UserRole.worker), isFalse);
    },
  );
  test(
    'repost creates a new pending ID and schedule, preserving original and all history',
    () async {
      final db = _Firestore();
      final original = {
        'clientId': 'client',
        'status': 'expired',
        'title': 'Original task',
      };
      db.documents['service_requests/old'] = original;
      db.documents['service_requests/old/applications/old-worker'] = {
        'status': 'rejected',
      };
      final date = DateTime.now().add(const Duration(days: 2));
      final id = await _repost(db, date: date);
      expect(id, 'new');
      expect(id, isNot('old'));
      expect(db.writes.keys, ['service_requests/new']);
      final job = ServiceRequest.fromMap(id, {
        ...db.writes['service_requests/new']!,
        'createdAt': Timestamp.now(),
      });
      expect(job.status, ServiceRequestStatus.pending);
      expect(job.scheduleFrom!.isAtSameMomentAs(date), isTrue);
      expect(job.title, 'Original task');
      expect(job.description, 'Original description');
      expect(job.workerId, isNull);
      expect(job.expiredAt, isNull);
      expect(db.documents['service_requests/old'], original);
      expect(db.documents['service_requests/old/applications/old-worker'], {
        'status': 'rejected',
      });
    },
  );
  test(
    'errand repost keeps exact pickup and drop-off private without copying assignment',
    () async {
      final db = _Firestore()
        ..documents['service_requests/old'] = {
          'clientId': 'client',
          'status': 'expired',
        };
      const pickup = JobLocationSelection(
        position: JobCoordinate(latitude: 14.84, longitude: 120.81),
        exactAddress: 'Pickup building',
        areaLabel: 'Malolos',
      );
      const dropoff = JobLocationSelection(
        position: JobCoordinate(latitude: 14.85, longitude: 120.82),
        exactAddress: 'Drop-off building',
        areaLabel: 'Malolos',
      );
      await _repost(
        db,
        modality: JobModality.errand,
        location: pickup,
        errand: const ErrandDetails(
          dropoff: dropoff,
          items: 'Package',
          distanceKm: 1.5,
          itemCostEstimate: 100,
        ),
      );
      final private = db.writes['service_requests/new/private/location']!;
      expect(private['position'], pickup.position.toGeoPoint());
      expect(private['address'], 'Pickup building');
      expect(private['dropoffPosition'], dropoff.position.toGeoPoint());
      expect(private['dropoffAddress'], 'Drop-off building');
      expect(db.writes.length, 2);
      expect(db.writes['service_requests/new']!['errandItems'], 'Package');
    },
  );
  for (final scenario in [
    'not owner',
    'signed out',
    'missing',
    'pending',
    'past',
  ]) {
    test('repost rejects $scenario before writing', () async {
      final db = _Firestore();
      if (scenario != 'missing') {
        db.documents['service_requests/old'] = {
          'clientId': 'client',
          'status': scenario == 'pending' ? 'pending' : 'expired',
        };
      }
      await expectLater(
        _repost(
          db,
          uid: scenario == 'not owner'
              ? 'other'
              : scenario == 'signed out'
              ? null
              : 'client',
          date: scenario == 'past' ? DateTime(2020) : null,
        ),
        throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
      );
      expect(db.writes, isEmpty);
    });
  }
  for (final viewer in ['client', 'other', null]) {
    testWidgets(
      'expired details show status; repost available only to owner ($viewer)',
      (tester) async {
        await loadFont(tester);
        var tapped = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'ExpiryTestFont'),
            home: ClientRequestDetailsContent(
              request: oldJob(),
              dateLabel: 'Old schedule',
              saving: false,
              viewerId: viewer,
              onRepost: () => tapped++,
              onEdit: () {},
              onCancel: () {},
              onMessage: () {},
              onRate: () {},
              onViewProfile: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Job Post Expired'), findsOneWidget);
        final button = find.byKey(const ValueKey('repost-job'));
        expect(button, viewer == 'client' ? findsOneWidget : findsNothing);
        if (viewer == 'client') {
          await tester.tap(button);
          expect(tapped, 1);
        }
        expect(find.text('Cancel request'), findsNothing);
        expect(
          find.byKey(const ValueKey('request-details-edit')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'repost form prefills editable details but requires entirely new dates and time',
    (tester) async {
      await loadFont(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'ExpiryTestFont'),
          home: PostRequestScreen(
            repostOf: oldJob(),
            categoryNames: Stream.value(['Other']),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Original task'),
        findsOneWidget,
      );
      expect(find.text('Online'), findsOneWidget);
      for (final key in [
        'post-job-from-date',
        'post-job-to-date',
        'post-job-time',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.text('Select'),
          ),
          findsOneWidget,
        );
      }
      expect(find.widgetWithText(TextFormField, '250'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Original description'),
        findsOneWidget,
      );
      final submit = find.byKey(const ValueKey('post-job-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Please choose both FROM and TO dates.'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
