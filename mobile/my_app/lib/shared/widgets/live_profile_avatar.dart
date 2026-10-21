import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'profile_avatar.dart';

/// Shows the latest photo from the canonical `users/{uid}` profile.
class LiveProfileAvatar extends StatelessWidget {
  const LiveProfileAvatar({
    super.key,
    required this.userId,
    required this.fallbackName,
    this.radius = 24,
    this.backgroundColor = const Color(0xFFFFF1C8),
    this.foregroundColor = const Color(0xFF242424),
    this.textStyle,
    this.fallbackPhotoBase64 = '',
    this.joinedAt,
  });

  final String userId;
  final String fallbackName;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;
  final TextStyle? textStyle;
  final String fallbackPhotoBase64;
  final DateTime? joinedAt;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty || Firebase.apps.isEmpty) return _fallback();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('public_profiles')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data() ?? const <String, dynamic>{};
        final storedPhoto = (profile['photoBase64'] ?? '').toString().trim();
        final photoBase64 = storedPhoto.isEmpty
            ? fallbackPhotoBase64
            : storedPhoto;
        final createdAt = profile['createdAt'];
        final effectiveJoinedAt = createdAt is Timestamp
            ? createdAt.toDate()
            : joinedAt;
        var photoUrl = (profile['photoUrl'] ?? profile['photoURL'] ?? '')
            .toString()
            .trim();
        if (photoUrl.isEmpty &&
            FirebaseAuth.instance.currentUser?.uid == userId) {
          photoUrl = FirebaseAuth.instance.currentUser?.photoURL ?? '';
        }

        if (photoBase64.isEmpty && photoUrl.isEmpty) {
          return _fallback(effectiveJoinedAt);
        }
        return ProfileAvatar(
          photoBase64: photoBase64,
          photoUrl: photoUrl,
          radius: radius,
          joinedAt: effectiveJoinedAt,
        );
      },
    );
  }

  Widget _fallback([DateTime? effectiveJoinedAt]) => RecentMemberAvatarBadge(
    joinedAt: effectiveJoinedAt ?? joinedAt,
    radius: radius,
    child: CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      child: Text(
        _initials(fallbackName),
        style:
            textStyle ??
            TextStyle(
              color: foregroundColor,
              fontSize: radius * 0.62,
              fontWeight: FontWeight.w800,
            ),
      ),
    ),
  );
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return 'U';
  if (words.length == 1) return words.first.characters.first.toUpperCase();
  return '${words.first.characters.first}${words.last.characters.first}'
      .toUpperCase();
}
