import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/widgets/live_profile_avatar.dart';

class ClientSearchScreen extends StatefulWidget {
  const ClientSearchScreen({super.key});

  @override
  State<ClientSearchScreen> createState() => _ClientSearchScreenState();
}

class _ClientSearchScreenState extends State<ClientSearchScreen> {
  final _searchController = TextEditingController();
  final _preferences = SharedPreferencesAsync();

  final List<String> _recentSearches = [];
  final _focusNode = FocusNode();

  String get _storageKey {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return 'swiftserve_recent_searches_$uid';
  }

  @override
  void initState() {
    super.initState();
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
    final saved = await _preferences.getStringList(_storageKey) ?? <String>[];

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

    await _preferences.setStringList(_storageKey, _recentSearches);
  }

  Future<void> _clearSearches() async {
    setState(_recentSearches.clear);
    await _preferences.remove(_storageKey);
  }

  Future<void> _removeSearch(String search) async {
    setState(() => _recentSearches.remove(search));
    await _preferences.setStringList(_storageKey, _recentSearches);
  }

  void _showWorkerDetails(BuildContext context, Map<String, dynamic> worker) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (worker['fullName'] ?? 'Service provider').toString(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Skills: ${_skillsText(worker['skills'])}'),
                const SizedBox(height: 8),
                Text('Location: ${worker['location'] ?? 'Not provided'}'),
              ],
            ),
          ),
        );
      },
    );
  }

  String _skillsText(dynamic skills) {
    if (skills is List) return skills.join(', ');
    if (skills is String && skills.trim().isNotEmpty) return skills;
    return 'Not provided';
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : const Color(0xFFFFF9E9);
    final field = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF2F2F2) : const Color(0xFF252525);

    return Scaffold(
      backgroundColor: const Color(0xFFFFC72C),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                Container(
                  height: 124,
                  padding: const EdgeInsets.fromLTRB(8, 30, 18, 18),
                  color: const Color(0xFFFFC72C),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: Color(0xFF252525),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Material(
                          color: field,
                          elevation: 3,
                          shadowColor: Colors.black26,
                          borderRadius: BorderRadius.circular(18),
                          child: TextField(
                            key: const ValueKey('client-search-field'),
                            controller: _searchController,
                            focusNode: _focusNode,
                            textInputAction: TextInputAction.search,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: _saveSearch,
                            style: TextStyle(color: text, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search for a service or worker...',
                              hintStyle: const TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 12,
                              ),
                              prefixIcon: const Icon(Icons.search, size: 21),
                              suffixIcon: Padding(
                                padding: const EdgeInsets.all(5),
                                child: IconButton.filled(
                                  tooltip: 'Search filters',
                                  onPressed: () {},
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFC72C),
                                    foregroundColor: const Color(0xFF252525),
                                  ),
                                  icon: const Icon(Icons.tune, size: 19),
                                ),
                              ),
                              filled: true,
                              fillColor: field,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(46),
                      ),
                    ),
                    child: query.isEmpty
                        ? _buildRecentSearches()
                        : _buildSearchResults(query),
                  ),
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
    final text = dark ? const Color(0xFFF2F2F2) : const Color(0xFF252525);
    final muted = dark ? const Color(0xFFAAAAAA) : const Color(0xFF666666);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 46, 20, 24),
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
              style: TextButton.styleFrom(foregroundColor: text),
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
            elevation: 2,
            shadowColor: Colors.black38,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              leading: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0BE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search,
                  size: 18,
                  color: Color(0xFF252525),
                ),
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
          .collection('worker_profiles')
          .where('verificationStatus', isEqualTo: 'verified')
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not search workers:\n${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final workers = snapshot.data!.docs.where((doc) {
          final data = doc.data();

          final name = (data['fullName'] ?? '').toString().toLowerCase();
          final skills = _skillsText(data['skills']).toLowerCase();
          final location = (data['location'] ?? '').toString().toLowerCase();
          final category = (data['category'] ?? '').toString().toLowerCase();

          return name.contains(query) ||
              skills.contains(query) ||
              location.contains(query) ||
              category.contains(query);
        }).toList();

        if (workers.isEmpty) {
          return const Center(child: Text('No matching workers found.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 42, 20, 24),
          itemCount: workers.length,
          itemBuilder: (context, index) {
            final worker = workers[index].data();
            final name = (worker['fullName'] ?? 'Service provider').toString();

            return Card(
              color: Theme.of(context).colorScheme.surface,
              child: ListTile(
                leading: LiveProfileAvatar(
                  userId: workers[index].id,
                  fallbackName: name,
                ),
                title: Text(name),
                subtitle: Text(
                  '${_skillsText(worker['skills'])}\n'
                  '${worker['location'] ?? 'Location not provided'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () async {
                  await _saveSearch(_searchController.text);

                  if (!context.mounted) return;
                  _showWorkerDetails(context, worker);
                },
              ),
            );
          },
        );
      },
    );
  }
}
