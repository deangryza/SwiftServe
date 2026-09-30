import 'package:flutter/material.dart';

import '../widgets/search_box.dart';
import '../widgets/recent_search_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController searchController = TextEditingController();

  List<String> recentSearches = [
    "Plumber near me",
    "House cleaning",
    "Algebra tutor",
    "Aircon repair",
  ];

  void clearHistory() {
    setState(() {
      recentSearches.clear();
    });
  }

  void addSearch(String value) {
    final search = value.trim();

    if (search.isEmpty) return;

    setState(() {
      recentSearches.remove(search);
      recentSearches.insert(0, search);
    });

    searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(),
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            /// Search Box
            SearchBox(
              controller: searchController,
              readOnly: false,
              onChanged: (_) {
                setState(() {});
              },
              onSubmitted: addSearch,
            ),

            const SizedBox(height: 25),

            /// Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Recent searches",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                GestureDetector(
                  onTap: clearHistory,
                  child: const Text(
                    "Clear",
                    style: TextStyle(
                      color: Color(0xFF2F80ED),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Expanded(
              child: recentSearches.isEmpty
                  ? const Center(
                      child: Text(
                        "No recent searches",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    )
                  : ListView.separated(
                      itemCount: recentSearches.length,

                      separatorBuilder: (context, index) {
                        return const Divider(
                          height: 1,
                          color: Color(0xFFEAEAEA),
                        );
                      },

                      itemBuilder: (context, index) {
                        return RecentSearchTile(title: recentSearches[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
