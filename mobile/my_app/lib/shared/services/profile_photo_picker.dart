import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

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
