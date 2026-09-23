import 'package:flutter/material.dart';
import 'post_request_screen.dart';
import 'client_sections.dart';
import 'client_search_screen.dart';

class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 700;

            return Center(
              child: Container(
                width: isDesktop ? 430 : double.infinity,
                height: isDesktop
                    ? constraints.maxHeight
                    : double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: isDesktop
                      ? BorderRadius.circular(20)
                      : BorderRadius.zero,
                ),
                child: Column(
                  children: [
                    // Main content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          18,
                          20,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // -----------------------------
                            // GREETING
                            // -----------------------------
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'Good day, User',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF202124),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Malolos City · 12 workers nearby',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF7B8190),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Notification
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        // Notifications later
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 36,
                                      ),
                                      icon: const Icon(
                                        Icons.notifications,
                                        size: 25,
                                        color: Color(0xFF202124),
                                      ),
                                    ),

                                    Positioned(
                                      right: 1,
                                      top: 1,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF5A5F),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 25),

                            // -----------------------------
                            // SEARCH BAR
                            // -----------------------------
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const ClientSearchScreen(),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(13),
                                child: Container(
                                  height: 46,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F3F5),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.search,
                                        size: 21,
                                        color: Color(0xFF9CA1AB),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Search for a service or worker...',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF9CA1AB),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
),

                            const SizedBox(height: 25),

                            // -----------------------------
                            // CATEGORIES
                            // -----------------------------
                            const Text(
                              'Categories',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF202124),
                              ),
                            ),

                            const SizedBox(height: 13),

                            GridView.count(
                              crossAxisCount: 3,
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1.0,
                              children: [
                                categoryCard(
                                  icon: Icons.home_outlined,
                                  title: 'Home\nservices',
                                  iconColor: const Color(0xFFFF6B35),
                                ),

                                categoryCard(
                                  icon: Icons.menu_book_outlined,
                                  title: 'Academic\nhelp',
                                  iconColor: const Color(0xFF13B981),
                                ),

                                categoryCard(
                                  icon: Icons.build_outlined,
                                  title: 'Repairs',
                                  iconColor: const Color(0xFF64748B),
                                ),

                                categoryCard(
                                  icon: Icons.pedal_bike_outlined,
                                  title: 'Errands',
                                  iconColor: const Color(0xFFEC4899),
                                ),

                                categoryCard(
                                  icon: Icons.auto_awesome_outlined,
                                  title: 'Cleaning',
                                  iconColor: const Color(0xFF2563EB),
                                ),

                                categoryCard(
                                  icon: Icons.content_cut_outlined,
                                  title: 'Beauty',
                                  iconColor: const Color(0xFF8B5CF6),
                                ),
                              ],
                            ),

                            const SizedBox(height: 9),

                            // -----------------------------
                            // OTHER SERVICES
                            // -----------------------------
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: OutlinedButton(
                                onPressed: () {
                                  // Other services later
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFFF8F9FB),
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.more_horiz,
                                      size: 18,
                                      color: Color(0xFF7B8190),
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'Other services',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF596273),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 15),

                            // -----------------------------
                            // POST REQUEST BUTTON
                            // -----------------------------
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const PostRequestScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF17191D),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      size: 20,
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'Post what you need help',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 26),

                            // -----------------------------
                            // COMMUNITY REQUESTS
                            // -----------------------------
                            const Text(
                              'Community requests',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF202124),
                              ),
                            ),

                            const SizedBox(height: 13),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(13),
                                border: Border.all(
                                  color: const Color(0xFFE4E7EC),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  // User row
                                  Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFE9D5FF),
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          'LR',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight:
                                                FontWeight.w600,
                                            color:
                                                Color(0xFF7C3AED),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 9),

                                      const Expanded(
                                        child: Text(
                                          'Lia R.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w600,
                                          ),
                                        ),
                                      ),

                                      const Text(
                                        '5 min ago',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color:
                                              Color(0xFF9CA1AB),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 11),

                                  const Text(
                                    '"Anyone available for motorcycle\n'
                                    'delivery?"',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.45,
                                      color: Color(0xFF3F4652),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // -----------------------------
                    // BOTTOM NAVIGATION
                    // -----------------------------
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(
                            color: Color(0xFFEAECEF),
                          ),
                        ),
                      ),
                      child: BottomNavigationBar(
                        currentIndex: 0,
                        onTap: (index) {
                           if (index == 0) return; // Already on Home

                              final screens = <Widget>[
                                const ClientHistoryScreen(),
                                const ClientMessagesScreen(),
                                const ClientProfileScreen(),
                              ];
                              
                              Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => screens[index - 1],
                              ),
                            );
                        },
                        backgroundColor: Colors.white,
                        elevation: 0,
                        type: BottomNavigationBarType.fixed,
                        selectedItemColor:
                            const Color(0xFF2563EB),
                        unselectedItemColor:
                            const Color(0xFF89919F),
                        selectedFontSize: 10,
                        unselectedFontSize: 10,
                        showUnselectedLabels: true,
                        items: const [
                          BottomNavigationBarItem(
                            icon: Icon(
                              Icons.home_outlined,
                            ),
                            activeIcon: Icon(
                              Icons.home,
                            ),
                            label: 'Home',
                          ),

                          BottomNavigationBarItem(
                            icon: Icon(
                              Icons.history,
                            ),
                            label: 'History',
                          ),

                          BottomNavigationBarItem(
                            icon: Icon(
                              Icons.chat_bubble_outline,
                            ),
                            label: 'Message',
                          ),

                          BottomNavigationBarItem(
                            icon: Icon(
                              Icons.person_outline,
                            ),
                            activeIcon: Icon(
                              Icons.person,
                            ),
                            label: 'Profile',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --------------------------------------------------
  // CATEGORY CARD
  // --------------------------------------------------

  Widget categoryCard({
    required IconData icon,
    required String title,
    required Color iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 27,
            color: iconColor,
          ),

          const SizedBox(height: 7),

          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: Color(0xFF273142),
            ),
          ),
        ],
      ),
    );
  }
}