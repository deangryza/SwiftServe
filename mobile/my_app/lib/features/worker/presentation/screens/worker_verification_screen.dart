import 'package:my_app/shared/services/expiry_push_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:crypto/crypto.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/repositories/verification_repository.dart';
import '../../../../shared/repositories/document_review_repository.dart';
import '../../../../shared/repositories/profile_repository.dart';
import '../../../../shared/widgets/action_confirmation_dialog.dart';
import '../models/worker_verification_ui_state.dart';
import 'face_capture_screens.dart';
import '../../../../shared/models/verification_evidence.dart';
import '../../../../shared/widgets/verification_evidence_panel.dart';

typedef VerificationCaptureLauncher =
    Future<File?> Function(BuildContext context);
typedef VerificationSubmitter =
    Future<FaceVerificationResult> Function({
      required String idType,
      required String idNumber,
      required File governmentId,
      required File facePhoto,
    });
typedef VerificationFileDeleter = Future<void> Function(File file);

class WorkerVerificationScreen extends StatefulWidget {
  const WorkerVerificationScreen({
    super.key,
    required this.profile,
    this.statusStream,
    this.profileStream,
    this.submitter,
    this.documentCaptureLauncher,
    this.selfieCaptureLauncher,
    this.deleteFile,
    this.signOut,
    this.documentReview,
  });

  final AppUser profile;

  /// Optional seams keep the production repository and cameras unchanged while
  /// allowing the onboarding coordinator to be exercised in widget tests.
  final Stream<VerificationStatus?>? statusStream;
  final Stream<AppUser?>? profileStream;
  final VerificationSubmitter? submitter;
  final VerificationCaptureLauncher? documentCaptureLauncher;
  final VerificationCaptureLauncher? selfieCaptureLauncher;
  final VerificationFileDeleter? deleteFile;
  final Future<void> Function()? signOut;
  final DocumentReviewGateway? documentReview;

  @override
  State<WorkerVerificationScreen> createState() =>
      _WorkerVerificationScreenState();
}

class _WorkerVerificationScreenState extends State<WorkerVerificationScreen> {
  static const List<String> _idTypes = <String>[
    'National ID',
    "Driver's License",
    'Passport',
    'UMID',
    'Postal ID',
    "Voter's ID",
  ];

  final _draft = _VerificationDraft();
  final _idNumberController = TextEditingController();
  final _idDetailsFormKey = GlobalKey<FormState>();

  VerificationRepository? _repository;
  late final Stream<VerificationStatus?> _statusStream;
  late final VerificationSubmitter _submitter;
  StreamSubscription<AppUser?>? _profileUpdates;
  AppUser? _liveProfile;

  bool _submitting = false;
  String _processingMessage = 'Processing your verification request…';
  bool _submissionComplete = false;
  bool _consent = false;
  String _qrStatus = 'DEMO NOT SCANNED';
  Map<String, dynamic> _evidence = {};
  late final DocumentReviewGateway _documentGateway;
  Map<String, dynamic> _documentReview = {};
  bool _documentMatches = false;
  bool get _requester => widget.profile.role == UserRole.client;
  Widget _checks() => VerificationEvidencePanel(
    evidence: VerificationEvidence(
      data: _evidence,
      requester: _requester,
      legacyAccess:
          (_liveProfile ?? widget.profile).verificationStatus ==
          VerificationStatus.verified,
    ),
    qr: _qrStatus,
  );
  double? _submittedConfidence;
  bool _submittedVerified = false;
  String? _stepMessage;
  double? _mismatchSimilarity;

  @override
  void initState() {
    super.initState();
    _documentGateway = widget.documentReview ?? DocumentReviewRepository();
    if (widget.statusStream == null || widget.submitter == null) {
      _repository = VerificationRepository();
    }
    _statusStream =
        widget.statusStream ??
        (_requester
            ? Stream.value(null)
            : _repository!.watch(widget.profile.id).map((doc) {
                _evidence = doc.data() ?? {};
                return doc.exists
                    ? VerificationStatus.fromWire(doc.data()?['status'])
                    : null;
              }));
    _submitter =
        widget.submitter ??
        ({
          required idType,
          required idNumber,
          required governmentId,
          required facePhoto,
        }) => _repository!.submit(
          idType: idType,
          idNumber: idNumber,
          governmentId: governmentId,
          facePhoto: facePhoto,
          comparisonOnly: _requester,
          documentSessionId: _documentReview['sessionId'],
          documentAttemptId: _documentReview['attemptId'],
        );
    final profiles =
        widget.profileStream ??
        (Firebase.apps.isNotEmpty &&
                FirebaseAuth.instance.currentUser?.uid == widget.profile.id
            ? ProfileRepository().watch(widget.profile.id)
            : null);
    _profileUpdates = profiles?.listen((profile) {
      if (mounted && profile != null && profile.id == widget.profile.id) {
        setState(() {
          _liveProfile = profile;
          if (profile.verificationStatus != VerificationStatus.verified) {
            _submittedVerified = false;
            _submissionComplete = false;
          }
        });
      }
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _documentGateway.close();
    _profileUpdates?.cancel();
    final files = <File?>[_draft.document, _draft.selfie];
    _draft.document = null;
    _draft.selfie = null;
    for (final file in files) {
      if (file != null) {
        unawaited(_deleteTemporaryFile(file));
      }
    }
    _idNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_draft.hasProgress && !_submitting,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _submitting) return;
        if (await _confirmDiscard()) {
          await _discardDraft();
          if (context.mounted) Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Verification',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              onPressed: _submitting ? null : _handleSignOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(
          child: StreamBuilder<VerificationStatus?>(
            stream: _statusStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  snapshot.data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _VerificationStatusView(
                  icon: Icons.cloud_off_outlined,
                  title: 'Checks could not be loaded',
                  description:
                      'Your account access has not changed. Go back and try again.',
                  accentColor: AppTheme.ink,
                );
              }

              final state = WorkerVerificationUiState.resolve(
                profileStatus:
                    (_liveProfile ?? widget.profile).verificationStatus,
                submissionStatus: snapshot.data,
              );
              return _buildContent(state);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(WorkerVerificationUiState state) {
    if (state.isVerified && !_requester) {
      return _VerificationStatusView(
        key: ValueKey('verification_verified_status'),
        icon: Icons.verified_outlined,
        title: 'Worker access retained',
        description:
            'Existing worker access does not establish official PSA authentication.',
        accentColor: AppTheme.ink,
        action: _checks(),
      );
    }

    if (_submissionComplete) {
      final similarity = _formatPercent(_submittedConfidence);
      if (_submittedVerified && !_requester) {
        return _VerificationStatusView(
          key: const ValueKey('verification_submission_verified'),
          icon: Icons.verified_outlined,
          title: 'Worker approval recorded',
          description: similarity == null
              ? 'The backend reported worker approval. Face matching alone does not establish official identity.'
              : 'Your selfie matched your ID with $similarity similarity. '
                    'Worker approval is a separate backend decision.',
          accentColor: AppTheme.ink,
          action: _checks(),
        );
      }
      return _VerificationStatusView(
        key: ValueKey('verification_submission_complete'),
        icon: Icons.schedule_send_outlined,
        title: _requester
            ? 'Face comparison complete'
            : 'Worker approval pending',
        description:
            'Face and DEMO QR results cannot approve an account. Official government authentication and trusted server liveness remain unavailable.',
        accentColor: AppTheme.ink,
        action: Column(
          children: [
            _checks(),
            if (_requester)
              TextButton(
                onPressed: _startFreshWizard,
                child: const Text('Run another face check'),
              ),
          ],
        ),
      );
    }

    if (state.isAwaitingReview && !_requester) {
      return _VerificationStatusView(
        key: ValueKey('verification_pending_status'),
        icon: Icons.hourglass_top_rounded,
        title: 'Verification under review',
        description:
            'Your documents were submitted successfully. We will '
            'notify you when the review is complete.',
        accentColor: AppTheme.ink,
        action: _checks(),
      );
    }

    final needsResubmission =
        state.status == VerificationStatus.rejected ||
        state.status == VerificationStatus.resubmissionRequired;
    if (needsResubmission && !_draft.started) {
      return _VerificationStatusView(
        key: const ValueKey('verification_resubmission_status'),
        icon: Icons.assignment_late_outlined,
        title: state.status == VerificationStatus.rejected
            ? 'Verification was not approved'
            : 'New submission required',
        description: state.description,
        accentColor: AppTheme.ink,
        action: FilledButton(
          key: const ValueKey('verification_resubmit_button'),
          onPressed: _startFreshWizard,
          child: const Text('Start resubmission'),
        ),
      );
    }

    if (!_draft.started) return _buildPreparation();
    return _buildWizard();
  }

  Widget _buildPreparation() {
    return SingleChildScrollView(
      key: const ValueKey('verification_preparation'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Verify your identity',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Verification helps keep customers and workers safe. You will '
                'enter your ID details, photograph your government ID, and '
                'take a live selfie so we can match your face to the ID.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              const _PreparationItem(
                icon: Icons.badge_outlined,
                title: 'Have a valid government ID ready',
                description:
                    'National ID, driver’s license, passport, UMID, '
                    'Postal ID, and voter’s ID are accepted.',
              ),
              const _PreparationItem(
                icon: Icons.wb_sunny_outlined,
                title: 'Find a bright, quiet place',
                description:
                    'Avoid glare on your ID, keep all four corners visible, '
                    'and remove glasses or hats for the selfie.',
              ),
              const _PreparationItem(
                icon: Icons.lock_outline,
                title: 'Your information stays protected',
                description:
                    'Photos are used for verification and retained '
                    'only under the existing review and deletion policy.',
              ),
              const _PreparationItem(
                icon: Icons.timer_outlined,
                title: 'Allow about 3–5 minutes',
                description:
                    'Your progress is kept only while this screen is '
                    'open and is not saved across app restarts.',
              ),
              const SizedBox(height: 24),
              _checks(),
              DemoQrCheck(
                onResult: (value) => setState(() => _qrStatus = value),
              ),
              CheckboxListTile(
                key: const ValueKey('verification-consent'),
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (value) => setState(() => _consent = value == true),
                title: const Text(
                  'I consent to private document suitability review and face comparison.',
                ),
                subtitle: Text(
                  _requester
                      ? 'Requester face checks are processed in memory and are not saved as worker verification. DEMO QR data stays on this screen.'
                      : 'Worker photos use the existing private review storage and deletion process. Pending retention still needs review before production. No PSA service is contacted.',
                ),
              ),
              FilledButton(
                key: const ValueKey('verification_start_button'),
                onPressed: !_consent
                    ? null
                    : () => setState(() {
                        _draft.started = true;
                        _draft.step = _VerificationStep.idDetails;
                      }),
                child: const Text('Start verification'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWizard() {
    final totalSteps = _VerificationStep.values.length;
    final stepNumber = _draft.step.index + 1;
    return SingleChildScrollView(
      key: ValueKey('verification_step_$stepNumber'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Step $stepNumber of $totalSteps',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  Text('${((stepNumber / totalSteps) * 100).round()}%'),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: stepNumber / totalSteps),
              const SizedBox(height: 24),
              if (_mismatchSimilarity != null) ...[
                _buildMismatchCard(),
                const SizedBox(height: 16),
              ] else if (_stepMessage != null) ...[
                _MessageCard(message: _stepMessage!),
                const SizedBox(height: 16),
              ],
              _buildCurrentStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    return switch (_draft.step) {
      _VerificationStep.idDetails => _buildIdDetailsStep(),
      _VerificationStep.document => _buildDocumentStep(),
      _VerificationStep.selfie => _buildSelfieStep(),
      _VerificationStep.review => _buildReviewStep(),
    };
  }

  Widget _buildIdDetailsStep() {
    return Form(
      key: _idDetailsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ID details',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the details exactly as they appear on your government ID.',
          ),
          if (!_consent)
            CheckboxListTile(
              key: const ValueKey('verification-consent'),
              value: _consent,
              onChanged: (value) => setState(() => _consent = value == true),
              title: const Text(
                'I consent to private document suitability review and face comparison. No PSA authentication is performed.',
              ),
            ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            key: const ValueKey('verification_id_type'),
            initialValue: _draft.idType,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'ID type',
              border: OutlineInputBorder(),
            ),
            items: _idTypes
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(
                      type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _draft.idType = value;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('verification_id_number'),
            controller: _idNumberController,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'ID number',
              hintText: 'Enter your ID number',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'ID number is required'
                : null,
            onChanged: (value) => _draft.idNumber = value,
            onFieldSubmitted: (_) => _continueFromIdDetails(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('verification_continue'),
            onPressed: _continueFromIdDetails,
            child: const Text('Continue'),
          ),
          TextButton(onPressed: _goBackOneStep, child: const Text('Back')),
        ],
      ),
    );
  }

  Widget _documentPanel() {
    final status = _documentMatches
        ? _documentReview['status']
        : 'DOCUMENT_PENDING';
    final label = switch (status) {
      'DOCUMENT_ACCEPTED' => 'Document accepted for further verification',
      'DOCUMENT_REJECTED' => 'Document rejected — upload a replacement',
      'DOCUMENT_UNREADABLE' => 'Document unreadable — upload another image',
      'DOCUMENT_REVIEW_REQUIRED' =>
        'Document submitted — awaiting document review',
      _ => 'Document not submitted for review',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text(
              'Suitability review is not government authentication or worker approval.',
            ),
            if (_documentReview['reason'] is String &&
                _documentReview['reason'] != '')
              Text(_documentReview['reason']),
            TextButton(
              onPressed: _submitting ? null : _refreshDocument,
              child: const Text('Refresh document review'),
            ),
            if (['DOCUMENT_REJECTED', 'DOCUMENT_UNREADABLE'].contains(status))
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(
                        () => _draft.step = _VerificationStep.document,
                      ),
                child: const Text('Replace document'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshDocument() async {
    if (_submitting || !_consent) return;
    setState(() {
      _submitting = true;
      _processingMessage = 'Refreshing document review…';
    });
    try {
      final result = await _documentGateway.get();
      if (!mounted) return;
      bool? bytesMatch;
      if (_draft.document != null && result['imageDigest'] is String) {
        bytesMatch =
            sha256.convert(await _draft.document!.readAsBytes()).toString() ==
                result['imageDigest'] &&
            _draft.idType == result['declaredType'];
        if (!mounted) return;
      }
      // Never associate a new local photo with an older reviewed attempt.
      if (_draft.document == null && result['attemptId'] != null) {
        final restored = await _documentGateway.restore(result);
        if (!mounted) {
          await restored.delete();
          return;
        }
        setState(() {
          _draft.document = restored;
          _documentMatches = true;
          _documentReview = result;
          _draft.idType = result['declaredType'] ?? _draft.idType;
        });
      }
      setState(() {
        if (bytesMatch != null) {
          _documentMatches = bytesMatch;
        } else if (_documentReview['attemptId'] != null &&
            _documentReview['attemptId'] != result['attemptId'] &&
            _draft.document != null) {
          _documentMatches = false;
        }
        _documentReview = result;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _stepMessage =
              'Could not refresh document review. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildDocumentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Photograph your government ID',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Place the ID on a flat surface. Keep all four corners inside the '
          'frame and tilt the card slightly if you see glare.',
        ),
        const SizedBox(height: 20),
        _documentPanel(),
        if (_documentMatches &&
            _documentReview['status'] == 'DOCUMENT_ACCEPTED')
          FilledButton(
            onPressed: _submitting
                ? null
                : () => setState(
                    () => _draft.step = _draft.selfie == null
                        ? _VerificationStep.selfie
                        : _VerificationStep.review,
                  ),
            child: const Text('Continue with reviewed document'),
          ),
        if (_draft.document != null) ...[
          _PhotoPreview(
            file: _draft.document!,
            semanticLabel: 'Captured government ID',
          ),
          const SizedBox(height: 16),
        ],
        FilledButton(
          key: const ValueKey('verification_capture_id'),
          onPressed: _submitting ? null : () => _captureDocument(advance: true),
          child: Text(
            _draft.document == null ? 'Open ID camera' : 'Capture ID again',
          ),
        ),
        TextButton.icon(
          onPressed: _submitting ? null : _uploadDocument,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Upload digital ID image (JPEG / PNG)'),
        ),
        TextButton(
          onPressed: _submitting ? null : _goBackOneStep,
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildMismatchCard() {
    final similarity = _formatPercent(_mismatchSimilarity);
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('verification_mismatch'),
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              similarity == null
                  ? 'Your selfie did not match your ID'
                  : 'Your selfie did not match your ID ($similarity similarity)',
              style: TextStyle(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try again in good, even light, remove glasses or hats, and '
              'hold the ID flat so your photo on it is sharp.',
              style: TextStyle(color: colors.onErrorContainer),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('verification_retry_selfie'),
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _mismatchSimilarity = null;
                      _stepMessage = null;
                      _draft.step = _VerificationStep.selfie;
                    }),
              child: const Text('Retake selfie'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelfieStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Take a live selfie',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Face the camera in good light and follow the on-screen prompts. '
          'Remove glasses or hats so we can match your face to your ID.',
        ),
        const SizedBox(height: 20),
        if (_draft.selfie != null) ...[
          _PhotoPreview(file: _draft.selfie!, semanticLabel: 'Live selfie'),
          const SizedBox(height: 16),
        ],
        FilledButton(
          key: const ValueKey('verification_capture_selfie'),
          onPressed: _submitting ? null : () => _captureSelfie(advance: true),
          child: Text(
            _draft.selfie == null ? 'Open selfie camera' : 'Take selfie again',
          ),
        ),
        TextButton(
          onPressed: _submitting ? null : _goBackOneStep,
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review and submit',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Check that your ID is readable and your selfie is clear before '
          'submitting your verification.',
        ),
        const SizedBox(height: 20),
        _documentPanel(),
        _ReviewPhoto(
          title: 'Government ID',
          file: _draft.document,
          onRetake: () => _captureDocument(advance: false),
          buttonKey: const ValueKey('verification_retake_id'),
        ),
        const SizedBox(height: 16),
        _ReviewPhoto(
          title: 'Live selfie',
          file: _draft.selfie,
          onRetake: () => _captureSelfie(advance: false),
          buttonKey: const ValueKey('verification_retake_selfie'),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ID details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Type: ${_draft.idType}'),
                const SizedBox(height: 6),
                Text('Number: ${_draft.maskedIdNumber}'),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('verification_edit_details'),
                  onPressed: _submitting
                      ? null
                      : () => setState(() {
                          _stepMessage = null;
                          _mismatchSimilarity = null;
                          _draft.step = _VerificationStep.idDetails;
                        }),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit details'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('verification_submit'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit verification'),
        ),
        if (_submitting) ...[
          const LinearProgressIndicator(),
          Text(_processingMessage),
        ],
        TextButton(
          onPressed: _submitting ? null : _goBackOneStep,
          child: const Text('Back'),
        ),
      ],
    );
  }

  void _continueFromIdDetails() {
    if (!_consent) {
      setState(() => _stepMessage = 'Consent is required before capture.');
      return;
    }
    if (!(_idDetailsFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _draft.idNumber = _idNumberController.text.trim();
      if (_documentReview['declaredType'] != null &&
          _documentReview['declaredType'] != _draft.idType) {
        _documentMatches = false;
      }
      _stepMessage = null;
      _draft.step = _VerificationStep.document;
    });
    if (widget.documentReview == null) unawaited(_refreshDocument());
  }

  void _goBackOneStep() {
    setState(() {
      _stepMessage = null;
      _mismatchSimilarity = null;
      if (_draft.step == _VerificationStep.idDetails) {
        _draft.started = false;
      } else {
        _draft.step = _VerificationStep.values[_draft.step.index - 1];
      }
    });
  }

  Future<void> _captureDocument({required bool advance}) async {
    final launcher = widget.documentCaptureLauncher ?? _openDocumentCamera;
    final captured = await launcher(context);
    if (!mounted || captured == null) return;
    final previous = _draft.document;
    setState(() {
      _draft.document = captured;
      _documentMatches = false;
      _stepMessage = null;
      _mismatchSimilarity = null;
      if (advance) {
        _draft.step = _draft.selfie == null
            ? _VerificationStep.selfie
            : _VerificationStep.review;
      }
    });
    if (previous != null && previous.path != captured.path) {
      await _deleteTemporaryFile(previous);
    }
  }

  Future<File?> _openDocumentCamera(BuildContext context) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => const DocumentCaptureScreen()),
    );
  }

  Future<void> _uploadDocument() async {
    setState(() => _submitting = true);
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return;
      if (await selected.length() > 5 * 1024 * 1024) {
        throw const FormatException('Image too large');
      }
      final bytes = await selected
          .openRead(0, 8)
          .expand((chunk) => chunk)
          .toList();
      final png =
          bytes.length == 8 && bytes.join(',') == '137,80,78,71,13,10,26,10';
      final jpeg =
          bytes.length >= 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255;
      if (!png && !jpeg) {
        throw const FormatException('JPEG/PNG required');
      }
      final ownedCopy = await File(selected.path).copy(
        '${Directory.systemTemp.path}/swiftserve-id-${DateTime.now().microsecondsSinceEpoch}.${png ? 'png' : 'jpg'}',
      );
      if (!mounted) {
        await ownedCopy.delete();
        return;
      }
      final previous = _draft.document;
      setState(() {
        _draft.document = ownedCopy;
        _documentMatches = false;
        _draft.step = _draft.selfie == null
            ? _VerificationStep.selfie
            : _VerificationStep.review;
      });
      if (previous != null) await _deleteTemporaryFile(previous);
    } catch (_) {
      if (mounted) {
        setState(
          () => _stepMessage =
              'Choose a JPEG/PNG image no larger than 5 MB. The backend also validates and processes it.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _captureSelfie({required bool advance}) async {
    final launcher = widget.selfieCaptureLauncher ?? _openSelfieCamera;
    final captured = await launcher(context);
    if (!mounted || captured == null) return;
    final previous = _draft.selfie;
    setState(() {
      _draft.selfie = captured;
      _stepMessage = null;
      _mismatchSimilarity = null;
      if (advance) _draft.step = _VerificationStep.review;
    });
    if (previous != null && previous.path != captured.path) {
      await _deleteTemporaryFile(previous);
    }
  }

  Future<File?> _openSelfieCamera(BuildContext context) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => const SelfieLivenessScreen()),
    );
  }

  Future<void> _submit() async {
    // A second tap can arrive before the disabled button is rebuilt.
    if (_submitting) return;
    if (!_consent) {
      setState(
        () => _stepMessage = 'Consent is required before processing images.',
      );
      return;
    }
    final document = _draft.document;
    final selfie = _draft.selfie;
    if (document == null || selfie == null || _draft.idNumber.trim().isEmpty) {
      setState(() {
        _stepMessage = 'Complete all verification steps before submitting.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _processingMessage = 'Preparing verification…';
      _stepMessage = null;
      _mismatchSimilarity = null;
    });
    try {
      if (!_documentMatches ||
          _documentReview['status'] != 'DOCUMENT_ACCEPTED') {
        if (!_documentMatches) {
          setState(() => _processingMessage = 'Uploading document for review…');
          final result = await _documentGateway.submit(
            document,
            _draft.idType,
            _documentReview,
          );
          if (!mounted) return;
          setState(() {
            _documentReview = result;
            _documentMatches = true;
          });
        }
        if (_documentReview['status'] != 'DOCUMENT_ACCEPTED') {
          setState(() {
            _submitting = false;
            _stepMessage =
                _documentReview['status'] == 'DOCUMENT_REVIEW_REQUIRED'
                ? 'Document submitted. Awaiting document review. This does not establish government authenticity.'
                : 'Document not accepted. Upload a replacement and submit it for review.';
          });
          return;
        }
      }
      setState(
        () => _processingMessage =
            'Uploading images and processing face comparison…',
      );
      final result = await _submitter(
        idType: _draft.idType,
        idNumber: _draft.idNumber.trim(),
        governmentId: document,
        facePhoto: selfie,
      );
      await _deleteDraftFiles();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submissionComplete = true;
        _submittedConfidence = result.similarity ?? result.confidence;
        _submittedVerified = result.isVerified;
        _evidence = {
          ..._evidence,
          ...result.evidence,
          if (result.evidence['faceResult'] is Map)
            'face': result.evidence['faceResult'],
          if (!result.evidence.containsKey('faceResult'))
            'face': {
              'status': result.band == 'strong' ? 'MATCH' : 'BORDERLINE',
            },
        };
        _draft.reset();
        _idNumberController.clear();
      });
    } on DocumentReviewException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _stepMessage = error.message;
        if ([
          'DOCUMENT_UNREADABLE',
          'INVALID_DOCUMENT_UPLOAD',
        ].contains(error.code)) {
          _draft.step = _VerificationStep.document;
        }
      });
    } on FaceVerificationException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        switch (error.failure) {
          case FaceVerificationFailure.mismatch:
            // Stay on review so both photos are visible; the mismatch card
            // offers a button back to the selfie step.
            _draft.step = _VerificationStep.review;
            _mismatchSimilarity = error.similarity ?? 0;
          case FaceVerificationFailure.noFace ||
                  FaceVerificationFailure.multipleFaces ||
                  FaceVerificationFailure.quality
              when error.image != null:
            final retakeId = error.image == VerificationImage.document;
            _draft.step = retakeId
                ? _VerificationStep.document
                : _VerificationStep.selfie;
            _stepMessage = retakeId
                ? '${error.message} Photograph your ID again so only the '
                      'face printed on it is visible.'
                : '${error.message} Take your selfie again alone, facing '
                      'the camera in good light.';
          default:
            _draft.step = _VerificationStep.review;
            _stepMessage = error.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _draft.step = _VerificationStep.review;
        _stepMessage =
            'Verification could not be submitted. Check your '
            'connection and try again.';
      });
    }
  }

  Future<void> _handleSignOut() async {
    if (_draft.hasProgress && !await _confirmDiscard()) return;
    await _discardDraft();
    if (widget.signOut != null) {
      await widget.signOut!();
    } else {
      await ExpiryPushService.instance.beforeSignOut();
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_draft.hasProgress) return true;
    return showActionConfirmation(
      context,
      title: 'Discard verification?',
      message:
          'Are you sure you want to discard this verification? Your entered details and captured photos will be deleted.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      icon: Icons.delete_outline_rounded,
      confirmButtonKey: const ValueKey('verification_confirm_discard'),
    );
  }

  Future<void> _discardDraft() async {
    await _deleteDraftFiles();
    if (!mounted) return;
    setState(() {
      _draft.reset();
      _idNumberController.clear();
      _stepMessage = null;
    });
  }

  Future<void> _deleteDraftFiles() async {
    final files = <File?>[_draft.document, _draft.selfie];
    _draft.document = null;
    _draft.selfie = null;
    for (final file in files) {
      if (file != null) await _deleteTemporaryFile(file);
    }
  }

  Future<void> _deleteTemporaryFile(File file) async {
    try {
      if (widget.deleteFile != null) {
        await widget.deleteFile!(file);
      } else if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup must not replace the user's submission result.
    }
  }

  Future<void> _startFreshWizard() async {
    await _deleteDraftFiles();
    if (!mounted) return;
    setState(() {
      _draft.reset();
      _draft.started = true;
      _idNumberController.clear();
      _stepMessage = null;
      _mismatchSimilarity = null;
      _submissionComplete = false;
      _submittedConfidence = null;
      _submittedVerified = false;
    });
  }

  String? _formatPercent(double? value) =>
      value == null ? null : '${value.round()}%';
}

enum _VerificationStep { idDetails, document, selfie, review }

class _VerificationDraft {
  bool started = false;
  _VerificationStep step = _VerificationStep.idDetails;
  String idType = 'National ID';
  String idNumber = '';
  File? document;
  File? selfie;

  bool get hasProgress =>
      started ||
      idNumber.trim().isNotEmpty ||
      document != null ||
      selfie != null;

  String get maskedIdNumber {
    final value = idNumber.trim();
    if (value.isEmpty) return 'Not provided';
    if (value.length <= 4) return List.filled(value.length, '•').join();
    return '${List.filled(value.length - 4, '•').join()}${value.substring(value.length - 4)}';
  }

  void reset() {
    started = false;
    step = _VerificationStep.idDetails;
    idType = 'National ID';
    idNumber = '';
    document = null;
    selfie = null;
  }
}

class _VerificationStatusView extends StatelessWidget {
  const _VerificationStatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Icon(icon, size: 80, color: accentColor),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(description, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 28), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _PreparationItem extends StatelessWidget {
  const _PreparationItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.file, required this.semanticLabel});

  final File file;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: AppTheme.line,
              child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewPhoto extends StatelessWidget {
  const _ReviewPhoto({
    required this.title,
    required this.file,
    required this.onRetake,
    required this.buttonKey,
  });

  final String title;
  final File? file;
  final VoidCallback onRetake;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (file != null)
            _PhotoPreview(file: file!, semanticLabel: title)
          else
            const AspectRatio(
              aspectRatio: 4 / 3,
              child: ColoredBox(
                color: AppTheme.line,
                child: Center(child: Icon(Icons.add_a_photo_outlined)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            key: buttonKey,
            onPressed: onRetake,
            child: Text(
              title == 'Government ID' ? 'Retake ID' : 'Retake selfie',
            ),
          ),
        ],
      ),
    );
  }
}
