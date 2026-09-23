import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final saved =
        await _preferences.getStringList(_storageKey) ?? <String>[];

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

    await _preferences.setStringList(
      _storageKey,
      _recentSearches,
    );
  }

  Future<void> _clearSearches() async {
    setState(_recentSearches.clear);
    await _preferences.remove(_storageKey);
  }

  void _showWorkerDetails(
    BuildContext context,
    Map<String, dynamic> worker,
  ) {
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
                  (worker['fullName'] ?? 'Service provider')
                      .toString(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Skills: ${_skillsText(worker['skills'])}',
                ),
                const SizedBox(height: 8),
                Text(
                  'Location: ${worker['location'] ?? 'Not provided'}',
                ),
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                // Search header
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 15, 20, 18),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 21),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          textInputAction: TextInputAction.search,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: _saveSearch,
                          decoration: InputDecoration(
                            hintText: 'Search for a service or worker...',
                            hintStyle: const TextStyle(
                              color: Color(0xFF9098A8),
                              fontSize: 12,
                            ),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                      _focusNode.requestFocus();
                                    },
                                  ),
                            filled: true,
                            fillColor: const Color(0xFFF6F7FA),
                            contentPadding:
                                const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(11),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
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
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent searches',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: _recentSearches.isEmpty
                  ? null
                  : _clearSearches,
              child: const Text(
                'Clear',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        if (_recentSearches.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Text(
              'Your recent searches will appear here.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        for (final search in _recentSearches)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.access_time,
              size: 18,
              color: Color(0xFF929AAA),
            ),
            title: Text(
              search,
              style: const TextStyle(fontSize: 13),
            ),
            trailing: const Icon(
              Icons.north_east,
              size: 16,
              color: Color(0xFFB0B6C0),
            ),
            onTap: () {
              _searchController.text = search;
              _searchController.selection =
                  TextSelection.collapsed(
                offset: search.length,
              );
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _buildSearchResults(String query) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
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

          // Change 'worker' if your registration stores a
          // different role value, such as 'service_provider'.
          if (data['role'] != 'worker') return false;

          final name =
              (data['fullName'] ?? '').toString().toLowerCase();
          final skills =
              _skillsText(data['skills']).toLowerCase();
          final location =
              (data['location'] ?? '').toString().toLowerCase();

          return name.contains(query) ||
              skills.contains(query) ||
              location.contains(query);
        }).toList();

        if (workers.isEmpty) {
          return const Center(
            child: Text('No matching workers found.'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: workers.length,
          itemBuilder: (context, index) {
            final worker = workers[index].data();
            final name =
                (worker['fullName'] ?? 'Service provider')
                    .toString();

            return Card(
              color: Colors.white,
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline),
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
                  await _saveSearch(
                    _searchController.text,
                  );

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