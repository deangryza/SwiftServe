import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ProfileDraft {
  const ProfileDraft({
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.address,
    required this.role,
    this.dateOfBirth = '',
    this.category = '',
    this.skills = const [],
    this.photoBase64 = '',
    this.phoneVerificationUid = '',
    this.phoneVerificationProject = '',
    this.phoneVerificationToken,
  });

  final String dateOfBirth;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String address;
  final String role;
  final String category;
  final List<String> skills;
  final String photoBase64;
  final String phoneVerificationUid, phoneVerificationProject;

  /// Proof from the live SMS code step (IPROG SMS via the backend) that
  /// [phoneNumber] belongs to the user.
  final String? phoneVerificationToken;

  ProfileDraft withPhoneVerificationToken(String? token) => ProfileDraft(
    dateOfBirth: dateOfBirth,
    fullName: fullName,
    email: email,
    phoneNumber: phoneNumber,
    address: address,
    role: role,
    category: category,
    skills: skills,
    photoBase64: photoBase64,
    phoneVerificationUid: phoneVerificationUid,
    phoneVerificationProject: phoneVerificationProject,
    phoneVerificationToken: token,
  );

  Map<String, dynamic> toJson() => {
    'dateOfBirth': dateOfBirth,
    'fullName': fullName,
    'email': email,
    'phoneNumber': phoneNumber,
    'address': address,
    'role': role,
    'category': category,
    'skills': skills,
    'photoBase64': photoBase64,
    if (phoneVerificationUid.isNotEmpty)
      'phoneVerificationUid': phoneVerificationUid,
    if (phoneVerificationProject.isNotEmpty)
      'phoneVerificationProject': phoneVerificationProject,
    'phoneVerificationToken': ?phoneVerificationToken,
  };

  factory ProfileDraft.fromJson(Map<String, dynamic> json) => ProfileDraft(
    dateOfBirth: (json['dateOfBirth'] ?? '').toString(),
    fullName: (json['fullName'] ?? '').toString(),
    email: (json['email'] ?? '').toString(),
    phoneNumber: (json['phoneNumber'] ?? '').toString(),
    address: (json['address'] ?? '').toString(),
    role: (json['role'] ?? 'client').toString(),
    category: (json['category'] ?? '').toString(),
    skills: List<String>.from(json['skills'] ?? const []),
    photoBase64: (json['photoBase64'] ?? '').toString(),
    phoneVerificationUid: (json['phoneVerificationUid'] ?? '').toString(),
    phoneVerificationProject: (json['phoneVerificationProject'] ?? '')
        .toString(),
    phoneVerificationToken: json['phoneVerificationToken'] as String?,
  );
}

class ProfileDraftStore {
  static const _key = 'pending_profile_draft';

  Future<ProfileDraft?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return null;
    return ProfileDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(ProfileDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(draft.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}
