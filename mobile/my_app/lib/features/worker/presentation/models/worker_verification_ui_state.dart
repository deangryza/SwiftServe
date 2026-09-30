import '../../../../shared/models/app_user.dart';

class WorkerVerificationUiState {
  const WorkerVerificationUiState._({
    required this.status,
    required this.hasSubmission,
    required this.canAcceptJobs,
  });

  factory WorkerVerificationUiState.resolve({
    required VerificationStatus profileStatus,
    required VerificationStatus? submissionStatus,
  }) {
    final canAcceptJobs = profileStatus == VerificationStatus.verified;
    return WorkerVerificationUiState._(
      status: canAcceptJobs
          ? VerificationStatus.verified
          : submissionStatus ?? profileStatus,
      hasSubmission: submissionStatus != null,
      canAcceptJobs: canAcceptJobs,
    );
  }

  final VerificationStatus status;
  final bool hasSubmission;
  final bool canAcceptJobs;

  bool get isVerified => canAcceptJobs;

  bool get isAwaitingReview =>
      hasSubmission &&
      (status == VerificationStatus.pending ||
          status == VerificationStatus.underReview);

  bool get shouldShowForm =>
      !hasSubmission ||
      status == VerificationStatus.rejected ||
      status == VerificationStatus.resubmissionRequired;

  String get statusLabel {
    if (isVerified) return 'Verified';
    if (!hasSubmission) return 'Not verified';
    return switch (status) {
      VerificationStatus.pending => 'Verification pending',
      VerificationStatus.underReview => 'Under review',
      VerificationStatus.rejected => 'Verification rejected',
      VerificationStatus.resubmissionRequired => 'Resubmission required',
      VerificationStatus.verified => 'Verified',
    };
  }

  String get actionLabel {
    if (isVerified) return 'View verification status';
    if (!hasSubmission) return 'Verify account';
    return switch (status) {
      VerificationStatus.rejected ||
      VerificationStatus.resubmissionRequired => 'Resubmit verification',
      _ => 'View verification status',
    };
  }

  String get bannerTitle {
    if (!hasSubmission) return 'Verify your account';
    return statusLabel;
  }

  String get description {
    if (isVerified) return 'Your identity has been approved.';
    if (!hasSubmission) {
      return 'Submit your identity documents before accepting jobs.';
    }
    return switch (status) {
      VerificationStatus.pending || VerificationStatus.underReview =>
        'Your documents are being reviewed. You can browse jobs while you wait.',
      VerificationStatus.rejected =>
        'Your submission was rejected. Submit updated documents to try again.',
      VerificationStatus.resubmissionRequired =>
        'An administrator requested updated verification documents.',
      VerificationStatus.verified => 'Your identity has been approved.',
    };
  }
}
