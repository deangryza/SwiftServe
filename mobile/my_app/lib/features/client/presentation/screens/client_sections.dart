import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/services/client_theme_controller.dart';
import '../widgets/conversation_ui.dart';
import 'client_booking_flow.dart';
import 'client_profile_screen.dart';
import 'client_request_details_screen.dart';

export 'client_profile_screen.dart';

String? get clientUid => FirebaseAuth.instance.currentUser?.uid;

String displayDate(dynamic value) {
  if (value is! Timestamp) return 'Date unavailable';

  final date = value.toDate();
  return '${date.month}/${date.day}/${date.year}';
}

// =====================================================
// HISTORY
// =====================================================

class ClientHistoryScreen extends StatelessWidget {
  const ClientHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = clientUid;

    return Scaffold(
      appBar: AppBar(title: const Text('Bookings')),
      body: uid == null
          ? const Center(child: Text('Please log in again.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .where('clientId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load history:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final requests = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final aTime = a.data()['createdAt'];
                    final bTime = b.data()['createdAt'];

                    if (aTime is! Timestamp && bTime is! Timestamp) return 0;
                    if (aTime is! Timestamp) return 1;
                    if (bTime is! Timestamp) return -1;

                    return bTime.compareTo(aTime);
                  });

                if (requests.isEmpty) {
                  return const Center(
                    child: Text('You have not posted any jobs yet.'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final document = requests[index];
                    final data = document.data();
                    final status = (data['status'] ?? 'pending').toString();

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        clientPageRoute(
                          ClientRequestDetailsScreen(requestId: document.id),
                        ),
                      ),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (data['title'] ?? 'Untitled job')
                                          .toString(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Chip(label: Text(status.toUpperCase())),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${data['category'] ?? 'Other'} • '
                                '${data['location'] ?? 'No location'}',
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Posted: ${displayDate(data['createdAt'])}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              if (data['budget'] != null)
                                Text('Budget: ₱${data['budget']}'),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

// =====================================================
// MESSAGES
// =====================================================

class ClientMessagesScreen extends StatelessWidget {
  const ClientMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = clientUid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please log in again.')));
    }
    return ClientTabSwipeRegion(
      currentIndex: 2,
      onSwipeToIndex: (index) {
        final screen = index == 1
            ? const ClientBookingsScreen()
            : const ClientProfileScreen();
        Navigator.pushReplacement(
          context,
          clientTabPageRoute(screen, fromIndex: 2, toIndex: index),
        );
      },
      child: ConversationInboxScreen(
        userId: uid,
        counterpartIdField: 'workerId',
        counterpartNameField: 'workerName',
        bottomNavigationBar: _ClientMessagesBottomNav(userId: uid),
        onOpenConversation: (conversationId, name) {
          Navigator.push(
            context,
            clientPageRoute(
              ClientChatScreen(
                conversationId: conversationId,
                otherPersonName: name,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ClientMessagesBottomNav extends StatelessWidget {
  const _ClientMessagesBottomNav({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : const Color(0xFFFFF9E9);
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : const Color(0xFF242424);

    void replaceWith(Widget screen, int toIndex) {
      Navigator.pushReplacement(
        context,
        clientTabPageRoute(screen, fromIndex: 2, toIndex: toIndex),
      );
    }

    return Container(
      color: background,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              _MessagesNavItem(
                icon: Icons.home_outlined,
                label: 'Home',
                textColor: text,
                onTap: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
              ),
              _MessagesNavItem(
                icon: Icons.calendar_month_outlined,
                label: 'Bookings',
                textColor: text,
                onTap: () => replaceWith(const ClientBookingsScreen(), 1),
              ),
              _MessagesNavItem(
                icon: Icons.chat_bubble_outline,
                label: 'Chat',
                textColor: text,
                selected: true,
                userId: userId,
                onTap: () {},
              ),
              _MessagesNavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                textColor: text,
                onTap: () => replaceWith(const ClientProfileScreen(), 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesNavItem extends StatelessWidget {
  const _MessagesNavItem({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.onTap,
    this.selected = false,
    this.userId,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final VoidCallback onTap;
  final bool selected;
  final String? userId;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 27,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFC72C) : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: userId == null
                    ? Icon(icon, color: textColor, size: 19)
                    : ConversationUnreadBadge(
                        userId: userId,
                        child: Icon(icon, color: textColor, size: 19),
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: textColor, fontSize: 10)),
          ],
        ),
      ),
    ),
  );
}

class ClientChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherPersonName;

  const ClientChatScreen({
    super.key,
    required this.conversationId,
    required this.otherPersonName,
  });

  @override
  State<ClientChatScreen> createState() => _ClientChatScreenState();
}

class _ClientChatScreenState extends State<ClientChatScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;
  bool _markingRead = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  Future<void> _markRead() async {
    final uid = clientUid;
    if (uid == null || _markingRead) return;
    _markingRead = true;
    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .update({
            'unreadFor': FieldValue.arrayRemove([uid]),
          });
    } catch (_) {
      // Older or removed conversations are handled by the chat error state.
    } finally {
      _markingRead = false;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final uid = clientUid;

    if (text.isEmpty || uid == null || _sending) return;

    setState(() => _sending = true);

    try {
      final conversation = FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId);

      // Check that this client belongs to the conversation.
      final conversationDoc = await conversation.get();
      final participants = List<String>.from(
        conversationDoc.data()?['participantIds'] ?? [],
      );

      if (!participants.contains(uid)) {
        throw Exception('You cannot send to this conversation.');
      }
      final otherParticipant = participants.firstWhere(
        (participantId) => participantId != uid,
        orElse: () => '',
      );
      if (otherParticipant.isEmpty) {
        throw Exception('This conversation has no recipient.');
      }
      final blocks = await Future.wait([
        FirebaseFirestore.instance
            .collection('user_blocks')
            .doc('${uid}_$otherParticipant')
            .get(),
        FirebaseFirestore.instance
            .collection('user_blocks')
            .doc('${otherParticipant}_$uid')
            .get(),
      ]);
      if (blocks.any((block) => block.exists)) {
        throw Exception(
          'Messaging is unavailable because this user is blocked.',
        );
      }
      final unreadFor = participants
          .where((participantId) => participantId != uid)
          .toList(growable: false);

      final batch = FirebaseFirestore.instance.batch();

      final message = conversation.collection('messages').doc();

      batch.set(message, {
        'senderId': uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.update(conversation, {
        'lastMessage': text,
        'lastSenderId': uid,
        'unreadFor': unreadFor,
        'hiddenFor': FieldValue.arrayRemove(participants),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      _messageController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send message: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = clientUid;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : const Color(0xFFFFF9E9);
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : const Color(0xFF242424);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFC72C),
        foregroundColor: const Color(0xFF242424),
        title: Text(
          widget.otherPersonName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .doc(widget.conversationId)
                  .collection('messages')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load chat: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _markRead(),
                );

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return const Center(child: Text('Start the conversation.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final isMine = data['senderId'] == uid;

                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 270),
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMine ? const Color(0xFFFFC72C) : surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          (data['text'] ?? '').toString(),
                          style: TextStyle(
                            color: isMine ? const Color(0xFF242424) : text,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: text),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC72C),
                      foregroundColor: const Color(0xFF242424),
                    ),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
