import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/account_review.dart';

abstract interface class AccountReviewSource {
  Stream<List<AccountReview>> watch(String uid);
}

class AccountReviewRepository implements AccountReviewSource {
  AccountReviewRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;
  @override
  Stream<List<AccountReview>> watch(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    late StreamController<List<AccountReview>> controller;
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final results = <ReviewedRole, List<AccountReview>>{};
    controller = StreamController(
      onListen: () {
        for (final role in ReviewedRole.values) {
          final collection = role == ReviewedRole.worker
              ? 'reviews'
              : 'client_reviews';
          final recipient = role == ReviewedRole.worker
              ? 'workerId'
              : 'clientId';
          subscriptions.add(
            _firestore
                .collection(collection)
                .where(recipient, isEqualTo: uid)
                .snapshots()
                .listen(
                  (snapshot) {
                    results[role] = [
                      for (final doc in snapshot.docs)
                        AccountReview.fromMap(doc.id, role, doc.data()),
                    ];
                    // A partial role result is not a complete account rating.
                    if (results.length == ReviewedRole.values.length) {
                      controller.add(
                        mergeAccountReviews(
                          uid,
                          results.values.expand((reviews) => reviews),
                        ),
                      );
                    }
                  },
                  onError: (Object error, StackTrace stack) {
                    results.remove(role);
                    controller.addError(error, stack);
                  },
                ),
          );
        }
      },
      onCancel: () async {
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      },
    );
    return controller.stream;
  }
}
