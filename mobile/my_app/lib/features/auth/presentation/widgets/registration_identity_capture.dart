import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import '../../domain/registration_identity_draft.dart';
import '../../../worker/domain/national_id_photo_validator.dart';
import '../../../worker/domain/capture_quality.dart';
import '../../../worker/presentation/screens/national_id_capture_screen.dart';
import '../../../worker/presentation/screens/face_capture_screens.dart';

/// Both registration roles use exactly the same final-image checks.
class RegistrationIdentityCapture extends StatefulWidget {
  const RegistrationIdentityCapture({
    super.key,
    required this.draft,
    this.face = false,
    this.onRequestId,
  });
  final RegistrationIdentityDraft draft;
  final bool face;
  final VoidCallback? onRequestId;
  @override
  State<RegistrationIdentityCapture> createState() =>
      _RegistrationIdentityCaptureState();
}

class _RegistrationIdentityCaptureState
    extends State<RegistrationIdentityCapture> {
  bool _selecting = false;
  String? _error;
  Future<void> _chooseSource(bool front) async {
    if (_selecting || widget.draft.busy || widget.draft.capturing) return;
    setState(() => _selecting = true);
    widget.draft.capturing = true;
    bool? camera;
    var chosen = false;
    try {
      camera = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${front ? 'Front' : 'Back'} side photo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                key: const ValueKey('registration-id-camera'),
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take photo'),
                onTap: () {
                  if (chosen) return;
                  chosen = true;
                  Navigator.pop(context, true);
                },
              ),
              ListTile(
                key: const ValueKey('registration-id-gallery'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  if (chosen) return;
                  chosen = true;
                  Navigator.pop(context, false);
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      widget.draft.capturing = false;
      if (mounted) setState(() => _selecting = false);
    }
    if (!mounted || camera == null) return;
    if (camera) {
      await _camera(front);
    } else {
      await _pick(front);
    }
  }

  Future<void> _camera(bool front) async {
    if (_selecting || widget.draft.busy) return;
    setState(() {
      _selecting = true;
      _error = null;
    });
    widget.draft.capturing = true;
    try {
      final photo = await Navigator.of(context).push<File>(
        MaterialPageRoute(
          builder: (_) => NationalIdCaptureScreen(frontSide: front),
        ),
      );
      if (photo == null) return;
      if (!mounted) {
        await RegistrationIdentityDraft.deleteTemporary(photo);
        return;
      }
      // The existing guided route validates this exact owned file before pop.
      // Do not repeat native detection or change/recompress the accepted bytes.
      await widget.draft.acceptId(
        photo,
        isFront: front,
        validate: (_, _) async {},
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not capture the ID. Allow camera access and try again, or choose a gallery photo.',
        );
      }
    } finally {
      widget.draft.capturing = false;
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<void> _pick(bool front) async {
    if (_selecting || widget.draft.busy) return;
    setState(() {
      _selecting = true;
      _error = null;
    });
    widget.draft.capturing = true;
    File? owned;
    FaceDetector? faces;
    BarcodeScanner? qr;
    try {
      if (!await requestIdGalleryConsent(context) || !mounted) return;
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null || !mounted) return;
      final original = File(selected.path);
      final extension = await NationalIdPhotoValidator.imageExtension(original);
      final directory = await Directory.systemTemp.createTemp(
        'swiftserve-registration-id-',
      );
      owned = await original.copy('${directory.path}/id.$extension');
      if (!mounted) return;
      faces = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableLandmarks: true,
        ),
      );
      qr = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
      final validator = NationalIdPhotoValidator(faces, qr);
      final candidate = owned;
      owned = null; // Draft owns cleanup whether validation succeeds or fails.
      await widget.draft.acceptId(
        candidate,
        isFront: front,
        validate: validator.validate,
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is CaptureQualityException
              ? error.message
              : 'Could not read or validate this photo. Allow photo access and choose another JPEG or PNG.',
        );
      }
    } finally {
      await RegistrationIdentityDraft.deleteTemporary(owned);
      try {
        await faces?.close();
      } catch (_) {
        /* Native shutdown is best effort. */
      }
      try {
        await qr?.close();
      } catch (_) {
        /* Never keep the form locked. */
      }
      widget.draft.capturing = false;
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<void> _selfie() async {
    if (_selecting ||
        widget.draft.busy ||
        widget.draft.capturing ||
        !widget.draft.hasId) {
      return;
    }
    setState(() {
      _selecting = true;
      _error = null;
    });
    widget.draft.capturing = true;
    try {
      final photo = await Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => const SelfieLivenessScreen()),
      );
      if (photo != null) {
        if (mounted) {
          await widget.draft.acceptSelfie(photo);
        } else {
          await RegistrationIdentityDraft.deleteTemporary(photo);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not capture a selfie. Allow camera access and try again.',
        );
      }
    } finally {
      widget.draft.capturing = false;
      if (mounted) setState(() => _selecting = false);
    }
  }

  Widget _card(
    String label,
    File? file,
    VoidCallback onTap,
    String hint,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OutlinedButton(
      key: ValueKey('registration-${label == 'Front side' ? 'front' : 'back'}'),
      onPressed: _selecting || widget.draft.busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 120),
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Column(
        children: [
          if (file != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                file,
                key: ValueKey(
                  'registration-${label == 'Front side' ? 'front' : 'back'}-preview',
                ),
                height: 150,
                width: double.infinity,
                fit: BoxFit.contain,
                cacheWidth: 600, // Display only; upload bytes remain unchanged.
                semanticLabel: '$label accepted ID photo',
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      'Preview unavailable. Tap to retake or replace.',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Icon(
            file == null
                ? Icons.add_photo_alternate_outlined
                : Icons.check_circle_outline,
          ),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            file == null ? hint : 'Photo accepted · Tap to replace',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.draft,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.face ? 'Face verification' : 'National ID',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (!widget.face) ...[
          const Text(
            'Select a clear photo of the entire card. Front: portrait on the left. Back: readable QR on the right. JPEG/PNG up to 20 MB and 16 megapixels.',
          ),
          const SizedBox(height: 12),
          _card(
            'Front side',
            widget.draft.front,
            () => _chooseSource(true),
            'Must contain one clear ID portrait',
          ),
          _card(
            'Back side',
            widget.draft.back,
            () => _chooseSource(false),
            'Must contain a readable QR code',
          ),
          const Text(
            'For other government ID layouts, skip and use Verification checks in Settings. Photo checks do not prove ID authenticity.',
          ),
        ] else ...[
          const Icon(Icons.face_retouching_natural, size: 100),
          Text(
            widget.draft.selfie == null
                ? 'Capture a live selfie using the existing blink and head-turn checks.'
                : 'Selfie captured. Face comparison has not run yet.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('registration-selfie'),
            onPressed: _selecting || widget.draft.busy || widget.draft.capturing
                ? null
                : widget.draft.hasId
                ? _selfie
                : widget.onRequestId ??
                      () => setState(
                        () => _error =
                            'Both ID photos must be accepted first: a clear front portrait and a readable QR on the back. Go back to the ID screen to upload or retake them.',
                      ),
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(
              !widget.draft.hasId
                  ? 'Add ID photos first'
                  : widget.draft.selfie == null
                  ? 'Take selfie'
                  : 'Retake selfie',
            ),
          ),
          if (!widget.draft.hasId)
            const Text(
              'Selfie capture needs both accepted ID photos. If you skipped ID upload or a photo was rejected, add or retake it first. You can also skip verification for now.',
            ),
          const Text(
            'After account creation, complete consent and ID details in Verification checks. Document review is required before the server compares faces. A selfie does not grant official verification.',
          ),
        ],
        if (_selecting || widget.draft.busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        if (_error ?? widget.draft.error case final String message)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              message,
              key: const ValueKey('registration-id-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
