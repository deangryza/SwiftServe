import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../onboarding/onboarding_screen.dart';

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
      appBar: AppBar(title: const Text('History')),
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
                    final data = requests[index].data();
                    final status =
                        (data['status'] ?? 'pending').toString();

                    return Card(
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

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: uid == null
          ? const Center(child: Text('Please log in again.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .where('participantIds', arrayContains: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load messages:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final conversations = snapshot.data!.docs.toList();

                if (conversations.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No conversations yet.\n'
                        'A conversation will appear after you connect '
                        'with a service provider.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    final data = conversation.data();

                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(
                        (data['workerName'] ?? 'Service provider')
                            .toString(),
                      ),
                      subtitle: Text(
                        (data['lastMessage'] ?? 'Open conversation')
                            .toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClientChatScreen(
                              conversationId: conversation.id,
                              otherPersonName:
                                  (data['workerName'] ??
                                          'Service provider')
                                      .toString(),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
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

      final batch = FirebaseFirestore.instance.batch();

      final message = conversation.collection('messages').doc();

      batch.set(message, {
        'senderId': uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.update(conversation, {
        'lastMessage': text,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      _messageController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = clientUid;

    return Scaffold(
      appBar: AppBar(title: Text(widget.otherPersonName)),
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
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Start the conversation.'),
                  );
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
                        constraints:
                            const BoxConstraints(maxWidth: 270),
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? const Color(0xFF1D1E21)
                              : const Color(0xFFF0F1F4),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          (data['text'] ?? '').toString(),
                          style: TextStyle(
                            color: isMine
                                ? Colors.white
                                : Colors.black87,
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
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _sendMessage,
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

// =====================================================
// PROFILE
// =====================================================

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() =>
      _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  Future<void> _editName(String currentName) async {
    final controller = TextEditingController(text: currentName);

    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Edit name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Full name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(dialogContext, name);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (newName == null || clientUid == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(clientUid)
          .update({'fullName': newName});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update name: $error')),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _logOut() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const OnboardingScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in again.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load profile: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() ?? {};
          final name = (data['fullName'] ?? 'Client').toString();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Center(
                child: CircleAvatar(
                  radius: 35,
                  child: Icon(Icons.person, size: 40),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Email'),
                      subtitle: Text(user.email ?? 'No email available'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: const Text('Contact number'),
                      subtitle: Text(
                        (data['contactNumber'] ??
                                'No contact number saved')
                            .toString(),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Edit name'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _editName(name),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _logOut,
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
              ),
            ],
          );
        },
      ),
    );
  }
}