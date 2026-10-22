import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/utils/message_time.dart';

void main() {
  final now = DateTime(2026, 10, 22, 15, 0);

  test('formats today and yesterday timestamps consistently', () {
    expect(
      messageTimestampLabel(DateTime(2026, 10, 22, 10, 30), now: now),
      'Today, 10:30 AM',
    );
    expect(
      messageTimestampLabel(DateTime(2026, 10, 21, 19, 5), now: now),
      'Yesterday, 7:05 PM',
    );
  });

  test('formats older dates and detects calendar boundaries', () {
    expect(
      messageDateSeparatorLabel(DateTime(2026, 10, 10, 8), now: now),
      'October 10, 2026',
    );
    expect(
      isSameMessageDate(DateTime(2026, 10, 22, 8), DateTime(2026, 10, 22, 20)),
      isTrue,
    );
    expect(
      isSameMessageDate(DateTime(2026, 10, 21, 23, 59), DateTime(2026, 10, 22)),
      isFalse,
    );
  });
}
