import 'package:flutter/material.dart';

import '../../../domain/models/category_model.dart';
import '../../widgets/legacy/home_header.dart';
import '../../widgets/legacy/search_box.dart';
import '../../widgets/legacy/category_card.dart';
import '../../widgets/legacy/post_button.dart';
import '../../widgets/legacy/request_card.dart';
import '../../widgets/legacy/bottom_nav.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF7F8FC),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HomeHeader(
                name: "Guest",
                location: "Malolos City",
                workersNearby: 12,
              ),

              const SizedBox(height: 25),

              const SearchBox(),

              const SizedBox(height: 25),

              const Text(
                "Browse Categories",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 15),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: categories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: .95,
                ),
                itemBuilder: (context, index) {
                  return CategoryCard(
                    category: categories[index],
                    onTap: () {},
                  );
                },
              ),

              const SizedBox(height: 18),

              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text("Other Services"),
              ),

              const SizedBox(height: 25),

              PostButton(
                onPressed: () {
                  // TODO:
                  // Open Post Request Screen
                },
              ),

              const SizedBox(height: 30),

              const Text(
                "Community Requests",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 15),

              RequestCard(
                name: "Guest",
                service: "Need help assembling furniture",
                location: "Malolos City",
                budget: "₱500",
                time: "2 hours ago",
                onView: () {},
              ),

              const SizedBox(height: 15),

              RequestCard(
                name: "Guest",
                service: "House Cleaning",
                location: "Bulacan",
                budget: "₱800",
                time: "5 hours ago",
                onView: () {},
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),

      bottomNavigationBar: BottomNav(
        currentIndex: currentIndex,
        onTap: (index) {
          setState(() {
            currentIndex = index;
          });

          // TODO:
          // Navigate to Home / History / Messages / Profile
        },
      ),
    );
  }
}
