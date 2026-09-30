enum UserRole { client, worker, admin }

enum VerificationStatus {
  pending,
  underReview,
  verified,
  rejected,
  resubmissionRequired;

  String get wireValue => switch (this) {
    VerificationStatus.pending => 'pending',
    VerificationStatus.underReview => 'under_review',
    VerificationStatus.verified => 'verified',
    VerificationStatus.rejected => 'rejected',
    VerificationStatus.resubmissionRequired => 'resubmission_required',
  };

  static VerificationStatus fromWire(Object? value) => switch (value) {
    'under_review' => VerificationStatus.underReview,
    'verified' => VerificationStatus.verified,
    'rejected' => VerificationStatus.rejected,
    'resubmission_required' => VerificationStatus.resubmissionRequired,
    _ => VerificationStatus.pending,
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.verificationStatus,
    this.phoneNumber = '',
    this.address = '',
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final VerificationStatus verificationStatus;
  final String phoneNumber;
  final String address;

  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    final role = switch (data['role']) {
      'worker' => UserRole.worker,
      'admin' => UserRole.admin,
      _ => UserRole.client,
    };
    return AppUser(
      id: id,
      fullName: (data['fullName'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      role: role,
      verificationStatus: VerificationStatus.fromWire(
        data['verificationStatus'],
      ),
      phoneNumber: (data['phoneNumber'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
    );
  }
}
