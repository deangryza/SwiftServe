import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/services/client_theme_controller.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../widgets/conversation_ui.dart';
import 'client_booking_flow.dart';
import 'client_notifications_screen.dart';
import 'client_search_screen.dart';
import 'client_sections.dart';
import 'post_request_screen.dart';

class ClientDashboardView extends StatelessWidget {
  const ClientDashboardView({super.key, this.profile});

  final AppUser? profile;

  static const _yellow = Color(0xFFFFC72C);
  static const _cream = Color(0xFFFFF9E9);
  static const _ink = Color(0xFF171717);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : _cream;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF2F2F2) : _ink;
    final muted = dark ? const Color(0xFFB8B8B8) : const Color(0xFF666666);
    final name = profile?.fullName.trim();

    return ClientTabSwipeRegion(
      currentIndex: 0,
      onSwipeToIndex: (index) => _openTab(context, index),
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Greeting(
                            profile: profile,
                            name: name == null || name.isEmpty
                                ? 'Client'
                                : name,
                            textColor: text,
                            surface: surface,
                          ),
                          const SizedBox(height: 16),
                          _SearchButton(
                            surface: surface,
                            textColor: muted,
                            onTap: () =>
                                _open(context, const ClientSearchScreen()),
                          ),
                          const SizedBox(height: 18),
                          _RequestBanner(
                            onPostRequest: () =>
                                _open(context, const PostRequestScreen()),
                            onOpenMap: () =>
                                _open(context, const ClientSearchScreen()),
                            onOpenPlus: () {
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'SwiftServe Plus is coming soon.',
                                    ),
                                  ),
                                );
                            },
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'Most Booked Services',
                            style: TextStyle(
                              color: text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.93,
                            children: [
                              _ServiceCard(
                                icon: Icons.home_outlined,
                                title: 'Home Services',
                                tint: const Color(0xFFFFE9A8),
                                surface: surface,
                                textColor: text,
                                onTap: () => _open(
                                  context,
                                  const PostRequestScreen(
                                    initialCategory: 'Home Services',
                                  ),
                                ),
                              ),
                              _ServiceCard(
                                icon: Icons.school_outlined,
                                title: 'Academic Help',
                                tint: const Color(0xFFFFDDD5),
                                surface: surface,
                                textColor: text,
                                onTap: () => _open(
                                  context,
                                  const PostRequestScreen(
                                    initialCategory: 'Academic Help',
                                  ),
                                ),
                              ),
                              _ServiceCard(
                                icon: Icons.handyman_outlined,
                                title: 'Repairs',
                                tint: const Color(0xFFF4ECD3),
                                surface: surface,
                                textColor: text,
                                onTap: () => _open(
                                  context,
                                  const PostRequestScreen(
                                    initialCategory: 'Repairs',
                                  ),
                                ),
                              ),
                              _ServiceCard(
                                icon: Icons.shopping_bag_outlined,
                                title: 'Errands',
                                tint: const Color(0xFFDDF4E9),
                                surface: surface,
                                textColor: text,
                                onTap: () => _open(
                                  context,
                                  const PostRequestScreen(
                                    initialCategory: 'Errands',
                                  ),
                                ),
                              ),
                              _ServiceCard(
                                icon: Icons.auto_awesome_outlined,
                                title: 'Cleaning',
                                tint: const Color(0xFFFFE9A8),
                                surface: surface,
                                textColor: text,
                                onTap: () => _open(
                                  context,
                                  const PostRequestScreen(
                                    initialCategory: 'Cleaning',
                                  ),
                                ),
                              ),
                              _ServiceCard(
                                icon: Icons.content_cut_outlined,
                                title: 'Beauty',
                                tint: const Color(0xFFFFDDD5),
                                surface: surface,
                                textColor: text,
                                onTap: () => _open(
                                  context,
                                  const PostRequestScreen(
                                    initialCategory: 'Beauty',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey('client-other-services'),
                            onPressed: () =>
                                _open(context, const PostRequestScreen()),
                            style: FilledButton.styleFrom(
                              backgroundColor: _yellow,
                              foregroundColor: _ink,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.grid_view_rounded, size: 19),
                            label: const Text(
                              'Other services',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _ClientNavigation(
                    userId: profile?.id,
                    surface: surface,
                    textColor: text,
                    onSelected: (index) => _openTab(context, index),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openTab(BuildContext context, int index) {
    if (index == 0) return;
    final screen = switch (index) {
      1 => const ClientBookingsScreen(),
      2 => const ClientMessagesScreen(),
      _ => const ClientProfileScreen(),
    };
    Navigator.push(
      context,
      clientTabPageRoute(screen, fromIndex: 0, toIndex: index),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, clientPageRoute(screen));
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.profile,
    required this.name,
    required this.textColor,
    required this.surface,
  });

  final AppUser? profile;
  final String name;
  final Color textColor;
  final Color surface;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (profile?.photoBase64.isNotEmpty ?? false)
        ProfileAvatar(photoBase64: profile!.photoBase64, radius: 23)
      else
        CircleAvatar(
          radius: 23,
          backgroundColor: const Color(0xFF252525),
          child: Text(
            name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: ClientDashboardView._yellow,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello 👋', style: TextStyle(color: textColor, fontSize: 13)),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      Material(
        color: surface,
        borderRadius: BorderRadius.circular(13),
        child: IconButton(
          key: const ValueKey('client-notifications'),
          onPressed: () => Navigator.push(
            context,
            clientPageRoute(const ClientNotificationsScreen()),
          ),
          icon: NotificationUnreadBadge(
            userId: profile?.id,
            child: Icon(Icons.notifications_none, color: textColor),
          ),
        ),
      ),
    ],
  );
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({
    required this.surface,
    required this.textColor,
    required this.onTap,
  });

  final Color surface;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    elevation: 2,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      key: const ValueKey('client-home-search'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.search, color: textColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search for a service or worker...',
                style: TextStyle(color: textColor, fontSize: 13),
              ),
            ),
            Container(
              width: 42,
              height: 42,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: ClientDashboardView._yellow,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.tune, color: ClientDashboardView._ink),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RequestBanner extends StatefulWidget {
  const _RequestBanner({
    required this.onPostRequest,
    required this.onOpenMap,
    required this.onOpenPlus,
  });

  final VoidCallback onPostRequest;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenPlus;

  @override
  State<_RequestBanner> createState() => _RequestBannerState();
}

class _RequestBannerState extends State<_RequestBanner> {
  static const _assets = [
    'assets/dashboard/hero_post_request.svg',
    'assets/dashboard/hero_nearby.svg',
    'assets/dashboard/hero_plus.svg',
  ];

  String _semanticLabel(int index) => switch (index) {
    0 => 'Post a Request',
    1 => 'Open Map',
    _ => 'Try SwiftServe Plus',
  };

  VoidCallback _actionFor(int index) => switch (index) {
    0 => widget.onPostRequest,
    1 => widget.onOpenMap,
    _ => widget.onOpenPlus,
  };

  final _controller = PageController();
  var _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 350 / 168,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _assets.length,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => Semantics(
              button: true,
              label: _semanticLabel(index),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('client-hero-slide-$index'),
                  onTap: _actionFor(index),
                  child: SvgPicture.asset(_assets[index], fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 7,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x66000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    _assets.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: index == _currentPage ? 14 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: index == _currentPage
                            ? ClientDashboardView._yellow
                            : Colors.white70,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.tint,
    required this.surface,
    required this.textColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color tint;
  final Color surface;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    elevation: 2,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: ClientDashboardView._ink, size: 21),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ClientNavigation extends StatelessWidget {
  const _ClientNavigation({
    required this.userId,
    required this.surface,
    required this.textColor,
    required this.onSelected,
  });

  final String? userId;
  final Color surface;
  final Color textColor;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _NavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            selected: true,
            textColor: textColor,
            onTap: () => onSelected(0),
          ),
          _NavItem(
            icon: Icons.calendar_month_outlined,
            label: 'Bookings',
            textColor: textColor,
            onTap: () => onSelected(1),
          ),
          _NavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            textColor: textColor,
            showUnreadBadge: true,
            userId: userId,
            onTap: () => onSelected(2),
          ),
          _NavItem(
            icon: Icons.person_outline,
            label: 'Profile',
            textColor: textColor,
            onTap: () => onSelected(3),
          ),
        ],
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.onTap,
    this.selected = false,
    this.showUnreadBadge = false,
    this.userId,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final VoidCallback onTap;
  final bool selected;
  final bool showUnreadBadge;
  final String? userId;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? ClientDashboardView._yellow : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: showUnreadBadge
                    ? ConversationUnreadBadge(
                        userId: userId,
                        child: Icon(icon, color: textColor, size: 20),
                      )
                    : Icon(icon, color: textColor, size: 20),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: textColor, fontSize: 10)),
          ],
        ),
      ),
    ),
  );
}
