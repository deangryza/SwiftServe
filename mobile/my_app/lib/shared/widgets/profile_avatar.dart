import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.photoBase64 = '',
    this.photoUrl,
    this.radius = 35,
    this.joinedAt,
  });

  final String photoBase64;
  final String? photoUrl;
  final double radius;
  final DateTime? joinedAt;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      if (photoBase64.isNotEmpty) bytes = base64Decode(photoBase64);
    } on FormatException {
      // Older or invalid photos retain the default avatar.
    }
    final fallback = Icon(Icons.person, size: radius * 1.15);
    return RecentMemberAvatarBadge(
      joinedAt: joinedAt,
      radius: radius,
      child: CircleAvatar(
        radius: radius,
        child: ClipOval(
          child: SizedBox.square(
            dimension: radius * 2,
            child: bytes != null
                ? Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  )
                : photoUrl != null && photoUrl!.isNotEmpty
                ? Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  )
                : fallback,
          ),
        ),
      ),
    );
  }
}

bool isRecentlyJoined(DateTime? joinedAt, {DateTime? now}) {
  if (joinedAt == null) return false;
  final age = (now ?? DateTime.now()).difference(joinedAt);
  return !age.isNegative && age <= const Duration(days: 14);
}

class RecentMemberAvatarBadge extends StatelessWidget {
  const RecentMemberAvatarBadge({
    super.key,
    required this.child,
    required this.radius,
    this.joinedAt,
  });

  final Widget child;
  final double radius;
  final DateTime? joinedAt;

  @override
  Widget build(BuildContext context) {
    if (!isRecentlyJoined(joinedAt)) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -radius * 0.22,
          bottom: -radius * 0.08,
          child: Semantics(
            label: 'New member',
            child: Container(
              key: const ValueKey('recent-member-badge'),
              padding: EdgeInsets.symmetric(
                horizontal: radius < 28 ? 4 : 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF20B978),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                'NEW',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: radius < 28 ? 7 : 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
