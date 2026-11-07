import 'package:flutter/material.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/services/client_theme_controller.dart';
import '../../../../shared/theme/app_theme.dart';
import '../widgets/conversation_ui.dart';
import 'client_booking_flow.dart';
import 'client_dashboard_view.dart';
import 'client_sections.dart';

/// Hosts the four client tabs under a single, persistent bottom bar so the
/// bar is not rebuilt or animated with each page when switching tabs.
class ClientTabShell extends StatefulWidget {
  const ClientTabShell({super.key, this.profile});

  final AppUser? profile;

  @override
  State<ClientTabShell> createState() => _ClientTabShellState();
}

class _ClientTabShellState extends State<ClientTabShell> {
  final ValueNotifier<int> _index = ValueNotifier<int>(0);
  int _tabDirection = 1;

  @override
  void dispose() {
    _index.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    final current = _index.value;
    if (index == current || index < 0 || index > 3) return;
    _tabDirection = index > current ? 1 : -1;
    _index.value = index;
  }

  Widget _page(int index) => switch (index) {
    0 => ClientDashboardView(profile: widget.profile),
    1 => const ClientBookingsScreen(),
    2 => const ClientMessagesScreen(),
    _ => const ClientProfileScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClientTabShellScope(
      selectTab: _selectTab,
      child: ValueListenableBuilder<int>(
        valueListenable: _index,
        builder: (context, index, child) => ClientTabSwipeRegion(
          currentIndex: index,
          onSwipeToIndex: _selectTab,
          child: child!,
        ),
        child: Scaffold(
          backgroundColor: dark ? const Color(0xFF171717) : Colors.white,
          body: ValueListenableBuilder<int>(
            valueListenable: _index,
            builder: (context, index, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              reverseDuration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final childIndex =
                    (child.key as ValueKey<int>?)?.value ?? index;
                final incoming = childIndex == index;
                final horizontalOffset = incoming
                    ? _tabDirection * 0.08
                    : _tabDirection * -0.04;
                return FadeTransition(
                  key: ValueKey('client-tab-transition-$childIndex'),
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(horizontalOffset, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(index),
                child: _page(index),
              ),
            ),
          ),
          bottomNavigationBar: ValueListenableBuilder<int>(
            valueListenable: _index,
            builder: (context, index, _) => _ClientShellNavigation(
              selectedIndex: index,
              userId: widget.profile?.id,
              onSelected: _selectTab,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientShellNavigation extends StatelessWidget {
  const _ClientShellNavigation({
    required this.selectedIndex,
    required this.userId,
    required this.onSelected,
  });

  final int selectedIndex;
  final String? userId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : Colors.white;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : AppTheme.ink;
    return ColoredBox(
      color: background,
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  _ClientShellNavItem(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    selected: selectedIndex == 0,
                    textColor: text,
                    onTap: () => onSelected(0),
                  ),
                  _ClientShellNavItem(
                    icon: Icons.calendar_month_outlined,
                    label: 'Bookings',
                    selected: selectedIndex == 1,
                    textColor: text,
                    onTap: () => onSelected(1),
                  ),
                  _ClientShellNavItem(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    selected: selectedIndex == 2,
                    textColor: text,
                    badgeUserId: userId,
                    onTap: () => onSelected(2),
                  ),
                  _ClientShellNavItem(
                    icon: Icons.person_outline,
                    label: 'Profile',
                    selected: selectedIndex == 3,
                    textColor: text,
                    onTap: () => onSelected(3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientShellNavItem extends StatelessWidget {
  const _ClientShellNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.textColor,
    required this.onTap,
    this.badgeUserId,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color textColor;
  final VoidCallback onTap;
  final String? badgeUserId;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, color: textColor, size: 20);
    return Expanded(
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
                  color: selected ? AppTheme.yellow : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: badgeUserId == null
                      ? iconWidget
                      : ConversationUnreadBadge(
                          userId: badgeUserId,
                          child: iconWidget,
                        ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
