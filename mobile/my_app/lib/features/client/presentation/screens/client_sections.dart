import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/widgets/simple_back_button.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/message_time.dart';
import '../../../../shared/widgets/action_confirmation_dialog.dart';


import '../../../../shared/screens/public_profile_screen.dart';
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
    final background = dark ? const Color(0xFF171717) : const Color(0xFFFFFFFF);
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : AppTheme.ink;

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
            border: Border.all(color: Theme.of(context).dividerColor),
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
                color: selected ? AppTheme.yellow : null,
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

enum _ChatConversationAction { viewProfile, delete, block }

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

  Future<void> _handleChatConversationAction(
    _ChatConversationAction action,
  ) async {
    final uid = clientUid;
    if (uid == null) return;

    try {
      final conversation = FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId);
      final conversationSnapshot = await conversation.get();
      final conversationData = conversationSnapshot.data();
      final participants = List<String>.from(
        conversationData?['participantIds'] ?? const <String>[],
      );
      if (!participants.contains(uid)) {
        throw Exception('This conversation is unavailable.');
      }
      final otherParticipant = participants.firstWhere(
        (participantId) => participantId != uid,
        orElse: () => '',
      );
      if (otherParticipant.isEmpty) {
        throw Exception('This conversation has no recipient.');
      }

      if (action == _ChatConversationAction.viewProfile) {
        final otherRole = conversationData?['clientId'] == otherParticipant
            ? PublicProfileRole.client
            : PublicProfileRole.worker;
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PublicProfileScreen(
              userId: otherParticipant,
              role: otherRole,
              initialData: {
                'fullName': widget.otherPersonName,
                'role': otherRole.name,
              },
            ),
          ),
        );
        return;
      }

      if (action == _ChatConversationAction.block) {
        final existingBlock = await FirebaseFirestore.instance
            .collection('user_blocks')
            .doc('${uid}_$otherParticipant')
            .get();
        if (existingBlock.exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.otherPersonName} is already blocked.'),
            ),
          );
          return;
        }
      }

      if (!mounted) return;
      final deleting = action == _ChatConversationAction.delete;
      final confirmed = await showActionConfirmation(
        context,
        title: deleting
            ? 'Delete conversation?'
            : 'Block ${widget.otherPersonName}?',
        message: deleting
            ? 'Are you sure you want to delete this conversation? It will be removed from your inbox.'
            : 'Are you sure you want to block ${widget.otherPersonName}? You will no longer be able to message each other.',
        confirmLabel: deleting ? 'Delete' : 'Block',
        icon: deleting ? Icons.delete_outline_rounded : Icons.block_rounded,
      );
      if (confirmed != true) return;

      if (deleting) {
        await conversation.update({
          'hiddenFor': FieldValue.arrayUnion([uid]),
          'unreadFor': FieldValue.arrayRemove([uid]),
        });
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Conversation deleted.')),
        );
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance
            .collection('user_blocks')
            .doc('${uid}_$otherParticipant'),
        {
          'blockerId': uid,
          'blockedId': otherParticipant,
          'conversationId': widget.conversationId,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      batch.update(conversation, {
        'hiddenFor': FieldValue.arrayRemove([uid]),
        'unreadFor': FieldValue.arrayRemove([uid]),
      });
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.otherPersonName} has been blocked. Messages are now restricted.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update this conversation: $error')),
      );
    }
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
      if (blocks.first.exists) {
        throw Exception(
          'You blocked this user. Unblock them before sending a message.',
        );
      }
      if (blocks.last.exists) {
        throw Exception(
          'You cannot send a message because this user blocked you.',
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
        'lastMessageId': message.id,
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

  Future<void> _unblock(String otherParticipant) async {
    final uid = clientUid;
    if (uid == null) return;
    final confirmed = await showActionConfirmation(
      context,
      title: 'Unblock ${widget.otherPersonName}?',
      message:
          'Are you sure you want to unblock ${widget.otherPersonName}? You will be able to message each other again.',
      confirmLabel: 'Unblock',
      icon: Icons.lock_open_rounded,
    );
    if (!confirmed) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(
        FirebaseFirestore.instance
            .collection('user_blocks')
            .doc('${uid}_$otherParticipant'),
      );
      batch.update(
        FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId),
        {
          'hiddenFor': FieldValue.arrayRemove([uid]),
        },
      );
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.otherPersonName} has been unblocked. You can message each other again.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unblock this user: $error')),
      );
    }
  }

  Widget _messageList({
    required String uid,
    required Color surface,
    required Color text,
  }) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('Could not load chat: ${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
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
          final createdAt = data['createdAt'] as Timestamp?;
          final date = createdAt?.toDate();
          final previousCreatedAt = index == 0
              ? null
              : messages[index - 1].data()['createdAt'] as Timestamp?;
          final showDateSeparator =
              date != null &&
              (previousCreatedAt == null ||
                  !isSameMessageDate(date, previousCreatedAt.toDate()));

          return Column(
            children: [
              if (showDateSeparator)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                  child: Text(
                    messageDateSeparatorLabel(date),
                    style: TextStyle(
                      color: text.withValues(alpha: 0.65),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Align(
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
                    color: isMine ? AppTheme.yellow : surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        (data['text'] ?? '').toString(),
                        style: TextStyle(color: isMine ? AppTheme.ink : text),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date == null ? 'Sending…' : messageClockLabel(date),
                        style: TextStyle(
                          color: (isMine ? AppTheme.ink : text).withValues(
                            alpha: 0.62,
                          ),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _composer({required Color surface, required Color text}) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('message-input'),
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
            key: const ValueKey('send-message'),
            onPressed: _sending ? null : _sendMessage,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.yellow,
              foregroundColor: AppTheme.ink,
            ),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    ),
  );

  Widget _restrictionPanel({
    required bool blockedByMe,
    required String otherParticipant,
    required Color surface,
    required Color text,
  }) => SafeArea(
    top: false,
    child: Container(
      key: const ValueKey('message-restriction'),
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.block, color: text),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              blockedByMe
                  ? 'You blocked ${widget.otherPersonName}. Unblock them to resume messaging.'
                  : '${widget.otherPersonName} blocked you. Messages cannot be sent or delivered in this conversation.',
              style: TextStyle(color: text, fontSize: 12),
            ),
          ),
          if (blockedByMe) ...[
            const SizedBox(width: 10),
            TextButton(
              key: const ValueKey('unblock-user'),
              onPressed: () => _unblock(otherParticipant),
              child: const Text('Unblock'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _conversationBody({
    required String uid,
    required Color surface,
    required Color text,
  }) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .snapshots(),
    builder: (context, conversationSnapshot) {
      if (conversationSnapshot.hasError) {
        return Center(
          child: Text(
            'Could not load conversation: ${conversationSnapshot.error}',
          ),
        );
      }
      if (!conversationSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = conversationSnapshot.data!.data();
      final participants = List<String>.from(data?['participantIds'] ?? []);
      if (!participants.contains(uid)) {
        return const Center(child: Text('This conversation is unavailable.'));
      }
      final otherParticipant = participants.firstWhere(
        (participant) => participant != uid,
        orElse: () => '',
      );
      if (otherParticipant.isEmpty) {
        return const Center(child: Text('This conversation has no recipient.'));
      }

      final blocks = FirebaseFirestore.instance.collection('user_blocks');
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: blocks.doc('${uid}_$otherParticipant').snapshots(),
        builder: (context, outgoingBlock) =>
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: blocks.doc('${otherParticipant}_$uid').snapshots(),
              builder: (context, incomingBlock) {
                if (!outgoingBlock.hasData || !incomingBlock.hasData) {
                  return Column(
                    children: [
                      Expanded(
                        child: _messageList(
                          uid: uid,
                          surface: surface,
                          text: text,
                        ),
                      ),
                      const SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: LinearProgressIndicator(),
                        ),
                      ),
                    ],
                  );
                }
                final blockedByMe = outgoingBlock.data?.exists == true;
                final blockedByThem = incomingBlock.data?.exists == true;
                return Column(
                  children: [
                    Expanded(
                      child: _messageList(
                        uid: uid,
                        surface: surface,
                        text: text,
                      ),
                    ),
                    if (blockedByMe || blockedByThem)
                      _restrictionPanel(
                        blockedByMe: blockedByMe,
                        otherParticipant: otherParticipant,
                        surface: surface,
                        text: text,
                      )
                    else
                      _composer(surface: surface, text: text),
                  ],
                );
              },
            ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final uid = clientUid;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : const Color(0xFFFFFFFF);
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : AppTheme.ink;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: text,
        toolbarHeight: 72,
        leadingWidth: 66,
        titleSpacing: 12,
        leading: Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Center(
            child: SimpleBackButton(onPressed: () => Navigator.pop(context)),
          ),
        ),
        title: Text(
          widget.otherPersonName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<_ChatConversationAction>(
            key: const ValueKey('chat-conversation-actions'),
            tooltip: 'Conversation actions',
            icon: const Icon(Icons.more_horiz),
            onSelected: _handleChatConversationAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ChatConversationAction.viewProfile,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_outline),
                  title: Text('View profile'),
                ),
              ),
              PopupMenuItem(
                value: _ChatConversationAction.delete,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete conversation'),
                ),
              ),
              PopupMenuItem(
                value: _ChatConversationAction.block,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.block),
                  title: Text('Block user'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Please log in again.'))
          : _conversationBody(uid: uid, surface: surface, text: text),
    );
  }
}
