// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/repositories/notification_repository.dart';

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
  final List<NotificationDocument> docs;
}

class _Firestore extends Fake implements FirebaseFirestore {
  final notices = <NotificationDocument>[];
  final requests = <String, Map<String, dynamic>>{};
  final reads = <String>[];
  bool fail = false;
  Object? recipient;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
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
  }) {
    expect(field, 'recipientId');
    db.recipient = isEqualTo;
    return this;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => Stream.value(_Snapshot(db.notices));
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Reference(db, path!);
}

class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.db, this.id);
  final _Firestore db;
  @override
  final String id;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    db.reads.add(id);
    if (db.fail) throw StateError('Network unavailable');
    return _SavedRequest(db.requests[id]);
  }
}

class _SavedRequest extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _SavedRequest(this.value);
  final Map<String, dynamic>? value;
  @override
  Map<String, dynamic>? data() => value;
}

void main() {
  test(
    'legacy review context is read once per job while types need no lookup',
    () async {
      final db = _Firestore()
        ..requests['job'] = {'clientId': 'me', 'workerId': 'other'};
      db.notices.addAll([
        _Document('review-1', {
          'recipientId': 'me',
          'requestId': 'job',
          'type': 'reviewReceived',
          'read': false,
        }),
        _Document('review-2', {
          'recipientId': 'me',
          'requestId': 'job',
          'type': 'reviewReceived',
          'read': true,
        }),
        _Document('application', {
          'recipientId': 'me',
          'type': 'workerApplication',
        }),
        _Document('worker-only', {
          'recipientId': 'me',
          'type': 'applicationAccepted',
        }),
        _Document('wrong-user', {
          'recipientId': 'other',
          'type': 'workerApplication',
        }),
      ]);
      final visible = await NotificationRepository(
        firestore: db,
      ).watch('me', UserRole.client).first;
      expect(db.recipient, 'me');
      expect(
        visible.map((doc) => doc.id),
        containsAll(['review-1', 'review-2', 'application']),
      );
      expect(visible, hasLength(3));
      expect(db.reads, ['job']);
      expect(
        visible.singleWhere((doc) => doc.id == 'review-1').data()['read'],
        isFalse,
      );
      expect(
        visible.singleWhere((doc) => doc.id == 'review-2').data()['read'],
        isTrue,
      );
    },
  );
  test(
    'unavailable legacy context is hidden while classifiable events remain',
    () async {
      final db = _Firestore()..fail = true;
      db.notices.addAll([
        _Document('unknown', {
          'recipientId': 'me',
          'requestId': 'missing',
          'type': 'reviewReceived',
        }),
        _Document('known', {
          'recipientId': 'me',
          'type': 'applicationAccepted',
        }),
      ]);
      expect(
        (await NotificationRepository(
          firestore: db,
        ).watch('me', UserRole.worker).first).map((doc) => doc.id),
        ['known'],
      );
    },
  );
}
