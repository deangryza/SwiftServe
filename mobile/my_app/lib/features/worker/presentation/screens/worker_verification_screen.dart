import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/repositories/verification_repository.dart';
import '../../../../shared/widgets/action_confirmation_dialog.dart';
import '../models/worker_verification_ui_state.dart';
import 'face_capture_screens.dart';

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
    this.submitter,
    this.documentCaptureLauncher,
    this.selfieCaptureLauncher,
    this.deleteFile,
    this.signOut,
  });

  final AppUser profile;

  /// Optional seams keep the production repository and cameras unchanged while
  /// allowing the onboarding coordinator to be exercised in widget tests.
  final Stream<VerificationStatus?>? statusStream;
  final VerificationSubmitter? submitter;
  final VerificationCaptureLauncher? documentCaptureLauncher;
  final VerificationCaptureLauncher? selfieCaptureLauncher;
  final VerificationFileDeleter? deleteFile;
  final Future<void> Function()? signOut;

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

  bool _submitting = false;
  bool _submissionComplete = false;
  double? _submittedConfidence;
  bool _submittedVerified = false;
  String? _stepMessage;
  double? _mismatchSimilarity;

  @override
  void initState() {
    super.initState();
    if (widget.statusStream == null || widget.submitter == null) {
      _repository = VerificationRepository();
    }
    _statusStream =
        widget.statusStream ?? _repository!.watchStatus(widget.profile.id);
    _submitter = widget.submitter ?? _repository!.submit;
  }

  @override
  void dispose() {
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

              final state = WorkerVerificationUiState.resolve(
                profileStatus: widget.profile.verificationStatus,
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
    if (_submissionComplete) {
      final similarity = _formatPercent(_submittedConfidence);
      if (_submittedVerified) {
        return _VerificationStatusView(
          key: const ValueKey('verification_submission_verified'),
          icon: Icons.verified_outlined,
          title: 'Verified',
          description: similarity == null
              ? 'Your selfie matched your ID. You can now accept jobs.'
              : 'Your selfie matched your ID with $similarity similarity. '
                    'You can now accept jobs.',
          accentColor: Colors.green,
        );
      }
      return const _VerificationStatusView(
        key: ValueKey('verification_submission_complete'),
        icon: Icons.schedule_send_outlined,
        title: 'Under review',
        description:
            'Under review — an admin will check your photos. You can return '
            'here to check the review status.',
        accentColor: Colors.blue,
      );
    }

    if (state.isVerified) {
      return const _VerificationStatusView(
        key: ValueKey('verification_verified_status'),
        icon: Icons.verified_outlined,
        title: 'Verification complete',
        description: 'Your identity is verified. You can now accept jobs.',
        accentColor: AppTheme.ink,
      );
    }

    if (state.isAwaitingReview) {
      return const _VerificationStatusView(
        key: ValueKey('verification_pending_status'),
        icon: Icons.hourglass_top_rounded,
        title: 'Verification under review',
        description:
            'Your documents were submitted successfully. We will '
            'notify you when the review is complete.',
        accentColor: AppTheme.ink,
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
              FilledButton(
                key: const ValueKey('verification_start_button'),
                onPressed: () => setState(() {
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
        TextButton(
          onPressed: _submitting ? null : _goBackOneStep,
          child: const Text('Back'),
        ),
      ],
    );
  }

  void _continueFromIdDetails() {
    if (!(_idDetailsFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _draft.idNumber = _idNumberController.text.trim();
      _stepMessage = null;
      _draft.step = _VerificationStep.document;
    });
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
      _stepMessage = null;
      _mismatchSimilarity = null;
    });
    try {
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
        _draft.reset();
        _idNumberController.clear();
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
                  FaceVerificationFailure.multipleFaces
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
