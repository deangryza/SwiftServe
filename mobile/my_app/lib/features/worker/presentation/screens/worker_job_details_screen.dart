import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/job_location.dart';
import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/services/device_location_service.dart';
import '../../../../shared/utils/job_location_utils.dart';
import '../../../../shared/widgets/open_street_map_layers.dart';
import '../../../client/presentation/screens/client_sections.dart';
import '../widgets/legacy/job_summary_card.dart';
import 'worker_verification_screen.dart';

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
  bool _saving = false;
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

  String _dateRange(ServiceRequest request) {
    String format(DateTime date) => '${date.month}/${date.day}/${date.year}';
    final from = request.scheduleFrom ?? request.schedule;
    final to = request.scheduleTo ?? from;
    if (from == null) return 'Flexible';
    if (to == null || DateUtils.isSameDay(from, to)) return format(from);
    return '${format(from)} – ${format(to)}';
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openClientChat() async {
    final request = widget.request;
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

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final canAcceptJobs =
        widget.worker.verificationStatus == VerificationStatus.verified;
    final isAssignedWorker = request.workerId == widget.worker.id;
    final displayedPosition = _exactLocation?.position ?? request.areaPosition;
    final displayedAddress = _exactLocation?.address ?? request.location;
    final isApproximate = _exactLocation == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Job details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          JobSummaryCard(
            service: request.title,
            client: request.clientName,
            location: displayedAddress,
            schedule: _dateRange(request),
            price: '₱${request.budget.toStringAsFixed(0)}',
          ),
          if (displayedPosition != null) ...[
            const SizedBox(height: 12),
            _JobLocationMapCard(
              position: displayedPosition,
              address: displayedAddress,
              approximate: isApproximate,
              workerPosition: _workerPosition,
              loadingDistance: _loadingLocation,
              locationError: _locationError,
              onRecoverLocation: _recoverLocation,
            ),
          ],
          const SizedBox(height: 12),
          Text(request.description),
          const SizedBox(height: 24),
          if (request.status == ServiceRequestStatus.pending && !canAcceptJobs)
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      WorkerVerificationScreen(profile: widget.worker),
                ),
              ),
              child: const Text('Verify to apply'),
            ),
          if (request.status == ServiceRequestStatus.pending && canAcceptJobs)
            StreamBuilder<ServiceApplication?>(
              stream: ServiceRequestRepository().watchApplication(
                requestId: request.id,
                workerId: widget.worker.id,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Could not load application: ${snapshot.error}');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final application = snapshot.data;
                if (application == null) {
                  return FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _run(
                            () => ServiceRequestRepository().apply(
                              request: request,
                              worker: widget.worker,
                            ),
                          ),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Apply for this request'),
                  );
                }
                final accepted =
                    application.status == ServiceApplicationStatus.accepted;
                final rejected =
                    application.status == ServiceApplicationStatus.rejected;
                return Card(
                  color: accepted
                      ? Colors.green.shade50
                      : rejected
                      ? Colors.red.shade50
                      : Colors.orange.shade50,
                  child: ListTile(
                    leading: Icon(
                      accepted
                          ? Icons.check_circle_outline
                          : rejected
                          ? Icons.cancel_outlined
                          : Icons.schedule_outlined,
                    ),
                    title: Text(
                      accepted
                          ? 'Your application was accepted'
                          : rejected
                          ? 'Another worker was selected'
                          : 'Application sent',
                    ),
                    subtitle: Text(
                      accepted
                          ? 'This request is now in My jobs.'
                          : rejected
                          ? 'You were not selected for this request.'
                          : 'Wait for the client to choose a worker.',
                    ),
                  ),
                );
              },
            ),
          if (isAssignedWorker &&
              request.status != ServiceRequestStatus.pending &&
              request.status != ServiceRequestStatus.cancelled) ...[
            FilledButton.icon(
              onPressed: _openClientChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Message client'),
            ),
            const SizedBox(height: 10),
          ],
          if (isAssignedWorker &&
              request.status == ServiceRequestStatus.accepted)
            FilledButton(
              onPressed: _saving
                  ? null
                  : () => _run(
                      () => ServiceRequestRepository().transition(
                        requestId: request.id,
                        from: ServiceRequestStatus.accepted,
                        to: ServiceRequestStatus.ongoing,
                        workerId: widget.worker.id,
                      ),
                    ),
              child: const Text('Start work'),
            ),
          if (isAssignedWorker &&
              request.status == ServiceRequestStatus.ongoing)
            FilledButton(
              onPressed: _saving
                  ? null
                  : () => _run(
                      () => ServiceRequestRepository().transition(
                        requestId: request.id,
                        from: ServiceRequestStatus.ongoing,
                        to: ServiceRequestStatus.completed,
                        workerId: widget.worker.id,
                      ),
                    ),
              child: const Text('Mark completed'),
            ),
        ],
      ),
    );
  }
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
  });

  final JobCoordinate position;
  final String address;
  final bool approximate;
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
    final error = widget.locationError;
    final requiresSettings =
        error?.failure == DeviceLocationFailure.serviceDisabled ||
        error?.failure == DeviceLocationFailure.permissionPermanentlyDenied;
    return Card(
      clipBehavior: Clip.antiAlias,
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
                    Icon(
                      widget.approximate
                          ? Icons.location_searching_outlined
                          : Icons.location_on_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.approximate
                            ? 'Approximate service area'
                            : 'Exact job location',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(widget.address),
                const SizedBox(height: 6),
                Text(
                  _distanceLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
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
