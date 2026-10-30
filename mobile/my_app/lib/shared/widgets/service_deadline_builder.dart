import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/service_request.dart';

/// Firestore streams do not emit merely because time passes. Rebuild at the
/// next application deadline and when returning from the background.
class ServiceDeadlineBuilder extends StatefulWidget {
  const ServiceDeadlineBuilder({
    super.key,
    required this.requests,
    required this.builder,
    this.now,
  });

  final Iterable<ServiceRequest> requests;
  final Widget Function(BuildContext, DateTime) builder;
  final DateTime Function()? now;

  @override
  State<ServiceDeadlineBuilder> createState() => _ServiceDeadlineBuilderState();
}

class _ServiceDeadlineBuilderState extends State<ServiceDeadlineBuilder>
    with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ServiceDeadlineBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _now = widget.now?.call() ?? DateTime.now();
    DateTime? next;
    for (final request in widget.requests) {
      final deadline = request.applicationDeadline;
      if (request.status == ServiceRequestStatus.pending &&
          deadline != null &&
          deadline.isAfter(_now) &&
          (next == null || deadline.isBefore(next))) {
        next = deadline;
      }
    }
    if (next != null) _timer = Timer(next.difference(_now), _refresh);
  }

  void _refresh() {
    if (mounted) setState(_schedule);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
