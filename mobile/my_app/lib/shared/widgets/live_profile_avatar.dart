import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'profile_avatar.dart';

/// Shows the latest public profile photo and new-member state for a user.
class LiveProfileAvatar extends StatelessWidget {
  const LiveProfileAvatar({
    super.key,
    required this.userId,
    required this.fallbackName,
    this.radius = 24,
    this.backgroundColor = AppTheme.softYellow,
    this.foregroundColor = AppTheme.ink,
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
    if (userId.isEmpty || Firebase.apps.isEmpty) {
      return _fallback(joinedAt);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('public_profiles')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data() ?? const <String, dynamic>{};
        final publicJoinedAt = _timestamp(profile['createdAt']) ?? joinedAt;
        if (publicJoinedAt != null) {
          return _avatar(profile, publicJoinedAt);
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('member_badges')
              .doc(userId)
              .snapshots(),
          builder: (context, badgeSnapshot) {
            final badgeData =
                badgeSnapshot.data?.data() ?? const <String, dynamic>{};
            return _avatar(profile, _timestamp(badgeData['joinedAt']));
          },
        );
      },
    );
  }

  Widget _avatar(Map<String, dynamic> profile, DateTime? effectiveJoinedAt) {
    final storedPhoto = (profile['photoBase64'] ?? '').toString().trim();
    final photoBase64 = storedPhoto.isEmpty ? fallbackPhotoBase64 : storedPhoto;
    var photoUrl = (profile['photoUrl'] ?? profile['photoURL'] ?? '')
        .toString()
        .trim();
    if (photoUrl.isEmpty && FirebaseAuth.instance.currentUser?.uid == userId) {
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

DateTime? _timestamp(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r's+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return 'U';
  if (words.length == 1) return words.first.characters.first.toUpperCase();
  return (words.first.characters.first + words.last.characters.first)
      .toUpperCase();
}
