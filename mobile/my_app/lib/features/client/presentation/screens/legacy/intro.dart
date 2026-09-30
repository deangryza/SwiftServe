import 'package:flutter/material.dart';
import '../../widgets/legacy/app_logo.dart';
import '../../widgets/legacy/page_indicator.dart';
import '../../widgets/legacy/onboarding_primary_button.dart';
import 'secintro.dart';

class OnboardingPage1 extends StatelessWidget {
  const OnboardingPage1({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,

            children: [
              const SizedBox(height: 20),
              // Logo
              const AppLogo(),
              const SizedBox(height: 40),

              // Image
              Container(
                height: 280,
                width: double.infinity,

                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FA),
                  borderRadius: BorderRadius.circular(25),
                ),

                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),

                  child: Image.asset("assets/map.png", fit: BoxFit.cover),
                ),
              ),

              const SizedBox(height: 35),

              // Title
              const Text(
                "Find Nearby Services Easily",

                textAlign: TextAlign.center,

                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 15),

              // Description
              const Text(
                "Connect with trusted workers near your location for short-term tasks and daily services anytime, anywhere.",

                textAlign: TextAlign.center,

                style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
              ),

              const Spacer(),

              // Page Indicator
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [
                  PageIndicator(active: true),
                  PageIndicator(active: false),
                ],
              ),

              const SizedBox(height: 25),

              // Next Button
              Align(
                alignment: Alignment.centerRight,

                child: OnboardingPrimaryButton(
                  text: "Next",

                  onPressed: () {
                    Navigator.push(
                      context,

                      MaterialPageRoute(
                        builder: (context) => const OnboardingPage2(),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
