import 'package:flutter/material.dart';
import '../widgets/primary_button.dart';
import 'entry.dart';

class OnboardingPage2 extends StatelessWidget {
  const OnboardingPage2({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),

          child: Column(
            children: [

              const SizedBox(height: 10),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    "SwiftServe",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff0D1B4C),
                    ),
                  ),
                  Text(
                    "SKIP",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xff0D1B4C),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Image
              Container(
                width: 200,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image: const DecorationImage(
                    image: AssetImage("assets/worker.png"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Title
              const Text(
                "Turn Your Skills Into\nOpportunities",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff0D1B4C),
                ),
              ),

              const SizedBox(height: 20),

              // Description
              const Text(
                "Workers can offer their skills, accept bookings,\n"
                "and earn with flexibility through\n"
                "one application platform.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  height: 1.6,
                ),
              ),

              const Spacer(),

              // Indicator
              Container(
                width: 35,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),

              const SizedBox(height: 30),

              // Button (iPhone smooth transition)
              Align(
                alignment: Alignment.bottomRight,
                child: PrimaryButton(
                  text: "Next",
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 450),
                        reverseTransitionDuration: const Duration(milliseconds: 350),

                        pageBuilder: (_, animation, _) =>
                            const Entry(),

                        transitionsBuilder: (_, animation, _, child) {
                          final curve = CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          );

                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(1.0, 0.0),
                              end: Offset.zero,
                            ).animate(curve),
                            child: FadeTransition(
                              opacity: curve,
                              child: child,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}