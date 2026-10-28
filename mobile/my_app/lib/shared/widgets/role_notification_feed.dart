import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../repositories/notification_repository.dart';

/// Replaces the subscription and snapshot when either account or role changes.
class RoleNotificationFeed extends StatefulWidget {
  const RoleNotificationFeed({
    super.key,
    required this.uid,
    required this.role,
    required this.builder,
    this.source,
  });
  final String uid;
  final UserRole role;
  final RoleNotificationSource? source;
  final AsyncWidgetBuilder<List<NotificationDocument>> builder;
  @override
  State<RoleNotificationFeed> createState() => _RoleNotificationFeedState();
}

class _RoleNotificationFeedState extends State<RoleNotificationFeed> {
  late Stream<List<NotificationDocument>> _stream;
  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() => _stream = (widget.source ?? NotificationRepository())
      .watch(widget.uid, widget.role);
  @override
  void didUpdateWidget(RoleNotificationFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.role != widget.role ||
        oldWidget.source != widget.source) {
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<NotificationDocument>>(
        key: ValueKey('${widget.uid}-${widget.role.name}'),
        stream: _stream,
        builder: widget.builder,
      );
}
