import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/utils/role_context.dart';
import '../../../../shared/widgets/role_notification_feed.dart';
import '../../../../shared/widgets/simple_back_button.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/message_time.dart';
import '../../../../shared/widgets/action_confirmation_dialog.dart';

import '../../../../shared/widgets/live_profile_avatar.dart';

const _chatYellow = AppTheme.yellow;
const _chatCream = Color(0xFFFFFFFF);
const _chatInk = AppTheme.ink;

enum _ConversationAction { delete, block, unblock }

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
  String userId, {
  UserRole role = UserRole.client,
}) {
  return conversations.where((conversation) {
    final data = conversation.data();
    if (!conversationMatchesRole(data, userId, role)) return false;
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
    this.role = UserRole.client,
  });

  final String? userId;
  final Widget child;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    if (userId == null || userId!.isEmpty || Firebase.apps.isEmpty) {
      return child;
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey('conversation-badge-$userId-${role.name}'),
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', arrayContains: userId)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData
            ? conversationUnreadCount(snapshot.data!.docs, userId!, role: role)
            : 0;
        return Badge(
          isLabelVisible: count > 0,
          backgroundColor: AppTheme.ink,
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
    this.role = UserRole.client,
  });

  final String? userId;
  final Widget child;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    if (userId == null || userId!.isEmpty || Firebase.apps.isEmpty) {
      return child;
    }
    return RoleNotificationFeed(
      uid: userId!,
      role: role,
      builder: (context, snapshot) {
        final hasUnread =
            snapshot.hasData &&
            snapshot.data!.any(
              (notification) => notification.data()['read'] != true,
            );
        return Badge(
          isLabelVisible: hasUnread,
          backgroundColor: AppTheme.ink,
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
    required this.role,
    this.conversationStream,
    required this.counterpartIdField,
    required this.counterpartNameField,
    required this.onOpenConversation,
    this.onBack,
    this.bottomNavigationBar,
    this.showBackButton = false,
  });

  final String userId;
  final UserRole role;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? conversationStream;
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
  late Stream<QuerySnapshot<Map<String, dynamic>>> _conversations;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() => _conversations =
      widget.conversationStream ??
      FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', arrayContains: widget.userId)
          .snapshots();

  @override
  void didUpdateWidget(ConversationInboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.role != widget.role ||
        oldWidget.conversationStream != widget.conversationStream) {
      _searchController.clear();
      _subscribe();
    }
  }

  Future<List<_ConversationChoice>> _blockedChoices() async {
    final blocks = await FirebaseFirestore.instance
        .collection('user_blocks')
        .where('blockerId', isEqualTo: widget.userId)
        .get();

    return Future.wait(
      blocks.docs.map((block) async {
        final data = block.data();
        final conversationId = (data['conversationId'] ?? '').toString();
        final counterpartId = (data['blockedId'] ?? '').toString();
        if (conversationId.isEmpty || counterpartId.isEmpty) return null;

        final conversation = await FirebaseFirestore.instance
            .collection('conversations')
            .doc(conversationId)
            .get();
        final conversationData = conversation.data();
        if (conversationData == null ||
            !conversationMatchesRole(
              conversationData,
              widget.userId,
              widget.role,
            )) {
          return null;
        }
        return _ConversationChoice(
          id: conversationId,
          counterpartId: counterpartId,
          name:
              (conversationData[widget.counterpartNameField] ?? 'Blocked user')
                  .toString(),
        );
      }),
    ).then(
      (choices) =>
          choices.whereType<_ConversationChoice>().toList(growable: false),
    );
  }

  Future<List<_ConversationChoice>> _conversationChoices(
    _ConversationAction action,
  ) async {
    if (action == _ConversationAction.unblock) return _blockedChoices();

    final snapshot = await FirebaseFirestore.instance
        .collection('conversations')
        .where('participantIds', arrayContains: widget.userId)
        .get();
    final blockedIds = action == _ConversationAction.block
        ? (await FirebaseFirestore.instance
                  .collection('user_blocks')
                  .where('blockerId', isEqualTo: widget.userId)
                  .get())
              .docs
              .map((block) => (block.data()['blockedId'] ?? '').toString())
              .toSet()
        : const <String>{};
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
      if (!conversationMatchesRole(data, widget.userId, widget.role)) continue;
      final hiddenFor = data['hiddenFor'];
      if (hiddenFor is List && hiddenFor.contains(widget.userId)) continue;
      final counterpartId = data[widget.counterpartIdField]?.toString();
      if (counterpartId == null || counterpartId.isEmpty) continue;
      if (blockedIds.contains(counterpartId)) continue;
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
    final choices = await _conversationChoices(action);
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
              title: Text(switch (action) {
                _ConversationAction.delete => 'Delete a conversation',
                _ConversationAction.block => 'Block a user',
                _ConversationAction.unblock => 'Unblock a user',
              }, style: const TextStyle(fontWeight: FontWeight.w700)),
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
      final verb = switch (action) {
        _ConversationAction.delete => 'delete',
        _ConversationAction.block => 'block',
        _ConversationAction.unblock => 'unblock',
      };
      final confirmed = await showActionConfirmation(
        context,
        title: switch (action) {
          _ConversationAction.delete => 'Delete conversation?',
          _ConversationAction.block => 'Block ${choice.name}?',
          _ConversationAction.unblock => 'Unblock ${choice.name}?',
        },
        message: switch (action) {
          _ConversationAction.delete =>
            'Are you sure you want to delete this conversation? It will be removed from your inbox.',
          _ConversationAction.block =>
            'Are you sure you want to block ${choice.name}? You will no longer be able to message each other.',
          _ConversationAction.unblock =>
            'Are you sure you want to unblock ${choice.name}? You will be able to message each other again.',
        },
        confirmLabel: verb[0].toUpperCase() + verb.substring(1),
        icon: action == _ConversationAction.block
            ? Icons.block_rounded
            : Icons.delete_outline_rounded,
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
      } else if (action == _ConversationAction.block) {
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
          'hiddenFor': FieldValue.arrayRemove([widget.userId]),
          'unreadFor': FieldValue.arrayRemove([widget.userId]),
        });
        await batch.commit();
      } else {
        final batch = FirebaseFirestore.instance.batch();
        batch.delete(
          FirebaseFirestore.instance
              .collection('user_blocks')
              .doc('${widget.userId}_${choice.counterpartId}'),
        );
        batch.update(conversation, {
          'hiddenFor': FieldValue.arrayRemove([widget.userId]),
        });
        await batch.commit();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            _ConversationAction.delete => 'Conversation deleted.',
            _ConversationAction.block =>
              '${choice.name} has been blocked. Messages are now restricted.',
            _ConversationAction.unblock =>
              '${choice.name} has been unblocked. You can message each other again.',
          }),
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
    final unreadSurface = dark ? const Color(0xFF393323) : AppTheme.softYellow;
    final text = dark ? const Color(0xFFF3F3F3) : _chatInk;
    final muted = dark ? const Color(0xFFB8B8B8) : AppTheme.muted;

    return Scaffold(
      backgroundColor: background,
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
                            SimpleBackButton(
                              onPressed:
                                  widget.onBack ?? () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Text(
                            'Messages',
                            style: TextStyle(
                              color: text,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          PopupMenuButton<_ConversationAction>(
                            key: const ValueKey('messages-more-actions'),
                            tooltip: 'Conversation actions',
                            icon: Icon(Icons.more_horiz, color: text),
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
                              PopupMenuItem(
                                value: _ConversationAction.unblock,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.lock_open_outlined),
                                  title: Text('Blocked users'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Material(
                        color: surface,
                        elevation: 0,
                        borderRadius: BorderRadius.circular(14),
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
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
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
                      borderRadius: BorderRadius.zero,
                    ),
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      key: ValueKey(
                        'inbox-${widget.userId}-${widget.role.name}',
                      ),
                      stream: _conversations,
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
                          if (!conversationMatchesRole(
                            document.data(),
                            widget.userId,
                            widget.role,
                          )) {
                            continue;
                          }
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
                            final updatedAt = data['updatedAt'] as Timestamp?;
                            return _ConversationCard(
                              userId: counterpartId,
                              name: name,
                              message:
                                  (data['lastMessage'] ?? 'Open conversation')
                                      .toString(),
                              timestamp: updatedAt?.toDate(),
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
    required this.timestamp,
    required this.unread,
    required this.surface,
    required this.text,
    required this.muted,
    required this.onTap,
  });

  final String userId;
  final String name;
  final String message;
  final DateTime? timestamp;
  final bool unread;
  final Color surface;
  final Color text;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: Theme.of(context).dividerColor),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 90),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: unread ? Border.all(color: _chatYellow, width: 1.2) : null,
        ),
        child: Row(
          children: [
            LiveProfileAvatar(
              userId: userId,
              fallbackName: name,
              radius: 25,
              backgroundColor: AppTheme.softYellow,
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
                      if (timestamp != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          messageTimestampLabel(timestamp!),
                          style: TextStyle(
                            color: muted,
                            fontSize: 9,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                      if (unread)
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppTheme.ink,
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
