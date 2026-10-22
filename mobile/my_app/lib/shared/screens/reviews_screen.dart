import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../widgets/live_profile_avatar.dart';

const _reviewsYellow = AppTheme.yellow;
const _reviewsCream = Color(0xFFFFFFFF);
const _reviewsInk = AppTheme.ink;

enum ReviewsFor { client, worker }

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({
    super.key,
    required this.userId,
    required this.reviewsFor,
  });

  final String userId;
  final ReviewsFor reviewsFor;

  String get _collection =>
      reviewsFor == ReviewsFor.worker ? 'reviews' : 'client_reviews';

  String get _recipientField =>
      reviewsFor == ReviewsFor.worker ? 'workerId' : 'clientId';

  String get _reviewerField =>
      reviewsFor == ReviewsFor.worker ? 'clientId' : 'workerId';

  String get _reviewerNameField =>
      reviewsFor == ReviewsFor.worker ? 'clientName' : 'workerName';

  String get _reviewerFallback =>
      reviewsFor == ReviewsFor.worker ? 'Client' : 'Worker';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF181818) : _reviewsCream;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF4F4F4) : _reviewsInk;
    final muted = dark ? const Color(0xFFB8B8B8) : AppTheme.muted;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: text,
        leading: IconButton(
          key: const ValueKey('reviews-back'),
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Reviews and Ratings'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(_collection)
                  .where(_recipientField, isEqualTo: userId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ReviewsMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Reviews are unavailable',
                    message: 'Please check your connection and try again.',
                    text: text,
                    muted: muted,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _reviewsYellow),
                  );
                }

                final reviews =
                    snapshot.data!.docs
                        .map(
                          (document) => _ReviewEntry.fromDocument(
                            document,
                            reviewerField: _reviewerField,
                            reviewerNameField: _reviewerNameField,
                          ),
                        )
                        .toList()
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                if (reviews.isEmpty) {
                  return _ReviewsMessage(
                    icon: Icons.reviews_outlined,
                    title: 'No reviews yet',
                    message:
                        'Reviews from completed bookings will appear here.',
                    text: text,
                    muted: muted,
                  );
                }

                final average =
                    reviews
                        .map((review) => review.rating)
                        .fold<int>(0, (total, rating) => total + rating) /
                    reviews.length;

                return ListView.builder(
                  key: const ValueKey('reviews-list'),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  itemCount: reviews.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _RatingOverview(
                          average: average,
                          count: reviews.length,
                          surface: surface,
                          text: text,
                          muted: muted,
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReviewCard(
                        review: reviews[index - 1],
                        fallbackName: _reviewerFallback,
                        surface: surface,
                        text: text,
                        muted: muted,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingOverview extends StatelessWidget {
  const _RatingOverview({
    required this.average,
    required this.count,
    required this.surface,
    required this.text,
    required this.muted,
  });

  final double average;
  final int count;
  final Color surface;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: _reviewCardDecoration(surface),
    child: Row(
      children: [
        Text(
          average.toStringAsFixed(1),
          style: TextStyle(
            color: text,
            fontSize: 40,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Stars(rating: average, size: 23),
              const SizedBox(height: 5),
              Text(
                count == 1 ? 'Based on 1 review' : 'Based on $count reviews',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.fallbackName,
    required this.surface,
    required this.text,
    required this.muted,
  });

  final _ReviewEntry review;
  final String fallbackName;
  final Color surface;
  final Color text;
  final Color muted;

  Future<String> _resolveReviewerName() async {
    if (review.reviewerId.isNotEmpty) {
      try {
        final publicProfile = await FirebaseFirestore.instance
            .collection('public_profiles')
            .doc(review.reviewerId)
            .get();
        final currentName = (publicProfile.data()?['fullName'] ?? '')
            .toString()
            .trim();
        if (currentName.isNotEmpty) return currentName;
      } catch (_) {
        // Continue with the review and booking snapshots for legacy records.
      }
    }

    if (review.reviewerName.isNotEmpty) return review.reviewerName;

    if (review.requestId.isNotEmpty && review.reviewerId.isNotEmpty) {
      try {
        final request = await FirebaseFirestore.instance
            .collection('service_requests')
            .doc(review.requestId)
            .get();
        final data = request.data();
        if ((data?[review.reviewerIdField] ?? '').toString() ==
            review.reviewerId) {
          final bookingName = (data?[review.reviewerNameField] ?? '')
              .toString()
              .trim();
          if (bookingName.isNotEmpty) return bookingName;
        }
      } catch (_) {
        // The generic role name remains available as the final fallback.
      }
    }

    return fallbackName;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _resolveReviewerName(),
    builder: (context, profileSnapshot) {
      final reviewerName =
          profileSnapshot.data ?? review.reviewerName.ifEmpty(fallbackName);
      return Container(
        padding: const EdgeInsets.all(17),
        decoration: _reviewCardDecoration(surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LiveProfileAvatar(
                  userId: review.reviewerId,
                  fallbackName: reviewerName,
                  radius: 23,
                  backgroundColor: AppTheme.softYellow,
                  foregroundColor: _reviewsInk,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reviewerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Stars(rating: review.rating.toDouble(), size: 17),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(review.createdAt),
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              review.comment.isEmpty ? 'No written comment.' : review.comment,
              style: TextStyle(
                color: review.comment.isEmpty ? muted : text,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, required this.size});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      5,
      (index) => Icon(
        index + 1 <= rating.round()
            ? Icons.star_rounded
            : Icons.star_border_rounded,
        color: _reviewsYellow,
        size: size,
      ),
    ),
  );
}

class _ReviewsMessage extends StatelessWidget {
  const _ReviewsMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.text,
    required this.muted,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: _reviewsYellow),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: text,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _ReviewEntry {
  const _ReviewEntry({
    required this.requestId,
    required this.reviewerId,
    required this.reviewerIdField,
    required this.reviewerName,
    required this.reviewerNameField,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory _ReviewEntry.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    required String reviewerField,
    required String reviewerNameField,
  }) {
    final data = document.data();
    final ratingValue = data['rating'];
    final timestamp = data['createdAt'];
    return _ReviewEntry(
      requestId: (data['requestId'] ?? document.id).toString(),
      reviewerId: (data[reviewerField] ?? '').toString(),
      reviewerIdField: reviewerField,
      reviewerName: (data[reviewerNameField] ?? '').toString().trim(),
      reviewerNameField: reviewerNameField,
      rating: ratingValue is num ? ratingValue.round().clamp(1, 5) : 1,
      comment: (data['comment'] ?? '').toString().trim(),
      createdAt: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String requestId;
  final String reviewerId;
  final String reviewerIdField;
  final String reviewerName;
  final String reviewerNameField;
  final int rating;
  final String comment;
  final DateTime createdAt;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

BoxDecoration _reviewCardDecoration(Color surface) => BoxDecoration(
  color: surface,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(
    color: surface.computeLuminance() < 0.5
        ? const Color(0xFF444444)
        : AppTheme.line,
  ),
);

String _formatDate(DateTime date) {
  if (date.millisecondsSinceEpoch == 0) return 'Recently';
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
