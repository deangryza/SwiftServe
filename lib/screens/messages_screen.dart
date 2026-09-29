import 'package:flutter/material.dart';
import '../widgets/message_tile.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> conversations = [
      {
        "initials": "MS",
        "name": "Martin S.",
        "message": "Sige po, papunta na ako.",
        "color": "blue",
      },
      {
        "initials": "BC",
        "name": "Ben C.",
        "message": "Salamat po sa booking!",
        "color": "green",
      },
      {
        "initials": "LT",
        "name": "Lea T.",
        "message": "Tutoring schedule?",
        "color": "orange",
      },
      {
        "initials": "MD",
        "name": "Mark D.",
        "message": "Received, thanks!",
        "color": "grey",
      },
      {
        "initials": "AL",
        "name": "Anna L.",
        "message": "Available pa po ba bukas?",
        "color": "purple",
      },
      {
        "initials": "MB",
        "name": "Miriam B.",
        "message": "Today lang po Ma'am.",
        "color": "amber",
      },
      {
        "initials": "BC",
        "name": "Bianca C.",
        "message": "Sige po, otw.",
        "color": "lightGreen",
      },
      {
        "initials": "ML",
        "name": "Manuel L.",
        "message": "See you later.",
        "color": "cyan",
      },
    ];

    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Row(
                children: [

                  const Expanded(
                    child: Text(
                      "Messages",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.search,
                      size: 15,
                    ),
                  ),

                ],
              ),

              const SizedBox(height: 15),

              TextField(
                decoration: InputDecoration(
                  hintText: "Search conversations...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 15),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Text(
                  "All",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 15),

              Expanded(
                child: ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final item = conversations[index];

                    return MessageTile(
                      initials: item["initials"]!,
                      name: item["name"]!,
                      message: item["message"]!,
                      colorName: item["color"]!,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}