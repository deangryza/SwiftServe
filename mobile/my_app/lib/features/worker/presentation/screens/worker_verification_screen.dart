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
import 'national_id_capture_screen.dart';
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
    this.initialDocument,
    this.initialSelfie,
  });

  final AppUser profile;

  /// Ownership of registration temporary copies transfers to this screen.
  final File? initialDocument;
  final File? initialSelfie;

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

  VerificationRepository? _repository;
  late final Stream<VerificationStatus?> _statusStream;
  late final VerificationSubmitter _submitter;
  StreamSubscription<AppUser?>? _profileUpdates;
  AppUser? _liveProfile;

  bool _submitting = false;
  String _processingMessage = 'Processing your verification request…';
  bool _submissionComplete = false;
  bool _consent = false;

  /// A connection failure (not a rejected photo) interrupted the ID check.
  bool _canRecheckDocument = false;

  /// The user chose to start over after a rejection or resubmission request.
  bool _resubmitting = false;
  Map<String, dynamic> _evidence = {};
  late final DocumentReviewGateway _documentGateway;
  Map<String, dynamic> _documentReview = {};
  bool _documentMatches = false;
  bool get _requester => widget.profile.role == UserRole.client;
  String get _accountLabel => _requester ? 'Account' : 'Worker';
  Widget _checks() => VerificationEvidencePanel(
    evidence: VerificationEvidence(
      data: _evidence,
      requester: _requester,
      legacyAccess:
          (_liveProfile ?? widget.profile).verificationStatus ==
          VerificationStatus.verified,
    ),
  );
  double? _submittedConfidence;
  bool _submittedVerified = false;
  String? _stepMessage;
  double? _mismatchSimilarity;

  @override
  void initState() {
    super.initState();
    _draft.document = widget.initialDocument;
    _draft.selfie = widget.initialSelfie;
    _documentGateway = widget.documentReview ?? DocumentReviewRepository();
    if (widget.statusStream == null || widget.submitter == null) {
      _repository = VerificationRepository();
    }
    _statusStream =
        widget.statusStream ??
        // Clients and workers share one submission record and review flow.
        _repository!.watch(widget.profile.id).map((doc) {
          _evidence = doc.data() ?? {};
          return doc.exists
              ? VerificationStatus.fromWire(doc.data()?['status'])
              : null;
        });
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
    // A result from this session is shown before the stored status.
    if (_submissionComplete && _submittedVerified) {
      final similarity = _formatPercent(_submittedConfidence);
      return _VerificationStatusView(
        key: const ValueKey('verification_submission_verified'),
        icon: Icons.verified_outlined,
        title: 'You are verified',
        description: similarity == null
            ? 'Your selfie matched your ID and your account is now verified.'
            : 'Your selfie matched your ID with $similarity similarity. '
                  'Your account is now verified.',
        action: _checks(),
      );
    }
    if (state.isVerified) {
      return _VerificationStatusView(
        key: ValueKey('verification_verified_status'),
        icon: Icons.verified_outlined,
        title: _requester ? 'Account verified' : 'Worker access retained',
        description: _requester
            ? 'Your account is verified. This does not establish official PSA authentication.'
            : 'Existing worker access does not establish official PSA authentication.',
        action: _checks(),
      );
    }

    if (_submissionComplete) {
      return _VerificationStatusView(
        key: const ValueKey('verification_submission_complete'),
        icon: Icons.schedule_send_outlined,
        title: 'Almost done',
        description:
            'Your ID and selfie were submitted. An administrator will take '
            'one more look before your ${_accountLabel.toLowerCase()} '
            'account is verified. We will notify you when it is done.',
        action: _checks(),
      );
    }

    if (state.isAwaitingReview) {
      return _VerificationStatusView(
        key: ValueKey('verification_pending_status'),
        icon: Icons.hourglass_top_rounded,
        title: 'Verification under review',
        description:
            'Your documents were submitted successfully. We will '
            'notify you when the review is complete.',
        action: _checks(),
      );
    }

    final needsResubmission =
        state.status == VerificationStatus.rejected ||
        state.status == VerificationStatus.resubmissionRequired;
    if (needsResubmission && !_draft.started && !_resubmitting) {
      return _VerificationStatusView(
        key: const ValueKey('verification_resubmission_status'),
        icon: Icons.assignment_late_outlined,
        title: state.status == VerificationStatus.rejected
            ? 'Verification was not approved'
            : 'New submission required',
        description: state.description,
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

  Widget _stepHeader(int step) {
    const total = 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Step $step of $total',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text(switch (step) {
              1 => 'Choose ID',
              2 => 'Scan ID',
              _ => 'Selfie',
            }),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: step / total),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPreparation() {
    final theme = Theme.of(context);
    final fromSignUp = _draft.document != null && _draft.selfie != null;
    return SingleChildScrollView(
      key: const ValueKey('verification_preparation'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stepHeader(1),
              Text(
                'Verify your identity',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                fromSignUp
                    ? 'We will use the ID and selfie you took during sign-up. '
                          'Choose the ID type and we will check them now.'
                    : 'It takes about two minutes. Scan your ID, then take a '
                          'selfie. We compare the two to confirm it is you.',
              ),
              if (!_requester) ...[
                const SizedBox(height: 8),
                const Text(
                  'For worker accounts, an administrator also checks your ID '
                  'before you can accept jobs.',
                  key: ValueKey('verification_worker_review_note'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Which ID will you use?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in _idTypes)
                    ChoiceChip(
                      key: ValueKey('verification_id_type_$type'),
                      label: Text(type),
                      selected: _draft.idType == type,
                      onSelected: (_) => setState(() => _draft.idType = type),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const _PreparationItem(
                icon: Icons.badge_outlined,
                title: 'Use the real card',
                description:
                    'Lay it flat in good light. Keep all four corners in the '
                    'frame and avoid glare on the photo.',
              ),
              const _PreparationItem(
                icon: Icons.face_outlined,
                title: 'Be ready for a selfie',
                description:
                    'Remove glasses or hats, face the camera and hold still.',
              ),
              const _PreparationItem(
                icon: Icons.lock_outline,
                title: 'Your photos stay private',
                description:
                    'They are used only to verify your account and are '
                    'removed under the review and deletion policy.',
              ),
              CheckboxListTile(
                key: const ValueKey('verification-consent'),
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (value) => setState(() => _consent = value == true),
                title: const Text(
                  'I agree to my ID and selfie being checked and compared to '
                  'verify my account.',
                ),
                subtitle: const Text(
                  'This is not an official government (PSA) check.',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('verification_start_button'),
                onPressed: _consent ? _start : null,
                child: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The current ID photo was accepted by the server for this attempt.
  bool get _documentAccepted =>
      _draft.document != null &&
      _documentMatches &&
      _documentReview['status'] == 'DOCUMENT_ACCEPTED';

  void _start() {
    if (!_consent) return;
    setState(() {
      _draft.started = true;
      _stepMessage = null;
      _mismatchSimilarity = null;
      if (_documentReview['declaredType'] != null &&
          _documentReview['declaredType'] != _draft.idType) {
        _documentMatches = false;
      }
      _draft.step = _documentAccepted
          ? _VerificationStep.selfie
          : _VerificationStep.document;
    });
    if (_draft.document != null && !_documentMatches) {
      unawaited(_checkDocument());
    } else if (_draft.document == null && widget.documentReview == null) {
      // Pick up an ID that was already accepted in an earlier session.
      unawaited(_refreshDocument());
    }
  }

  Widget _buildWizard() {
    final stepNumber = _draft.step.index + 2;
    return SingleChildScrollView(
      key: ValueKey('verification_step_$stepNumber'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stepHeader(stepNumber),
              if (_mismatchSimilarity != null) ...[
                _buildMismatchCard(),
                const SizedBox(height: 16),
              ] else if (_stepMessage != null) ...[
                _MessageCard(message: _stepMessage!),
                const SizedBox(height: 16),
              ],
              switch (_draft.step) {
                _VerificationStep.document => _buildDocumentStep(),
                _VerificationStep.selfie => _buildSelfieStep(),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 10),
        Text(_processingMessage, textAlign: TextAlign.center),
      ],
    ),
  );

  Future<void> _refreshDocument() async {
    if (_submitting || !_consent) return;
    setState(() {
      _submitting = true;
      _processingMessage = 'Checking your ID status…';
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
    } on DocumentReviewException catch (error) {
      // The server answered; show its reason instead of blaming the connection.
      if (mounted) setState(() => _stepMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _stepMessage =
              'Could not check your ID status. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted || !_documentAccepted) return;
    if (_draft.step == _VerificationStep.document) {
      setState(() => _draft.step = _VerificationStep.selfie);
    }
    if (_draft.selfie != null && _mismatchSimilarity == null) await _submit();
  }

  Widget _buildDocumentStep() {
    final theme = Theme.of(context);
    final status = _documentMatches ? _documentReview['status'] : null;
    final reason = _documentReview['reason'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Scan your ${_draft.idType}',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Lay the card flat and fill the frame with it. Keep all four '
          'corners visible and avoid glare. We check the photo right away.',
        ),
        const SizedBox(height: 20),
        if (_draft.document != null) ...[
          _PhotoPreview(
            file: _draft.document!,
            semanticLabel: 'Captured government ID',
          ),
          const SizedBox(height: 12),
        ],
        if (_submitting)
          _progress()
        else ...[
          if (status == 'DOCUMENT_ACCEPTED') ...[
            const _StatusCard(
              key: ValueKey('verification_id_accepted'),
              icon: Icons.check_circle_outline,
              title: 'ID accepted',
              body: 'Your ID photo is clear. Next, take a selfie.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('verification_continue'),
              onPressed: () => setState(() {
                _stepMessage = null;
                _draft.step = _VerificationStep.selfie;
              }),
              child: const Text('Continue to selfie'),
            ),
          ] else if (status == 'DOCUMENT_REVIEW_REQUIRED') ...[
            const _StatusCard(
              key: ValueKey('verification_id_waiting'),
              icon: Icons.hourglass_top_rounded,
              title: 'Waiting for ID review',
              body:
                  'An administrator needs to check this ID before you can '
                  'continue. This does not establish government authenticity.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('verification_refresh_document'),
              onPressed: _refreshDocument,
              child: const Text('Check again'),
            ),
          ] else if (status == 'DOCUMENT_REJECTED' ||
              status == 'DOCUMENT_UNREADABLE') ...[
            _StatusCard(
              key: const ValueKey('verification_id_rejected'),
              icon: Icons.error_outline,
              title: 'This ID photo was not accepted',
              body: reason is String && reason.isNotEmpty
                  ? reason
                  : 'Take a new, clearer photo of your ID.',
            ),
            const SizedBox(height: 12),
          ] else if (_canRecheckDocument && _draft.document != null) ...[
            OutlinedButton(
              key: const ValueKey('verification_check_id'),
              onPressed: _checkDocument,
              child: const Text('Check this photo again'),
            ),
            const SizedBox(height: 4),
          ],
          if (status == 'DOCUMENT_ACCEPTED')
            OutlinedButton(
              key: const ValueKey('verification_capture_id'),
              onPressed: _captureDocument,
              child: const Text('Retake ID'),
            )
          else
            FilledButton(
              key: const ValueKey('verification_capture_id'),
              onPressed: _captureDocument,
              child: Text(
                _draft.document == null ? 'Open ID camera' : 'Retake ID',
              ),
            ),
          TextButton.icon(
            key: const ValueKey('verification_upload_id'),
            onPressed: _uploadDocument,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Upload a photo of your ID instead'),
          ),
          TextButton(onPressed: _goBackOneStep, child: const Text('Back')),
        ],
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
              onPressed: _submitting ? null : _captureSelfie,
              child: const Text('Retake selfie'),
            ),
            TextButton(
              key: const ValueKey('verification_mismatch_retake_id'),
              onPressed: _submitting ? null : _changeDocument,
              child: Text(
                'Retake ID instead',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelfieStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Take a selfie',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Follow the prompt, then hold still for the countdown. We match '
          'your selfie with your ID automatically.',
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(
              Icons.check_circle_outline,
              color: theme.colorScheme.primary,
            ),
            title: const Text('ID accepted'),
            subtitle: Text(_draft.idType),
            trailing: TextButton(
              key: const ValueKey('verification_retake_id'),
              onPressed: _submitting ? null : _changeDocument,
              child: const Text('Change'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_draft.selfie != null) ...[
          _PhotoPreview(file: _draft.selfie!, semanticLabel: 'Live selfie'),
          const SizedBox(height: 12),
        ],
        if (_submitting)
          _progress()
        else ...[
          if (_mismatchSimilarity == null)
            FilledButton(
              key: const ValueKey('verification_capture_selfie'),
              onPressed: _captureSelfie,
              child: Text(
                _draft.selfie == null ? 'Open selfie camera' : 'Retake selfie',
              ),
            ),
          if (_draft.selfie != null && _mismatchSimilarity == null)
            OutlinedButton(
              key: const ValueKey('verification_submit'),
              onPressed: _submit,
              child: const Text('Try again with this selfie'),
            ),
          TextButton(onPressed: _goBackOneStep, child: const Text('Back')),
        ],
      ],
    );
  }

  void _changeDocument() {
    setState(() {
      _stepMessage = null;
      _mismatchSimilarity = null;
      _draft.step = _VerificationStep.document;
    });
  }

  void _goBackOneStep() {
    setState(() {
      _stepMessage = null;
      _mismatchSimilarity = null;
      if (_draft.step == _VerificationStep.document) {
        _draft.started = false;
      } else {
        _draft.step = _VerificationStep.document;
      }
    });
  }

  Future<void> _captureDocument() async {
    if (_submitting) return;
    final launcher = widget.documentCaptureLauncher ?? _openDocumentCamera;
    final captured = await launcher(context);
    if (captured == null) return;
    if (!mounted) {
      await _deleteTemporaryFile(captured);
      return;
    }
    await _useDocument(captured);
  }

  /// Replaces the draft ID photo and sends it for its check straight away.
  Future<void> _useDocument(File captured) async {
    final previous = _draft.document;
    setState(() {
      _draft.document = captured;
      _documentMatches = false;
      _canRecheckDocument = false;
      _stepMessage = null;
      _mismatchSimilarity = null;
      _draft.step = _VerificationStep.document;
    });
    if (previous != null && previous.path != captured.path) {
      await _deleteTemporaryFile(previous);
    }
    if (mounted) await _checkDocument();
  }

  Future<Map<String, dynamic>> _sendDocument(File document) async {
    try {
      return await _documentGateway.submit(
        document,
        _draft.idType,
        _documentReview,
      );
    } on DocumentReviewException catch (error) {
      if (error.code != 'DOCUMENT_ATTEMPT_STALE') rethrow;
      // The server holds an attempt this screen has not seen yet (an earlier
      // session). Learn its identifiers, then replace it.
      final current = await _documentGateway.get();
      return _documentGateway.submit(document, _draft.idType, current);
    }
  }

  Future<void> _checkDocument() async {
    final document = _draft.document;
    if (document == null || _submitting) return;
    setState(() {
      _submitting = true;
      _processingMessage = 'Checking your ID…';
      _stepMessage = null;
      _canRecheckDocument = false;
    });
    var accepted = false;
    try {
      final result = await _sendDocument(document);
      if (!mounted) return;
      accepted = result['status'] == 'DOCUMENT_ACCEPTED';
      setState(() {
        _submitting = false;
        _documentReview = result;
        _documentMatches = true;
        if (accepted) _draft.step = _VerificationStep.selfie;
      });
    } on DocumentReviewException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _stepMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _canRecheckDocument = true;
        _stepMessage =
            'Could not check your ID. Check your connection and try again.';
      });
    }
    // Sign-up already captured a selfie: finish without another tap.
    if (mounted && accepted && _draft.selfie != null) await _submit();
  }

  Future<File?> _openDocumentCamera(BuildContext context) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => _draft.idType == 'National ID'
            ? const NationalIdCaptureScreen()
            : const DocumentCaptureScreen(),
      ),
    );
  }

  Future<void> _uploadDocument() async {
    if (_submitting) return;
    if (_draft.idType == 'National ID') {
      final captured = await Navigator.of(context).push<File>(
        MaterialPageRoute(
          builder: (_) => const NationalIdCaptureScreen(openGallery: true),
        ),
      );
      if (captured == null) return;
      if (!mounted) {
        await _deleteTemporaryFile(captured);
        return;
      }
      await _useDocument(captured);
      return;
    }
    if (!await requestIdGalleryConsent(context) || !mounted) return;
    File? picked;
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
      picked = await File(selected.path).copy(
        '${Directory.systemTemp.path}/swiftserve-id-${DateTime.now().microsecondsSinceEpoch}.${png ? 'png' : 'jpg'}',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _stepMessage = 'Choose a JPEG or PNG image no larger than 5 MB.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (picked == null) return;
    if (!mounted) {
      await _deleteTemporaryFile(picked);
      return;
    }
    await _useDocument(picked);
  }

  Future<void> _captureSelfie() async {
    if (_submitting) return;
    final launcher = widget.selfieCaptureLauncher ?? _openSelfieCamera;
    final captured = await launcher(context);
    if (!mounted || captured == null) return;
    final previous = _draft.selfie;
    setState(() {
      _draft.selfie = captured;
      _stepMessage = null;
      _mismatchSimilarity = null;
      _draft.step = _VerificationStep.selfie;
    });
    if (previous != null && previous.path != captured.path) {
      await _deleteTemporaryFile(previous);
    }
    // No separate review page: the match runs as soon as the selfie is taken.
    if (mounted) await _submit();
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
    if (document == null || selfie == null) {
      setState(() {
        _stepMessage = 'Scan your ID and take a selfie first.';
      });
      return;
    }
    if (!_documentAccepted) {
      // Checks the ID, then comes back here once it is accepted.
      if (!_documentMatches) await _checkDocument();
      return;
    }

    setState(() {
      _submitting = true;
      _processingMessage = 'Matching your selfie with your ID…';
      _stepMessage = null;
      _mismatchSimilarity = null;
    });
    try {
      final result = await _submitter(
        idType: _draft.idType,
        idNumber: '',
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
        _documentMatches = false;
        _resubmitting = false;
      });
    } on FaceVerificationException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _draft.step = _VerificationStep.selfie;
        switch (error.failure) {
          case FaceVerificationFailure.mismatch:
            _mismatchSimilarity = error.similarity ?? 0;
          case FaceVerificationFailure.noFace ||
                  FaceVerificationFailure.multipleFaces ||
                  FaceVerificationFailure.quality
              when error.image == VerificationImage.document:
            // The accepted photo turned out unusable for matching.
            _documentMatches = false;
            _draft.step = _VerificationStep.document;
            _stepMessage = '${error.message} Take a new photo of your ID.';
          case FaceVerificationFailure.noFace ||
                  FaceVerificationFailure.multipleFaces ||
                  FaceVerificationFailure.quality
              when error.image == VerificationImage.selfie:
            _stepMessage =
                '${error.message} Take your selfie again alone, facing '
                'the camera in good light.';
          default:
            _stepMessage = error.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _draft.step = _VerificationStep.selfie;
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
      _documentMatches = false;
      _stepMessage = null;
      _mismatchSimilarity = null;
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
      _documentMatches = false;
      _resubmitting = true;
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

enum _VerificationStep { document, selfie }

class _VerificationDraft {
  bool started = false;
  _VerificationStep step = _VerificationStep.document;
  String idType = 'National ID';
  File? document;
  File? selfie;

  bool get hasProgress => started || document != null || selfie != null;

  void reset() {
    started = false;
    step = _VerificationStep.document;
    idType = 'National ID';
    document = null;
    selfie = null;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationStatusView extends StatelessWidget {
  const _VerificationStatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
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
              Icon(icon, size: 80, color: context.themeInk),
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
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: Theme.of(context).colorScheme.outlineVariant,
              child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
            ),
          ),
        ),
      ),
    );
  }
}
