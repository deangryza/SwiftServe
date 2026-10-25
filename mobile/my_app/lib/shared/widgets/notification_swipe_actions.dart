import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A continuous swipe-to-action container for notification cards.
///
/// Swipe left to view details and right to delete. Releasing past the threshold
/// runs the matching action; shorter gestures return the card to rest.
class NotificationSwipeActions extends StatefulWidget {
  const NotificationSwipeActions({
    super.key,
    required this.child,
    required this.onViewDetails,
    required this.onDelete,
    required this.actionKeyPrefix,
  });

  final Widget child;
  final VoidCallback onViewDetails;
  final VoidCallback onDelete;
  final String actionKeyPrefix;

  @override
  State<NotificationSwipeActions> createState() =>
      _NotificationSwipeActionsState();
}

class _NotificationSwipeActionsState extends State<NotificationSwipeActions> {
  static const double _actionWidth = 112;
  static const double _triggerThreshold = 68;
  static const double _velocityThreshold = 700;
  double _offset = 0;
  bool _dragging = false;

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragging = true;
      _offset = (_offset + details.delta.dx).clamp(-_actionWidth, _actionWidth);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final viewDetails =
        _offset <= -_triggerThreshold || velocity <= -_velocityThreshold;
    final delete =
        _offset >= _triggerThreshold || velocity >= _velocityThreshold;
    setState(() {
      _dragging = false;
      _offset = 0;
    });
    if (delete) {
      widget.onDelete();
    } else if (viewDetails) {
      widget.onViewDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final deleteColor = dark ? const Color(0xFF3A3A3A) : AppTheme.ink;
    final viewProgress = (-_offset / _triggerThreshold).clamp(0.0, 1.0);
    final deleteProgress = (_offset / _triggerThreshold).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: Row(
              children: [
                SizedBox(
                  width: _actionWidth,
                  child: _SwipeFeedback(
                    key: ValueKey('${widget.actionKeyPrefix}-delete-action'),
                    color: deleteColor,
                    foregroundColor: Colors.white,
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    progress: deleteProgress,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: _actionWidth,
                  child: _SwipeFeedback(
                    key: ValueKey('${widget.actionKeyPrefix}-view-action'),
                    color: AppTheme.yellow,
                    foregroundColor: AppTheme.ink,
                    icon: Icons.visibility_outlined,
                    label: 'View Details',
                    progress: viewProgress,
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: GestureDetector(
              key: ValueKey('${widget.actionKeyPrefix}-gesture'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              onHorizontalDragCancel: () => setState(() {
                _dragging = false;
                _offset = 0;
              }),
              child: AbsorbPointer(
                absorbing: _offset != 0,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeFeedback extends StatelessWidget {
  const _SwipeFeedback({
    super.key,
    required this.color,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    required this.progress,
  });

  final Color color;
  final Color foregroundColor;
  final IconData icon;
  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Semantics(
      label: label,
      child: Center(
        child: Opacity(
          opacity: 0.65 + (progress * 0.35),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 1 + (progress * 0.1),
                child: Icon(icon, color: foregroundColor, size: 23),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
