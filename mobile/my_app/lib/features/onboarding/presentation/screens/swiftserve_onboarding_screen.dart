import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../auth/presentation/screens/entry_screen.dart';

class SwiftServeOnboardingScreen extends StatefulWidget {
  const SwiftServeOnboardingScreen({super.key});

  @override
  State<SwiftServeOnboardingScreen> createState() =>
      _SwiftServeOnboardingScreenState();
}

class _SwiftServeOnboardingScreenState
    extends State<SwiftServeOnboardingScreen> {
  static const _background = Color(0xFFFFF9E9);
  static const _yellow = Color(0xFFFFC72C);
  static const _ink = Color(0xFF07182A);
  static const _muted = Color(0xFF555960);

  final _controller = PageController();
  var _page = 0;

  static const _pages = [
    _OnboardingPageData(
      illustration: 'assets/onboarding/find_nearby.svg',
      title: 'Find Nearby Services Easily',
      description:
          'Connect with trusted workers near your location for short-term tasks and daily services anytime and anywhere.',
    ),
    _OnboardingPageData(
      illustration: 'assets/onboarding/skills_opportunities.svg',
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
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: _background,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: _background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'SwiftServe',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('onboarding-skip'),
                    onPressed: _openEntry,
                    style: TextButton.styleFrom(
                      foregroundColor: _ink,
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
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE3DDCD))),
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

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.pageIndex,
    required this.selectedPage,
  });

  final _OnboardingPageData data;
  final int pageIndex;
  final int selectedPage;

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
                      child: SvgPicture.asset(data.illustration),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    data.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _SwiftServeOnboardingScreenState._ink,
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
                    style: const TextStyle(
                      color: _SwiftServeOnboardingScreenState._muted,
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
                              : const Color(0xFFD9D9D9),
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
    required this.illustration,
    required this.title,
    required this.description,
  });

  final String illustration;
  final String title;
  final String description;
}
