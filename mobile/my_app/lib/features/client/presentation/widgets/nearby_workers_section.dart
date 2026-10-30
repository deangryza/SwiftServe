import 'package:flutter/material.dart';

import '../../../../shared/models/discovered_worker.dart';
import '../../../../shared/repositories/worker_discovery_repository.dart';
import '../../../../shared/screens/public_profile_screen.dart';
import '../../../../shared/services/worker_discovery_service.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/live_profile_avatar.dart';
import '../screens/client_sections.dart';

PublicProfileScreen discoveredWorkerProfile(DiscoveredWorker worker) =>
    PublicProfileScreen(
      userId: worker.id,
      role: PublicProfileRole.worker,
      initialData: worker.data,
    );

ClientChatScreen discoveredWorkerChat(
  DiscoveredWorker worker,
  WorkerConversation conversation,
) => ClientChatScreen(
  conversationId: conversation.id,
  otherPersonName: worker.name,
);

String _workerServices(DiscoveredWorker worker) {
  final details = [
    if ((worker.data['category'] ?? '').toString().trim().isNotEmpty)
      worker.data['category'].toString(),
    ...profileSkills(worker.data['skills']),
  ].join(' · ');
  return details.isEmpty ? 'Service details not provided' : details;
}

class NearbyWorkersSection extends StatefulWidget {
  const NearbyWorkersSection({
    super.key,
    required this.clientId,
    this.service,
    this.onViewProfile,
    this.onOpenChat,
  });
  final String? clientId;
  final WorkerDiscoveryService? service;
  final ValueChanged<DiscoveredWorker>? onViewProfile;
  final void Function(DiscoveredWorker, WorkerConversation)? onOpenChat;

  @override
  State<NearbyWorkersSection> createState() => _NearbyWorkersSectionState();
}

class _NearbyWorkersSectionState extends State<NearbyWorkersSection> {
  WorkerDiscoveryService? _service;
  WorkerRecommendations? _recommendations;
  bool _loading = false;
  String? _error;
  String? _messagingWorker;

  @override
  void initState() {
    super.initState();
    if (widget.clientId != null) {
      _service =
          widget.service ??
          WorkerDiscoveryService(
            clientId: widget.clientId!,
            source: FirestoreWorkerDiscoverySource(),
          );
      _load();
    }
  }

  Future<void> _load({bool currentLocation = false}) async {
    if (_loading || _service == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _service!.nextBatch(
        useCurrentLocation: currentLocation,
      );
      if (mounted) setState(() => _recommendations = results);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load workers. Check your connection and try Refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _view(DiscoveredWorker worker) {
    FocusScope.of(context).unfocus();
    if (widget.onViewProfile != null) {
      widget.onViewProfile!(worker);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => discoveredWorkerProfile(worker)),
    );
  }

  Future<void> _message(DiscoveredWorker worker) async {
    if (_messagingWorker != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _messagingWorker = worker.id);
    try {
      final conversation = await _service!.conversationFor(worker.id);
      if (!mounted) return;
      if (conversation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Messaging is available after a worker accepts your job. No existing conversation was found.',
            ),
          ),
        );
        return;
      }
      if (widget.onOpenChat != null) {
        widget.onOpenChat!(worker, conversation);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => discoveredWorkerChat(worker, conversation),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this conversation. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _messagingWorker = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workers = _recommendations?.workers ?? const <DiscoveredWorker>[];
    final suggestions = workers.isNotEmpty && !workers.first.isNearby;
    return Column(
      key: const ValueKey('nearby-workers-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Nearby Workers',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('refresh-worker-recommendations'),
              onPressed: _loading || _service == null ? null : () => _load(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        if (widget.clientId == null)
          const Text('Sign in as a client to discover workers.')
        else ...[
          const Text(
            'Within 10 km · Nearest discovered workers first',
            style: TextStyle(fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : () => _load(currentLocation: true),
              icon: const Icon(Icons.my_location_outlined, size: 18),
              label: const Text('Use current location'),
            ),
          ),
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Finding workers…'),
          ],
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          if (_recommendations != null) ...[
            Text(
              _recommendations!.locationMessage,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (suggestions) ...[
              Text(
                'Suggested Workers',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'No more confirmed nearby workers in the loaded results. These suggestions may be farther away.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
            ],
            if (workers.isEmpty && !_loading)
              const Text(
                'No eligible workers found in this page. Try Refresh to discover more.',
              ),
            for (final worker in workers)
              Card(
                key: ValueKey('recommended-worker-${worker.id}'),
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: theme.dividerColor),
                ),
                child: InkWell(
                  onTap: () => _view(worker),
                  borderRadius: BorderRadius.circular(15),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            LiveProfileAvatar(
                              userId: worker.id,
                              fallbackName: worker.name,
                              fallbackPhotoBase64:
                                  (worker.data['photoBase64'] ?? '').toString(),
                              radius: 23,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    worker.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    _workerServices(worker),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          worker.publicLocationLabel,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${worker.isNearby ? 'Nearby' : 'Suggested'} · ${worker.distanceLabel}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: ValueKey(
                              'message-recommended-worker-${worker.id}',
                            ),
                            onPressed: _messagingWorker != null
                                ? null
                                : () => _message(worker),
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  theme.brightness == Brightness.dark
                                  ? AppTheme.yellow
                                  : AppTheme.ink,
                              minimumSize: const Size(88, 44),
                            ),
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                            ),
                            label: Text(
                              _messagingWorker == worker.id
                                  ? 'Opening…'
                                  : 'Message',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ],
    );
  }
}
