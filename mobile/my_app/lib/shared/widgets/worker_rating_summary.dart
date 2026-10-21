import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class WorkerRatingSummary {
  const WorkerRatingSummary({required this.average, required this.reviewCount});

  final double average;
  final int reviewCount;

  String get displayAverage =>
      reviewCount == 0 ? '—' : average.toStringAsFixed(1);
}

WorkerRatingSummary calculateWorkerRating(Iterable<Object?> values) {
  final ratings = values
      .whereType<num>()
      .map((rating) => rating.toDouble())
      .where((rating) => rating >= 1 && rating <= 5)
      .toList(growable: false);
  if (ratings.isEmpty) {
    return const WorkerRatingSummary(average: 0, reviewCount: 0);
  }
  final total = ratings.fold<double>(
    0,
    (runningTotal, rating) => runningTotal + rating,
  );
  return WorkerRatingSummary(
    average: total / ratings.length,
    reviewCount: ratings.length,
  );
}

class WorkerRatingBuilder extends StatelessWidget {
  const WorkerRatingBuilder({
    super.key,
    required this.workerId,
    required this.builder,
  });

  final String workerId;
  final Widget Function(BuildContext context, WorkerRatingSummary summary)
  builder;

  @override
  Widget build(BuildContext context) {
    if (workerId.isEmpty) {
      return builder(
        context,
        const WorkerRatingSummary(average: 0, reviewCount: 0),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('workerId', isEqualTo: workerId)
          .snapshots(),
      builder: (context, snapshot) {
        final summary = calculateWorkerRating(
          snapshot.data?.docs.map((document) => document.data()['rating']) ??
              const <Object?>[],
        );
        return builder(context, summary);
      },
    );
  }
}
