import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

/// App consent precedes the system picker; cancelling never opens the gallery.
/// The system picker grants access to the chosen photo, not the whole library.
Future<Uint8List?> pickProfilePhotoWithConsent(
  BuildContext context, {
  Future<Uint8List?> Function()? pickPhoto,
}) async {
  final allowed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Allow photo selection?'),
      content: const Text(
        'Allow SwiftServe to open your photo picker? Only the photo you choose '
        'will be used, and it will be visible on your public profile.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  if (allowed != true || !context.mounted) return null;
  try {
    return await (pickPhoto ?? pickProfilePhoto)();
  } on PlatformException catch (error) {
    if (error.code == 'photo_access_denied' ||
        error.code == 'photo_access_restricted') {
      throw const FormatException(
        'Photo access is not allowed. You can enable it in your device settings '
        'and try again. Your profile photo has not changed.',
      );
    }
    rethrow;
  }
}

// Small thumbnails fit within the existing profile document without a Storage bucket.
Future<Uint8List?> pickProfilePhoto() async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 256,
    maxHeight: 256,
    imageQuality: 70,
  );
  if (image == null) return null;
  final bytes = await image.readAsBytes();
  if (bytes.length > 48 * 1024) {
    throw const FormatException('Please choose a smaller profile photo.');
  }
  return bytes;
}
