import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/services/client_theme_controller.dart';
import '../../../../shared/widgets/action_confirmation_dialog.dart';
import '../../../../shared/widgets/live_profile_avatar.dart';
import '../../../../shared/widgets/booking_details_cards.dart';
import '../../../../shared/screens/public_profile_screen.dart';
import '../widgets/errand_tracking_map.dart';
import '../widgets/post_location_map.dart';
import 'client_sections.dart';
import 'post_request_screen.dart';

class ClientRequestDetailsScreen extends StatefulWidget {
  const ClientRequestDetailsScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<ClientRequestDetailsScreen> createState() =>
      _ClientRequestDetailsScreenState();
}

class _ClientRequestDetailsScreenState
    extends State<ClientRequestDetailsScreen> {
  bool _saving = false;

  /// The latest saved version of the post, kept live so edits show at once.
  late final _requestStream = ServiceRequestRepository().watchRequest(
    widget.requestId,
  );
  late ServiceRequest _request;

  String _dateRange(ServiceRequest request) {
    String format(DateTime date) => '${date.month}/${date.day}/${date.year}';
    final from = request.scheduleFrom ?? request.schedule;
    final to = request.scheduleTo ?? from;
    if (from == null) return 'Flexible';
    if (to == null || DateUtils.isSameDay(from, to)) return format(from);
    return '${format(from)} – ${format(to)}';
  }

  Future<void> _cancel() async {
    final confirmed = await showActionConfirmation(
      context,
      title: 'Cancel this booking?',
      message:
          'Are you sure you want to cancel ${_request.title}? This action cannot be undone.',
      confirmLabel: 'Cancel booking',
      icon: Icons.event_busy_outlined,
    );
    if (!confirmed || _saving) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(_request.id)
          .update({
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
          });
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _acceptApplicant(ServiceApplication application) async {
    final confirmed = await showActionConfirmation(
      context,
      title: 'Accept this worker?',
      message:
          'Choose ${application.workerName} for this request? Other applications will be declined.',
      confirmLabel: 'Accept worker',
      icon: Icons.person_add_alt_1_rounded,
    );
    if (!confirmed || _saving) return;

    setState(() => _saving = true);
    try {
      await ServiceRequestRepository().acceptApplicant(
        request: _request,
        application: application,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${application.workerName} was selected.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not select worker: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openWorkerChat() async {
    final request = _request;
    final pairConversationId = conversationIdFor(
      clientId: request.clientId,
      workerId: request.workerId!,
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

  Future<void> _rate() async {
    var rating = 5;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate this service'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              5,
              (index) => IconButton(
                onPressed: () => setDialogState(() => rating = index + 1),
                icon: Icon(index < rating ? Icons.star : Icons.star_border),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, rating),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final user = FirebaseAuth.instance.currentUser!;
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final reviewerName = (profile.data()?['fullName'] ?? _request.clientName)
        .toString()
        .trim();
    await FirebaseFirestore.instance
        .collection('reviews')
        .doc(_request.id)
        .set({
          'requestId': _request.id,
          'clientId': user.uid,
          'clientName': reviewerName,
          'workerId': _request.workerId,
          'workerName': _request.workerName ?? '',
          'rating': selected,
          'comment': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Thanks for your review.')));
    }
  }

  void _edit(ServiceRequest request) {
    Navigator.push(
      context,
      clientPageRoute(PostRequestScreen(existing: request)),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ServiceRequest?>(
    stream: _requestStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('Request details')),
          body: Center(
            child: Text('Could not load this post.\n${snapshot.error}'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('Request details')),
          body: snapshot.connectionState == ConnectionState.active
              ? const Center(child: Text('This post no longer exists.'))
              : const Center(child: CircularProgressIndicator()),
        );
      }
      _request = snapshot.data!;
      return _buildDetails(context, _request);
    },
  );

  Widget _buildDetails(BuildContext context, ServiceRequest request) {
    return ClientRequestDetailsContent(
      request: request,
      dateLabel: _dateRange(request),
      saving: _saving,
      onEdit: () => _edit(request),
      onCancel: _cancel,
      onMessage: _openWorkerChat,
      onRate: _rate,
      onViewProfile: () => Navigator.push(
        context,
        clientPageRoute(
          PublicProfileScreen(
            userId: request.workerId!,
            role: PublicProfileRole.worker,
            initialData: {'fullName': request.workerName ?? 'Worker'},
          ),
        ),
      ),
      applications: request.status == ServiceRequestStatus.pending
          ? _buildApplications(request)
          : null,
    );
  }

  Widget _buildApplications(ServiceRequest request) =>
      StreamBuilder<List<ServiceApplication>>(
        stream: ServiceRequestRepository().watchApplications(request.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load applications: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final applications = snapshot.data!;
          if (applications.isEmpty) {
            return const Card(
              margin: EdgeInsets.symmetric(horizontal: 8),
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'No workers have applied yet. Applications will '
                  'appear here.',
                ),
              ),
            );
          }
          return Column(
            children: applications.map((application) {
              return Card(
                margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: ListTile(
                  leading: LiveProfileAvatar(
                    userId: application.workerId,
                    fallbackName: application.workerName,
                  ),
                  title: Text(application.workerName),
                  subtitle: Text(
                    application.appliedAt == null
                        ? 'Application received'
                        : 'Applied ${_formatDate(application.appliedAt!)}',
                  ),
                  trailing: FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _acceptApplicant(application),
                    child: const Text('Accept'),
                  ),
                ),
              );
            }).toList(),
          );
        },
      );

  String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';
}

/// Presentation shared by the post-details entry point, with workflow callbacks
/// kept in the live screen above.
class ClientRequestDetailsContent extends StatelessWidget {
  const ClientRequestDetailsContent({
    super.key,
    required this.request,
    required this.dateLabel,
    required this.saving,
    required this.onEdit,
    required this.onCancel,
    required this.onMessage,
    required this.onRate,
    required this.onViewProfile,
    this.applications,
    this.map,
  });
  final ServiceRequest request;
  final String dateLabel;
  final bool saving;
  final VoidCallback onEdit, onCancel, onMessage, onRate, onViewProfile;
  final Widget? applications;
  final Widget? map;

  @override
  Widget build(BuildContext context) {
    final canEdit = request.status == ServiceRequestStatus.pending;
    final canCancel =
        canEdit || request.status == ServiceRequestStatus.accepted;
    final canMessage =
        request.workerId != null &&
        request.status != ServiceRequestStatus.cancelled;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                BookingDetailsHeader(
                  request: request,
                  showSos: false,
                  backButton: IconButton.outlined(
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  actions: [
                    if (canEdit)
                      IconButton(
                        key: const ValueKey('request-details-edit'),
                        tooltip: 'Edit post',
                        onPressed: saving ? null : onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      if (request.workerId != null)
                        BookingPartyCard(
                          userId: request.workerId!,
                          name: request.workerName ?? 'Worker',
                          role: 'Worker',
                          profileKey: const ValueKey('view-worker-profile'),
                          messageKey: const ValueKey('message-accepted-worker'),
                          onViewProfile: onViewProfile,
                          onMessage: canMessage ? onMessage : null,
                        )
                      else
                        const BookingSectionCard(
                          child: Text('No worker assigned yet.'),
                        ),
                      const SizedBox(height: 16),
                      BookingFeeProgressCard(request: request),
                      if (request.modality.needsLocation) ...[
                        const SizedBox(height: 16),
                        BookingRouteCard(request: request),
                        const SizedBox(height: 16),
                        map ??
                            (request.isErrand &&
                                    (request.status ==
                                            ServiceRequestStatus.accepted ||
                                        request.status ==
                                            ServiceRequestStatus.ongoing)
                                ? ErrandTrackingMap(
                                    request: request,
                                    showTimeline: false,
                                  )
                                : PostLocationMap(request: request)),
                      ],
                      const SizedBox(height: 16),
                      BookingInformationCard(
                        request: request,
                        dateLabel: dateLabel,
                      ),
                      if (applications != null) ...[
                        const SizedBox(height: 16),
                        BookingSectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Worker applications',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              applications!,
                            ],
                          ),
                        ),
                      ],
                      if (canCancel) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: saving ? null : onCancel,
                          child: const Text('Cancel request'),
                        ),
                      ],
                      if (request.status == ServiceRequestStatus.completed) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: onRate,
                          icon: const Icon(Icons.star_outline),
                          label: const Text('Rate worker'),
                        ),
                      ],
                    ],
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
