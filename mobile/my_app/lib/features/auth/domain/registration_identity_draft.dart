import 'dart:io';
import 'package:flutter/foundation.dart';

/// Owns temporary copies only. No identity evidence is written to preferences.
/// Presence checks are not official authentication or a face-comparison result.
class RegistrationIdentityDraft extends ChangeNotifier {
  File? front, back, selfie;
  bool busy = false;
  bool _capturing = false;
  bool get capturing => _capturing;
  set capturing(bool value) {
    _capturing = value;
    if (!_closed) notifyListeners();
  }

  bool _closed = false;
  String? error;
  bool get hasId => front != null && back != null;
  bool get hasProgress => front != null || back != null || selfie != null;

  Future<void> acceptId(
    File candidate, {
    required bool isFront,
    required Future<void> Function(File, bool) validate,
  }) async {
    if (busy || _closed) {
      await deleteTemporary(candidate);
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await validate(candidate, isFront);
      if (_closed) {
        await deleteTemporary(candidate);
        return;
      }
      final previous = isFront ? front : back;
      if (isFront) {
        front = candidate;
      } else {
        back = candidate;
      }
      // A retaken ID starts a new comparison; never reuse an old selfie proof.
      final oldSelfie = selfie;
      selfie = null;
      await deleteTemporary(previous);
      await deleteTemporary(oldSelfie);
    } catch (failure) {
      await deleteTemporary(candidate);
      if (!_closed) error = failure.toString();
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> acceptSelfie(File candidate) async {
    if (_closed || busy || !hasId) {
      await deleteTemporary(candidate);
      return;
    }
    final previous = selfie;
    selfie = candidate;
    error = null;
    notifyListeners();
    await deleteTemporary(previous);
  }

  Future<void> skip({required bool id}) async {
    if (busy || capturing || _closed) return;
    busy = true;
    final files = [if (id) front, if (id) back, selfie];
    if (id) {
      front = null;
      back = null;
    }
    selfie = null;
    error = null;
    notifyListeners();
    try {
      for (final file in files) {
        await deleteTemporary(file);
      }
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  /// Moves ownership into the existing authenticated verification screen.
  /// The QR side is intentionally local-only, as in guided ID capture.
  Future<({File document, File? selfie})?> takeForVerification() async {
    if (_closed || busy || capturing || !hasId) return null;
    final files = (document: front!, selfie: selfie);
    final qrSide = back;
    front = back = selfie = null;
    await deleteTemporary(qrSide);
    return files;
  }

  static Future<void> deleteTemporary(File? file) async {
    if (file == null) return;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await file.delete();
        return;
      } on FileSystemException catch (error) {
        // A preview decoder can briefly hold an owned file open on Windows.
        // Retry sharing violations only, with a bounded wait. Never originals.
        if (error.osError?.errorCode != 32 || attempt == 3) return;
        await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    for (final file in [front, back, selfie]) {
      deleteTemporary(file);
    }
    front = back = selfie = null;
    super.dispose();
  }
}
