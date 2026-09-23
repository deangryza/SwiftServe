import 'package:flutter/material.dart';

import '../../entry/entry_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  int currentPage = 0;

  final List<OnboardingData> pages = const [
    OnboardingData(
      title: 'Find Nearby Services Easily',
      description:
          'Connect with trusted workers near your location for short-term tasks and daily services anytime and anywhere.',
    ),
    OnboardingData(
      title: 'Turn Your Skills Into Opportunities',
      description:
          'Workers can offer their skills, accept bookings, and connect with clients through one organized platform.',
    ),
  ];

  void nextPage() {
    if (currentPage < pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      goToEntry();
    }
  }

  void skipOnboarding() {
    goToEntry();
  }

  void goToEntry() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const EntryScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 700;

            final contentWidth = isDesktop
                ? 430.0
                : constraints.maxWidth * 0.88;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  children: [
                    // Top navigation
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SwiftServe',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10233B),
                            ),
                          ),
                          TextButton(
                            onPressed: skipOnboarding,
                            child: const Text(
                              'SKIP',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Onboarding pages
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: pages.length,
                        onPageChanged: (index) {
                          setState(() {
                            currentPage = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final page = pages[index];

                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                const SizedBox(height: 12),

                                // Illustration placeholder
                                Container(
                                  height: isDesktop ? 340 : 300,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCE7F2),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.image_outlined,
                                      size: 70,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 30),

                                Text(
                                  page.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    height: 1.2,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10233B),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                Text(
                                  page.description,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Page indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        pages.length,
                        (index) {
                          final selected = index == currentPage;

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            width: selected ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF1478D4)
                                  : Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Bottom button
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentPage == pages.length - 1
                                    ? 'Get Started'
                                    : 'Next',
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String description;

  const OnboardingData({
    required this.title,
    required this.description,
  });
}