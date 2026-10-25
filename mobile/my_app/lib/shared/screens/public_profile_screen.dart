import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/client_rating_summary.dart';
import '../widgets/live_profile_avatar.dart';
import '../widgets/worker_rating_summary.dart';
import 'reviews_screen.dart';

enum PublicProfileRole { client, worker }

bool publicProfileMatchesQuery(
  Map<String, dynamic> profile,
  String query, {
  PublicProfileRole? role,
}) {
  if (role != null && (profile['role'] ?? '').toString() != role.name) {
    return false;
  }
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return <Object?>[
    profile['fullName'],
    profile['role'],
    profile['location'],
    profile['category'],
    profile['description'],
    profile['bio'],
    profile['about'],
    ...profileSkills(profile['skills']),
  ].any((value) => (value ?? '').toString().toLowerCase().contains(normalized));
}

List<String> profileSkills(Object? value) {
  if (value is Iterable) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return const [];
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

class PublicProfileScreen extends StatelessWidget {
  const PublicProfileScreen({
    super.key,
    required this.userId,
    required this.role,
    this.initialData = const <String, dynamic>{},
    this.onReport,
    this.reporting = false,
    this.reportLabel,
  });

  final String userId;
  final PublicProfileRole role;
  final Map<String, dynamic> initialData;
  final VoidCallback? onReport;
  final bool reporting;
  final String? reportLabel;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('public_profiles')
          .doc(userId)
          .snapshots(),
      builder: (context, publicSnapshot) {
        if (role == PublicProfileRole.worker) {
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('worker_profiles')
                .doc(userId)
                .snapshots(),
            builder: (context, workerSnapshot) => _ProfileView(
              userId: userId,
              role: role,
              data: <String, dynamic>{
                ...initialData,
                ...?workerSnapshot.data?.data(),
                ...?publicSnapshot.data?.data(),
              },
              loading: !publicSnapshot.hasData && !workerSnapshot.hasData,
              hasError: publicSnapshot.hasError && workerSnapshot.hasError,
              onReport: onReport,
              reporting: reporting,
              reportLabel: reportLabel,
            ),
          );
        }
        return _ProfileView(
          userId: userId,
          role: role,
          data: <String, dynamic>{
            ...initialData,
            ...?publicSnapshot.data?.data(),
          },
          loading: !publicSnapshot.hasData,
          hasError: publicSnapshot.hasError,
          onReport: onReport,
          reporting: reporting,
          reportLabel: reportLabel,
        );
      },
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({
    required this.userId,
    required this.role,
    required this.data,
    required this.loading,
    required this.hasError,
    required this.onReport,
    required this.reporting,
    required this.reportLabel,
  });

  final String userId;
  final PublicProfileRole role;
  final Map<String, dynamic> data;
  final bool loading;
  final bool hasError;
  final VoidCallback? onReport;
  final bool reporting;
  final String? reportLabel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF181818) : Colors.white;
    final surface = dark ? const Color(0xFF292929) : Colors.white;
    final text = dark ? const Color(0xFFF5F5F5) : AppTheme.ink;
    final muted = dark ? const Color(0xFFB6B6B6) : AppTheme.muted;
    final line = dark ? const Color(0xFF444444) : AppTheme.line;
    final name = _value(data['fullName'], 'SwiftServe user');
    final location = _value(data['location'], 'Location not provided');
    final skills = profileSkills(data['skills']);
    final category = _value(data['category'], '');
    final description = _description(data, role);
    final createdAt = data['createdAt'];
    final joinedAt = createdAt is Timestamp ? createdAt.toDate() : null;
    final verified =
        role == PublicProfileRole.worker &&
        data['verificationStatus'] == 'verified';

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: text,
        leading: IconButton(
          key: const ValueKey('public-profile-back'),
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          role == PublicProfileRole.worker
              ? 'Worker Profile'
              : 'Client Profile',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : hasError
                ? Center(
                    child: Text(
                      'This profile is unavailable right now.',
                      style: TextStyle(color: muted),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
                    children: [
                      Center(
                        child: LiveProfileAvatar(
                          userId: userId,
                          fallbackName: name,
                          fallbackPhotoBase64: _value(data['photoBase64'], ''),
                          joinedAt: joinedAt,
                          radius: 50,
                          backgroundColor: AppTheme.softYellow,
                          foregroundColor: AppTheme.ink,
                          textStyle: const TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: text,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Badge(
                            icon: role == PublicProfileRole.worker
                                ? Icons.handyman_outlined
                                : Icons.person_outline,
                            label: role == PublicProfileRole.worker
                                ? (category.isEmpty ? 'Worker' : category)
                                : 'Client',
                          ),
                          if (verified)
                            const _Badge(
                              icon: Icons.verified_rounded,
                              label: 'Verified',
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _Stats(
                        userId: userId,
                        role: role,
                        surface: surface,
                        text: text,
                        muted: muted,
                        line: line,
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'About',
                        surface: surface,
                        text: text,
                        line: line,
                        child: Text(
                          description,
                          style: TextStyle(
                            color: _hasDescription(data) ? text : muted,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (role == PublicProfileRole.worker) ...[
                        const SizedBox(height: 14),
                        _SectionCard(
                          title: 'Skills',
                          surface: surface,
                          text: text,
                          line: line,
                          child: skills.isEmpty
                              ? Text(
                                  'No skills added yet.',
                                  style: TextStyle(color: muted),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final skill in skills)
                                      Chip(label: Text(skill)),
                                  ],
                                ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Profile details',
                        surface: surface,
                        text: text,
                        line: line,
                        child: Column(
                          children: [
                            _Detail(
                              icon: Icons.location_on_outlined,
                              label: 'Location',
                              value: location,
                              text: text,
                              muted: muted,
                            ),
                            if (joinedAt != null)
                              _Detail(
                                icon: Icons.calendar_today_outlined,
                                label: 'Member since',
                                value: _monthYear(joinedAt),
                                text: text,
                                muted: muted,
                              ),
                            if (role == PublicProfileRole.worker)
                              _Detail(
                                icon: Icons.verified_user_outlined,
                                label: 'Verification',
                                value: verified
                                    ? 'Identity verified'
                                    : 'Verification pending',
                                text: text,
                                muted: muted,
                                last: true,
                              ),
                          ],
                        ),
                      ),
                      if (onReport != null) ...[
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          key: const ValueKey('report-public-profile'),
                          onPressed: reporting ? null : onReport,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: text,
                            minimumSize: const Size.fromHeight(50),
                            side: BorderSide(color: line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.report_outlined),
                          label: Text(
                            reporting
                                ? 'Submitting report...'
                                : (reportLabel ?? 'Report user'),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({
    required this.userId,
    required this.role,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
  });

  final String userId;
  final PublicProfileRole role;
  final Color surface;
  final Color text;
  final Color muted;
  final Color line;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    ),
    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('service_requests')
          .where(
            role == PublicProfileRole.worker ? 'workerId' : 'clientId',
            isEqualTo: userId,
          )
          .snapshots(),
      builder: (context, snapshot) {
        final documents = snapshot.data?.docs ?? const [];
        final count = role == PublicProfileRole.worker
            ? documents
                  .where((doc) => doc.data()['status'] == 'completed')
                  .length
            : documents.length;
        return Row(
          children: [
            Expanded(child: _rating(context)),
            Container(width: 1, height: 52, color: line),
            Expanded(
              child: _Stat(
                value: snapshot.hasData ? count.toString() : '-',
                label: role == PublicProfileRole.worker
                    ? 'Jobs done'
                    : 'Jobs posted',
                text: text,
                muted: muted,
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _rating(BuildContext context) {
    if (role == PublicProfileRole.worker) {
      return WorkerRatingBuilder(
        workerId: userId,
        builder: (context, summary) => _Stat(
          value: summary.displayAverage,
          label: summary.reviewCount == 1
              ? '1 review'
              : '${summary.reviewCount} reviews',
          text: text,
          muted: muted,
          onTap: () => _openReviews(context, ReviewsFor.worker),
        ),
      );
    }
    return ClientRatingBuilder(
      clientId: userId,
      builder: (context, summary) => _Stat(
        value: summary.displayAverage,
        label: summary.reviewCount == 1
            ? '1 review'
            : '${summary.reviewCount} reviews',
        text: text,
        muted: muted,
        onTap: () => _openReviews(context, ReviewsFor.client),
      ),
    );
  }

  void _openReviews(BuildContext context, ReviewsFor reviewsFor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewsScreen(userId: userId, reviewsFor: reviewsFor),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.text,
    required this.muted,
    this.onTap,
  });

  final String value;
  final String label;
  final Color text;
  final Color muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onTap != null) ...[
                const Icon(
                  Icons.star_rounded,
                  size: 19,
                  color: AppTheme.yellow,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: TextStyle(
                  color: text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.surface,
    required this.text,
    required this.line,
    required this.child,
  });

  final String title;
  final Color surface;
  final Color text;
  final Color line;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.icon,
    required this.label,
    required this.value,
    required this.text,
    required this.muted,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color text;
  final Color muted;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.yellow, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: muted, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(color: text, fontSize: 14)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.softYellow,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppTheme.ink),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

bool _hasDescription(Map<String, dynamic> data) => [
  data['description'],
  data['bio'],
  data['about'],
].any((value) => (value ?? '').toString().trim().isNotEmpty);

String _description(Map<String, dynamic> data, PublicProfileRole role) {
  for (final value in [data['description'], data['bio'], data['about']]) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return role == PublicProfileRole.worker
      ? 'This worker has not added a description yet.'
      : 'This client has not added a description yet.';
}

String _value(Object? value, String fallback) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

String _monthYear(DateTime value) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month - 1]} ${value.year}';
}
