import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:flutter/services.dart';

import '../../../auth/presentation/screens/entry_screen.dart';

class SwiftServeOnboardingScreen extends StatefulWidget {
  const SwiftServeOnboardingScreen({super.key});

  @override
  State<SwiftServeOnboardingScreen> createState() =>
      _SwiftServeOnboardingScreenState();
}

class _SwiftServeOnboardingScreenState
    extends State<SwiftServeOnboardingScreen> {
  static const _background = Color(0xFFFFFFFF);
  static const _yellow = AppTheme.yellow;
  static const _ink = AppTheme.ink;
  static const _muted = AppTheme.muted;

  final _controller = PageController();
  var _page = 0;

  static const _pages = [
    _OnboardingPageData(
      lightIllustration: 'assets/onboarding/onboarding_nearby_light.png',
      darkIllustration: 'assets/onboarding/onboarding_nearby_dark.png',
      title: 'Find Nearby Services Easily',
      description:
          'Connect with trusted workers near your location for short-term tasks and daily services anytime and anywhere.',
    ),
    _OnboardingPageData(
      lightIllustration: 'assets/onboarding/onboarding_skills_light.png',
      darkIllustration: 'assets/onboarding/onboarding_skills_dark.png',
      title: 'Turn your Skills into\nOpportunities',
      description:
          'Workers can offer their skills, accept bookings, and connect with clients through one organized platform.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openEntry() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EntryScreen()),
    );
  }

  void _continue() {
    if (_page == _pages.length - 1) {
      _openEntry();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : _background;
    final ink = dark ? const Color(0xFFF3F3F3) : _ink;
    final muted = dark ? const Color(0xFFB8B8B8) : _muted;
    final divider = dark ? const Color(0xFF444444) : const Color(0xFFE3DDCD);
    final inactiveDot = dark ? AppTheme.muted : const Color(0xFFD9D9D9);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: background,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SwiftServe',
                        style: TextStyle(
                          color: ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('onboarding-skip'),
                      onPressed: _openEntry,
                      style: TextButton.styleFrom(
                        foregroundColor: ink,
                        minimumSize: const Size(52, 36),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) => _OnboardingPage(
                    data: _pages[index],
                    pageIndex: index,
                    selectedPage: _page,
                    ink: ink,
                    muted: muted,
                    inactiveDot: inactiveDot,
                    dark: dark,
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: divider)),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: FilledButton(
                      key: const ValueKey('onboarding-next'),
                      onPressed: _continue,
                      style: FilledButton.styleFrom(
                        backgroundColor: _yellow,
                        foregroundColor: const Color(0xFF171717),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(
                        _page == _pages.length - 1 ? 'Get Started' : 'Next',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.pageIndex,
    required this.selectedPage,
    required this.ink,
    required this.muted,
    required this.inactiveDot,
    required this.dark,
  });

  final _OnboardingPageData data;
  final int pageIndex;
  final int selectedPage;
  final Color ink;
  final Color muted;
  final Color inactiveDot;
  final bool dark;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final illustrationSize = math.min(
        constraints.maxWidth * 0.72,
        math.max(190.0, constraints.maxHeight * 0.48),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 26),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    label: pageIndex == 0
                        ? 'Nearby workers on a map'
                        : 'Worker skills and a new booking',
                    image: true,
                    child: SizedBox.square(
                      key: ValueKey('onboarding-illustration-$pageIndex'),
                      dimension: illustrationSize,
                      child: Image.asset(
                        dark ? data.darkIllustration : data.lightIllustration,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    data.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ink,
                      fontSize: 24,
                      height: 29 / 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    data.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: muted,
                      fontSize: 14,
                      height: 21 / 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(2, (index) {
                      final selected = index == selectedPage;
                      return AnimatedContainer(
                        key: ValueKey('onboarding-dot-$index'),
                        duration: const Duration(milliseconds: 180),
                        width: selected ? 18 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: selected
                              ? _SwiftServeOnboardingScreenState._yellow
                              : inactiveDot,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.lightIllustration,
    required this.darkIllustration,
    required this.title,
    required this.description,
  });

  final String lightIllustration;
  final String darkIllustration;
  final String title;
  final String description;
}
