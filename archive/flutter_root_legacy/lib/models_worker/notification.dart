class NotificationItem {
  final String id;
  final String title;
  final String body;
  final bool read;

  const NotificationItem({required this.id, required this.title, required this.body, this.read = false});
}
