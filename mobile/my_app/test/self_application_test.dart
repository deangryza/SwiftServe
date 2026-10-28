// Firestore doubles exercise the real repository transaction without a backend.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/screens/worker_home_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_job_details_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_search_screen.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/repositories/service_request_repository.dart';

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

Map<String, dynamic> _job(Object? owner, {String status = 'pending'}) => {
  'clientId': ?owner,
  'clientName': 'Client',
  'title': 'Help with a task',
  'budget': 100,
  'status': status,
  'areaPosition': const GeoPoint(14.84, 120.81),
};

AppUser _worker({
  String id = 'user-a',
  VerificationStatus verification = VerificationStatus.verified,
}) => AppUser(
  id: id,
  fullName: 'Worker',
  email: '',
  role: UserRole.worker,
  verificationStatus: verification,
);

void main() {
  testWidgets(
    'own-job details show an explanation instead of Apply or Verify',
    (tester) async {
      final request = ServiceRequest.fromMap('own', {
        ..._job('user-a'),
        'modality': 'online',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerJobDetailsScreen(request: request, worker: _worker()),
        ),
      );
      final message = find.text('You cannot apply to your own job.');
      await tester.scrollUntilVisible(message, 200);
      await tester.pumpAndSettle();
      expect(message, findsOneWidget);
      expect(find.text('Apply for this request'), findsNothing);
      expect(find.text('Verify to apply'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'dashboard filters own and unknown jobs before recent limits, nearby and search',
    () {
      final jobs = [
        for (var i = 0; i < 6; i++)
          ServiceRequest.fromMap('own-$i', _job('user-a')),
        ServiceRequest.fromMap('unknown', _job(null)),
        ServiceRequest.fromMap('other', _job('user-b')),
      ];
      for (final filter in WorkerDashboardRequestFilter.values) {
        final results = filterWorkerDashboardRequests(
          workerId: 'user-a',
          requests: jobs,
          applications: const [],
          filter: filter,
          workerAddressPosition: const JobCoordinate(
            latitude: 14.84,
            longitude: 120.81,
          ),
        );
        expect(results.map((job) => job.id), ['other']);
      }
      expect(
        availableWorkerSearchRequests(
          workerId: 'user-a',
          requests: jobs,
          applications: const [],
          query: 'task',
        ).map((job) => job.id),
        ['other'],
      );
      expect(
        availableWorkerSearchRequests(
          workerId: '',
          requests: jobs,
          applications: const [],
          query: '',
        ),
        isEmpty,
      );
    },
  );

  test(
    'role cycles keep creator identity and do not mutate client history data',
    () {
      final job = ServiceRequest.fromMap('own', _job('user-a'));
      for (final role in ['client', 'worker', 'client', 'worker']) {
        final user = AppUser.fromMap('user-a', {
          'role': role,
          'roles': ['client', 'worker'],
        });
        expect(job.clientId, user.id);
        expect(job.isAvailableToWorker(user.id), isFalse);
        // The source job remains available to the unchanged clientId history query.
        expect([job].where((request) => request.clientId == user.id), [job]);
      }
    },
  );

  test(
    'repository discovery excludes own jobs using authenticated UID',
    () async {
      final db = _Firestore()
        ..documents.addAll({
          'service_requests/own': _job('user-a'),
          'service_requests/other': _job('user-b'),
          'service_requests/unknown': _job(null),
        });
      expect(
        (await ServiceRequestRepository(
          firestore: db,
          auth: _Auth('user-a'),
        ).watchAvailable().first).map((job) => job.id),
        ['other'],
      );
      expect(
        await ServiceRequestRepository(
          firestore: db,
          auth: _Auth(null),
        ).watchAvailable().first,
        isEmpty,
      );
    },
  );

  for (final owner in [
    null,
    '',
    '   ',
    42,
    false,
    <String, Object>{},
    'x' * 129,
    'user-a',
  ]) {
    test(
      'direct application rejects invalid/self owner $owner without side effects',
      () async {
        final db = _Firestore()
          ..documents['service_requests/job'] = _job(owner);
        final request = ServiceRequest.fromMap('job', _job('stale-other-user'));
        await expectLater(
          ServiceRequestRepository(
            firestore: db,
            auth: _Auth('user-a'),
          ).apply(request: request, worker: _worker()),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              owner == 'user-a'
                  ? 'You cannot apply to your own job.'
                  : 'This job has no valid creator and cannot accept applications.',
            ),
          ),
        );
        expect(db.writes, isEmpty);
        expect(
          ServiceRequest.fromMap(
            'job',
            _job(owner),
          ).isAvailableToWorker('user-a'),
          isFalse,
        );
      },
    );
  }

  test(
    'valid application uses latest stored creator for both writes',
    () async {
      final db = _Firestore()
        ..documents['service_requests/job'] = _job('user-b');
      await ServiceRequestRepository(
        firestore: db,
        auth: _Auth('user-a'),
      ).apply(
        request: ServiceRequest.fromMap('job', _job('stale-owner')),
        worker: _worker(),
      );
      expect(db.writes.keys, [
        'service_requests/job/applications/user-a',
        'notifications/new',
      ]);
      expect(db.writes.values.first['clientId'], 'user-b');
      expect(db.writes.values.last['recipientId'], 'user-b');
      expect(db.writes.values.last['senderId'], 'user-a');
    },
  );

  test(
    'unauthenticated and mismatched worker submissions never start a transaction',
    () async {
      for (final auth in [_Auth(null), _Auth('different-user')]) {
        final db = _Firestore();
        await expectLater(
          ServiceRequestRepository(firestore: db, auth: auth).apply(
            request: ServiceRequest.fromMap('job', _job('user-b')),
            worker: _worker(),
          ),
          throwsStateError,
        );
        expect(db.transactions, 0);
        expect(db.writes, isEmpty);
      }
    },
  );

  test(
    'missing, closed, duplicate and unverified applications still fail',
    () async {
      for (final mode in [
        'missing',
        'closed',
        'duplicate',
        'unverified',
        'session-changed',
      ]) {
        final db = _Firestore();
        final auth = _Auth('user-a');
        if (mode != 'missing') {
          db.documents['service_requests/job'] = _job(
            'user-b',
            status: mode == 'closed' ? 'accepted' : 'pending',
          );
        }
        if (mode == 'duplicate') {
          db.documents['service_requests/job/applications/user-a'] = {};
        }
        if (mode == 'session-changed') {
          db.onRead = () => auth.user = _User('user-c');
        }
        await expectLater(
          ServiceRequestRepository(firestore: db, auth: auth).apply(
            request: ServiceRequest.fromMap('job', _job('user-b')),
            worker: _worker(
              verification: mode == 'unverified'
                  ? VerificationStatus.pending
                  : VerificationStatus.verified,
            ),
          ),
          throwsStateError,
        );
        expect(db.writes, isEmpty, reason: mode);
      }
    },
  );
}
