import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/live_profile_avatar.dart';

const _reviewsYellow = Color(0xFFFFC72C);
const _reviewsCream = Color(0xFFFFF9E9);
const _reviewsInk = Color(0xFF242424);

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

  String get _reviewerFallback =>
      reviewsFor == ReviewsFor.worker ? 'Client' : 'Worker';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF181818) : _reviewsCream;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF4F4F4) : _reviewsInk;
    final muted = dark ? const Color(0xFFB8B8B8) : const Color(0xFF737373);

    return Scaffold(
      backgroundColor: _reviewsYellow,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                _ReviewsHeader(onBack: () => Navigator.maybePop(context)),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(34),
                      ),
                    ),
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
                            message:
                                'Please check your connection and try again.',
                            text: text,
                            muted: muted,
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: _reviewsYellow,
                            ),
                          );
                        }

                        final reviews =
                            snapshot.data!.docs
                                .map(
                                  (document) => _ReviewEntry.fromDocument(
                                    document,
                                    reviewerField: _reviewerField,
                                  ),
                                )
                                .toList()
                              ..sort(
                                (a, b) => b.createdAt.compareTo(a.createdAt),
                              );

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
                                .fold<int>(
                                  0,
                                  (total, rating) => total + rating,
                                ) /
                            reviews.length;

                        return ListView.builder(
                          key: const ValueKey('reviews-list'),
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewsHeader extends StatelessWidget {
  const _ReviewsHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 112,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        children: [
          Material(
            color: _reviewsCream,
            shape: const CircleBorder(),
            child: IconButton(
              key: const ValueKey('reviews-back'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              color: _reviewsInk,
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Reviews',
            style: TextStyle(
              color: _reviewsInk,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
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

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    future: review.reviewerId.isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(review.reviewerId)
              .get(),
    builder: (context, profileSnapshot) {
      final profile = profileSnapshot.data?.data() ?? const <String, dynamic>{};
      final profileName = (profile['fullName'] ?? '').toString().trim();
      final reviewerName = profileName.isEmpty ? fallbackName : profileName;
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
                  backgroundColor: const Color(0xFFFFE8A3),
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
    required this.reviewerId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory _ReviewEntry.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    required String reviewerField,
  }) {
    final data = document.data();
    final ratingValue = data['rating'];
    final timestamp = data['createdAt'];
    return _ReviewEntry(
      reviewerId: (data[reviewerField] ?? '').toString(),
      rating: ratingValue is num ? ratingValue.round().clamp(1, 5) : 1,
      comment: (data['comment'] ?? '').toString().trim(),
      createdAt: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String reviewerId;
  final int rating;
  final String comment;
  final DateTime createdAt;
}

BoxDecoration _reviewCardDecoration(Color surface) => BoxDecoration(
  color: surface,
  borderRadius: BorderRadius.circular(18),
  boxShadow: const [
    BoxShadow(color: Color(0x24000000), blurRadius: 7, offset: Offset(0, 3)),
  ],
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
