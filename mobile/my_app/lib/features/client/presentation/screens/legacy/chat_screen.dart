import 'package:flutter/material.dart';
import '../../widgets/legacy/chat_bubble.dart';
import '../../widgets/legacy/chat_message_input.dart';

class ChatScreen extends StatelessWidget {
  final String name;
  final String initials;

  const ChatScreen({super.key, required this.name, required this.initials});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF7F8FC),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 15),
            child: Icon(Icons.more_horiz, color: Colors.black),
          ),
        ],
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xffDCE8FF),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Color(0xff2F6FED),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 12),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const Text(
                  "Online",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),

      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),

            child: Column(
              children: [
                CircleAvatar(
                  radius: 55,
                  backgroundColor: const Color(0xffDCE8FF),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 40,
                      color: Color(0xff2F6FED),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, color: Colors.white, size: 18),
                      SizedBox(width: 5),
                      Text(
                        "Verified",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  SizedBox(height: 20),

                  Text("Today", style: TextStyle(color: Colors.grey)),

                  SizedBox(height: 20),

                  ChatBubble(
                    message: "Hi! Available pa po ba kayo ngayon?",
                    time: "9:15 AM",
                    isMe: true,
                  ),

                  SizedBox(height: 12),

                  ChatBubble(
                    message:
                        "Yes po, available ako. Ano pong service ang kailangan ninyo?",
                    time: "9:16 AM",
                    isMe: false,
                  ),

                  SizedBox(height: 12),

                  ChatBubble(
                    message: "Need ko po ng math tutor ngayong hapon.",
                    time: "9:17 AM",
                    isMe: true,
                  ),

                  SizedBox(height: 12),

                  ChatBubble(
                    message: "Okay po. Available ako ng 2:00 PM.",
                    time: "9:18 AM",
                    isMe: false,
                  ),
                ],
              ),
            ),
          ),

          const ChatMessageInput(),
        ],
      ),
    );
  }
}
