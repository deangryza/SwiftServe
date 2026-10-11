import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.photoBase64 = '',
    this.photoUrl,
    this.radius = 35,
  });

  final String photoBase64;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      if (photoBase64.isNotEmpty) bytes = base64Decode(photoBase64);
    } on FormatException {
      // Older or invalid photos retain the default avatar.
    }
    final fallback = Icon(Icons.person, size: radius * 1.15);
    return CircleAvatar(
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
    );
  }
}
