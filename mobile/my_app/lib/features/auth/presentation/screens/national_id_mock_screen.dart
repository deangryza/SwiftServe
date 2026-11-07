import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:image_picker/image_picker.dart';
import '../../../../shared/services/national_id_mock_client.dart';
import '../../../../shared/utils/synthetic_identity_image.dart';
import '../../../../shared/models/verification_evidence.dart';
import '../../../../shared/widgets/verification_evidence_panel.dart';
import '../../../worker/presentation/screens/face_capture_screens.dart';

typedef IdentityMockCapture =
    Future<Uint8List?> Function(
      BuildContext context,
      bool selfie,
      bool digital,
    );

class NationalIdMockScreen extends StatefulWidget {
  const NationalIdMockScreen({
    super.key,
    required this.onContinue,
    this.client,
    this.capture,
  });
  final VoidCallback onContinue;
  final NationalIdMockClient? client;
  final IdentityMockCapture? capture;
  @override
  State<NationalIdMockScreen> createState() => _NationalIdMockScreenState();
}

class _NationalIdMockScreenState extends State<NationalIdMockScreen> {
  late final _client = widget.client ?? NationalIdMockClient();
  MockIdentityResult? _result;
  Uint8List? _document, _selfie;
  bool _busy = true, _digital = false;
  double? _progress;
  String? _error;
  @override
  void initState() {
    super.initState();
    _run(() => _client.begin());
  }

  void _clear() {
    _document?.fillRange(0, _document!.length, 0);
    _selfie?.fillRange(0, _selfie!.length, 0);
    _document = null;
    _selfie = null;
  }

  Future<void> _run(
    Future<MockIdentityResult> Function() operation, {
    bool clearImages = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await operation();
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Local mock verification could not finish. Check the demo backend, birthday and consent, then refresh or retry.',
        );
      }
    } finally {
      if (clearImages) _clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<Uint8List?> _capture(
    BuildContext context,
    bool selfie,
    bool digital,
  ) async {
    if (!selfie && digital) {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return null;
      if (await selected.length() > 1536 * 1024) {
        throw const FormatException('Image too large.');
      }
      // System photo picker grants access to a selected image only. Do not delete
      // the user's gallery source. Nothing is copied to shared/public storage.
      return selected.readAsBytes();
    }
    final file = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => selfie
            ? const SelfieLivenessScreen()
            : const DocumentCaptureScreen(),
      ),
    );
    if (file == null) return null;
    try {
      if (await file.length() > 1536 * 1024) {
        throw const FormatException('Image too large.');
      }
      return await file.readAsBytes();
    } finally {
      // These are temporary files created by SwiftServe's camera screens.
      await file.delete().catchError((_) => file);
    }
  }

  Future<void> _pick(bool selfie) async {
    setState(() => _busy = true);
    try {
      final bytes = await (widget.capture ?? _capture)(
        context,
        selfie,
        _digital,
      );
      if (!mounted) {
        bytes?.fillRange(0, bytes.length, 0);
        return;
      }
      if (bytes != null) {
        setState(() {
          if (selfie) {
            _selfie?.fillRange(0, _selfie!.length, 0);
            _selfie = bytes;
          } else {
            _document?.fillRange(0, _document!.length, 0);
            _document = bytes;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Capture was unavailable or the image exceeded 1.5 MB. Use a clear synthetic JPEG/PNG.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _clear();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final canCapture =
        result?.consent == true &&
        (result?.state == IdentityState.pending || result?.retryable == true);
    return Scaffold(
      appBar: AppBar(title: const Text('National ID verification')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              MockIdentityResult.label,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'LOCAL TEST ONLY. Use synthetic documents and selfie images. No PSA service is contacted and no official identity or worker privileges are granted.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Identity verification privacy notice',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Text(
              'With your consent, the demo backend processes the two selected images in memory for mock government and independent face checks, then discards them. Only minimal session, consent and review metadata is stored in the local Firestore emulator. Camera blink/turn checks are not trusted server liveness evidence. Do not upload a real National ID. No ID number is requested.',
            ),
            CheckboxListTile(
              key: const ValueKey('identity-consent'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I agree to this synthetic identity verification test.',
              ),
              value: result?.consent == true,
              onChanged:
                  !_busy && result?.state == IdentityState.consentRequired
                  ? (value) {
                      if (value == true) {
                        _run(() => _client.accept(result!.reference));
                      }
                    }
                  : null,
            ),
            if (_busy) LinearProgressIndicator(value: _progress),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (result != null) ...[
              const SizedBox(height: 12),
              Text(
                'Mock status: ${result.state.name}',
                key: const ValueKey('identity-status'),
              ),
              VerificationEvidencePanel(
                evidence: VerificationEvidence(
                  data: {
                    'providerType': 'MOCK',
                    'face': {
                      'status': result.face == 'PASSED'
                          ? 'MATCH'
                          : result.face == 'FAILED'
                          ? 'NO_MATCH'
                          : 'NOT_STARTED',
                    },
                    'liveness': {'status': result.liveness},
                    'reviewStatus': result.state == IdentityState.verified
                        ? 'APPROVED'
                        : 'PENDING',
                  },
                ),
              ),
              Text(
                'Government (MOCK): ${result.government}\nFace: ${result.face}\nLiveness: ${result.liveness}',
              ),
              if (result.checkSource == 'SYNTHETIC_FIXTURE')
                const Text(
                  'Face and liveness results are synthetic server fixtures, not TensorFlow or live-person verification.',
                ),
              if (result.state == IdentityState.manualReview)
                const Text(
                  'Manual review is required. Missing or failed checks cannot be approved as genuine government verification.',
                ),
              if (result.state == IdentityState.rejected)
                const Text(
                  'The mock checks did not pass. Your actual account verification has not changed.',
                ),
              if (result.retryable)
                const Text(
                  'A recoverable interruption occurred. Recapture synthetic images and retry this same session.',
                ),
              if (canCapture) ...[
                if (kDebugMode &&
                    const bool.fromEnvironment('NATIONAL_ID_SYNTHETIC_CAPTURE'))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              final bytes = await syntheticIdentityImage();
                              if (!mounted) {
                                bytes.fillRange(0, bytes.length, 0);
                                return;
                              }
                              setState(() {
                                _clear();
                                _error = null;
                                _document = bytes;
                                _selfie = Uint8List.fromList(bytes);
                              });
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'Could not generate the synthetic test pair. Please try again.',
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    child: const Text('Use generated synthetic test pair'),
                  ),
                DropdownButtonFormField<bool>(
                  initialValue: _digital,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Document format',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text(
                        'Physical ID image (synthetic)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text(
                        'Digital ID image (synthetic)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _digital = value ?? false;
                          _clear();
                        }),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('identity-document'),
                  onPressed: _busy ? null : () => _pick(false),
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(
                    _document == null
                        ? 'Capture/select synthetic ID'
                        : 'Synthetic ID ready',
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('identity-selfie'),
                  onPressed: _busy ? null : () => _pick(true),
                  icon: const Icon(Icons.face_outlined),
                  label: Text(
                    _selfie == null
                        ? 'Capture synthetic selfie'
                        : 'Synthetic selfie ready',
                  ),
                ),
                FilledButton(
                  key: const ValueKey('identity-submit'),
                  onPressed: _busy || _document == null || _selfie == null
                      ? null
                      : () => _run(
                          () => _client.submit(
                            result.reference,
                            _document!,
                            _selfie!,
                            digital: _digital,
                            progress: (value) {
                              if (mounted) setState(() => _progress = value);
                            },
                          ),
                          clearImages: true,
                        ),
                  child: Text(
                    result.retryable
                        ? 'Retry mock verification'
                        : 'Run mock verification',
                  ),
                ),
              ],
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => _client.status(result.reference)),
                child: const Text('Refresh status'),
              ),
              if ([
                    IdentityState.expired,
                    IdentityState.rejected,
                    IdentityState.failed,
                  ].contains(result.state) &&
                  !result.retryable)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _clear();
                          _run(() => _client.begin(fresh: true));
                        },
                  child: const Text('Start another mock session'),
                ),
            ],
            if (result == null && !_busy)
              TextButton(
                onPressed: () => _run(() => _client.begin()),
                child: const Text('Retry connection'),
              ),
            TextButton(
              onPressed: _busy ? null : widget.onContinue,
              child: const Text('Continue to app (mock only)'),
            ),
          ],
        ),
      ),
    );
  }
}
