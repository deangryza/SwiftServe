import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/screens/reviews_screen.dart';
import '../../../../shared/services/client_theme_controller.dart';
import '../../../../shared/widgets/live_profile_avatar.dart';
import '../../../../shared/widgets/worker_rating_summary.dart';
import '../widgets/conversation_ui.dart';
import '../widgets/errand_tracking_map.dart';
import 'client_request_details_screen.dart';
import 'client_sections.dart';
import 'post_request_screen.dart';

const _bookingYellow = Color(0xFFFFC72C);
const _bookingCream = Color(0xFFFFF9E9);
const _bookingInk = Color(0xFF242424);

enum _BookingFilter { recent, past }

String bookingStatusLabel(ServiceRequestStatus status) => switch (status) {
  ServiceRequestStatus.pending => 'Open',
  ServiceRequestStatus.accepted => 'Accepted',
  ServiceRequestStatus.ongoing => 'Ongoing',
  ServiceRequestStatus.completed => 'Completed',
  ServiceRequestStatus.cancelled => 'Cancelled',
};

Color _statusColor(ServiceRequestStatus status) => switch (status) {
  ServiceRequestStatus.pending => const Color(0xFFFFC72C),
  ServiceRequestStatus.accepted => const Color(0xFFAEC8FF),
  ServiceRequestStatus.ongoing => const Color(0xFFFFC72C),
  ServiceRequestStatus.completed => const Color(0xFF6EF0B0),
  ServiceRequestStatus.cancelled => const Color(0xFFFF927C),
};

String _formatDate(DateTime? date) {
  if (date == null) return 'Flexible';
  final local = date.toLocal();
  return '${local.month}/${local.day}/${local.year}';
}

String _dateRange(ServiceRequest request) {
  final from = request.scheduleFrom ?? request.schedule;
  final to = request.scheduleTo ?? from;
  if (from == null) return 'Flexible';
  if (to == null || DateUtils.isSameDay(from, to)) return _formatDate(from);
  return '${_formatDate(from)} – ${_formatDate(to)}';
}

class _BookingPalette {
  _BookingPalette(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;

  final bool dark;
  Color get background => dark ? const Color(0xFF171717) : _bookingCream;
  Color get surface => dark ? const Color(0xFF2C2C2C) : Colors.white;
  Color get text => dark ? const Color(0xFFF3F3F3) : _bookingInk;
  Color get muted => dark ? const Color(0xFFB8B8B8) : const Color(0xFF707070);
  Color get border => dark ? const Color(0xFF707070) : _bookingYellow;
}

class ClientBookingsScreen extends StatefulWidget {
  const ClientBookingsScreen({super.key});

  @override
  State<ClientBookingsScreen> createState() => _ClientBookingsScreenState();
}

class _ClientBookingsScreenState extends State<ClientBookingsScreen> {
  final _searchController = TextEditingController();
  var _filter = _BookingFilter.recent;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _BookingPalette(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return ClientTabSwipeRegion(
      currentIndex: 1,
      onSwipeToIndex: (index) {
        if (index == 0) {
          Navigator.popUntil(context, (route) => route.isFirst);
        } else if (index == 2) {
          Navigator.pushReplacement(
            context,
            clientTabPageRoute(
              const ClientMessagesScreen(),
              fromIndex: 1,
              toIndex: 2,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: _bookingYellow,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  _BookingsHeader(
                    controller: _searchController,
                    palette: palette,
                    filter: _filter,
                    onChanged: (_) => setState(() {}),
                    onFilterChanged: (filter) =>
                        setState(() => _filter = filter),
                  ),
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(42),
                        ),
                      ),
                      child: uid == null
                          ? const Center(child: Text('Please log in again.'))
                          : _BookingList(
                              clientId: uid,
                              query: _searchController.text,
                              filter: _filter,
                              palette: palette,
                            ),
                    ),
                  ),
                  _BookingsBottomNav(palette: palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingsHeader extends StatelessWidget {
  const _BookingsHeader({
    required this.controller,
    required this.palette,
    required this.filter,
    required this.onChanged,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final _BookingPalette palette;
  final _BookingFilter filter;
  final ValueChanged<String> onChanged;
  final ValueChanged<_BookingFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text(
              'Bookings',
              style: TextStyle(
                color: _bookingInk,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SearchField(
          controller: controller,
          hint: 'Search bookings ...',
          onChanged: onChanged,
          palette: palette,
          showFilter: true,
        ),
        const SizedBox(height: 12),
        _BookingFilterSlider(
          filter: filter,
          palette: palette,
          onChanged: onFilterChanged,
        ),
      ],
    ),
  );
}

class _BookingFilterSlider extends StatelessWidget {
  const _BookingFilterSlider({
    required this.filter,
    required this.palette,
    required this.onChanged,
  });

  final _BookingFilter filter;
  final _BookingPalette palette;
  final ValueChanged<_BookingFilter> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Stack(
      children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: filter == _BookingFilter.recent
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _bookingCream,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        Row(
          children: [
            _BookingFilterButton(
              key: const ValueKey('booking-filter-recent'),
              label: 'Recent',
              selected: filter == _BookingFilter.recent,
              color: palette.text,
              onTap: () => onChanged(_BookingFilter.recent),
            ),
            _BookingFilterButton(
              key: const ValueKey('booking-filter-past'),
              label: 'Past',
              selected: filter == _BookingFilter.past,
              color: palette.text,
              onTap: () => onChanged(_BookingFilter.past),
            ),
          ],
        ),
      ],
    ),
  );
}

class _BookingFilterButton extends StatelessWidget {
  const _BookingFilterButton({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            color: selected ? _bookingInk : color,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          child: Text(label),
        ),
      ),
    ),
  );
}

class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.clientId,
    required this.query,
    required this.filter,
    required this.palette,
  });

  final String clientId;
  final String query;
  final _BookingFilter filter;
  final _BookingPalette palette;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('service_requests')
            .where('clientId', isEqualTo: clientId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load bookings:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.text),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final normalizedQuery = query.trim().toLowerCase();
          final requests = snapshot.data!.docs
              .map(ServiceRequest.fromDocument)
              .where((request) {
                final isPast =
                    request.status == ServiceRequestStatus.completed ||
                    request.status == ServiceRequestStatus.cancelled;
                return filter == _BookingFilter.past ? isPast : !isPast;
              })
              .where((request) {
                if (normalizedQuery.isEmpty) return true;
                return request.title.toLowerCase().contains(normalizedQuery) ||
                    request.category.toLowerCase().contains(normalizedQuery) ||
                    request.location.toLowerCase().contains(normalizedQuery) ||
                    bookingStatusLabel(
                      request.status,
                    ).toLowerCase().contains(normalizedQuery);
              })
              .toList();
          requests.sort((left, right) {
            final leftDate =
                left.createdAt ?? left.scheduleFrom ?? left.schedule;
            final rightDate =
                right.createdAt ?? right.scheduleFrom ?? right.schedule;
            final newestFirst = (rightDate?.millisecondsSinceEpoch ?? 0)
                .compareTo(leftDate?.millisecondsSinceEpoch ?? 0);
            return newestFirst != 0 ? newestFirst : right.id.compareTo(left.id);
          });
          if (requests.isEmpty) {
            return Center(
              child: Text(
                normalizedQuery.isEmpty
                    ? filter == _BookingFilter.recent
                          ? 'No recent bookings.'
                          : 'No past bookings.'
                    : 'No matching bookings found.',
                style: TextStyle(color: palette.muted),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 34, 18, 24),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _BookingCard(
              request: requests[index],
              palette: palette,
              onTap: () => Navigator.push(
                context,
                clientPageRoute(
                  ClientWorkersFoundScreen(requestId: requests[index].id),
                ),
              ),
              onViewPost: () => Navigator.push(
                context,
                clientPageRoute(
                  ClientRequestDetailsScreen(requestId: requests[index].id),
                ),
              ),
              onEditPost: () => Navigator.push(
                context,
                clientPageRoute(PostRequestScreen(existing: requests[index])),
              ),
            ),
          );
        },
      );
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.request,
    required this.palette,
    required this.onTap,
    required this.onViewPost,
    required this.onEditPost,
  });

  final ServiceRequest request;
  final _BookingPalette palette;
  final VoidCallback onTap;
  final VoidCallback onViewPost;
  final VoidCallback onEditPost;

  @override
  Widget build(BuildContext context) => Material(
    color: palette.surface,
    elevation: 3,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      key: ValueKey('booking-${request.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${request.description} · ${request.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                  Text(
                    'Booking: ${_dateRange(request)}',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                  Text(
                    'Budget: ₱${request.budget.toStringAsFixed(0)}',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: _statusColor(request.status),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                bookingStatusLabel(request.status),
                style: const TextStyle(
                  color: _bookingInk,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _BookingMoreMenu(
              key: ValueKey('booking-more-${request.id}'),
              canEdit: request.status == ServiceRequestStatus.pending,
              color: palette.text,
              onViewPost: onViewPost,
              onEditPost: onEditPost,
            ),
          ],
        ),
      ),
    ),
  );
}

enum _BookingAction { view, edit }

class _BookingMoreMenu extends StatelessWidget {
  const _BookingMoreMenu({
    super.key,
    required this.canEdit,
    required this.color,
    required this.onViewPost,
    required this.onEditPost,
  });

  final bool canEdit;
  final Color color;
  final VoidCallback onViewPost;
  final VoidCallback onEditPost;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 36,
    child: PopupMenuButton<_BookingAction>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, color: color, size: 20),
      onSelected: (action) => switch (action) {
        _BookingAction.view => onViewPost(),
        _BookingAction.edit => onEditPost(),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _BookingAction.view,
          child: ListTile(
            leading: Icon(Icons.article_outlined),
            title: Text('View post'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canEdit)
          const PopupMenuItem(
            value: _BookingAction.edit,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit post'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    ),
  );
}

class ClientWorkersFoundScreen extends StatefulWidget {
  const ClientWorkersFoundScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<ClientWorkersFoundScreen> createState() =>
      _ClientWorkersFoundScreenState();
}

class _ClientWorkersFoundScreenState extends State<ClientWorkersFoundScreen> {
  final _searchController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _accept(
    ServiceRequest request,
    ServiceApplication application,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept this worker?'),
        content: Text(
          '${application.workerName} will be selected for ${request.title}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept worker'),
          ),
        ],
      ),
    );
    if (confirmed != true || _saving) return;
    setState(() => _saving = true);
    try {
      await ServiceRequestRepository().acceptApplicant(
        request: request,
        application: application,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${application.workerName} was accepted.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept worker: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _BookingPalette(context);
    return Scaffold(
      backgroundColor: _bookingYellow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .doc(widget.requestId)
                  .snapshots(),
              builder: (context, requestSnapshot) {
                if (requestSnapshot.hasError) {
                  return _ErrorMessage('${requestSnapshot.error}');
                }
                if (!requestSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!requestSnapshot.data!.exists) {
                  return const _ErrorMessage('This booking no longer exists.');
                }
                final request = ServiceRequest.fromDocument(
                  requestSnapshot.data!,
                );
                return Column(
                  children: [
                    _WorkersHeader(
                      request: request,
                      controller: _searchController,
                      palette: palette,
                      onChanged: (_) => setState(() {}),
                    ),
                    Expanded(
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: palette.background,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(38),
                          ),
                        ),
                        child: _ApplicationsList(
                          request: request,
                          query: _searchController.text,
                          palette: palette,
                          saving: _saving,
                          onAccept: (application) =>
                              _accept(request, application),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkersHeader extends StatelessWidget {
  const _WorkersHeader({
    required this.request,
    required this.controller,
    required this.palette,
    required this.onChanged,
  });

  final ServiceRequest request;
  final TextEditingController controller;
  final _BookingPalette palette;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 156,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
      child: Column(
        children: [
          Row(
            children: [
              _CircleBackButton(onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Workers Found',
                  style: TextStyle(
                    color: _bookingInk,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Material(
                color: const Color(0xFFFFF7D9),
                shape: const CircleBorder(),
                child: IconButton(
                  key: const ValueKey('workers-found-post-details'),
                  tooltip: 'Post details',
                  onPressed: () => Navigator.push(
                    context,
                    clientPageRoute(
                      ClientRequestDetailsScreen(requestId: request.id),
                    ),
                  ),
                  icon: const Icon(
                    Icons.article_outlined,
                    color: _bookingInk,
                    size: 21,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SearchField(
            controller: controller,
            hint: 'For: “${request.title}” · search workers',
            onChanged: onChanged,
            palette: palette,
          ),
        ],
      ),
    ),
  );
}

class _ApplicationsList extends StatelessWidget {
  const _ApplicationsList({
    required this.request,
    required this.query,
    required this.palette,
    required this.saving,
    required this.onAccept,
  });

  final ServiceRequest request;
  final String query;
  final _BookingPalette palette;
  final bool saving;
  final ValueChanged<ServiceApplication> onAccept;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ServiceApplication>>(
    stream: ServiceRequestRepository().watchApplications(request.id),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ErrorMessage('Could not load workers:\n${snapshot.error}');
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final normalizedQuery = query.trim().toLowerCase();
      var applications = snapshot.data!;
      if (request.workerId != null) {
        applications = applications
            .where(
              (application) =>
                  application.workerId == request.workerId &&
                  application.status == ServiceApplicationStatus.accepted,
            )
            .toList();
        if (applications.isEmpty) {
          applications = [
            ServiceApplication(
              workerId: request.workerId!,
              workerName: request.workerName ?? 'Worker',
              requestId: request.id,
              clientId: request.clientId,
              status: ServiceApplicationStatus.accepted,
            ),
          ];
        }
      }
      applications = applications
          .where(
            (application) =>
                normalizedQuery.isEmpty ||
                application.workerName.toLowerCase().contains(normalizedQuery),
          )
          .toList();
      if (applications.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              request.workerId == null
                  ? 'No workers have applied yet.'
                  : 'The accepted worker could not be loaded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 30, 18, 24),
        itemCount: applications.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _ApplicationCard(
          request: request,
          application: applications[index],
          palette: palette,
          saving: saving,
          onAccept: () => onAccept(applications[index]),
        ),
      );
    },
  );
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.request,
    required this.application,
    required this.palette,
    required this.saving,
    required this.onAccept,
  });

  final ServiceRequest request;
  final ServiceApplication application;
  final _BookingPalette palette;
  final bool saving;
  final VoidCallback onAccept;

  bool get _accepted =>
      request.workerId == application.workerId &&
      application.status == ServiceApplicationStatus.accepted;

  bool get _canAccept =>
      request.status == ServiceRequestStatus.pending &&
      application.status == ServiceApplicationStatus.pending;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('worker_profiles')
        .doc(application.workerId)
        .snapshots(),
    builder: (context, snapshot) {
      final profile = snapshot.data?.data() ?? const <String, dynamic>{};
      final name = (profile['fullName'] ?? application.workerName).toString();
      final skills = _skills(profile);
      return Material(
        color: palette.surface,
        elevation: 3,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('worker-application-${application.workerId}'),
          onTap: _accepted
              ? () => Navigator.push(
                  context,
                  clientPageRoute(
                    ClientBookingDetailsScreen(
                      requestId: request.id,
                      workerId: application.workerId,
                    ),
                  ),
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: indexColor(_accepted),
                width: _accepted ? 1.3 : 0.8,
              ),
            ),
            child: Row(
              children: [
                LiveProfileAvatar(
                  userId: application.workerId,
                  fallbackName: name,
                  radius: 25,
                  backgroundColor: const Color(0xFFFFF1C8),
                  foregroundColor: _bookingInk,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _accepted ? 'Accepted worker' : 'Applied worker',
                        style: const TextStyle(
                          color: Color(0xFF8A6B00),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        skills,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_accepted)
                  const Icon(Icons.chevron_right, color: _bookingYellow)
                else if (_canAccept)
                  FilledButton(
                    onPressed: saving ? null : onAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: _bookingYellow,
                      foregroundColor: _bookingInk,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 38),
                    ),
                    child: const Text('Accept'),
                  )
                else
                  Text(
                    application.status.name.toUpperCase(),
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Color indexColor(bool accepted) =>
      accepted ? _bookingYellow : Colors.transparent;

  String _skills(Map<String, dynamic> profile) {
    final value = profile['skills'];
    if (value is List && value.isNotEmpty) return value.join(' · ');
    final category = (profile['category'] ?? request.category).toString();
    return category.isEmpty ? 'Service provider' : category;
  }
}

class ClientBookingDetailsScreen extends StatefulWidget {
  const ClientBookingDetailsScreen({
    super.key,
    required this.requestId,
    required this.workerId,
  });

  final String requestId;
  final String workerId;

  @override
  State<ClientBookingDetailsScreen> createState() =>
      _ClientBookingDetailsScreenState();
}

class _ClientBookingDetailsScreenState
    extends State<ClientBookingDetailsScreen> {
  bool _saving = false;
  bool _savingReview = false;
  bool _savingReport = false;

  Future<void> _message(ServiceRequest request) async {
    final pairConversationId = conversationIdFor(
      clientId: request.clientId,
      workerId: widget.workerId,
    );
    final pairConversation = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(pairConversationId)
        .get();
    if (!mounted) return;
    Navigator.push(
      context,
      clientPageRoute(
        ClientChatScreen(
          conversationId: pairConversation.exists
              ? pairConversationId
              : request.id,
          otherPersonName: request.workerName ?? 'Service provider',
        ),
      ),
    );
  }

  Future<void> _cancel(ServiceRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text('Cancel ${request.title}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || _saving) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(request.id)
          .update({
            'status': ServiceRequestStatus.cancelled.name,
            'cancelledAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request cancelled.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel request: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rateWorker(ServiceRequest request) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || request.workerId == null || _savingReview) return;

    final reviewReference = FirebaseFirestore.instance
        .collection('reviews')
        .doc(request.id);
    try {
      final existingReview = await reviewReference.get();
      if (!mounted) return;
      if (existingReview.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already reviewed this worker.')),
        );
        return;
      }

      final review = await showDialog<_WorkerReview>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WorkerReviewDialog(
          workerName: request.workerName ?? 'your worker',
        ),
      );
      if (review == null || !mounted) return;

      setState(() => _savingReview = true);
      final notificationReference = FirebaseFirestore.instance
          .collection('notifications')
          .doc();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(reviewReference, {
        'requestId': request.id,
        'clientId': user.uid,
        'workerId': request.workerId,
        'workerName': request.workerName ?? '',
        'rating': review.rating,
        'comment': review.comment,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(notificationReference, {
        'recipientId': request.workerId,
        'senderId': user.uid,
        'requestId': request.id,
        'title': 'New review received',
        'body':
            '${request.clientName} rated your work ${review.rating} out of 5 stars.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Thanks for your review.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit your review: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingReview = false);
    }
  }

  Future<void> _reportWorker(ServiceRequest request) async {
    final user = FirebaseAuth.instance.currentUser;
    final workerId = request.workerId;
    if (user == null || workerId == null || _savingReport) return;
    final reportReference = FirebaseFirestore.instance
        .collection('reports')
        .doc('${request.id}_${user.uid}');
    try {
      final existingReport = await reportReference.get();
      if (!mounted) return;
      if (existingReport.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already reported this booking.')),
        );
        return;
      }
      final report = await showDialog<_WorkerReport>(
        context: context,
        builder: (_) => _WorkerReportDialog(
          workerName: request.workerName ?? 'this worker',
        ),
      );
      if (report == null || !mounted) return;
      setState(() => _savingReport = true);
      await reportReference.set({
        'requestId': request.id,
        'reporterId': user.uid,
        'reportedUserId': workerId,
        'reportedUserName': request.workerName ?? '',
        'reason': report.reason,
        'details': report.details,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted for review.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit report: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _BookingPalette(context);
    return Scaffold(
      backgroundColor: _bookingYellow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .doc(widget.requestId)
                  .snapshots(),
              builder: (context, requestSnapshot) {
                if (requestSnapshot.hasError) {
                  return _ErrorMessage('${requestSnapshot.error}');
                }
                if (!requestSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!requestSnapshot.data!.exists) {
                  return const _ErrorMessage('This booking no longer exists.');
                }
                final request = ServiceRequest.fromDocument(
                  requestSnapshot.data!,
                );
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('worker_profiles')
                      .doc(widget.workerId)
                      .snapshots(),
                  builder: (context, workerSnapshot) {
                    final worker =
                        workerSnapshot.data?.data() ??
                        <String, dynamic>{
                          'fullName': request.workerName ?? 'Worker',
                        };
                    return _BookingDetailsBody(
                      request: request,
                      worker: worker,
                      palette: palette,
                      saving: _saving,
                      savingReview: _savingReview,
                      savingReport: _savingReport,
                      onRateWorker: () => _rateWorker(request),
                      onReportWorker: () => _reportWorker(request),
                      onMessage: () => _message(request),
                      onCancel: () => _cancel(request),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingDetailsBody extends StatelessWidget {
  const _BookingDetailsBody({
    required this.request,
    required this.worker,
    required this.palette,
    required this.saving,
    required this.savingReview,
    required this.savingReport,
    required this.onRateWorker,
    required this.onReportWorker,
    required this.onMessage,
    required this.onCancel,
  });

  final ServiceRequest request;
  final Map<String, dynamic> worker;
  final _BookingPalette palette;
  final bool saving;
  final bool savingReview;
  final bool savingReport;
  final VoidCallback onRateWorker;
  final VoidCallback onReportWorker;
  final VoidCallback onMessage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final name = (worker['fullName'] ?? request.workerName ?? 'Worker')
        .toString();
    final canCancel =
        request.status == ServiceRequestStatus.pending ||
        request.status == ServiceRequestStatus.accepted;
    return Stack(
      children: [
        Column(
          children: [
            SizedBox(
              height: 180,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _CircleBackButton(
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Booking Details',
                          style: TextStyle(
                            color: _bookingInk,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LiveProfileAvatar(
                      userId: request.workerId ?? '',
                      fallbackName: name,
                      radius: 38,
                      backgroundColor: const Color(0xFFDCE5FF),
                      foregroundColor: const Color(0xFF24458E),
                      textStyle: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(48),
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 190),
                  children: [
                    _AcceptedWorkerCard(
                      name: name,
                      request: request,
                      worker: worker,
                      palette: palette,
                    ),
                    const SizedBox(height: 18),
                    _RequestSummaryCard(request: request, palette: palette),
                    if (request.isErrand &&
                        (request.status == ServiceRequestStatus.accepted ||
                            request.status ==
                                ServiceRequestStatus.ongoing)) ...[
                      const SizedBox(height: 18),
                      ErrandTrackingMap(
                        key: ValueKey('errand-tracking-${request.id}'),
                        request: request,
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (request.status == ServiceRequestStatus.completed) ...[
                      FilledButton(
                        key: const ValueKey('rate-completed-worker'),
                        onPressed: savingReview ? null : onRateWorker,
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.surface,
                          foregroundColor: palette.text,
                          minimumSize: const Size.fromHeight(52),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          savingReview
                              ? 'Submitting Review...'
                              : 'Rate your worker',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      key: const ValueKey('message-accepted-worker'),
                      onPressed: onMessage,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.surface,
                        foregroundColor: palette.text,
                        minimumSize: const Size.fromHeight(52),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Message Worker'),
                    ),
                    if (canCancel) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: saving ? null : onCancel,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFDDDD),
                          foregroundColor: const Color(0xFFE74632),
                          minimumSize: const Size.fromHeight(52),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          saving ? 'Cancelling...' : 'Cancel Request',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        _WorkerProfileSheet(
          worker: worker,
          workerId: request.workerId ?? '',
          name: name,
          palette: palette,
          savingReport: savingReport,
          onReport: onReportWorker,
        ),
      ],
    );
  }
}

class _WorkerReview {
  const _WorkerReview({required this.rating, required this.comment});

  final int rating;
  final String comment;
}

class _WorkerReviewDialog extends StatefulWidget {
  const _WorkerReviewDialog({required this.workerName});

  final String workerName;

  @override
  State<_WorkerReviewDialog> createState() => _WorkerReviewDialogState();
}

class _WorkerReviewDialogState extends State<_WorkerReviewDialog> {
  final _commentController = TextEditingController();
  var _rating = 0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF272727) : _bookingCream;
    final field = dark ? const Color(0xFF333333) : Colors.white;
    final text = dark ? const Color(0xFFF4F4F4) : _bookingInk;
    final muted = dark ? const Color(0xFFB5B5B5) : const Color(0xFF6F7480);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: Material(
            color: surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 126,
                  child: ColoredBox(
                    color: _bookingYellow,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 10,
                          bottom: -3,
                          child: Image.asset(
                            'assets/dashboard/review_mascot.png',
                            width: 128,
                            height: 128,
                            fit: BoxFit.contain,
                            semanticLabel: 'SwiftServe thumbs-up mascot',
                          ),
                        ),
                        Positioned(
                          left: 138,
                          right: 42,
                          top: 35,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Leave a review',
                                maxLines: 1,
                                style: TextStyle(
                                  color: _bookingInk,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'How was your experience?',
                                maxLines: 1,
                                style: TextStyle(
                                  color: _bookingInk.withValues(alpha: 0.72),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 12,
                          child: IconButton(
                            key: const ValueKey('close-worker-review'),
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF62666F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          label: _rating == 0
                              ? 'No rating selected'
                              : '$_rating out of 5 stars selected',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              5,
                              (index) => Expanded(
                                child: IconButton(
                                  key: ValueKey('worker-rating-${index + 1}'),
                                  tooltip: '${index + 1} star rating',
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      setState(() => _rating = index + 1),
                                  iconSize: 49,
                                  icon: Icon(
                                    Icons.star_rounded,
                                    color: index < _rating
                                        ? const Color(0xFFE37B00)
                                        : const Color(0xFFA7A9AD),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Leave a comment (optional)',
                          style: TextStyle(color: muted, fontSize: 14),
                        ),
                        const SizedBox(height: 9),
                        TextField(
                          key: const ValueKey('worker-review-comment'),
                          controller: _commentController,
                          minLines: 3,
                          maxLines: 4,
                          maxLength: 500,
                          style: TextStyle(color: text),
                          decoration: InputDecoration(
                            hintText:
                                '${widget.workerName} did a great job. Share what stood out...',
                            hintStyle: TextStyle(color: muted),
                            counterText: '',
                            filled: true,
                            fillColor: field,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: muted.withValues(alpha: 0.24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(context),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFC7C7C9),
                                  foregroundColor: _bookingInk,
                                  minimumSize: const Size.fromHeight(54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Not now',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey('submit-worker-review'),
                                onPressed: _rating == 0
                                    ? null
                                    : () => Navigator.pop(
                                        context,
                                        _WorkerReview(
                                          rating: _rating,
                                          comment: _commentController.text
                                              .trim(),
                                        ),
                                      ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF17BD8A),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(
                                    0xFF9EDBC8,
                                  ),
                                  minimumSize: const Size.fromHeight(54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Submit',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

class _WorkerReport {
  const _WorkerReport({required this.reason, required this.details});

  final String reason;
  final String details;
}

class _WorkerReportDialog extends StatefulWidget {
  const _WorkerReportDialog({required this.workerName});

  final String workerName;

  @override
  State<_WorkerReportDialog> createState() => _WorkerReportDialogState();
}

class _WorkerReportDialogState extends State<_WorkerReportDialog> {
  static const _reasons = [
    'Inappropriate behavior',
    'Fraud or scam',
    'Poor service',
    'Safety concern',
    'Other',
  ];

  final _detailsController = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.report_outlined, color: Color(0xFFE74632), size: 34),
    title: Text('Report ${widget.workerName}?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell us what happened. Your report will be saved for review.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const ValueKey('worker-report-reason'),
            initialValue: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason',
              border: OutlineInputBorder(),
            ),
            items: _reasons
                .map(
                  (reason) =>
                      DropdownMenuItem(value: reason, child: Text(reason)),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _reason = value),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('worker-report-details'),
            controller: _detailsController,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Additional details',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('submit-worker-report'),
        onPressed: _reason == null
            ? null
            : () => Navigator.pop(
                context,
                _WorkerReport(
                  reason: _reason!,
                  details: _detailsController.text.trim(),
                ),
              ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE74632),
          foregroundColor: Colors.white,
        ),
        child: const Text('Submit report'),
      ),
    ],
  );
}

class _AcceptedWorkerCard extends StatelessWidget {
  const _AcceptedWorkerCard({
    required this.name,
    required this.request,
    required this.worker,
    required this.palette,
  });

  final String name;
  final ServiceRequest request;
  final Map<String, dynamic> worker;
  final _BookingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _bookingYellow, width: 1.3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          LiveProfileAvatar(
            userId: request.workerId ?? '',
            fallbackName: name,
            radius: 24,
            backgroundColor: const Color(0xFFFFF1C8),
            foregroundColor: _bookingInk,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                WorkerRatingBuilder(
                  workerId: request.workerId ?? '',
                  builder: (context, summary) => Text(
                    '${request.category} · ⭐ ${summary.displayAverage}',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Budget',
                style: TextStyle(color: palette.muted, fontSize: 10),
              ),
              Text(
                '₱${request.budget.toStringAsFixed(0)}',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestSummaryCard extends StatelessWidget {
  const _RequestSummaryCard({required this.request, required this.palette});

  final ServiceRequest request;
  final _BookingPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.title,
          style: TextStyle(
            color: palette.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _DetailLine(
          icon: Icons.date_range_outlined,
          label: _dateRange(request),
          palette: palette,
        ),
        _DetailLine(
          icon: request.isErrand
              ? Icons.delivery_dining_outlined
              : Icons.location_on_outlined,
          label: request.isErrand ? request.placeLabel : request.location,
          palette: palette,
        ),
        if (request.errandItems?.isNotEmpty ?? false)
          _DetailLine(
            icon: Icons.shopping_bag_outlined,
            label: request.errandItems!,
            palette: palette,
          ),
        _DetailLine(
          icon: Icons.info_outline,
          label: bookingStatusLabel(request.status),
          palette: palette,
        ),
        const SizedBox(height: 8),
        Text(request.description, style: TextStyle(color: palette.muted)),
      ],
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final _BookingPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Icon(icon, size: 18, color: _bookingYellow),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: TextStyle(color: palette.text)),
        ),
      ],
    ),
  );
}

class _WorkerProfileSheet extends StatelessWidget {
  const _WorkerProfileSheet({
    required this.worker,
    required this.workerId,
    required this.name,
    required this.palette,
    required this.savingReport,
    required this.onReport,
  });

  final Map<String, dynamic> worker;
  final String workerId;
  final String name;
  final _BookingPalette palette;
  final bool savingReport;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final skills = worker['skills'];
    final skillText = skills is List && skills.isNotEmpty
        ? skills.join(', ')
        : (worker['category'] ?? 'Service provider').toString();
    return DraggableScrollableSheet(
      initialChildSize: 0.18,
      minChildSize: 0.18,
      maxChildSize: 0.72,
      snap: true,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(42)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
          children: [
            Center(
              child: Container(
                width: 52,
                height: 5,
                decoration: BoxDecoration(
                  color: palette.muted,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Icon(Icons.keyboard_arrow_up, color: palette.text, size: 30),
            Text(
              'Swipe to view worker’s profile',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            LiveProfileAvatar(
              userId: workerId,
              fallbackName: name,
              radius: 42,
              backgroundColor: const Color(0xFFFFF1C8),
              foregroundColor: _bookingInk,
              textStyle: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              skillText,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
            const SizedBox(height: 22),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .where('workerId', isEqualTo: workerId)
                  .snapshots(),
              builder: (context, jobsSnapshot) {
                final completedJobs =
                    jobsSnapshot.data?.docs
                        .where(
                          (document) =>
                              document.data()['status'] == 'completed',
                        )
                        .length ??
                    0;
                return Row(
                  children: [
                    Expanded(
                      child: WorkerRatingBuilder(
                        workerId: workerId,
                        builder: (context, summary) => _ProfileStat(
                          value: summary.displayAverage,
                          label: summary.reviewCount == 1
                              ? '1 review'
                              : '${summary.reviewCount} reviews',
                          palette: palette,
                          onTap: () => Navigator.push(
                            context,
                            clientPageRoute(
                              ReviewsScreen(
                                userId: workerId,
                                reviewsFor: ReviewsFor.worker,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _ProfileStat(
                        value: jobsSnapshot.hasData ? '$completedJobs' : '—',
                        label: 'Jobs done',
                        palette: palette,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            _DetailLine(
              icon: Icons.location_on_outlined,
              label: (worker['location'] ?? 'Location not provided').toString(),
              palette: palette,
            ),
            _DetailLine(
              icon: Icons.verified_outlined,
              label: worker['verificationStatus'] == 'verified'
                  ? 'Identity verified'
                  : 'Verification status unavailable',
              palette: palette,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey('report-worker'),
              onPressed: savingReport ? null : onReport,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE74632),
                side: const BorderSide(color: Color(0xFFE74632)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.report_outlined),
              label: Text(
                savingReport ? 'Submitting report...' : 'Report worker',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.value,
    required this.label,
    required this.palette,
    this.onTap,
  });

  final String value;
  final String label;
  final _BookingPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: onTap == null ? null : const ValueKey('worker-reviews-link'),
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: palette.text,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: TextStyle(color: palette.muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFF7D9),
    shape: const CircleBorder(),
    child: IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back, color: _bookingInk, size: 19),
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      padding: EdgeInsets.zero,
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.palette,
    this.showFilter = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final _BookingPalette palette;
  final bool showFilter;

  @override
  Widget build(BuildContext context) => Material(
    color: palette.surface,
    elevation: 3,
    borderRadius: BorderRadius.circular(20),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: palette.text, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.muted, fontSize: 11),
        prefixIcon: Icon(Icons.search, color: palette.muted, size: 19),
        suffixIcon: showFilter
            ? Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _bookingYellow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune, color: _bookingInk, size: 18),
              )
            : null,
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}

class _BookingsBottomNav extends StatelessWidget {
  const _BookingsBottomNav({required this.palette});

  final _BookingPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    color: palette.background,
    child: SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 6, 18, 12),
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 5,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            _BookingNavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              palette: palette,
              onTap: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
            ),
            _BookingNavItem(
              icon: Icons.calendar_month_outlined,
              label: 'Bookings',
              palette: palette,
              selected: true,
              onTap: () {},
            ),
            _BookingNavItem(
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              palette: palette,
              showUnreadBadge: true,
              onTap: () => Navigator.pushReplacement(
                context,
                clientTabPageRoute(
                  const ClientMessagesScreen(),
                  fromIndex: 1,
                  toIndex: 2,
                ),
              ),
            ),
            _BookingNavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              palette: palette,
              onTap: () => Navigator.pushReplacement(
                context,
                clientTabPageRoute(
                  const ClientProfileScreen(),
                  fromIndex: 1,
                  toIndex: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BookingNavItem extends StatelessWidget {
  const _BookingNavItem({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.selected = false,
    this.showUnreadBadge = false,
  });

  final IconData icon;
  final String label;
  final _BookingPalette palette;
  final VoidCallback onTap;
  final bool selected;
  final bool showUnreadBadge;

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
                color: selected ? _bookingYellow : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: showUnreadBadge
                    ? ConversationUnreadBadge(
                        userId: FirebaseAuth.instance.currentUser?.uid,
                        child: Icon(icon, color: palette.text, size: 19),
                      )
                    : Icon(icon, color: palette.text, size: 19),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: palette.text, fontSize: 10)),
          ],
        ),
      ),
    ),
  );
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
