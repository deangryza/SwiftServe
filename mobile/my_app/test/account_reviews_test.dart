// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/account_review.dart';
import 'package:my_app/shared/repositories/account_review_repository.dart';
import 'package:my_app/shared/screens/reviews_screen.dart';
import 'package:my_app/shared/widgets/account_rating_summary.dart';

Map<String, dynamic> data(
  ReviewedRole role, {
  String uid = 'account',
  Object? rating = 5,
  String? booking = 'booking',
  String reviewer = 'Reviewer',
}) => {
  'workerId': role == ReviewedRole.worker ? uid : 'reviewer',
  'clientId': role == ReviewedRole.client ? uid : 'reviewer',
  'workerName': role == ReviewedRole.client ? reviewer : 'Account',
  'clientName': role == ReviewedRole.worker ? reviewer : 'Account',
  'requestId': ?booking,
  'rating': rating,
  'comment': 'Original review',
  'createdAt': Timestamp.fromDate(DateTime(2026, 10, 20)),
};

class _Doc extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this.value);
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

class _Firestore extends Fake implements FirebaseFirestore {
  final clients =
      StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  final workers =
      StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  final queries = <String>[];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  Future<void> close() async {
    await clients.close();
    await workers.close();
  }
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
    db.queries.add('$path:$field=$isEqualTo');
    return this;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => path == 'reviews' ? db.workers.stream : db.clients.stream;
}

void main() {
  test(
    'account summary is weighted by individual ratings and deduplicates source paths only',
    () {
      final worker = AccountReview.fromMap(
        'same-booking',
        ReviewedRole.worker,
        data(ReviewedRole.worker),
      );
      final client = AccountReview.fromMap(
        'same-booking',
        ReviewedRole.client,
        data(ReviewedRole.client, rating: 1),
      );
      final another = AccountReview.fromMap(
        'second',
        ReviewedRole.worker,
        data(ReviewedRole.worker, rating: 3),
      );
      final unrelated = AccountReview.fromMap(
        'unrelated',
        ReviewedRole.worker,
        data(ReviewedRole.worker, uid: 'other'),
      );
      final reviews = mergeAccountReviews('account', [
        worker,
        client,
        another,
        worker,
        unrelated,
      ]);
      expect(reviews, hasLength(3));
      expect(reviews.map((review) => review.sourcePath).toSet(), {
        'reviews/same-booking',
        'client_reviews/same-booking',
        'reviews/second',
      });
      final summary = AccountRatingSummary(reviews);
      expect(summary.average, 3);
      expect(summary.reviewCount, 3);
      expect(worker.requestId, 'booking');
      expect(worker.reviewerId, 'reviewer');
      expect(worker.reviewerName, 'Reviewer');
      expect(worker.createdAt, DateTime(2026, 10, 20));
    },
  );

  test(
    'legacy data keeps booking fallback and never fabricates invalid ratings',
    () {
      final valid = AccountReview.fromMap(
        'legacy-booking',
        ReviewedRole.client,
        data(ReviewedRole.client, rating: 4.5, booking: null),
      );
      expect(valid.requestId, 'legacy-booking');
      final invalid = [null, '5', 0, 6, double.nan]
          .map(
            (rating) => AccountReview.fromMap(
              '$rating',
              ReviewedRole.worker,
              data(ReviewedRole.worker, rating: rating),
            ),
          )
          .toList();
      expect(invalid.every((review) => review.rating == null), isTrue);
      final summary = AccountRatingSummary([valid, ...invalid]);
      expect(summary.average, 4.5);
      expect(summary.reviewCount, 1);
      expect(AccountRatingSummary([]).displayAverage, '\u2014');
    },
  );

  testWidgets(
    'account rating remains identical through Client Worker Client switches',
    (tester) async {
      final db = _Firestore();
      addTearDown(db.close);
      final source = AccountReviewRepository(firestore: db);
      Future<void> pump(String role) => tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Text(role),
              AccountRatingBuilder(
                userId: 'account',
                source: source,
                builder: (_, summary) =>
                    Text('${summary.displayAverage} ${summary.label}'),
              ),
            ],
          ),
        ),
      );
      await pump('Client');
      db.clients.add(
        _Snapshot([
          _Doc('client-booking', data(ReviewedRole.client, rating: 3)),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Loading ratings'), findsOneWidget);
      db.workers.add(
        _Snapshot([_Doc('worker-booking', data(ReviewedRole.worker))]),
      );
      await tester.pumpAndSettle();
      expect(find.text('4.0 2 ratings'), findsOneWidget);
      await pump('Worker');
      await tester.pumpAndSettle();
      expect(find.text('4.0 2 ratings'), findsOneWidget);
      await pump('Client');
      await tester.pumpAndSettle();
      expect(find.text('4.0 2 ratings'), findsOneWidget);
      expect(db.queries, [
        'client_reviews:clientId=account',
        'reviews:workerId=account',
      ]);
      db.workers.add(
        _Snapshot([_Doc('worker-booking', data(ReviewedRole.worker))]),
      );
      await tester.pumpAndSettle();
      expect(find.text('4.0 2 ratings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(db.clients.hasListener, isFalse);
      expect(db.workers.hasListener, isFalse);
    },
  );

  testWidgets(
    'public review history shows both contexts, reviewer and transaction in either active role',
    (tester) async {
      final db = _Firestore();
      addTearDown(db.close);
      final source = AccountReviewRepository(firestore: db);
      for (final role in ['Client', 'Worker', 'Client']) {
        await tester.pumpWidget(
          MaterialApp(
            title: role,
            home: ReviewsScreen(userId: 'account', source: source),
          ),
        );
        db.clients.add(
          _Snapshot([
            _Doc(
              'client-booking',
              data(ReviewedRole.client, reviewer: 'Worker reviewer'),
            ),
          ]),
        );
        db.workers.add(
          _Snapshot([
            _Doc(
              'worker-booking',
              data(ReviewedRole.worker, reviewer: 'Client reviewer'),
            ),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.text('Based on 2 reviews'), findsOneWidget);
        expect(find.text('Reviewed as Client'), findsOneWidget);
        expect(find.text('Reviewed as Worker'), findsOneWidget);
        expect(find.text('Worker reviewer'), findsOneWidget);
        expect(find.text('Client reviewer'), findsOneWidget);
        expect(find.text('Booking: booking'), findsNWidgets(2));
      }
      expect(db.queries, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'another account replaces streams and never shows the previous account rating',
    (tester) async {
      final db = _Firestore();
      addTearDown(db.close);
      final source = AccountReviewRepository(firestore: db);
      Future<void> pump(String uid) => tester.pumpWidget(
        MaterialApp(
          home: AccountRatingBuilder(
            userId: uid,
            source: source,
            builder: (_, summary) => Text(summary.displayAverage),
          ),
        ),
      );
      await pump('account');
      db.clients.add(_Snapshot([]));
      db.workers.add(_Snapshot([_Doc('first', data(ReviewedRole.worker))]));
      await tester.pumpAndSettle();
      expect(find.text('5.0'), findsOneWidget);
      await pump('different');
      await tester.pumpAndSettle();
      expect(find.text('5.0'), findsNothing);
      db.clients.add(_Snapshot([]));
      db.workers.add(
        _Snapshot([
          _Doc('first', data(ReviewedRole.worker)),
          _Doc(
            'second',
            data(ReviewedRole.worker, uid: 'different', rating: 2),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('2.0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a failed role query does not publish a partial account average',
    (tester) async {
      final db = _Firestore();
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountRatingBuilder(
            userId: 'account',
            source: AccountReviewRepository(firestore: db),
            builder: (_, summary) => Text(summary.label),
          ),
        ),
      );
      db.clients.add(_Snapshot([_Doc('first', data(ReviewedRole.client))]));
      db.workers.addError(StateError('Network unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Ratings unavailable'), findsOneWidget);
      db.clients.add(_Snapshot([_Doc('first', data(ReviewedRole.client))]));
      await tester.pumpAndSettle();
      expect(find.text('Ratings unavailable'), findsOneWidget);
      db.workers.add(_Snapshot([]));
      await tester.pumpAndSettle();
      expect(find.text('1 rating'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
