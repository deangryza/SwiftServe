import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/job_location.dart';
import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/screens/reviews_screen.dart';
import '../../../../shared/services/device_location_service.dart';
import '../../../../shared/services/rider_location_service.dart';
import '../../../../shared/utils/job_location_utils.dart';
import '../../../../shared/widgets/client_rating_summary.dart';
import '../../../../shared/widgets/errand_map_layers.dart';
import '../../../../shared/widgets/live_profile_avatar.dart';
import '../../../../shared/widgets/open_street_map_layers.dart';
import '../../../client/presentation/screens/client_sections.dart';
import 'worker_verification_screen.dart';

const _detailsYellow = Color(0xFFFFC72C);
const _detailsCream = Color(0xFFFFF9E9);
const _detailsInk = Color(0xFF242424);

class WorkerJobDetailsScreen extends StatefulWidget {
  const WorkerJobDetailsScreen({
    super.key,
    required this.request,
    required this.worker,
  });

  final ServiceRequest request;
  final AppUser worker;

  @override
  State<WorkerJobDetailsScreen> createState() => _WorkerJobDetailsScreenState();
}

class _WorkerJobDetailsScreenState extends State<WorkerJobDetailsScreen> {
  static const _locationService = DeviceLocationService();
  bool _savingAction = false;
  bool _savingReview = false;
  bool _savingReport = false;
  bool _loadingLocation = true;
  JobCoordinate? _workerPosition;
  ExactJobLocation? _exactLocation;
  DeviceLocationException? _locationError;

  @override
  void initState() {
    super.initState();
    _loadLocationContext();
  }

  Future<void> _loadLocationContext() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });

    final request = widget.request;
    // Online jobs have no place to measure distance to.
    if (!request.modality.needsLocation) {
      setState(() => _loadingLocation = false);
      return;
    }
    final canReadExact =
        request.workerId == widget.worker.id &&
        request.status != ServiceRequestStatus.pending &&
        request.status != ServiceRequestStatus.cancelled;

    if (canReadExact) {
      try {
        final exact = await ServiceRequestRepository().getExactLocation(
          request.id,
        );
        if (mounted) setState(() => _exactLocation = exact);
      } catch (_) {
        // Legacy jobs and temporarily unavailable private documents retain the
        // approximate public location rather than blocking the job workflow.
      }
    }

    try {
      final position = await _locationService.currentPosition();
      if (mounted) setState(() => _workerPosition = position);
    } on DeviceLocationException catch (error) {
      if (mounted) setState(() => _locationError = error);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _recoverLocation() async {
    final error = _locationError;
    if (error != null &&
        (error.failure == DeviceLocationFailure.serviceDisabled ||
            error.failure ==
                DeviceLocationFailure.permissionPermanentlyDenied)) {
      await _locationService.openRecoverySettings(error.failure);
      return;
    }
    await _loadLocationContext();
  }

  Widget? _locationCard(ServiceRequest request, _WorkerDetailsPalette palette) {
    if (!request.modality.needsLocation) return null;
    final position = _exactLocation?.position ?? request.areaPosition;
    if (position == null) return null;
    return _JobLocationMapCard(
      position: position,
      address: _exactLocation?.address ?? request.location,
      approximate: _exactLocation == null,
      dropoffPosition: request.isErrand
          ? _exactLocation?.dropoffPosition ?? request.dropoffAreaPosition
          : null,
      dropoffAddress: _exactLocation?.dropoffAddress ?? request.dropoffLocation,
      workerPosition: _workerPosition,
      loadingDistance: _loadingLocation,
      locationError: _locationError,
      onRecoverLocation: _recoverLocation,
      palette: palette,
    );
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_savingAction) return;
    setState(() => _savingAction = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _savingAction = false);
    }
  }

  Future<void> _openClientChat(ServiceRequest request) async {
    final pairConversationId = conversationIdFor(
      clientId: request.clientId,
      workerId: widget.worker.id,
    );
    final pairConversation = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(pairConversationId)
        .get();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientChatScreen(
          conversationId: pairConversation.exists
              ? pairConversationId
              : request.id,
          otherPersonName: request.clientName,
        ),
      ),
    );
  }

  Future<void> _reportClient(ServiceRequest request) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || request.workerId != user.uid || _savingReport) return;
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
      final report = await showDialog<_ClientReport>(
        context: context,
        builder: (_) => _ClientReportDialog(clientName: request.clientName),
      );
      if (report == null || !mounted) return;
      setState(() => _savingReport = true);
      await reportReference.set({
        'requestId': request.id,
        'reporterId': user.uid,
        'reportedUserId': request.clientId,
        'reportedUserName': request.clientName,
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

  Future<void> _rateClient(ServiceRequest request) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null ||
        request.workerId != user.uid ||
        request.status != ServiceRequestStatus.completed ||
        _savingReview) {
      return;
    }

    final reviewReference = FirebaseFirestore.instance
        .collection('client_reviews')
        .doc(request.id);
    try {
      final existingReview = await reviewReference.get();
      if (!mounted) return;
      if (existingReview.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already reviewed this client.')),
        );
        return;
      }

      final review = await showDialog<_ClientReview>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ClientReviewDialog(clientName: request.clientName),
      );
      if (review == null || !mounted) return;

      setState(() => _savingReview = true);
      final notificationReference = FirebaseFirestore.instance
          .collection('notifications')
          .doc();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(reviewReference, {
        'requestId': request.id,
        'workerId': user.uid,
        'clientId': request.clientId,
        'clientName': request.clientName,
        'rating': review.rating,
        'comment': review.comment,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(notificationReference, {
        'recipientId': request.clientId,
        'senderId': user.uid,
        'requestId': request.id,
        'title': 'New review received',
        'body':
            '${widget.worker.fullName} rated you ${review.rating} out of 5 stars.',
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

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerDetailsPalette(
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    return Scaffold(
      backgroundColor: _detailsYellow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .doc(widget.request.id)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _DetailsMessage(
                    message: 'Could not load booking: ${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.data!.exists) {
                  return const _DetailsMessage(
                    message: 'This booking no longer exists.',
                  );
                }
                final request = ServiceRequest.fromDocument(snapshot.data!);
                return _WorkerBookingDetailsBody(
                  request: request,
                  worker: widget.worker,
                  palette: palette,
                  locationCard: _locationCard(request, palette),
                  savingAction: _savingAction,
                  savingReview: _savingReview,
                  savingReport: _savingReport,
                  onMessage: () => _openClientChat(request),
                  onRateClient: () => _rateClient(request),
                  onReport: () => _reportClient(request),
                  onVerify: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          WorkerVerificationScreen(profile: widget.worker),
                    ),
                  ),
                  onApply: () => _runAction(
                    () => ServiceRequestRepository().apply(
                      request: request,
                      worker: widget.worker,
                    ),
                    'Application sent.',
                  ),
                  onStart: () => _runAction(
                    () => ServiceRequestRepository().transition(
                      requestId: request.id,
                      from: ServiceRequestStatus.accepted,
                      to: ServiceRequestStatus.ongoing,
                      workerId: widget.worker.id,
                    ),
                    request.isErrand ? 'Errand started.' : 'Work started.',
                  ),
                  onAdvanceStage: (stage) => _runAction(
                    () => ServiceRequestRepository().advanceErrandStage(
                      requestId: request.id,
                      from: stage,
                      workerId: widget.worker.id,
                    ),
                    'Customer updated: ${stage.next?.label ?? ''}.',
                  ),
                  onComplete: () => _runAction(
                    () => ServiceRequestRepository().transition(
                      requestId: request.id,
                      from: ServiceRequestStatus.ongoing,
                      to: ServiceRequestStatus.completed,
                      workerId: widget.worker.id,
                    ),
                    request.isErrand
                        ? 'Errand delivered.'
                        : 'Booking marked completed.',
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerBookingDetailsBody extends StatelessWidget {
  const _WorkerBookingDetailsBody({
    required this.request,
    required this.worker,
    required this.palette,
    required this.savingAction,
    required this.savingReview,
    required this.savingReport,
    required this.onMessage,
    required this.onRateClient,
    required this.onReport,
    required this.onVerify,
    required this.onApply,
    required this.onStart,
    required this.onAdvanceStage,
    required this.onComplete,
    this.locationCard,
  });

  final ServiceRequest request;
  final AppUser worker;
  final _WorkerDetailsPalette palette;
  final Widget? locationCard;
  final bool savingAction;
  final bool savingReview;
  final bool savingReport;
  final VoidCallback onMessage;
  final VoidCallback onRateClient;
  final VoidCallback onReport;
  final VoidCallback onVerify;
  final VoidCallback onApply;
  final VoidCallback onStart;
  final ValueChanged<ErrandStage> onAdvanceStage;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final isAssignedWorker = request.workerId == worker.id;
    final sharesLocation =
        request.isErrand &&
        isAssignedWorker &&
        request.status == ServiceRequestStatus.ongoing;
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
                        Material(
                          color: const Color(0xFFFFF7D9),
                          shape: const CircleBorder(),
                          child: IconButton(
                            key: const ValueKey('worker-booking-back'),
                            onPressed: () => Navigator.pop(context),
                            constraints: const BoxConstraints.tightFor(
                              width: 38,
                              height: 38,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.arrow_back,
                              color: _detailsInk,
                              size: 19,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Booking Details',
                          style: TextStyle(
                            color: _detailsInk,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LiveProfileAvatar(
                      userId: request.clientId,
                      fallbackName: request.clientName,
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
                    _ClientSummaryCard(request: request, palette: palette),
                    const SizedBox(height: 18),
                    _JobSummaryCard(request: request, palette: palette),
                    if (locationCard != null) ...[
                      const SizedBox(height: 18),
                      locationCard!,
                    ],
                    if (sharesLocation) ...[
                      const SizedBox(height: 18),
                      _RiderSharingBanner(
                        key: ValueKey('rider-sharing-${request.id}'),
                        requestId: request.id,
                        palette: palette,
                      ),
                    ],
                    const SizedBox(height: 22),
                    _WorkerBookingActions(
                      request: request,
                      worker: worker,
                      palette: palette,
                      isAssignedWorker: isAssignedWorker,
                      saving: savingAction,
                      savingReview: savingReview,
                      onMessage: onMessage,
                      onRateClient: onRateClient,
                      onVerify: onVerify,
                      onApply: onApply,
                      onStart: onStart,
                      onAdvanceStage: onAdvanceStage,
                      onComplete: onComplete,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        _ClientProfileSheet(
          request: request,
          palette: palette,
          canContact: isAssignedWorker,
          savingReport: savingReport,
          onMessage: onMessage,
          onReport: onReport,
        ),
      ],
    );
  }
}

class _ClientSummaryCard extends StatelessWidget {
  const _ClientSummaryCard({required this.request, required this.palette});

  final ServiceRequest request;
  final _WorkerDetailsPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: palette.surface,
      border: Border.all(color: _detailsYellow, width: 1.4),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 5,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      children: [
        LiveProfileAvatar(
          userId: request.clientId,
          fallbackName: request.clientName,
          radius: 24,
          backgroundColor: const Color(0xFFFFF1C8),
          foregroundColor: _detailsInk,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.clientName,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text('Client', style: TextStyle(color: palette.muted)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              request.isErrand ? 'Delivery fee' : 'Budget',
              style: TextStyle(color: palette.muted, fontSize: 11),
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

class _JobSummaryCard extends StatelessWidget {
  const _JobSummaryCard({required this.request, required this.palette});

  final ServiceRequest request;
  final _WorkerDetailsPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x20000000),
          blurRadius: 5,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.title,
          style: TextStyle(
            color: palette.text,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        _DetailLine(
          icon: Icons.category_outlined,
          label: request.category,
          palette: palette,
        ),
        _DetailLine(
          icon: Icons.calendar_month_outlined,
          label: _dateRange(request),
          palette: palette,
        ),
        _DetailLine(
          icon: request.modality.needsLocation
              ? Icons.work_outline
              : Icons.laptop_mac_outlined,
          label: request.modality.needsLocation
              ? request.modality.label
              : 'Online · done remotely',
          palette: palette,
        ),
        if (request.isErrand) ...[
          _DetailLine(
            icon: Icons.storefront_outlined,
            label: 'Pickup: ${request.location}',
            palette: palette,
          ),
          _DetailLine(
            icon: Icons.flag_outlined,
            label: 'Drop-off: ${request.dropoffLocation ?? 'Not set'}',
            palette: palette,
          ),
          if (request.distanceKm != null)
            _DetailLine(
              icon: Icons.route_outlined,
              label: '~${request.distanceKm!.toStringAsFixed(1)} km trip',
              palette: palette,
            ),
          if (request.errandItems?.isNotEmpty ?? false)
            _DetailLine(
              icon: Icons.shopping_bag_outlined,
              label: request.errandItems!,
              palette: palette,
            ),
          if (request.itemCostEstimate != null)
            _DetailLine(
              icon: Icons.payments_outlined,
              label:
                  'Items ~₱${request.itemCostEstimate!.toStringAsFixed(0)} '
                  '(paid back on delivery)',
              palette: palette,
            ),
        ] else if (request.modality.needsLocation)
          _DetailLine(
            icon: Icons.location_on_outlined,
            label: request.location,
            palette: palette,
          ),
        _DetailLine(
          icon: Icons.info_outline,
          label:
              request.status == ServiceRequestStatus.ongoing &&
                  request.errandStage != null
              ? 'ONGOING · ${request.errandStage!.label.toUpperCase()}'
              : request.status.name.toUpperCase(),
          palette: palette,
        ),
        const SizedBox(height: 10),
        Text(
          request.description,
          style: TextStyle(color: palette.muted, height: 1.35),
        ),
      ],
    ),
  );
}

class _WorkerBookingActions extends StatelessWidget {
  const _WorkerBookingActions({
    required this.request,
    required this.worker,
    required this.palette,
    required this.isAssignedWorker,
    required this.saving,
    required this.savingReview,
    required this.onMessage,
    required this.onRateClient,
    required this.onVerify,
    required this.onApply,
    required this.onStart,
    required this.onAdvanceStage,
    required this.onComplete,
  });

  final ServiceRequest request;
  final AppUser worker;
  final _WorkerDetailsPalette palette;
  final bool isAssignedWorker;
  final ValueChanged<ErrandStage> onAdvanceStage;
  final bool saving;
  final bool savingReview;
  final VoidCallback onMessage;
  final VoidCallback onRateClient;
  final VoidCallback onVerify;
  final VoidCallback onApply;
  final VoidCallback onStart;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    if (request.status == ServiceRequestStatus.pending &&
        worker.verificationStatus != VerificationStatus.verified) {
      return _DetailsButton(
        label: 'Verify to apply',
        onPressed: onVerify,
        palette: palette,
        yellow: true,
      );
    }
    if (request.status == ServiceRequestStatus.pending) {
      return StreamBuilder<ServiceApplication?>(
        stream: ServiceRequestRepository().watchApplication(
          requestId: request.id,
          workerId: worker.id,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              'Could not load application: ${snapshot.error}',
              style: TextStyle(color: palette.text),
            );
          }
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final application = snapshot.data;
          if (application == null) {
            return _DetailsButton(
              label: saving ? 'Applying...' : 'Apply for this request',
              onPressed: saving ? null : onApply,
              palette: palette,
              yellow: true,
            );
          }
          final (title, description, color) = switch (application.status) {
            ServiceApplicationStatus.accepted => (
              'Application accepted',
              'This booking is ready for you.',
              const Color(0xFF20B978),
            ),
            ServiceApplicationStatus.rejected => (
              'Application not selected',
              'The client selected another worker.',
              const Color(0xFFE74632),
            ),
            ServiceApplicationStatus.pending => (
              'Application sent',
              'Wait for the client to choose a worker.',
              const Color(0xFFE3A500),
            ),
          };
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        description,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    if (!isAssignedWorker) return const SizedBox.shrink();
    return Column(
      children: [
        if (request.status == ServiceRequestStatus.completed) ...[
          _DetailsButton(
            key: const ValueKey('rate-completed-client'),
            label: savingReview ? 'Submitting Review...' : 'Rate your client',
            onPressed: savingReview ? null : onRateClient,
            palette: palette,
          ),
          const SizedBox(height: 12),
        ],
        _DetailsButton(
          key: const ValueKey('message-booking-client'),
          label: 'Message Client',
          onPressed: onMessage,
          palette: palette,
        ),
        if (request.status == ServiceRequestStatus.accepted) ...[
          const SizedBox(height: 12),
          _DetailsButton(
            label: saving
                ? 'Starting...'
                : request.isErrand
                ? 'Start errand'
                : 'Start work',
            onPressed: saving ? null : onStart,
            palette: palette,
            yellow: true,
          ),
        ],
        if (request.status == ServiceRequestStatus.ongoing) ...[
          const SizedBox(height: 12),
          _ongoingButton(),
        ],
      ],
    );
  }
}

extension on _WorkerBookingActions {
  Widget _ongoingButton() {
    if (!request.isErrand) {
      return _DetailsButton(
        label: saving ? 'Completing...' : 'Mark completed',
        onPressed: saving ? null : onComplete,
        palette: palette,
        yellow: true,
      );
    }
    final stage = request.errandStage;
    final next = stage?.next;
    // Errands started before stages existed go straight to delivered.
    if (stage == null || next == null) {
      return _DetailsButton(
        key: const ValueKey('errand-next-stage'),
        label: saving ? 'Updating...' : 'Mark delivered',
        onPressed: saving ? null : onComplete,
        palette: palette,
        yellow: true,
      );
    }
    return _DetailsButton(
      key: const ValueKey('errand-next-stage'),
      label: saving
          ? 'Updating...'
          : switch (next) {
              ErrandStage.pickedUp => 'Picked up items',
              _ => 'On the way to drop-off',
            },
      onPressed: saving ? null : () => onAdvanceStage(stage),
      palette: palette,
      yellow: true,
    );
  }
}

class _RiderSharingBanner extends StatefulWidget {
  const _RiderSharingBanner({
    super.key,
    required this.requestId,
    required this.palette,
  });

  final String requestId;
  final _WorkerDetailsPalette palette;

  @override
  State<_RiderSharingBanner> createState() => _RiderSharingBannerState();
}

class _RiderSharingBannerState extends State<_RiderSharingBanner>
    with WidgetsBindingObserver {
  late final _publisher = RiderLocationPublisher(requestId: widget.requestId);
  DeviceLocationException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _publisher.stop();
    super.dispose();
  }

  // Sharing only runs while the app is in the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _publisher.stop();
      if (mounted) setState(() {});
    }
  }

  Future<void> _start() async {
    try {
      await _publisher.start();
      if (mounted) setState(() => _error = null);
    } on DeviceLocationException catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Container(
      key: const ValueKey('rider-sharing-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error == null
            ? _detailsYellow.withValues(alpha: 0.18)
            : Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            error == null ? Icons.my_location : Icons.location_disabled,
            color: widget.palette.text,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error?.userMessage ??
                  (_publisher.isRunning
                      ? 'Sharing your location with the customer. Keep the app open.'
                      : 'Starting location sharing…'),
              style: TextStyle(color: widget.palette.text, fontSize: 13),
            ),
          ),
          if (error != null)
            TextButton(onPressed: _start, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ClientProfileSheet extends StatelessWidget {
  const _ClientProfileSheet({
    required this.request,
    required this.palette,
    required this.canContact,
    required this.savingReport,
    required this.onMessage,
    required this.onReport,
  });

  final ServiceRequest request;
  final _WorkerDetailsPalette palette;
  final bool canContact;
  final bool savingReport;
  final VoidCallback onMessage;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
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
            'Swipe to view client’s profile',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 28),
          LiveProfileAvatar(
            userId: request.clientId,
            fallbackName: request.clientName,
            radius: 42,
            backgroundColor: const Color(0xFFFFF1C8),
            foregroundColor: _detailsInk,
            textStyle: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            request.clientName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Client',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted),
          ),
          const SizedBox(height: 22),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('service_requests')
                .where('clientId', isEqualTo: request.clientId)
                .snapshots(),
            builder: (context, snapshot) {
              final requests = snapshot.data?.docs ?? const [];
              return Row(
                children: [
                  Expanded(
                    child: _ProfileStat(
                      value: snapshot.hasData ? '${requests.length}' : '—',
                      label: 'Jobs posted',
                      palette: palette,
                    ),
                  ),
                  Expanded(
                    child: ClientRatingBuilder(
                      clientId: request.clientId,
                      builder: (context, summary) => _ProfileStat(
                        value: summary.displayAverage,
                        label: summary.reviewCount == 1
                            ? '1 rating'
                            : '${summary.reviewCount} ratings',
                        palette: palette,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReviewsScreen(
                              userId: request.clientId,
                              reviewsFor: ReviewsFor.client,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _DetailLine(
            icon: Icons.location_on_outlined,
            label: request.placeLabel,
            palette: palette,
          ),
          _DetailLine(
            icon: Icons.handshake_outlined,
            label: canContact
                ? 'Confirmed booking client'
                : 'Client application pending',
            palette: palette,
          ),
          const SizedBox(height: 14),
          if (canContact) ...[
            _DetailsButton(
              key: const ValueKey('message-client-profile'),
              label: 'Message Client',
              onPressed: onMessage,
              palette: palette,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('report-client'),
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
                savingReport ? 'Submitting report...' : 'Report client',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ClientReview {
  const _ClientReview({required this.rating, required this.comment});

  final int rating;
  final String comment;
}

class _ClientReviewDialog extends StatefulWidget {
  const _ClientReviewDialog({required this.clientName});

  final String clientName;

  @override
  State<_ClientReviewDialog> createState() => _ClientReviewDialogState();
}

class _ClientReviewDialogState extends State<_ClientReviewDialog> {
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
    final surface = dark ? const Color(0xFF272727) : _detailsCream;
    final field = dark ? const Color(0xFF333333) : Colors.white;
    final text = dark ? const Color(0xFFF4F4F4) : _detailsInk;
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
                    color: _detailsYellow,
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
                        const Positioned(
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
                                  color: _detailsInk,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'How was your experience?',
                                maxLines: 1,
                                style: TextStyle(
                                  color: Color(0xB8242424),
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
                            key: const ValueKey('close-client-review'),
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
                                  key: ValueKey('client-rating-${index + 1}'),
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
                          key: const ValueKey('client-review-comment'),
                          controller: _commentController,
                          minLines: 3,
                          maxLines: 4,
                          maxLength: 500,
                          style: TextStyle(color: text),
                          decoration: InputDecoration(
                            hintText:
                                'Share your experience working with ${widget.clientName}...',
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
                                  foregroundColor: _detailsInk,
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
                                key: const ValueKey('submit-client-review'),
                                onPressed: _rating == 0
                                    ? null
                                    : () => Navigator.pop(
                                        context,
                                        _ClientReview(
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

class _ClientReport {
  const _ClientReport({required this.reason, required this.details});

  final String reason;
  final String details;
}

class _ClientReportDialog extends StatefulWidget {
  const _ClientReportDialog({required this.clientName});

  final String clientName;

  @override
  State<_ClientReportDialog> createState() => _ClientReportDialogState();
}

class _ClientReportDialogState extends State<_ClientReportDialog> {
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
    title: Text('Report ${widget.clientName}?'),
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
            key: const ValueKey('client-report-reason'),
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
            key: const ValueKey('client-report-details'),
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
        key: const ValueKey('submit-client-report'),
        onPressed: _reason == null
            ? null
            : () => Navigator.pop(
                context,
                _ClientReport(
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

class _DetailsButton extends StatelessWidget {
  const _DetailsButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.palette,
    this.yellow = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final _WorkerDetailsPalette palette;
  final bool yellow;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: yellow ? _detailsYellow : palette.surface,
      foregroundColor: yellow ? _detailsInk : palette.text,
      minimumSize: const Size.fromHeight(52),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
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
  final _WorkerDetailsPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        const SizedBox(width: 1),
        Icon(icon, size: 18, color: _detailsYellow),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label, style: TextStyle(color: palette.text)),
        ),
      ],
    ),
  );
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
  final _WorkerDetailsPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: onTap == null ? null : const ValueKey('client-reviews-link'),
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
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: TextStyle(color: palette.muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

class _DetailsMessage extends StatelessWidget {
  const _DetailsMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _JobLocationMapCard extends StatefulWidget {
  const _JobLocationMapCard({
    required this.position,
    required this.address,
    required this.approximate,
    required this.workerPosition,
    required this.loadingDistance,
    required this.locationError,
    required this.onRecoverLocation,
    required this.palette,
    this.dropoffPosition,
    this.dropoffAddress,
  });

  final _WorkerDetailsPalette palette;

  /// The job site, or the pickup point for errands.
  final JobCoordinate position;
  final String address;
  final bool approximate;
  final JobCoordinate? dropoffPosition;
  final String? dropoffAddress;
  final JobCoordinate? workerPosition;
  final bool loadingDistance;
  final DeviceLocationException? locationError;
  final VoidCallback onRecoverLocation;

  @override
  State<_JobLocationMapCard> createState() => _JobLocationMapCardState();
}

class _JobLocationMapCardState extends State<_JobLocationMapCard> {
  bool _mapFailed = false;
  int _mapErrorCount = 0;
  int _mapReloadVersion = 0;

  String get _distanceLabel {
    if (widget.loadingDistance) return 'Finding your distance…';
    final origin = widget.workerPosition;
    if (origin == null) return 'Distance unavailable';
    return formatDistance(
      distanceMetersBetween(origin, widget.position),
      approximate: widget.approximate,
    );
  }

  void _handleMapTileError(Object error) {
    if (_mapFailed || !mounted) return;
    _mapErrorCount += 1;
    if (_mapErrorCount < 3) return;
    setState(() => _mapFailed = true);
  }

  void _retryMap() {
    setState(() {
      _mapFailed = false;
      _mapErrorCount = 0;
      _mapReloadVersion += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = LatLng(widget.position.latitude, widget.position.longitude);
    final dropoff = widget.dropoffPosition;
    final error = widget.locationError;
    final requiresSettings =
        error?.failure == DeviceLocationFailure.serviceDisabled ||
        error?.failure == DeviceLocationFailure.permissionPermanentlyDenied;
    return Material(
      color: widget.palette.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: const Color(0x33000000),
      textStyle: TextStyle(color: widget.palette.text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 210,
            child: Stack(
              children: [
                Semantics(
                  label: widget.approximate
                      ? 'Map showing the approximate service area.'
                      : 'Map showing the exact job location.',
                  child: FlutterMap(
                    key: ValueKey(
                      '${widget.position.latitude},${widget.position.longitude}',
                    ),
                    options: MapOptions(
                      initialCenter: target,
                      initialZoom: widget.approximate ? 13 : 16,
                      initialCameraFit: dropoff == null
                          ? null
                          : errandCameraFit([
                              widget.position,
                              dropoff,
                            ], maxZoom: widget.approximate ? 14 : 16),
                      minZoom: 3,
                      maxZoom: 18,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    children: [
                      SwiftServeMapTiles(
                        key: ValueKey(_mapReloadVersion),
                        onError: (_, error, _) => _handleMapTileError(error),
                      ),
                      if (dropoff != null)
                        ...errandMapLayers(
                          pickup: widget.position,
                          dropoff: dropoff,
                          routeColor: _detailsInk,
                          approximate: widget.approximate,
                        )
                      else if (widget.approximate)
                        CircleLayer(
                          circles: [
                            publicAreaCircle(
                              widget.position,
                              Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        )
                      else
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: target,
                              width: 48,
                              height: 48,
                              alignment: Alignment.bottomCenter,
                              child: SwiftServeMapPin(
                                label: widget.approximate
                                    ? 'Approximate job location'
                                    : 'Exact job location',
                              ),
                            ),
                          ],
                        ),
                      const SwiftServeMapAttribution(),
                    ],
                  ),
                ),
                if (_mapFailed) MapUnavailableOverlay(onRetry: _retryMap),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (widget.approximate && dropoff != null)
                      const ErrandAreaBadge(pickup: true, size: 22)
                    else
                      Icon(
                        widget.approximate
                            ? Icons.location_searching_outlined
                            : Icons.location_on_outlined,
                        size: 20,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(switch ((
                        widget.approximate,
                        dropoff != null,
                      )) {
                        (true, true) => 'Approximate pickup area',
                        (false, true) => 'Pickup',
                        (true, false) => 'Approximate service area',
                        (false, false) => 'Exact job location',
                      }, style: Theme.of(context).textTheme.titleSmall),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(widget.address),
                if (dropoff != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (widget.approximate) ...[
                        const ErrandAreaBadge(pickup: false, size: 22),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          widget.approximate
                              ? 'Approximate drop-off area'
                              : 'Drop-off',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(widget.dropoffAddress ?? ''),
                ],
                const SizedBox(height: 6),
                Text(
                  _distanceLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (widget.approximate) ...[
                  const SizedBox(height: 6),
                  Text(
                    dropoff != null
                        ? "Exact addresses are shared once you're hired."
                        : "The exact address is shared once you're hired.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: widget.palette.muted,
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error.userMessage,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onRecoverLocation,
                    child: Text(
                      requiresSettings ? 'Open settings' : 'Try again',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerDetailsPalette {
  const _WorkerDetailsPalette({required bool dark})
    : background = dark ? const Color(0xFF171717) : _detailsCream,
      surface = dark ? const Color(0xFF2C2C2C) : Colors.white,
      text = dark ? const Color(0xFFF3F3F3) : _detailsInk,
      muted = dark ? const Color(0xFFB8B8B8) : const Color(0xFF737373);

  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
}

String _dateRange(ServiceRequest request) {
  String format(DateTime date) => '${date.month}/${date.day}/${date.year}';
  final from = request.scheduleFrom ?? request.schedule;
  final to = request.scheduleTo ?? from;
  if (from == null) return 'Flexible schedule';
  if (to == null || DateUtils.isSameDay(from, to)) return format(from);
  return '${format(from)} – ${format(to)}';
}
