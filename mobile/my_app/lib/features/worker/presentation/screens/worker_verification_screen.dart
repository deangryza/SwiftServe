import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/repositories/verification_repository.dart';
import '../models/worker_verification_ui_state.dart';
import 'face_capture_screens.dart';

typedef VerificationCaptureLauncher =
    Future<File?> Function(BuildContext context);
typedef VerificationSubmitter =
    Future<FaceVerificationResult> Function({
      required String idType,
      required String idNumber,
      required File governmentId,
      // TODO(face-verification): nullable while ID-only bypass is active.
      // Restore to `required File facePhoto` to re-enable face matching.
      File? facePhoto,
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
  // TODO(face-verification): unused while ID-only bypass is active. Kept so
  // existing tests/callers still compile; remove the deprecation comment and
  // restore the selfie step to re-enable face matching.
  @Deprecated('Unused while face verification is bypassed')
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
  // TODO(face-verification): restore `double? _submittedConfidence` and the
  // confidence-based success copy when face matching returns.
  String? _stepMessage;

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
    final files = <File?>[_draft.document];
    _draft.document = null;
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
      // TODO(face-verification): bypass shows the generic message. When face
      // matching returns, restore the confidence-based "face match passed" copy.
      return const _VerificationStatusView(
        key: ValueKey('verification_submission_complete'),
        icon: Icons.schedule_send_outlined,
        title: 'Submitted for review',
        description:
            'Your verification was submitted successfully. An administrator '
            'will review your ID and notify you of the decision. You can '
            'return here to check its review status.',
        accentColor: Colors.blue,
      );
    }

    if (state.isVerified) {
      return const _VerificationStatusView(
        key: ValueKey('verification_verified_status'),
        icon: Icons.verified_outlined,
        title: 'Verification complete',
        description: 'Your identity is verified. You can now accept jobs.',
        accentColor: Colors.green,
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
        accentColor: Colors.orange,
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
        accentColor: Colors.redAccent,
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
              // TODO(face-verification): ID-only copy while bypassed. Restore
              // the live-selfie wording when face matching returns.
              const Text(
                'Verification helps keep customers and workers safe. You will '
                'enter your ID details, photograph your government ID, and '
                'submit it for administrator review.',
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
                    'Avoid glare on your ID and keep all four corners '
                    'visible inside the frame.',
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
    // TODO(face-verification): 3 steps while ID-only. Restore to 4 steps
    // (idDetails, document, selfie, review) to re-enable face matching.
    const totalSteps = 3;
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
              if (_stepMessage != null) ...[
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
    // TODO(face-verification): selfie step removed while ID-only bypass is
    // active. Restore `_VerificationStep.selfie => _buildSelfieStep()`.
    return switch (_draft.step) {
      _VerificationStep.idDetails => _buildIdDetailsStep(),
      _VerificationStep.document => _buildDocumentStep(),
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

  // TODO(face-verification): selfie step removed while ID-only bypass is
  // active. Restore _buildSelfieStep() (live-selfie challenge) to re-enable.
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
          'Check that your ID is readable before '
          'sending your verification for review.',
        ),
        const SizedBox(height: 20),
        _ReviewPhoto(
          title: 'Government ID',
          file: _draft.document,
          onRetake: () => _captureDocument(advance: false),
          buttonKey: const ValueKey('verification_retake_id'),
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
      // TODO(face-verification): ID-only skips straight to review. Restore
      // `_VerificationStep.selfie` here to re-enable face matching.
      if (advance) _draft.step = _VerificationStep.review;
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

  // TODO(face-verification): selfie capture removed while ID-only bypass is
  // active. Restore _captureSelfie() + _openSelfieCamera() to re-enable.

  Future<void> _submit() async {
    final document = _draft.document;
    if (document == null || _draft.idNumber.trim().isEmpty) {
      setState(() {
        _stepMessage = 'Complete all verification steps before submitting.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _stepMessage = null;
    });
    try {
      await _submitter(
        idType: _draft.idType,
        idNumber: _draft.idNumber.trim(),
        governmentId: document,
      );
      await _deleteDraftFiles();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submissionComplete = true;
        _draft.reset();
        _idNumberController.clear();
      });
    } on FaceVerificationException catch (error) {
      if (!mounted) return;
      // TODO(face-verification): mismatch branch removed while ID-only bypass
      // is active. Restore the selfie-retake handling to re-enable.
      setState(() {
        _submitting = false;
        _draft.step = _VerificationStep.review;
        _stepMessage = error.message;
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
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard verification?'),
            content: const Text(
              'Your entered details and captured photos will be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                key: const ValueKey('verification_confirm_discard'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
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
    final files = <File?>[_draft.document];
    _draft.document = null;
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
      _submissionComplete = false;
    });
  }
}

// TODO(face-verification): `selfie` step removed while ID-only bypass is
// active. Restore `selfie` in the enum to re-enable face matching.
enum _VerificationStep { idDetails, document, review }

class _VerificationDraft {
  bool started = false;
  _VerificationStep step = _VerificationStep.idDetails;
  String idType = 'National ID';
  String idNumber = '';
  File? document;

  bool get hasProgress =>
      started || idNumber.trim().isNotEmpty || document != null;

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
              color: Color(0xFFE4E7EB),
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
                color: Color(0xFFE4E7EB),
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
