import 'package:flutter/material.dart';

class MessageTile extends StatelessWidget {
  final String initials;
  final String name;
  final String message;
  final String colorName;

  const MessageTile({
    super.key,
    required this.initials,
    required this.name,
    required this.message,
    required this.colorName,
  });

  Color get avatarColor {
    switch (colorName) {
      case "blue":
        return const Color(0xFFE8F0FF);
      case "green":
        return const Color(0xFFEAF8EE);
      case "orange":
        return const Color(0xFFFFF2E7);
      case "grey":
        return const Color(0xFFF2F2F2);
      case "purple":
        return const Color(0xFFF3E9FF);
      case "amber":
        return const Color(0xFFFFF3E0);
      case "lightGreen":
        return const Color(0xFFE8FFE8);
      case "cyan":
        return const Color(0xFFE6FAFF);
      default:
        return const Color(0xFFF2F2F2);
    }
  }

  Color get textColor {
    switch (colorName) {
      case "blue":
        return Colors.blue;
      case "green":
        return Colors.green;
      case "orange":
        return Colors.orange;
      case "grey":
        return Colors.grey;
      case "purple":
        return Colors.purple;
      case "amber":
        return Colors.orangeAccent;
      case "lightGreen":
        return Colors.green;
      case "cyan":
        return Colors.cyan;
      default:
        return Colors.black;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        // TODO:
        // Navigator.push(
        //   context,
        //   MaterialPageRoute(
        //     builder: (_) => const ChatScreen(),
        //   ),
        // );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: avatarColor,
              child: Text(
                initials,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),

            const SizedBox(width: 18),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
