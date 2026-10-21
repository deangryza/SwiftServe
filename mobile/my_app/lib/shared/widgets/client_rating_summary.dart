import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ClientRatingSummary {
  const ClientRatingSummary({required this.average, required this.reviewCount});

  final double average;
  final int reviewCount;

  String get displayAverage =>
      reviewCount == 0 ? '—' : average.toStringAsFixed(1);
}

ClientRatingSummary calculateClientRating(Iterable<Object?> values) {
  final ratings = values
      .whereType<num>()
      .map((rating) => rating.toDouble())
      .where((rating) => rating >= 1 && rating <= 5)
      .toList(growable: false);
  if (ratings.isEmpty) {
    return const ClientRatingSummary(average: 0, reviewCount: 0);
  }
  final total = ratings.fold<double>(
    0,
    (runningTotal, rating) => runningTotal + rating,
  );
  return ClientRatingSummary(
    average: total / ratings.length,
    reviewCount: ratings.length,
  );
}

class ClientRatingBuilder extends StatelessWidget {
  const ClientRatingBuilder({
    super.key,
    required this.clientId,
    required this.builder,
  });

  final String clientId;
  final Widget Function(BuildContext context, ClientRatingSummary summary)
  builder;

  @override
  Widget build(BuildContext context) {
    if (clientId.isEmpty) {
      return builder(
        context,
        const ClientRatingSummary(average: 0, reviewCount: 0),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('client_reviews')
          .where('clientId', isEqualTo: clientId)
          .snapshots(),
      builder: (context, snapshot) {
        final summary = calculateClientRating(
          snapshot.data?.docs.map((document) => document.data()['rating']) ??
              const <Object?>[],
        );
        return builder(context, summary);
      },
    );
  }
}
