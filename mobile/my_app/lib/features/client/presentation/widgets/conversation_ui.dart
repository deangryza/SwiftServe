import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/live_profile_avatar.dart';

const _chatYellow = Color(0xFFFFC72C);
const _chatCream = Color(0xFFFFF9E9);
const _chatInk = Color(0xFF242424);

enum _ConversationAction { delete, block }

class _ConversationChoice {
  const _ConversationChoice({
    required this.id,
    required this.counterpartId,
    required this.name,
  });

  final String id;
  final String counterpartId;
  final String name;
}

int conversationUnreadCount(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> conversations,
  String userId,
) {
  return conversations.where((conversation) {
    final data = conversation.data();
    final hiddenFor = data['hiddenFor'];
    final unreadFor = data['unreadFor'];
    return !(hiddenFor is List && hiddenFor.contains(userId)) &&
        unreadFor is List &&
        unreadFor.contains(userId);
  }).length;
}

class ConversationUnreadBadge extends StatelessWidget {
  const ConversationUnreadBadge({
    super.key,
    required this.userId,
    required this.child,
  });

  final String? userId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (userId == null || userId!.isEmpty || Firebase.apps.isEmpty) {
      return child;
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', arrayContains: userId)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData
            ? conversationUnreadCount(snapshot.data!.docs, userId!)
            : 0;
        return Badge(
          isLabelVisible: count > 0,
          backgroundColor: Colors.red,
          smallSize: 8,
          child: child,
        );
      },
    );
  }
}

class NotificationUnreadBadge extends StatelessWidget {
  const NotificationUnreadBadge({
    super.key,
    required this.userId,
    required this.child,
  });

  final String? userId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (userId == null || userId!.isEmpty || Firebase.apps.isEmpty) {
      return child;
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        final hasUnread =
            snapshot.hasData &&
            snapshot.data!.docs.any(
              (notification) => notification.data()['read'] != true,
            );
        return Badge(
          isLabelVisible: hasUnread,
          backgroundColor: Colors.red,
          smallSize: 8,
          child: child,
        );
      },
    );
  }
}

class ConversationInboxScreen extends StatefulWidget {
  const ConversationInboxScreen({
    super.key,
    required this.userId,
    required this.counterpartIdField,
    required this.counterpartNameField,
    required this.onOpenConversation,
    this.onBack,
    this.bottomNavigationBar,
    this.showBackButton = false,
  });

  final String userId;
  final String counterpartIdField;
  final String counterpartNameField;
  final void Function(String conversationId, String counterpartName)
  onOpenConversation;
  final VoidCallback? onBack;
  final Widget? bottomNavigationBar;
  final bool showBackButton;

  @override
  State<ConversationInboxScreen> createState() =>
      _ConversationInboxScreenState();
}

class _ConversationInboxScreenState extends State<ConversationInboxScreen> {
  final _searchController = TextEditingController();

  Future<List<_ConversationChoice>> _conversationChoices() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('conversations')
        .where('participantIds', arrayContains: widget.userId)
        .get();
    final latestByCounterpart =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final documents = snapshot.docs.toList()
      ..sort((left, right) {
        final leftTime = left.data()['updatedAt'] as Timestamp?;
        final rightTime = right.data()['updatedAt'] as Timestamp?;
        return (rightTime?.millisecondsSinceEpoch ?? 0).compareTo(
          leftTime?.millisecondsSinceEpoch ?? 0,
        );
      });
    for (final document in documents) {
      final data = document.data();
      final hiddenFor = data['hiddenFor'];
      if (hiddenFor is List && hiddenFor.contains(widget.userId)) continue;
      final counterpartId = data[widget.counterpartIdField]?.toString();
      if (counterpartId == null || counterpartId.isEmpty) continue;
      latestByCounterpart.putIfAbsent(counterpartId, () => document);
    }
    return latestByCounterpart.entries
        .map(
          (entry) => _ConversationChoice(
            id: entry.value.id,
            counterpartId: entry.key,
            name:
                (entry.value.data()[widget.counterpartNameField] ??
                        'Service user')
                    .toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<_ConversationChoice?> _chooseConversation(
    _ConversationAction action,
  ) async {
    final choices = await _conversationChoices();
    if (!mounted) return null;
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no conversations to manage.')),
      );
      return null;
    }
    return showModalBottomSheet<_ConversationChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                action == _ConversationAction.delete
                    ? 'Delete a conversation'
                    : 'Block a user',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Choose a conversation below'),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: choices.length,
                itemBuilder: (context, index) {
                  final choice = choices[index];
                  return ListTile(
                    leading: LiveProfileAvatar(
                      userId: choice.counterpartId,
                      fallbackName: choice.name,
                    ),
                    title: Text(choice.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, choice),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleConversationAction(_ConversationAction action) async {
    try {
      final choice = await _chooseConversation(action);
      if (choice == null || !mounted) return;
      final verb = action == _ConversationAction.delete ? 'delete' : 'block';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            action == _ConversationAction.delete
                ? 'Delete conversation?'
                : 'Block ${choice.name}?',
          ),
          content: Text(
            action == _ConversationAction.delete
                ? 'This conversation will be removed from your inbox.'
                : 'You and ${choice.name} will no longer be able to send each other messages.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(verb[0].toUpperCase() + verb.substring(1)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final conversation = FirebaseFirestore.instance
          .collection('conversations')
          .doc(choice.id);
      if (action == _ConversationAction.delete) {
        await conversation.update({
          'hiddenFor': FieldValue.arrayUnion([widget.userId]),
          'unreadFor': FieldValue.arrayRemove([widget.userId]),
        });
      } else {
        final batch = FirebaseFirestore.instance.batch();
        final block = FirebaseFirestore.instance
            .collection('user_blocks')
            .doc('${widget.userId}_${choice.counterpartId}');
        batch.set(block, {
          'blockerId': widget.userId,
          'blockedId': choice.counterpartId,
          'conversationId': choice.id,
          'createdAt': FieldValue.serverTimestamp(),
        });
        batch.update(conversation, {
          'hiddenFor': FieldValue.arrayUnion([widget.userId]),
          'unreadFor': FieldValue.arrayRemove([widget.userId]),
        });
        await batch.commit();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == _ConversationAction.delete
                ? 'Conversation deleted.'
                : '${choice.name} has been blocked.',
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : _chatCream;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final unreadSurface = dark
        ? const Color(0xFF393323)
        : const Color(0xFFFFF4CE);
    final text = dark ? const Color(0xFFF3F3F3) : _chatInk;
    final muted = dark ? const Color(0xFFB8B8B8) : const Color(0xFF737373);

    return Scaffold(
      backgroundColor: _chatYellow,
      bottomNavigationBar: widget.bottomNavigationBar,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (widget.showBackButton) ...[
                            Material(
                              color: const Color(0xFFFFF7D9),
                              shape: const CircleBorder(),
                              child: IconButton(
                                onPressed:
                                    widget.onBack ??
                                    () => Navigator.pop(context),
                                constraints: const BoxConstraints.tightFor(
                                  width: 38,
                                  height: 38,
                                ),
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: _chatInk,
                                  size: 19,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          const Text(
                            'Messages',
                            style: TextStyle(
                              color: _chatInk,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          PopupMenuButton<_ConversationAction>(
                            key: const ValueKey('messages-more-actions'),
                            tooltip: 'Conversation actions',
                            icon: const Icon(Icons.more_horiz, color: _chatInk),
                            onSelected: _handleConversationAction,
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: _ConversationAction.delete,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Delete conversation'),
                                ),
                              ),
                              PopupMenuItem(
                                value: _ConversationAction.block,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.block),
                                  title: Text('Block user'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Material(
                        color: surface,
                        elevation: 3,
                        borderRadius: BorderRadius.circular(20),
                        child: TextField(
                          key: const ValueKey('conversation-search'),
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(color: text, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search conversations...',
                            hintStyle: TextStyle(color: muted, fontSize: 12),
                            prefixIcon: Icon(
                              Icons.search,
                              color: muted,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(42),
                      ),
                    ),
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('conversations')
                          .where('participantIds', arrayContains: widget.userId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Could not load messages:\n${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: text),
                              ),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final documents = snapshot.data!.docs.toList()
                          ..sort((left, right) {
                            final leftTime =
                                left.data()['updatedAt'] as Timestamp?;
                            final rightTime =
                                right.data()['updatedAt'] as Timestamp?;
                            return (rightTime?.millisecondsSinceEpoch ?? 0)
                                .compareTo(
                                  leftTime?.millisecondsSinceEpoch ?? 0,
                                );
                          });
                        final latestByCounterpart =
                            <
                              String,
                              QueryDocumentSnapshot<Map<String, dynamic>>
                            >{};
                        for (final document in documents) {
                          final hiddenFor = document.data()['hiddenFor'];
                          if (hiddenFor is List &&
                              hiddenFor.contains(widget.userId)) {
                            continue;
                          }
                          final counterpartId = document
                              .data()[widget.counterpartIdField]
                              ?.toString();
                          if (counterpartId != null &&
                              counterpartId.isNotEmpty) {
                            latestByCounterpart.putIfAbsent(
                              counterpartId,
                              () => document,
                            );
                          }
                        }
                        final query = _searchController.text
                            .trim()
                            .toLowerCase();
                        final conversations = latestByCounterpart.values.where((
                          document,
                        ) {
                          if (query.isEmpty) return true;
                          final data = document.data();
                          final name = (data[widget.counterpartNameField] ?? '')
                              .toString()
                              .toLowerCase();
                          final message = (data['lastMessage'] ?? '')
                              .toString()
                              .toLowerCase();
                          return name.contains(query) ||
                              message.contains(query);
                        }).toList();
                        if (conversations.isEmpty) {
                          return Center(
                            child: Text(
                              query.isEmpty
                                  ? 'No conversations yet.'
                                  : 'No matching conversations.',
                              style: TextStyle(color: muted),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 30, 18, 24),
                          itemCount: conversations.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final conversation = conversations[index];
                            final data = conversation.data();
                            final counterpartId =
                                (data[widget.counterpartIdField] ?? '')
                                    .toString();
                            final name =
                                (data[widget.counterpartNameField] ??
                                        'Service user')
                                    .toString();
                            final unreadFor = data['unreadFor'];
                            final unread =
                                unreadFor is List &&
                                unreadFor.contains(widget.userId);
                            return _ConversationCard(
                              userId: counterpartId,
                              name: name,
                              message:
                                  (data['lastMessage'] ?? 'Open conversation')
                                      .toString(),
                              unread: unread,
                              surface: unread ? unreadSurface : surface,
                              text: text,
                              muted: muted,
                              onTap: () => widget.onOpenConversation(
                                conversation.id,
                                name,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.userId,
    required this.name,
    required this.message,
    required this.unread,
    required this.surface,
    required this.text,
    required this.muted,
    required this.onTap,
  });

  final String userId;
  final String name;
  final String message;
  final bool unread;
  final Color surface;
  final Color text;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    elevation: 3,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 90),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: unread ? Border.all(color: _chatYellow, width: 1.2) : null,
        ),
        child: Row(
          children: [
            LiveProfileAvatar(
              userId: userId,
              fallbackName: name,
              radius: 25,
              backgroundColor: const Color(0xFFFFF1C8),
              foregroundColor: _chatInk,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: text,
                            fontSize: 15,
                            fontWeight: unread
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unread ? text : muted,
                      fontSize: 11,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: text, size: 30),
          ],
        ),
      ),
    ),
  );
}
