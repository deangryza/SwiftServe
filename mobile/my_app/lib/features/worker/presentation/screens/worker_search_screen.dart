import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/screens/public_profile_screen.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/client_rating_summary.dart';
import '../../../../shared/widgets/live_profile_avatar.dart';
import '../../../../shared/widgets/worker_rating_summary.dart';
import 'worker_job_details_screen.dart';

abstract interface class WorkerSearchHistoryStore {
  Future<List<String>> load(String key);
  Future<void> save(String key, List<String> searches);
  Future<void> clear(String key);
}

class _SharedPreferencesWorkerSearchHistoryStore
    implements WorkerSearchHistoryStore {
  _SharedPreferencesWorkerSearchHistoryStore()
    : _preferences = SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<String>> load(String key) async =>
      await _preferences.getStringList(key) ?? <String>[];

  @override
  Future<void> save(String key, List<String> searches) =>
      _preferences.setStringList(key, searches);

  @override
  Future<void> clear(String key) => _preferences.remove(key);
}

bool matchesWorkerSearchRequest(ServiceRequest request, String query) {
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

List<ServiceRequest> availableWorkerSearchRequests({
  required String workerId,
  required Iterable<ServiceRequest> requests,
  required Iterable<ServiceApplication> applications,
  required String query,
}) {
  final appliedRequestIds = applications
      .map((application) => application.requestId)
      .toSet();
  final matches =
      requests
          .where(
            (request) =>
                request.isAvailableToWorker(workerId) &&
                !appliedRequestIds.contains(request.id) &&
                matchesWorkerSearchRequest(request, query),
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
  return matches;
}

class WorkerSearchScreen extends StatefulWidget {
  const WorkerSearchScreen({
    super.key,
    required this.worker,
    this.historyStore,
  });

  final AppUser worker;
  final WorkerSearchHistoryStore? historyStore;

  @override
  State<WorkerSearchScreen> createState() => _WorkerSearchScreenState();
}

class _WorkerSearchScreenState extends State<WorkerSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final List<String> _recentSearches = [];
  late final WorkerSearchHistoryStore _historyStore;

  String get _storageKey =>
      'swiftserve_worker_recent_searches_${widget.worker.id}';

  @override
  void initState() {
    super.initState();
    _historyStore =
        widget.historyStore ?? _SharedPreferencesWorkerSearchHistoryStore();
    _loadRecentSearches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final saved = await _historyStore.load(_storageKey);
    if (!mounted) return;
    setState(() {
      _recentSearches
        ..clear()
        ..addAll(saved);
    });
  }

  Future<void> _saveSearch(String text) async {
    final term = text.trim();
    if (term.isEmpty) return;
    setState(() {
      _recentSearches.removeWhere(
        (item) => item.toLowerCase() == term.toLowerCase(),
      );
      _recentSearches.insert(0, term);
      if (_recentSearches.length > 8) {
        _recentSearches.removeRange(8, _recentSearches.length);
      }
      _searchController.text = term;
      _searchController.selection = TextSelection.collapsed(
        offset: term.length,
      );
    });
    await _historyStore.save(_storageKey, _recentSearches);
  }

  Future<void> _clearSearches() async {
    setState(_recentSearches.clear);
    await _historyStore.clear(_storageKey);
  }

  Future<void> _removeSearch(String search) async {
    setState(() => _recentSearches.remove(search));
    await _historyStore.save(_storageKey, _recentSearches);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : Colors.white;
    final field = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF2F2F2) : AppTheme.ink;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: text,
        leading: IconButton(
          key: const ValueKey('worker-search-back'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Search'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: Material(
                    color: field,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    child: TextField(
                      key: const ValueKey('worker-search-field'),
                      controller: _searchController,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: _saveSearch,
                      style: TextStyle(color: text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search users or services...',
                        prefixIcon: const Icon(Icons.search, size: 21),
                        suffixIcon: query.isEmpty
                            ? null
                            : Padding(
                                padding: const EdgeInsets.all(5),
                                child: IconButton.filled(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppTheme.yellow,
                                    foregroundColor: AppTheme.ink,
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 19,
                                  ),
                                ),
                              ),
                        filled: true,
                        fillColor: field,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: query.isEmpty
                      ? _buildRecentSearches()
                      : _buildSearchResults(query),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSearches() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF2F2F2) : AppTheme.ink;
    final muted = dark ? const Color(0xFFAAAAAA) : AppTheme.muted;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent searches',
                style: TextStyle(
                  color: text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _recentSearches.isEmpty ? null : _clearSearches,
              child: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_recentSearches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              'Your recent searches will appear here.',
              style: TextStyle(color: muted),
            ),
          ),
        for (final search in _recentSearches)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: surface,
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              leading: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppTheme.softYellow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.search, size: 18),
              ),
              title: Text(search, style: TextStyle(color: text, fontSize: 13)),
              trailing: IconButton(
                tooltip: 'Remove $search',
                onPressed: () => _removeSearch(search),
                icon: Icon(Icons.close, size: 17, color: muted),
              ),
              onTap: () {
                _searchController.text = search;
                _searchController.selection = TextSelection.collapsed(
                  offset: search.length,
                );
                setState(() {});
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSearchResults(String query) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('public_profiles')
          .limit(100)
          .snapshots(),
      builder: (context, clientSnapshot) {
        if (clientSnapshot.hasError) {
          return const _SearchMessage(
            message: 'Could not search users right now.',
          );
        }
        return StreamBuilder<List<ServiceRequest>>(
          stream: ServiceRequestRepository().watchAvailable(),
          builder: (context, requestSnapshot) {
            if (requestSnapshot.hasError) {
              return const _SearchMessage(
                message: 'Could not search services right now.',
              );
            }
            return StreamBuilder<List<ServiceApplication>>(
              stream: ServiceRequestRepository().watchWorkerApplications(
                widget.worker.id,
              ),
              builder: (context, applicationSnapshot) {
                if (applicationSnapshot.hasError) {
                  return const _SearchMessage(
                    message: 'Could not check your applications right now.',
                  );
                }
                if (!clientSnapshot.hasData ||
                    !requestSnapshot.hasData ||
                    !applicationSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = clientSnapshot.data!.docs
                    .where(
                      (document) =>
                          document.id != widget.worker.id &&
                          publicProfileMatchesQuery(document.data(), query),
                    )
                    .toList(growable: false);
                final services = availableWorkerSearchRequests(
                  workerId: widget.worker.id,
                  requests: requestSnapshot.data!,
                  applications: applicationSnapshot.data!,
                  query: query,
                );
                if (users.isEmpty && services.isEmpty) {
                  return const _SearchMessage(
                    message: 'No matching users or services found.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    if (users.isNotEmpty) ...[
                      const _ResultsTitle(title: 'Users'),
                      const SizedBox(height: 10),
                      for (final user in users) ...[
                        _UserResult(
                          id: user.id,
                          data: user.data(),
                          onOpen: () async {
                            await _saveSearch(_searchController.text);
                            if (!context.mounted) return;
                            final role = profileHasRole(user.data(), 'worker')
                                ? PublicProfileRole.worker
                                : PublicProfileRole.client;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(
                                  userId: user.id,
                                  role: role,
                                  initialData: user.data(),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (services.isNotEmpty) ...[
                      if (users.isNotEmpty) const SizedBox(height: 18),
                      const _ResultsTitle(title: 'Services'),
                      const SizedBox(height: 10),
                      for (final request in services) ...[
                        _ServiceResult(
                          request: request,
                          onOpen: () async {
                            await _saveSearch(_searchController.text);
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkerJobDetailsScreen(
                                  request: request,
                                  worker: widget.worker,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ResultsTitle extends StatelessWidget {
  const _ResultsTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
  );
}

class _UserResult extends StatelessWidget {
  const _UserResult({
    required this.id,
    required this.data,
    required this.onOpen,
  });

  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final name = (data['fullName'] ?? 'SwiftServe user').toString();
    final location = (data['location'] ?? 'Location not provided').toString();
    final worker = profileHasRole(data, 'worker');
    return Card(
      child: ListTile(
        onTap: onOpen,
        leading: LiveProfileAvatar(userId: id, fallbackName: name),
        title: Text(name),
        subtitle: worker
            ? WorkerRatingBuilder(
                workerId: id,
                builder: (context, summary) => Text(
                  'Worker · $location · ★ ${summary.displayAverage}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : ClientRatingBuilder(
                clientId: id,
                builder: (context, summary) => Text(
                  'Client · $location · ★ ${summary.displayAverage}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _ServiceResult extends StatelessWidget {
  const _ServiceResult({required this.request, required this.onOpen});

  final ServiceRequest request;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onOpen,
      leading: const CircleAvatar(
        backgroundColor: AppTheme.softYellow,
        foregroundColor: AppTheme.ink,
        child: Icon(Icons.work_outline_rounded),
      ),
      title: Text(request.title),
      subtitle: Text(
        '${request.clientName} · ${request.category}\n'
        '${request.location} · ₱${request.budget.toStringAsFixed(0)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
