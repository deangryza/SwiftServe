import 'package:cloud_firestore/cloud_firestore.dart';

enum ReviewedRole { client, worker }

class AccountReview {
  AccountReview.fromMap(this.documentId, this.role, Map<String, dynamic> data)
    : userId = _string(
        data[role == ReviewedRole.worker ? 'workerId' : 'clientId'],
      ),
      requestId = _string(data['requestId']).isEmpty
          ? documentId
          : _string(data['requestId']),
      reviewerId = _string(
        data[role == ReviewedRole.worker ? 'clientId' : 'workerId'],
      ),
      reviewerName = _string(
        data[role == ReviewedRole.worker ? 'clientName' : 'workerName'],
      ).trim(),
      rating = _rating(data['rating']),
      comment = _string(data['comment']).trim(),
      createdAt = data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null;

  final String documentId, userId, requestId, reviewerId, reviewerName, comment;
  final ReviewedRole role;
  final double? rating;
  final DateTime? createdAt;
  String get sourcePath =>
      '${role == ReviewedRole.worker ? 'reviews' : 'client_reviews'}/$documentId';
  String get reviewerIdField =>
      role == ReviewedRole.worker ? 'clientId' : 'workerId';
  String get reviewerNameField =>
      role == ReviewedRole.worker ? 'clientName' : 'workerName';
  String get reviewerFallback =>
      role == ReviewedRole.worker ? 'Client' : 'Worker';
  String get contextLabel =>
      role == ReviewedRole.worker ? 'Reviewed as Worker' : 'Reviewed as Client';

  static String _string(Object? value) => value is String ? value : '';
  static double? _rating(Object? value) =>
      value is num && value >= 1 && value <= 5 ? value.toDouble() : null;
}

List<AccountReview> mergeAccountReviews(
  String uid,
  Iterable<AccountReview> reviews,
) {
  final byPath = <String, AccountReview>{};
  for (final review in reviews) {
    if (uid.isNotEmpty && review.userId == uid) {
      byPath[review.sourcePath] = review;
    }
  }
  return byPath.values.toList()..sort((a, b) {
    final time = (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
      a.createdAt?.millisecondsSinceEpoch ?? 0,
    );
    return time == 0 ? a.sourcePath.compareTo(b.sourcePath) : time;
  });
}

class AccountRatingSummary {
  AccountRatingSummary(
    Iterable<AccountReview> reviews, {
    this.loading = false,
    this.unavailable = false,
  }) {
    final ratings = reviews
        .map((review) => review.rating)
        .whereType<double>()
        .toList();
    reviewCount = ratings.length;
    average = ratings.isEmpty
        ? 0
        : ratings.reduce((a, b) => a + b) / ratings.length;
  }
  late final double average;
  late final int reviewCount;
  final bool loading, unavailable;
  String get displayAverage => loading || unavailable || reviewCount == 0
      ? '\u2014'
      : average.toStringAsFixed(1);
  String get label => unavailable
      ? 'Ratings unavailable'
      : loading
      ? 'Loading ratings'
      : reviewCount == 1
      ? '1 rating'
      : '$reviewCount ratings';
}
