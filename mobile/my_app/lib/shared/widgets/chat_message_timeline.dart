import 'package:flutter/material.dart';

class ChatMessageIdentity {
  const ChatMessageIdentity({required this.id, required this.senderId});
  final String id, senderId;
}

/// Receives chronological messages while rendering the latest at offset zero.
/// Incoming messages are deferred while reading history, so inserting new rows
/// never shifts that history's pixel position. Older pages still render normally.
class ChatMessageTimeline extends StatefulWidget {
  const ChatMessageTimeline({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.messages,
    required this.itemBuilder,
  });
  final String conversationId, currentUserId;
  final List<ChatMessageIdentity> messages;
  final IndexedWidgetBuilder itemBuilder;
  @override
  State<ChatMessageTimeline> createState() => _ChatMessageTimelineState();
}

class _ChatMessageTimelineState extends State<ChatMessageTimeline> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final _deferred = <String>{};
  bool _following = true;
  bool _scrollScheduled = false;
  bool _forceLatest = false;
  int _generation = 0;
  static const _nearLatest = 80.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _following =
        _scroll.position.pixels - _scroll.position.minScrollExtent <=
        _nearLatest;
    if (_following && _deferred.isNotEmpty) _scheduleLatest();
  }

  void _scheduleLatest({bool force = false}) {
    _forceLatest = _forceLatest || force;
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _scrollScheduled = false;
      final force = _forceLatest;
      _forceLatest = false;
      if (!_following && !force) return;
      if (_deferred.isNotEmpty) setState(_deferred.clear);
      _following = true;
      if (_scroll.hasClients &&
          _scroll.position.pixels != _scroll.position.minScrollExtent) {
        // A reversed list has an exact, stable latest offset even with thousands
        // of variable-height rows. No estimated maxScrollExtent or retry loop.
        _scroll.jumpTo(_scroll.position.minScrollExtent);
      }
    });
  }

  @override
  void didUpdateWidget(ChatMessageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId ||
        oldWidget.currentUserId != widget.currentUserId) {
      _generation++;
      _scrollScheduled = false;
      _forceLatest = false;
      _deferred.clear();
      _following = true;
      _scheduleLatest(force: true);
      return;
    }
    final oldIds = oldWidget.messages.map((message) => message.id).toSet();
    final indices = {
      for (var i = 0; i < widget.messages.length; i++) widget.messages[i].id: i,
    };
    int? boundary;
    for (final message in oldWidget.messages.reversed) {
      if (indices.containsKey(message.id)) {
        boundary = indices[message.id];
        break;
      }
    }
    final newTail = widget.messages
        .skip(boundary == null ? 0 : boundary + 1)
        .where((message) => !oldIds.contains(message.id))
        .toList();
    _deferred.removeWhere((id) => !indices.containsKey(id));
    if (newTail.isEmpty) {
      return; // Includes timestamp acknowledgements and older pages.
    }
    if (_following ||
        newTail.any((message) => message.senderId == widget.currentUserId)) {
      _deferred.clear();
      _scheduleLatest(
        force: newTail.any(
          (message) => message.senderId == widget.currentUserId,
        ),
      );
    } else {
      _deferred.addAll(newTail.map((message) => message.id));
    }
  }

  @override
  void dispose() {
    _generation++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indices = [
      for (var i = widget.messages.length - 1; i >= 0; i--)
        if (!_deferred.contains(widget.messages[i].id)) i,
    ];
    final childIndices = {
      for (var i = 0; i < indices.length; i++)
        widget.messages[indices[i]].id: i,
    };
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 && _following) _scheduleLatest();
            return false;
          },
          child: ListView.builder(
            key: ValueKey('chat-timeline-${widget.conversationId}'),
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: indices.length,
            findChildIndexCallback: (key) =>
                key is ValueKey<String> ? childIndices[key.value] : null,
            itemBuilder: (context, index) => KeyedSubtree(
              key: ValueKey(widget.messages[indices[index]].id),
              child: widget.itemBuilder(context, indices[index]),
            ),
          ),
        ),
        if (_deferred.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(
              child: FilledButton.tonalIcon(
                key: const ValueKey('chat-new-messages'),
                onPressed: () {
                  _scheduleLatest(force: true);
                  setState(() {});
                },
                icon: const Icon(Icons.arrow_downward, size: 18),
                label: Text('New messages (${_deferred.length})'),
              ),
            ),
          ),
      ],
    );
  }
}
