import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.roles = const [],
    this.phoneNumber = '',
    this.address = '',
    this.photoBase64 = '',
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final VerificationStatus verificationStatus;

  /// Every role this account can switch into; [role] is the active one.
  final List<UserRole> roles;
  final String phoneNumber;
  final String address;
  final String photoBase64;
  final DateTime? createdAt;

  bool hasRole(UserRole value) => roles.contains(value);

  /// The client/worker role this account could add or switch to.
  UserRole get otherRole =>
      role == UserRole.worker ? UserRole.client : UserRole.worker;

  static UserRole _parseRole(Object? value) => switch (value) {
    'worker' => UserRole.worker,
    'admin' => UserRole.admin,
    _ => UserRole.client,
  };

  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    final role = _parseRole(data['role']);
    final stored = data['roles'];
    // Accounts created before dual roles only have `role`.
    final roles = stored is List && stored.isNotEmpty
        ? stored.map(_parseRole).toSet().toList()
        : [role];
    if (!roles.contains(role)) roles.add(role);
    return AppUser(
      id: id,
      fullName: (data['fullName'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      role: role,
      roles: List.unmodifiable(roles),
      verificationStatus: VerificationStatus.fromWire(
        data['verificationStatus'],
      ),
      phoneNumber: (data['phoneNumber'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      photoBase64: (data['photoBase64'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}
