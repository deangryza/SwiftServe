import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/profile_photo_picker.dart';
import '../../../../shared/widgets/new_user_badge.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../widgets/conversation_ui.dart';
import 'client_booking_flow.dart';
import 'client_sections.dart' show ClientMessagesScreen;
import 'client_settings_screen.dart';

const _profileYellow = Color(0xFFFFC72C);
const _profileCream = Color(0xFFFFFFFF);
const _profileInk = Color(0xFF242424);

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in again.')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Could not load profile: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() ?? <String, dynamic>{};
        return _ProfileView(user: user, data: data);
      },
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.user, required this.data});

  final User user;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF1B1B1B) : _profileCream;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF2F2F2) : _profileInk;
    final muted = dark ? const Color(0xFFB6B6B6) : const Color(0xFF697386);
    final name = (data['fullName'] ?? 'Client').toString().trim();
    final safeName = name.isEmpty ? 'Client' : name;
    final email = (data['email'] ?? user.email ?? 'No email available')
        .toString();
    final phone = (data['phoneNumber'] ?? 'No phone number saved').toString();
    final address = (data['address'] ?? 'No address saved').toString();
    final status = (data['verificationStatus'] ?? 'pending').toString();
    final ratingValue = data['rating'] ?? data['averageRating'];
    final rating = ratingValue is num ? ratingValue.toStringAsFixed(1) : '—';
    final createdAt = data['createdAt'];
    final since = createdAt is Timestamp
        ? createdAt.toDate().year.toString()
        : (user.metadata.creationTime?.year.toString() ?? '—');

    return Scaffold(
      backgroundColor: _profileYellow,
      bottomNavigationBar: _ProfileBottomNavigation(
        userId: user.uid,
        background: background,
        surface: surface,
        text: text,
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_profileYellow, background, background],
                  stops: const [0, 0.34, 1],
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(
                      color: _profileInk,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                    decoration: _cardDecoration(surface),
                    child: Column(
                      children: [
                        _ProfilePhoto(
                          name: safeName,
                          photoBase64: (data['photoBase64'] ?? '').toString(),
                          photoUrl: user.photoURL,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          safeName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 7,
                          runSpacing: 6,
                          children: [
                            _VerificationBadge(status: status),
                            NewUserBadge(
                              createdAt: data['createdAt'],
                              fallbackCreatedAt: user.metadata.creationTime,
                            ),
                          ],
                        ),
                        const SizedBox(height: 21),
                        Divider(
                          color: muted.withValues(alpha: 0.18),
                          height: 1,
                        ),
                        const SizedBox(height: 18),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('service_requests')
                              .where('clientId', isEqualTo: user.uid)
                              .snapshots(),
                          builder: (context, jobsSnapshot) => Row(
                            children: [
                              _ProfileStat(
                                value: jobsSnapshot.hasData
                                    ? '${jobsSnapshot.data!.docs.length}'
                                    : '—',
                                label: 'Jobs',
                                text: text,
                                muted: muted,
                              ),
                              _ProfileStat(
                                value: rating,
                                label: 'Rating',
                                text: text,
                                muted: muted,
                              ),
                              _ProfileStat(
                                value: since,
                                label: 'Since',
                                text: text,
                                muted: muted,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            key: const ValueKey('client-edit-profile'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ClientEditProfileScreen(
                                  initialData: data,
                                  photoUrl: user.photoURL,
                                ),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: text,
                              side: BorderSide(
                                color: muted.withValues(alpha: 0.3),
                              ),
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              backgroundColor: surface,
                            ),
                            child: const Text(
                              'Edit Profile',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: _cardDecoration(surface),
                    child: Column(
                      children: [
                        _ContactRow(
                          icon: Icons.mail_outline,
                          value: email,
                          text: text,
                          muted: muted,
                        ),
                        _ContactRow(
                          icon: Icons.phone_outlined,
                          value: phone,
                          text: text,
                          muted: muted,
                        ),
                        _ContactRow(
                          icon: Icons.location_on_outlined,
                          value: address,
                          text: text,
                          muted: muted,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: surface,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      key: const ValueKey('client-profile-settings'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(Icons.settings_outlined, color: muted),
                      title: Text('Settings', style: TextStyle(color: text)),
                      trailing: Icon(Icons.chevron_right, color: muted),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ClientSettingsScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ClientEditProfileScreen extends StatefulWidget {
  const ClientEditProfileScreen({
    super.key,
    required this.initialData,
    this.photoUrl,
  });

  final Map<String, dynamic> initialData;
  final String? photoUrl;

  @override
  State<ClientEditProfileScreen> createState() =>
      _ClientEditProfileScreenState();
}

class _ClientEditProfileScreenState extends State<ClientEditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  var _saving = false;
  var _savingPhoto = false;
  late String _photoBase64;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: (widget.initialData['fullName'] ?? '').toString(),
    );
    _emailController = TextEditingController(
      text:
          FirebaseAuth.instance.currentUser?.email ??
          (widget.initialData['email'] ?? '').toString(),
    );
    _phoneController = TextEditingController(
      text: (widget.initialData['phoneNumber'] ?? '').toString(),
    );
    _addressController = TextEditingController(
      text: (widget.initialData['address'] ?? '').toString(),
    );
    _photoBase64 = (widget.initialData['photoBase64'] ?? '').toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _changePhoto() async {
    if (_savingPhoto) return;
    final bytes = await pickProfilePhoto();
    if (bytes == null || !mounted) return;
    setState(() => _savingPhoto = true);
    try {
      final encoded = base64Encode(bytes);
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw StateError('Your session has expired.');
      await ApiService().updateProfilePhoto(
        idToken: token,
        photoBase64: encoded,
      );
      if (!mounted) return;
      setState(() => _photoBase64 = encoded);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo saved.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save photo. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    final name = _nameController.text.trim();
    if (user == null || name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'fullName': name, 'address': _addressController.text.trim()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update profile: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF1B1B1B) : _profileCream;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF2F2F2) : _profileInk;
    final muted = dark ? const Color(0xFFB6B6B6) : const Color(0xFF697386);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: _profileYellow,
        foregroundColor: _profileInk,
        elevation: 0,
        title: const Text(
          'Edit Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Center(
                  child: _ProfilePhoto(
                    name: _nameController.text.trim().isEmpty
                        ? 'Client'
                        : _nameController.text.trim(),
                    photoBase64: _photoBase64,
                    photoUrl: widget.photoUrl,
                    radius: 46,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _savingPhoto ? null : _changePhoto,
                    style: TextButton.styleFrom(
                      foregroundColor: _profileYellow,
                    ),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(
                      _savingPhoto ? 'Saving photo…' : 'Change photo',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: _cardDecoration(surface),
                  child: Column(
                    children: [
                      _EditField(
                        controller: _nameController,
                        label: 'Full name',
                        icon: Icons.person_outline,
                        text: text,
                        muted: muted,
                      ),
                      const SizedBox(height: 14),
                      _EditField(
                        controller: _emailController,
                        label: 'Email address',
                        icon: Icons.mail_outline,
                        text: text,
                        muted: muted,
                        readOnly: true,
                      ),
                      const SizedBox(height: 14),
                      _EditField(
                        controller: _phoneController,
                        label: 'Phone number',
                        icon: Icons.phone_outlined,
                        text: text,
                        muted: muted,
                        keyboardType: TextInputType.phone,
                        readOnly: true,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Verified phone numbers cannot be changed here.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _EditField(
                        controller: _addressController,
                        label: 'Address',
                        icon: Icons.location_on_outlined,
                        text: text,
                        muted: muted,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('client-save-profile'),
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _profileYellow,
                    foregroundColor: _profileInk,
                    disabledBackgroundColor: _profileYellow.withValues(
                      alpha: 0.55,
                    ),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _saving ? 'Saving…' : 'Save Changes',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfilePhoto extends StatelessWidget {
  const _ProfilePhoto({
    required this.name,
    required this.photoBase64,
    required this.photoUrl,
    this.radius = 42,
  });

  final String name;
  final String photoBase64;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (photoBase64.isNotEmpty || (photoUrl?.isNotEmpty ?? false)) {
      return ProfileAvatar(
        photoBase64: photoBase64,
        photoUrl: photoUrl,
        radius: radius,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFFFF3CC),
      child: Text(
        name.characters.first.toUpperCase(),
        style: TextStyle(
          color: const Color(0xFF242424),
          fontSize: radius * 0.62,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final verified = status == 'verified';
    final label = switch (status) {
      'verified' => 'Verified',
      'under_review' => 'Under review',
      'rejected' => 'Needs review',
      'resubmission_required' => 'Action required',
      _ => 'Pending',
    };
    final color = verified ? const Color(0xFF20B978) : const Color(0xFFE3A500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified : Icons.schedule,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.value,
    required this.label,
    required this.text,
    required this.muted,
  });

  final String value;
  final String label;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: muted, fontSize: 11)),
      ],
    ),
  );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.value,
    required this.text,
    required this.muted,
    this.showDivider = true,
  });

  final IconData icon;
  final String value;
  final Color text;
  final Color muted;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      children: [
        SizedBox(
          height: 54,
          child: Row(
            children: [
              Icon(icon, color: muted, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: text, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 32, color: muted.withValues(alpha: 0.16)),
      ],
    ),
  );
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.text,
    required this.muted,
    this.readOnly = false,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color text;
  final Color muted;
  final bool readOnly;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    readOnly: readOnly,
    keyboardType: keyboardType,
    maxLines: maxLines,
    style: TextStyle(color: text),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: muted),
      prefixIcon: Icon(icon, color: muted),
      filled: true,
      fillColor: readOnly ? muted.withValues(alpha: 0.08) : Colors.transparent,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: muted.withValues(alpha: 0.45)),
      ),
    ),
  );
}

class _ProfileBottomNavigation extends StatelessWidget {
  const _ProfileBottomNavigation({
    required this.userId,
    required this.background,
    required this.surface,
    required this.text,
  });

  final String userId;
  final Color background;
  final Color surface;
  final Color text;

  @override
  Widget build(BuildContext context) {
    void replaceWith(Widget screen) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => screen),
      );
    }

    return Container(
      color: background,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: _cardDecoration(surface, radius: 22),
          child: Row(
            children: [
              _ProfileNavItem(
                icon: Icons.home_outlined,
                label: 'Home',
                text: text,
                onTap: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
              ),
              _ProfileNavItem(
                icon: Icons.calendar_month_outlined,
                label: 'Bookings',
                text: text,
                onTap: () => replaceWith(const ClientBookingsScreen()),
              ),
              _ProfileNavItem(
                icon: Icons.chat_bubble_outline,
                label: 'Chat',
                text: text,
                badgeUserId: userId,
                onTap: () => replaceWith(const ClientMessagesScreen()),
              ),
              _ProfileNavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                text: text,
                selected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileNavItem extends StatelessWidget {
  const _ProfileNavItem({
    required this.icon,
    required this.label,
    required this.text,
    required this.onTap,
    this.selected = false,
    this.badgeUserId,
  });

  final IconData icon;
  final String label;
  final Color text;
  final VoidCallback onTap;
  final bool selected;
  final String? badgeUserId;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 27,
              decoration: BoxDecoration(
                color: selected ? _profileYellow : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: badgeUserId == null
                    ? Icon(icon, color: text, size: 19)
                    : ConversationUnreadBadge(
                        userId: badgeUserId,
                        child: Icon(icon, color: text, size: 19),
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: text, fontSize: 10)),
          ],
        ),
      ),
    ),
  );
}

BoxDecoration _cardDecoration(Color color, {double radius = 16}) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 5,
          offset: Offset(0, 3),
        ),
      ],
    );
