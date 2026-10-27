import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../../../shared/widgets/simple_back_button.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/job_location.dart';
import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/screens/public_profile_screen.dart';
import '../../../../shared/widgets/action_confirmation_dialog.dart';
import '../../../../shared/services/device_location_service.dart';
import '../../../../shared/services/rider_location_service.dart';
import '../../../../shared/services/road_route_service.dart';
import '../../../../shared/utils/job_location_utils.dart';
import '../../../../shared/utils/navigation_links.dart';
import '../../../../shared/utils/reroute_throttle.dart';
import '../../../../shared/widgets/errand_map_layers.dart';
import '../../../../shared/widgets/live_profile_avatar.dart';
import '../../../../shared/widgets/open_street_map_layers.dart';
import '../../../client/presentation/screens/client_sections.dart';
import 'worker_verification_screen.dart';

const _detailsYellow = AppTheme.yellow;
const _detailsCream = Color(0xFFFFFFFF);
const _detailsInk = AppTheme.ink;

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

class _WorkerJobDetailsScreenState extends State<WorkerJobDetailsScreen>
    with WidgetsBindingObserver {
  static const _locationService = DeviceLocationService();
  bool _savingAction = false;
  bool _savingReview = false;
  bool _savingReport = false;
  bool _loadingLocation = true;
  JobCoordinate? _workerPosition;
  ExactJobLocation? _exactLocation;
  DeviceLocationException? _locationError;
  // Keeps the worker's own marker moving on errand maps.
  StreamSubscription<Position>? _positionUpdates;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLocationContext();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionUpdates?.cancel();
    super.dispose();
  }

  // GPS only runs while the screen is in the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_workerPosition != null) _followPosition();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _positionUpdates?.cancel();
      _positionUpdates = null;
    }
  }

  void _followPosition() {
    if (!widget.request.isErrand || _positionUpdates != null) return;
    _positionUpdates =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((position) {
          if (!mounted) return;
          setState(
            () => _workerPosition = JobCoordinate(
              latitude: position.latitude,
              longitude: position.longitude,
            ),
          );
        }, onError: (_) {});
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
      if (mounted) {
        setState(() => _workerPosition = position);
        _followPosition();
      }
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
      headsToDropoff:
          request.status == ServiceRequestStatus.ongoing &&
          (request.errandStage?.headsToDropoff ?? false),
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

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    final confirmed = await showActionConfirmation(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
    );
    if (!confirmed) return;
    await _runAction(action, successMessage);
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

      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final reviewerName =
          (profile.data()?['fullName'] ?? widget.worker.fullName)
              .toString()
              .trim();
      if (!mounted) return;
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
        'workerName': reviewerName,
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
        'type': 'reviewReceived',
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

  Widget _buildDetailsBody(
    ServiceRequest request,
    _WorkerDetailsPalette palette,
  ) {
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
          builder: (_) => WorkerVerificationScreen(profile: widget.worker),
        ),
      ),
      onApply: () => _confirmAndRun(
        title: 'Apply for this job?',
        message:
            'Are you sure you want to apply for ${request.title}? The client will be able to review your profile.',
        confirmLabel: 'Apply',
        icon: Icons.send_outlined,
        action: () => ServiceRequestRepository().apply(
          request: request,
          worker: widget.worker,
        ),
        successMessage: 'Application sent.',
      ),
      onStart: () => _confirmAndRun(
        title: 'Start this booking?',
        message:
            'Confirm that you are starting ${request.title}. The booking status will be visible to the client.',
        confirmLabel: request.isErrand ? 'Start errand' : 'Start work',
        icon: Icons.play_arrow_rounded,
        action: () => ServiceRequestRepository().transition(
          requestId: request.id,
          from: ServiceRequestStatus.accepted,
          to: ServiceRequestStatus.ongoing,
          workerId: widget.worker.id,
        ),
        successMessage: request.isErrand ? 'Errand started.' : 'Work started.',
      ),
      onAdvanceStage: (stage) => _runAction(
        () => ServiceRequestRepository().advanceErrandStage(
          requestId: request.id,
          from: stage,
          workerId: widget.worker.id,
        ),
        'Customer updated: ${stage.next?.label ?? ''}.',
      ),
      onComplete: () => _confirmAndRun(
        title: 'Complete this booking?',
        message:
            'Are you sure the work for ${request.title} is complete? This will move the booking to completed.',
        confirmLabel: request.isErrand ? 'Mark delivered' : 'Mark complete',
        icon: Icons.task_alt_rounded,
        action: () => ServiceRequestRepository().transition(
          requestId: request.id,
          from: ServiceRequestStatus.ongoing,
          to: ServiceRequestStatus.completed,
          workerId: widget.worker.id,
        ),
        successMessage: request.isErrand
            ? 'Errand delivered.'
            : 'Booking marked completed.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _WorkerDetailsPalette(
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Firebase.apps.isEmpty
                ? _buildDetailsBody(widget.request, palette)
                : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                      final request = ServiceRequest.fromDocument(
                        snapshot.data!,
                      );
                      return _buildDetailsBody(request, palette);
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
    return Column(
      children: [
        SizedBox(
          height: 168,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    SimpleBackButton(
                      key: const ValueKey('worker-booking-back'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Booking Details',
                      style: TextStyle(
                        color: palette.text,
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
                  radius: 32,
                  backgroundColor: AppTheme.softYellow,
                  foregroundColor: AppTheme.ink,
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
              borderRadius: BorderRadius.zero,
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
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
                FilledButton.icon(
                  key: const ValueKey('view-client-profile'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PublicProfileScreen(
                        userId: request.clientId,
                        role: PublicProfileRole.client,
                        initialData: <String, dynamic>{
                          'fullName': request.clientName,
                          'location': request.location,
                        },
                        onReport: isAssignedWorker ? onReport : null,
                        reporting: savingReport,
                        reportLabel: 'Report client',
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.yellow,
                    foregroundColor: AppTheme.ink,
                    minimumSize: const Size.fromHeight(52),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.person_outline_rounded),
                  label: const Text('View Profile'),
                ),
                const SizedBox(height: 12),
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
      boxShadow: const [],
    ),
    child: Row(
      children: [
        LiveProfileAvatar(
          userId: request.clientId,
          fallbackName: request.clientName,
          radius: 24,
          backgroundColor: AppTheme.softYellow,
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
              AppTheme.ink,
            ),
            ServiceApplicationStatus.rejected => (
              'Application not selected',
              'The client selected another worker.',
              AppTheme.ink,
            ),
            ServiceApplicationStatus.pending => (
              'Application sent',
              'Wait for the client to choose a worker.',
              AppTheme.ink,
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
    final muted = dark ? const Color(0xFFB5B5B5) : AppTheme.muted;

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
                              color: AppTheme.muted,
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
                                        ? AppTheme.yellow
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
                                  backgroundColor: AppTheme.yellow,
                                  foregroundColor: AppTheme.ink,
                                  disabledBackgroundColor: AppTheme.softYellow,
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
    icon: const Icon(Icons.report_outlined, color: AppTheme.ink, size: 34),
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
          backgroundColor: AppTheme.ink,
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
      elevation: 0,
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
    this.headsToDropoff = false,
  });

  final _WorkerDetailsPalette palette;

  /// The worker has the items and is now going to the drop-off.
  final bool headsToDropoff;

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
  RoadRoute? _riderLeg;
  RoadRoute? _errandLeg;
  final _reroute = RerouteThrottle();
  JobCoordinate? _legFrom;

  @override
  void initState() {
    super.initState();
    _legFrom = _reroute.update(widget.workerPosition);
  }

  @override
  void didUpdateWidget(_JobLocationMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _legFrom = _reroute.update(widget.workerPosition);
    if (oldWidget.headsToDropoff != widget.headsToDropoff) _riderLeg = null;
  }

  /// Where the worker goes next: the pickup, then the drop-off.
  JobCoordinate get _nextStop => widget.headsToDropoff
      ? widget.dropoffPosition ?? widget.position
      : widget.position;

  Future<void> _openNavigation() async {
    final app = await showModalBottomSheet<NavigationApp>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Google Maps'),
              onTap: () => Navigator.pop(context, NavigationApp.googleMaps),
            ),
            ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: const Text('Waze'),
              onTap: () => Navigator.pop(context, NavigationApp.waze),
            ),
          ],
        ),
      ),
    );
    if (app == null) return;
    var opened = false;
    for (final link in navigationLinks(
      app,
      _nextStop,
      android: defaultTargetPlatform == TargetPlatform.android,
    )) {
      try {
        opened = await launchUrl(link, mode: LaunchMode.externalApplication);
      } catch (_) {
        // The app is not installed; try the next link.
      }
      if (opened) break;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open a navigation app.')),
      );
    }
  }

  void _setRiderLeg(RoadRoute route) {
    if (mounted) setState(() => _riderLeg = route);
  }

  void _setErrandLeg(RoadRoute route) {
    if (mounted) setState(() => _errandLeg = route);
  }

  Widget _tripLeg({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  String get _distanceLabel {
    if (widget.loadingDistance) return 'Finding your distance…';
    final origin = widget.workerPosition;
    if (origin == null) return 'Distance unavailable';
    return formatDistance(
      distanceMetersBetween(origin, _nextStop),
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
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      textStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: widget.palette.text),
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
                    // Refit once the worker's position arrives so their leg
                    // to the pickup is in view too.
                    key: ValueKey(
                      '${widget.position.latitude},${widget.position.longitude}'
                      '|${widget.workerPosition != null}',
                    ),
                    options: MapOptions(
                      initialCenter: target,
                      initialZoom: widget.approximate ? 13 : 16,
                      initialCameraFit: dropoff == null
                          ? null
                          : errandCameraFit([
                              ?widget.workerPosition,
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
                          rider: widget.workerPosition,
                          routeColor: _detailsInk,
                          approximate: widget.approximate,
                          riderLegFrom: _legFrom,
                          riderToDropoff: widget.headsToDropoff,
                          onRoute: _setErrandLeg,
                          onRiderLeg: _setRiderLeg,
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
                if (dropoff != null) ...[
                  const SizedBox(height: 6),
                  _tripLeg(
                    icon: Icons.near_me_outlined,
                    color: riderLegColor,
                    label: widget.headsToDropoff
                        ? 'You to drop-off'
                        : 'You to pickup',
                    value: switch (_riderLeg) {
                      final leg? => formatRouteLeg(
                        leg.distanceMeters,
                        leg.durationSeconds,
                        approximate: widget.approximate,
                      ),
                      null => _distanceLabel,
                    },
                  ),
                  // Once the items are picked up, the worker's own leg is
                  // the rest of the errand.
                  if (!widget.headsToDropoff)
                    _tripLeg(
                      icon: Icons.route_outlined,
                      color: errandDropoffColor,
                      label: 'Pickup to drop-off',
                      value: switch (_errandLeg) {
                        final leg? => formatRouteLeg(
                          leg.distanceMeters,
                          leg.durationSeconds,
                          approximate: widget.approximate,
                        ),
                        // Straight-line distance until (or if never) routed.
                        null =>
                          '${widget.approximate ? '~' : ''}'
                              '${(distanceMetersBetween(widget.position, dropoff) / 1000).toStringAsFixed(1)} km',
                      },
                    ),
                  if (!widget.approximate) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('errand-navigate'),
                        onPressed: _openNavigation,
                        icon: const Icon(Icons.navigation_outlined),
                        label: Text(
                          widget.headsToDropoff
                              ? 'Navigate to drop-off'
                              : 'Navigate to pickup',
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    _distanceLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
      muted = dark ? const Color(0xFFB8B8B8) : AppTheme.muted;

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
