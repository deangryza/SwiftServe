import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ProfileDraft {
  const ProfileDraft({
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.address,
    required this.role,
    this.category = '',
    this.skills = const [],
  });

  final String fullName;
  final String email;
  final String phoneNumber;
  final String address;
  final String role;
  final String category;
  final List<String> skills;

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'email': email,
    'phoneNumber': phoneNumber,
    'address': address,
    'role': role,
    'category': category,
    'skills': skills,
  };

  factory ProfileDraft.fromJson(Map<String, dynamic> json) => ProfileDraft(
    fullName: (json['fullName'] ?? '').toString(),
    email: (json['email'] ?? '').toString(),
    phoneNumber: (json['phoneNumber'] ?? '').toString(),
    address: (json['address'] ?? '').toString(),
    role: (json['role'] ?? 'client').toString(),
    category: (json['category'] ?? '').toString(),
    skills: List<String>.from(json['skills'] ?? const []),
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
