import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/job_location.dart';
import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/repositories/verification_repository.dart';
import '../../../../shared/services/client_theme_controller.dart';
import '../../../../shared/services/device_location_service.dart';
import '../../../../shared/utils/job_location_utils.dart';
import '../../../../shared/widgets/live_profile_avatar.dart';
import '../../../../shared/widgets/client_rating_summary.dart';
import '../../../../shared/widgets/worker_rating_summary.dart';
import '../../../../shared/screens/reviews_screen.dart';
import '../../../client/presentation/screens/client_sections.dart';
import '../../../client/presentation/widgets/conversation_ui.dart';
import '../models/worker_verification_ui_state.dart';
import 'worker_job_details_screen.dart';
import 'worker_verification_screen.dart';

class _WorkerPalette {
  const _WorkerPalette._({
    required this.background,
    required this.surface,
    required this.softSurface,
    required this.text,
    required this.muted,
    required this.segment,
  });

  final Color background;
  final Color surface;
  final Color softSurface;
  final Color text;
  final Color muted;
  final Color segment;

  factory _WorkerPalette.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _WorkerPalette._(
      background: dark ? const Color(0xFF171717) : const Color(0xFFFFF9E9),
      surface: dark ? const Color(0xFF2C2C2C) : Colors.white,
      softSurface: dark ? const Color(0xFF303030) : const Color(0xFFFFFAEE),
      text: dark ? const Color(0xFFF3F3F3) : const Color(0xFF242424),
      muted: dark ? const Color(0xFFB8B8B8) : const Color(0xFF737373),
      segment: dark ? const Color(0xFF3A3A3A) : const Color(0xFFE1E1E1),
    );
  }
}

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key, required this.profile});

  final AppUser profile;

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  final VerificationRepository _verificationRepository =
      VerificationRepository();
  int _index = 0;
  int _tabDirection = 1;

  void _selectTab(int index) {
    if (index == _index || index < 0 || index > 3) return;
    setState(() {
      _tabDirection = index > _index ? 1 : -1;
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<VerificationStatus?>(
    stream: _verificationRepository.watchStatus(widget.profile.id),
    builder: (context, verificationSnapshot) {
      final verificationState = WorkerVerificationUiState.resolve(
        profileStatus: widget.profile.verificationStatus,
        submissionStatus: verificationSnapshot.data,
      );
      final pages = [
        _WorkerDashboard(
          worker: widget.profile,
          verificationState: verificationState,
        ),
        _WorkerJobs(worker: widget.profile),
        _WorkerMessages(worker: widget.profile, onBack: () => _selectTab(0)),
        _WorkerProfile(
          worker: widget.profile,
          verificationState: verificationState,
        ),
      ];
      return _WorkerTabSwipeRegion(
        currentIndex: _index,
        onSwipeToIndex: _selectTab,
        child: Scaffold(
          backgroundColor: _WorkerPalette.of(context).background,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            reverseDuration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final childIndex = (child.key as ValueKey<int>?)?.value ?? _index;
              final incoming = childIndex == _index;
              final horizontalOffset = incoming
                  ? _tabDirection * 0.08
                  : _tabDirection * -0.04;
              return FadeTransition(
                key: ValueKey('worker-tab-transition-$childIndex'),
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(horizontalOffset, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_index),
              child: pages[_index],
            ),
          ),
          bottomNavigationBar: _WorkerBottomNavigation(
            selectedIndex: _index,
            workerId: widget.profile.id,
            onSelected: _selectTab,
          ),
        ),
      );
    },
  );
}

class _WorkerTabSwipeRegion extends StatefulWidget {
  const _WorkerTabSwipeRegion({
    required this.currentIndex,
    required this.onSwipeToIndex,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onSwipeToIndex;
  final Widget child;

  @override
  State<_WorkerTabSwipeRegion> createState() => _WorkerTabSwipeRegionState();
}

class _WorkerTabSwipeRegionState extends State<_WorkerTabSwipeRegion> {
  static const _distanceThreshold = 54.0;
  static const _velocityThreshold = 500.0;
  double _horizontalDistance = 0;

  void _finishSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final movesForward =
        _horizontalDistance <= -_distanceThreshold ||
        velocity <= -_velocityThreshold;
    final movesBackward =
        _horizontalDistance >= _distanceThreshold ||
        velocity >= _velocityThreshold;
    _horizontalDistance = 0;

    final targetIndex = movesForward
        ? widget.currentIndex + 1
        : movesBackward
        ? widget.currentIndex - 1
        : widget.currentIndex;
    if (targetIndex >= 0 &&
        targetIndex <= 3 &&
        targetIndex != widget.currentIndex) {
      widget.onSwipeToIndex(targetIndex);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _horizontalDistance = 0,
    onHorizontalDragUpdate: (details) =>
        _horizontalDistance += details.primaryDelta ?? 0,
    onHorizontalDragCancel: () => _horizontalDistance = 0,
    onHorizontalDragEnd: _finishSwipe,
    child: widget.child,
  );
}

enum WorkerDashboardRequestFilter { recent, available }

List<ServiceRequest> filterWorkerDashboardRequests({
  required Iterable<ServiceRequest> requests,
  required Iterable<ServiceApplication> applications,
  required WorkerDashboardRequestFilter filter,
}) {
  final appliedRequestIds = applications
      .map((application) => application.requestId)
      .toSet();
  final eligible =
      requests
          .where(
            (request) =>
                request.status == ServiceRequestStatus.pending &&
                !appliedRequestIds.contains(request.id),
          )
          .toList()
        ..sort((left, right) {
          final leftTime = left.createdAt;
          final rightTime = right.createdAt;
          if (leftTime == null && rightTime == null) return 0;
          if (leftTime == null) return 1;
          if (rightTime == null) return -1;
          return rightTime.compareTo(leftTime);
        });
  return filter == WorkerDashboardRequestFilter.recent
      ? eligible.take(5).toList(growable: false)
      : eligible;
}

bool matchesWorkerDashboardSearch(ServiceRequest request, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return [
    request.title,
    request.category,
    request.clientName,
    request.description,
    request.location,
    request.modality.label,
  ].any((value) => value.toLowerCase().contains(normalized));
}

class _WorkerDashboard extends StatefulWidget {
  const _WorkerDashboard({
    required this.worker,
    required this.verificationState,
  });

  final AppUser worker;
  final WorkerVerificationUiState verificationState;

  @override
  State<_WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<_WorkerDashboard> {
  static const _locationService = DeviceLocationService();
  var _filter = WorkerDashboardRequestFilter.recent;
  final _searchController = TextEditingController();
  var _searchQuery = '';
  JobCoordinate? _workerPosition;
  DeviceLocationException? _locationError;
  bool _loadingLocation = true;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });
    try {
      final position = await _locationService.currentPosition();
      if (!mounted) return;
      setState(() => _workerPosition = position);
    } on DeviceLocationException catch (error) {
      if (!mounted) return;
      setState(() => _locationError = error);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _openLocationSettings() async {
    final error = _locationError;
    if (error == null) return;
    await _locationService.openRecoverySettings(error.failure);
  }

  String? _distanceLabel(ServiceRequest request) {
    // Online jobs have no place to measure distance to.
    if (!request.modality.needsLocation) return null;
    final jobPosition = request.areaPosition;
    if (jobPosition == null) return 'Distance unavailable';
    if (_loadingLocation) return 'Finding distance…';
    final workerPosition = _workerPosition;
    if (workerPosition == null) return 'Distance unavailable';
    return formatDistance(
      distanceMetersBetween(workerPosition, jobPosition),
      approximate: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return StreamBuilder<List<ServiceRequest>>(
      stream: ServiceRequestRepository().watchAvailable(),
      builder: (context, requestSnapshot) {
        if (requestSnapshot.hasError) {
          return Center(child: Text('${requestSnapshot.error}'));
        }
        if (!requestSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<List<ServiceApplication>>(
          stream: ServiceRequestRepository().watchWorkerApplications(
            widget.worker.id,
          ),
          builder: (context, applicationSnapshot) {
            if (applicationSnapshot.hasError) {
              return Center(child: Text('${applicationSnapshot.error}'));
            }
            if (!applicationSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final allEligible = filterWorkerDashboardRequests(
              requests: requestSnapshot.data!,
              applications: applicationSnapshot.data!,
              filter: WorkerDashboardRequestFilter.available,
            );
            final requests =
                filterWorkerDashboardRequests(
                      requests: requestSnapshot.data!,
                      applications: applicationSnapshot.data!,
                      filter: _filter,
                    )
                    .where(
                      (request) =>
                          matchesWorkerDashboardSearch(request, _searchQuery),
                    )
                    .toList(growable: false);
            return ColoredBox(
              color: palette.background,
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      children: [
                        _WorkerDashboardHeader(worker: widget.worker),
                        const SizedBox(height: 14),
                        _WorkerDashboardSearchField(
                          controller: _searchController,
                          onChanged: (query) =>
                              setState(() => _searchQuery = query),
                          onClear: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                        const SizedBox(height: 18),
                        const _WorkerHeroBannerCarousel(),
                        if (_searchQuery.trim().isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _WorkerUserSearchResults(
                            query: _searchQuery,
                            currentUserId: widget.worker.id,
                          ),
                        ],
                        if (!widget.verificationState.isVerified) ...[
                          const SizedBox(height: 14),
                          _VerificationBanner(
                            state: widget.verificationState,
                            onTap: () =>
                                _openVerification(context, widget.worker),
                          ),
                        ],
                        if (_locationError != null &&
                            requests.any(
                              (request) => request.areaPosition != null,
                            )) ...[
                          const SizedBox(height: 14),
                          _LocationStatusBanner(
                            error: _locationError!,
                            onRetry: _loadLocation,
                            onOpenSettings: _openLocationSettings,
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _searchQuery.trim().isEmpty
                                    ? 'Job Requests'
                                    : 'Matching Services',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${allEligible.length} open',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _WorkerRequestFilter(
                          selected: _filter,
                          onChanged: (filter) =>
                              setState(() => _filter = filter),
                        ),
                        const SizedBox(height: 14),
                        if (requests.isEmpty)
                          const _EmptyWorkerRequests()
                        else
                          for (final request in requests) ...[
                            _WorkerRequestCard(
                              request: request,
                              distanceLabel: _distanceLabel(request),
                              onTap: () =>
                                  _openJob(context, request, widget.worker),
                            ),
                            const SizedBox(height: 14),
                          ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WorkerDashboardSearchField extends StatelessWidget {
  const _WorkerDashboardSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return Material(
      color: palette.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      child: TextField(
        key: const ValueKey('worker-dashboard-search'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: palette.text),
        decoration: InputDecoration(
          hintText: 'Search users or services...',
          hintStyle: TextStyle(color: palette.muted, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: palette.muted),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('worker-dashboard-search-clear'),
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: Icon(Icons.close, color: palette.muted),
                ),
          filled: true,
          fillColor: palette.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

class _WorkerUserSearchResults extends StatelessWidget {
  const _WorkerUserSearchResults({
    required this.query,
    required this.currentUserId,
  });

  final String query;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    final normalized = query.trim().toLowerCase();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('public_profiles')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'User results are unavailable.',
            style: TextStyle(color: palette.muted, fontSize: 12),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: LinearProgressIndicator());
        }
        final users = snapshot.data!.docs
            .where((document) {
              if (document.id == currentUserId) return false;
              final data = document.data();
              final name = (data['fullName'] ?? '').toString().toLowerCase();
              final role = (data['role'] ?? '').toString().toLowerCase();
              return name.contains(normalized) || role.contains(normalized);
            })
            .take(5)
            .toList(growable: false);
        if (users.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Users',
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (final user in users) ...[
              _WorkerUserSearchTile(id: user.id, data: user.data()),
              const SizedBox(height: 9),
            ],
          ],
        );
      },
    );
  }
}

class _WorkerUserSearchTile extends StatelessWidget {
  const _WorkerUserSearchTile({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    final name = (data['fullName'] ?? 'SwiftServe user').toString();
    final role = data['role'] == 'worker' ? 'Worker' : 'Client';
    final createdAt = data['createdAt'];
    final joinedAt = createdAt is Timestamp ? createdAt.toDate() : null;
    final rating = role == 'Worker'
        ? WorkerRatingBuilder(
            workerId: id,
            builder: (context, summary) => Text(
              'Worker · ★ ${summary.displayAverage}',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          )
        : ClientRatingBuilder(
            clientId: id,
            builder: (context, summary) => Text(
              'Client · ★ ${summary.displayAverage}',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          );
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReviewsScreen(
              userId: id,
              reviewsFor: role == 'Worker'
                  ? ReviewsFor.worker
                  : ReviewsFor.client,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              LiveProfileAvatar(
                userId: id,
                fallbackName: name,
                fallbackPhotoBase64: (data['photoBase64'] ?? '').toString(),
                joinedAt: joinedAt,
                radius: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    rating,
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkerHeroBannerCarousel extends StatefulWidget {
  const _WorkerHeroBannerCarousel();

  @override
  State<_WorkerHeroBannerCarousel> createState() =>
      _WorkerHeroBannerCarouselState();
}

class _WorkerHeroBannerCarouselState extends State<_WorkerHeroBannerCarousel> {
  static const _assets = [
    'assets/dashboard/worker_fees_banner.svg',
    'assets/dashboard/worker_banner_2.svg',
    'assets/dashboard/worker_banner_3.svg',
  ];

  final _controller = PageController();
  var _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 2.5,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _assets.length,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => Semantics(
              image: true,
              label:
                  'Worker dashboard promotion ${index + 1} of ${_assets.length}',
              child: SvgPicture.asset(
                _assets[index],
                key: ValueKey('worker-hero-slide-$index'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            bottom: 7,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x66000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    _assets.length,
                    (index) => AnimatedContainer(
                      key: ValueKey('worker-hero-indicator-$index'),
                      duration: const Duration(milliseconds: 180),
                      width: index == _currentPage ? 14 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: index == _currentPage
                            ? const Color(0xFFFFC72C)
                            : Colors.white70,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WorkerDashboardHeader extends StatelessWidget {
  const _WorkerDashboardHeader({required this.worker});

  final AppUser worker;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    final name = worker.fullName.trim().isEmpty ? 'Worker' : worker.fullName;
    return Row(
      children: [
        LiveProfileAvatar(
          userId: worker.id,
          fallbackName: name,
          fallbackPhotoBase64: worker.photoBase64,
          joinedAt: worker.createdAt,
          radius: 24,
          backgroundColor: const Color(0xFF252525),
          foregroundColor: const Color(0xFFFFC72C),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello 👋',
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(15),
          child: IconButton(
            key: const ValueKey('worker-notifications'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _WorkerNotifications(worker: worker),
              ),
            ),
            icon: NotificationUnreadBadge(
              userId: worker.id,
              child: Icon(
                Icons.notifications_none_rounded,
                color: palette.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkerRequestFilter extends StatelessWidget {
  const _WorkerRequestFilter({required this.selected, required this.onChanged});

  final WorkerDashboardRequestFilter selected;
  final ValueChanged<WorkerDashboardRequestFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.segment,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: WorkerDashboardRequestFilter.values.map((filter) {
          final active = filter == selected;
          return Expanded(
            child: InkWell(
              key: ValueKey('worker-filter-${filter.name}'),
              onTap: () => onChanged(filter),
              borderRadius: BorderRadius.circular(17),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF252525) : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  filter == WorkerDashboardRequestFilter.recent
                      ? 'Recent'
                      : 'Available',
                  style: TextStyle(
                    color: active ? Colors.white : palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LocationStatusBanner extends StatelessWidget {
  const _LocationStatusBanner({
    required this.error,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final DeviceLocationException error;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    final requiresSettings =
        error.failure == DeviceLocationFailure.serviceDisabled ||
        error.failure == DeviceLocationFailure.permissionPermanentlyDenied;
    return Material(
      color: palette.softSurface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.location_off_outlined,
                color: Color(0xFFFF4F9A),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Distance unavailable',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    error.userMessage,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: requiresSettings ? onOpenSettings : onRetry,
                    child: Text(
                      requiresSettings ? 'Open settings' : 'Try again',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerRequestCard extends StatelessWidget {
  const _WorkerRequestCard({
    required this.request,
    required this.onTap,
    this.distanceLabel,
  });

  final ServiceRequest request;
  final VoidCallback onTap;
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return Material(
      color: palette.softSurface,
      elevation: 3,
      shadowColor: const Color(0x55000000),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0BD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.work_outline_rounded,
                  color: Color(0xFF252525),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                    Text(
                      '${request.placeLabel} · ₱${request.budget.toStringAsFixed(0)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                    if (distanceLabel != null)
                      Text(
                        distanceLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC72C),
                  foregroundColor: const Color(0xFF171717),
                  elevation: 0,
                  minimumSize: const Size(70, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: const Text(
                  'View',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWorkerRequests extends StatelessWidget {
  const _EmptyWorkerRequests();

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: palette.softSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        'No available job requests right now.',
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.muted),
      ),
    );
  }
}

enum _WorkerBookingFilter { recent, completed }

class _WorkerBookingEntry {
  const _WorkerBookingEntry({required this.application, required this.request});

  final ServiceApplication application;
  final ServiceRequest request;
}

class _WorkerJobs extends StatefulWidget {
  const _WorkerJobs({required this.worker});

  final AppUser worker;

  @override
  State<_WorkerJobs> createState() => _WorkerJobsState();
}

class _WorkerJobsState extends State<_WorkerJobs> {
  final _searchController = TextEditingController();
  var _filter = _WorkerBookingFilter.recent;
  String _query = '';
  String? _applicationsKey;
  Future<List<_WorkerBookingEntry>>? _bookingsFuture;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_WorkerBookingEntry>> _bookingsFor(
    List<ServiceApplication> applications,
    List<ServiceRequest> assignedJobs,
  ) {
    final applicationKey = applications
        .map(
          (application) =>
              '${application.requestId}:${application.status.name}:'
              '${application.appliedAt?.millisecondsSinceEpoch ?? 0}',
        )
        .join('|');
    final jobKey = assignedJobs
        .map((request) => '${request.id}:${request.status.name}')
        .join('|');
    final key = '$applicationKey::$jobKey';
    if (_applicationsKey == key && _bookingsFuture != null) {
      return _bookingsFuture!;
    }
    _applicationsKey = key;
    final assignedById = {
      for (final request in assignedJobs) request.id: request,
    };
    _bookingsFuture =
        Future.wait(
          applications.map((application) async {
            final request =
                assignedById[application.requestId] ??
                await ServiceRequestRepository().getRequest(
                  application.requestId,
                );
            return request == null
                ? null
                : _WorkerBookingEntry(
                    application: application,
                    request: request,
                  );
          }),
        ).then((entries) {
          final resolved = entries.whereType<_WorkerBookingEntry>().toList();
          resolved.sort((left, right) {
            final leftDate =
                left.application.appliedAt ??
                left.request.createdAt ??
                DateTime(0);
            final rightDate =
                right.application.appliedAt ??
                right.request.createdAt ??
                DateTime(0);
            return rightDate.compareTo(leftDate);
          });
          return resolved;
        });
    return _bookingsFuture!;
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF242424);
    final palette = _WorkerPalette.of(context);
    return ColoredBox(
      color: const Color(0xFFFFC72C),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ColoredBox(
              color: const Color(0xFFFFC72C),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(32, 28, 32, 16),
                    child: Text(
                      'Bookings',
                      style: TextStyle(
                        color: ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: _WorkerBookingsSearch(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: _WorkerBookingsFilter(
                      selected: _filter,
                      onChanged: (filter) => setState(() => _filter = filter),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(48),
                        ),
                      ),
                      child: StreamBuilder<List<ServiceApplication>>(
                        stream: ServiceRequestRepository()
                            .watchWorkerApplications(widget.worker.id),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Could not load bookings:\n${snapshot.error}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return StreamBuilder<List<ServiceRequest>>(
                            stream: ServiceRequestRepository().watchWorkerJobs(
                              widget.worker.id,
                            ),
                            builder: (context, jobsSnapshot) {
                              if (jobsSnapshot.hasError) {
                                return Center(
                                  child: Text(
                                    'Could not update bookings:\n'
                                    '${jobsSnapshot.error}',
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }
                              if (!jobsSnapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return FutureBuilder<List<_WorkerBookingEntry>>(
                                future: _bookingsFor(
                                  snapshot.data!,
                                  jobsSnapshot.data!,
                                ),
                                builder: (context, bookingsSnapshot) {
                                  if (bookingsSnapshot.hasError) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          'Could not load booking details:\n'
                                          '${bookingsSnapshot.error}',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    );
                                  }
                                  if (!bookingsSnapshot.hasData) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }
                                  final bookings = bookingsSnapshot.data!.where(
                                    (entry) {
                                      final completed =
                                          entry.request.status ==
                                          ServiceRequestStatus.completed;
                                      final matchesFilter =
                                          _filter ==
                                              _WorkerBookingFilter.completed
                                          ? completed
                                          : !completed;
                                      if (!matchesFilter) return false;
                                      if (_query.isEmpty) return true;
                                      return entry.request.title
                                              .toLowerCase()
                                              .contains(_query) ||
                                          entry.request.location
                                              .toLowerCase()
                                              .contains(_query) ||
                                          entry.request.clientName
                                              .toLowerCase()
                                              .contains(_query);
                                    },
                                  ).toList();
                                  if (bookings.isEmpty) {
                                    return _WorkerBookingsEmptyState(
                                      completed:
                                          _filter ==
                                          _WorkerBookingFilter.completed,
                                      searching: _query.isNotEmpty,
                                    );
                                  }
                                  return ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      30,
                                      28,
                                      30,
                                      24,
                                    ),
                                    itemCount: bookings.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) =>
                                        _WorkerBookingCard(
                                          entry: bookings[index],
                                          onTap: () => _openJob(
                                            context,
                                            bookings[index].request,
                                            widget.worker,
                                          ),
                                        ),
                                  );
                                },
                              );
                            },
                          );
                        },
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

class _WorkerBookingsSearch extends StatelessWidget {
  const _WorkerBookingsSearch({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return Material(
      color: palette.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: palette.text, fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Search recent bookings ....',
          hintStyle: const TextStyle(color: Color(0xFF858585), fontSize: 11),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF727272),
            size: 20,
          ),
          suffixIcon: Container(
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC72C),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Color(0xFF242424),
              size: 20,
            ),
          ),
          filled: true,
          fillColor: palette.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _WorkerBookingsFilter extends StatelessWidget {
  const _WorkerBookingsFilter({
    required this.selected,
    required this.onChanged,
  });

  final _WorkerBookingFilter selected;
  final ValueChanged<_WorkerBookingFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.segment,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: _WorkerBookingFilter.values.map((filter) {
          final active = selected == filter;
          return Expanded(
            child: InkWell(
              key: ValueKey('worker-bookings-filter-${filter.name}'),
              onTap: () => onChanged(filter),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF252525) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  filter == _WorkerBookingFilter.recent
                      ? 'Recent'
                      : 'Completed',
                  style: TextStyle(
                    color: active ? Colors.white : palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WorkerBookingCard extends StatelessWidget {
  const _WorkerBookingCard({required this.entry, required this.onTap});

  final _WorkerBookingEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    final request = entry.request;
    final (statusLabel, statusColor) = _workerBookingStatus(entry);
    final date = request.scheduleFrom ?? request.schedule ?? request.createdAt;
    return Material(
      color: palette.surface,
      elevation: 3,
      shadowColor: const Color(0x44000000),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 82),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${request.location.isEmpty ? 'Location unavailable' : request.placeLabel}'
                        '${date == null ? '' : ' · ${_formatBookingDate(date)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 11),
                      ),
                      Text(
                        'Budget: ₱${request.budget.toStringAsFixed(0)}',
                        style: TextStyle(color: palette.muted, fontSize: 11),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.text,
                  size: 32,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerBookingsEmptyState extends StatelessWidget {
  const _WorkerBookingsEmptyState({
    required this.completed,
    required this.searching,
  });

  final bool completed;
  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        searching
            ? 'No bookings match your search.'
            : completed
            ? 'No completed bookings yet.'
            : 'No recent bookings yet.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF737373)),
      ),
    ),
  );
}

(String, Color) _workerBookingStatus(_WorkerBookingEntry entry) {
  final requestStatus = entry.request.status;
  if (requestStatus == ServiceRequestStatus.completed) {
    return ('COMPLETED', const Color(0xFF20B978));
  }
  if (requestStatus == ServiceRequestStatus.cancelled) {
    return ('CANCELLED', const Color(0xFFFF675B));
  }
  if (requestStatus == ServiceRequestStatus.ongoing) {
    return ('ONGOING', const Color(0xFFE3A500));
  }
  return switch (entry.application.status) {
    ServiceApplicationStatus.accepted => ('ACCEPTED', const Color(0xFF647CFF)),
    ServiceApplicationStatus.rejected => ('REJECTED', const Color(0xFFFF675B)),
    ServiceApplicationStatus.pending => ('PENDING', const Color(0xFF20B978)),
  };
}

String _formatBookingDate(DateTime date) {
  final local = date.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

void _openJob(BuildContext context, ServiceRequest request, AppUser worker) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => WorkerJobDetailsScreen(request: request, worker: worker),
    ),
  );
}

void _openVerification(BuildContext context, AppUser worker) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => WorkerVerificationScreen(profile: worker),
    ),
  );
}

class _WorkerMessages extends StatelessWidget {
  const _WorkerMessages({required this.worker, required this.onBack});

  final AppUser worker;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ConversationInboxScreen(
    userId: worker.id,
    counterpartIdField: 'clientId',
    counterpartNameField: 'clientName',
    onBack: onBack,
    onOpenConversation: (conversationId, name) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientChatScreen(
          conversationId: conversationId,
          otherPersonName: name,
        ),
      ),
    ),
  );
}

class _WorkerProfile extends StatelessWidget {
  const _WorkerProfile({required this.worker, required this.verificationState});

  final AppUser worker;
  final WorkerVerificationUiState verificationState;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(worker.id)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load profile: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() ?? <String, dynamic>{};
          return _WorkerProfileView(
            worker: AppUser.fromMap(worker.id, {...data, 'role': 'worker'}),
            data: data,
            verificationState: verificationState,
          );
        },
      );
}

class _WorkerProfileView extends StatelessWidget {
  const _WorkerProfileView({
    required this.worker,
    required this.data,
    required this.verificationState,
  });

  final AppUser worker;
  final Map<String, dynamic> data;
  final WorkerVerificationUiState verificationState;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF1B1B1B) : const Color(0xFFFFF9E9);
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF2F2F2) : const Color(0xFF242424);
    final muted = dark ? const Color(0xFFB6B6B6) : const Color(0xFF697386);
    final name = worker.fullName.trim().isEmpty ? 'Worker' : worker.fullName;
    final createdAt = data['createdAt'];
    final since = createdAt is Timestamp
        ? createdAt.toDate().year.toString()
        : (FirebaseAuth.instance.currentUser?.metadata.creationTime?.year
                  .toString() ??
              '—');

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFFFC72C), background, background],
          stops: const [0, 0.34, 1],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  color: Color(0xFF242424),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                decoration: _workerProfileCardDecoration(surface),
                child: Column(
                  children: [
                    _WorkerProfilePhoto(worker: worker),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _WorkerVerificationBadge(state: verificationState),
                    const SizedBox(height: 21),
                    Divider(color: muted.withValues(alpha: 0.18), height: 1),
                    const SizedBox(height: 18),
                    WorkerRatingBuilder(
                      workerId: worker.id,
                      builder: (context, rating) =>
                          StreamBuilder<List<ServiceApplication>>(
                            stream: ServiceRequestRepository()
                                .watchWorkerApplications(worker.id),
                            builder: (context, applications) => Row(
                              children: [
                                _WorkerProfileStat(
                                  value: applications.hasData
                                      ? '${applications.data!.length}'
                                      : '—',
                                  label: 'Jobs',
                                  text: text,
                                  muted: muted,
                                ),
                                _WorkerProfileStat(
                                  value: rating.displayAverage,
                                  label: rating.reviewCount == 1
                                      ? '1 rating'
                                      : '${rating.reviewCount} ratings',
                                  text: text,
                                  muted: muted,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReviewsScreen(
                                        userId: worker.id,
                                        reviewsFor: ReviewsFor.worker,
                                      ),
                                    ),
                                  ),
                                ),
                                _WorkerProfileStat(
                                  value: since,
                                  label: 'Since',
                                  text: text,
                                  muted: muted,
                                ),
                              ],
                            ),
                          ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const ValueKey('worker-edit-profile'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClientEditProfileScreen(
                              initialData: data,
                              photoUrl:
                                  FirebaseAuth.instance.currentUser?.photoURL,
                            ),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: text,
                          side: BorderSide(color: muted.withValues(alpha: 0.3)),
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
                decoration: _workerProfileCardDecoration(surface),
                child: Column(
                  children: [
                    _WorkerContactRow(
                      icon: Icons.mail_outline,
                      value: worker.email.isEmpty
                          ? 'No email available'
                          : worker.email,
                      text: text,
                      muted: muted,
                    ),
                    _WorkerContactRow(
                      icon: Icons.phone_outlined,
                      value: worker.phoneNumber.isEmpty
                          ? 'No phone number saved'
                          : worker.phoneNumber,
                      text: text,
                      muted: muted,
                    ),
                    _WorkerContactRow(
                      icon: Icons.location_on_outlined,
                      value: worker.address.isEmpty
                          ? 'No address saved'
                          : worker.address,
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
                  key: const ValueKey('worker-profile-reviews'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(Icons.reviews_outlined, color: muted),
                  title: Text('Reviews', style: TextStyle(color: text)),
                  subtitle: Text(
                    'See all reviews you received',
                    style: TextStyle(color: muted),
                  ),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReviewsScreen(
                        userId: worker.id,
                        reviewsFor: ReviewsFor.worker,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  key: const ValueKey('worker-profile-settings'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(Icons.settings_outlined, color: muted),
                  title: Text('Settings', style: TextStyle(color: text)),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _WorkerSettingsScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkerProfilePhoto extends StatelessWidget {
  const _WorkerProfilePhoto({required this.worker});

  final AppUser worker;

  @override
  Widget build(BuildContext context) {
    final name = worker.fullName.trim().isEmpty ? 'Worker' : worker.fullName;
    return LiveProfileAvatar(
      userId: worker.id,
      fallbackName: name,
      fallbackPhotoBase64: worker.photoBase64,
      joinedAt: worker.createdAt,
      radius: 42,
      backgroundColor: const Color(0xFFE6EDFA),
      foregroundColor: const Color(0xFF21458B),
      textStyle: const TextStyle(
        color: Color(0xFF21458B),
        fontSize: 26,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _WorkerVerificationBadge extends StatelessWidget {
  const _WorkerVerificationBadge({required this.state});

  final WorkerVerificationUiState state;

  @override
  Widget build(BuildContext context) {
    final color = state.isVerified
        ? const Color(0xFF20B978)
        : const Color(0xFFE3A500);
    return InkWell(
      onTap: state.isVerified
          ? null
          : () {
              final home = context
                  .findAncestorWidgetOfExactType<WorkerHomeScreen>();
              if (home != null) _openVerification(context, home.profile);
            },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.isVerified ? Icons.verified : Icons.schedule,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              state.statusLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerProfileStat extends StatelessWidget {
  const _WorkerProfileStat({
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
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
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
      ),
    ),
  );
}

class _WorkerContactRow extends StatelessWidget {
  const _WorkerContactRow({
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

BoxDecoration _workerProfileCardDecoration(Color surface) => BoxDecoration(
  color: surface,
  borderRadius: BorderRadius.circular(18),
  boxShadow: const [
    BoxShadow(color: Color(0x26000000), blurRadius: 5, offset: Offset(0, 3)),
  ],
);

class _WorkerSettingsScreen extends StatelessWidget {
  const _WorkerSettingsScreen();

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFC72C),
        foregroundColor: const Color(0xFF242424),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: ClientThemeController.darkMode,
            builder: (context, darkMode, _) => Card(
              color: palette.surface,
              child: SwitchListTile(
                key: const ValueKey('worker-dark-mode-toggle'),
                secondary: const Icon(Icons.dark_mode_outlined),
                title: Text('Dark mode', style: TextStyle(color: palette.text)),
                subtitle: Text(
                  'Use the dark theme across worker screens',
                  style: TextStyle(color: palette.muted),
                ),
                value: darkMode,
                activeThumbColor: const Color(0xFFFFC72C),
                onChanged: ClientThemeController.setDarkMode,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: palette.surface,
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: Text('Log out', style: TextStyle(color: palette.text)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerBottomNavigation extends StatelessWidget {
  const _WorkerBottomNavigation({
    required this.selectedIndex,
    required this.workerId,
    required this.onSelected,
  });

  final int selectedIndex;
  final String workerId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerPalette.of(context);
    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 7, 20, 12),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _WorkerNavItem(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    selected: selectedIndex == 0,
                    palette: palette,
                    onTap: () => onSelected(0),
                  ),
                  _WorkerNavItem(
                    icon: Icons.calendar_month_outlined,
                    label: 'Bookings',
                    selected: selectedIndex == 1,
                    palette: palette,
                    onTap: () => onSelected(1),
                  ),
                  _WorkerNavItem(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    selected: selectedIndex == 2,
                    palette: palette,
                    badgeUserId: workerId,
                    onTap: () => onSelected(2),
                  ),
                  _WorkerNavItem(
                    icon: Icons.person_outline,
                    label: 'Profile',
                    selected: selectedIndex == 3,
                    palette: palette,
                    onTap: () => onSelected(3),
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

class _WorkerNavItem extends StatelessWidget {
  const _WorkerNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.palette,
    this.badgeUserId,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final _WorkerPalette palette;
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
              width: 40,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFC72C) : null,
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: badgeUserId == null
                  ? Icon(icon, color: palette.text, size: 20)
                  : ConversationUnreadBadge(
                      userId: badgeUserId,
                      child: Icon(icon, color: palette.text, size: 20),
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: palette.text,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.state, required this.onTap});

  final WorkerVerificationUiState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: const Icon(Icons.verified_user_outlined),
      title: Text(state.bannerTitle),
      subtitle: Text(state.description),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _WorkerNotifications extends StatelessWidget {
  const _WorkerNotifications({required this.worker});

  final AppUser worker;

  Future<void> _openNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> notification,
  ) async {
    final requestId = notification.data()['requestId']?.toString();
    try {
      await notification.reference.update({'read': true});
      if (requestId == null || requestId.isEmpty) {
        throw StateError('This notification has no linked request.');
      }
      final requestDocument = await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(requestId)
          .get();
      if (!requestDocument.exists) {
        throw StateError('This service request is no longer available.');
      }
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkerJobDetailsScreen(
            request: ServiceRequest.fromDocument(requestDocument),
            worker: worker,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open notification: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : const Color(0xFFFFF9E9);
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : const Color(0xFF242424);
    final muted = dark ? const Color(0xFFB8B8B8) : const Color(0xFF737373);

    return Scaffold(
      backgroundColor: const Color(0xFFFFC72C),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                SizedBox(
                  height: 112,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
                    child: Row(
                      children: [
                        Material(
                          color: const Color(0xFFFFF7D9),
                          shape: const CircleBorder(),
                          child: IconButton(
                            key: const ValueKey('worker-notifications-back'),
                            onPressed: () => Navigator.pop(context),
                            constraints: const BoxConstraints.tightFor(
                              width: 38,
                              height: 38,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Color(0xFF242424),
                              size: 19,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            color: Color(0xFF242424),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(48),
                      ),
                    ),
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('notifications')
                          .where('recipientId', isEqualTo: worker.id)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Could not load notifications:\n'
                                '${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: text),
                              ),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final notifications = snapshot.data!.docs.toList()
                          ..sort((left, right) {
                            final leftTime =
                                left.data()['createdAt'] as Timestamp?;
                            final rightTime =
                                right.data()['createdAt'] as Timestamp?;
                            return (rightTime?.millisecondsSinceEpoch ?? 0)
                                .compareTo(
                                  leftTime?.millisecondsSinceEpoch ?? 0,
                                );
                          });
                        if (notifications.isEmpty) {
                          return Center(
                            child: Text(
                              'No notifications yet.',
                              style: TextStyle(color: muted),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 32, 18, 28),
                          itemCount: notifications.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final notification = notifications[index];
                            final data = notification.data();
                            return _WorkerNotificationCard(
                              key: ValueKey(
                                'worker-notification-${notification.id}',
                              ),
                              title: (data['title'] ?? 'Update').toString(),
                              body: (data['body'] ?? '').toString(),
                              opened: data['read'] == true,
                              surface: surface,
                              text: text,
                              muted: muted,
                              onTap: () =>
                                  _openNotification(context, notification),
                            );
                          },
                        );
                      },
                    ),
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

class _WorkerNotificationCard extends StatelessWidget {
  const _WorkerNotificationCard({
    super.key,
    required this.title,
    required this.body,
    required this.opened,
    required this.surface,
    required this.text,
    required this.muted,
    required this.onTap,
  });

  final String title;
  final String body;
  final bool opened;
  final Color surface;
  final Color text;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    elevation: 3,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 94),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 38,
                child: Icon(
                  opened
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_rounded,
                  color: opened ? muted : const Color(0xFFFFD14E),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 11, height: 1.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: text, size: 30),
            ],
          ),
        ),
      ),
    ),
  );
}
