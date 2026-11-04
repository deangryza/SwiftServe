/// Birthdays are calendar dates, not instants. SwiftServe uses Philippine dates.
abstract final class RegistrationBirthday {
  static const ineligibleMessage =
      'You are not eligible to use SwiftServe. You must be at least 18 years old to create an account.';

  static DateTime today([DateTime? now]) {
    final pht = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    return DateTime(pht.year, pht.month, pht.day);
  }

  static String encode(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static DateTime? parse(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime(parts[0], parts[1], parts[2]);
    return date.year >= 1900 && encode(date) == value ? date : null;
  }

  static String? validate(String? value, {DateTime? now}) {
    if (value == null || value.isEmpty) return 'Birthday is required.';
    final birth = parse(value);
    if (birth == null) return 'Select a valid birthday.';
    final current = today(now);
    if (birth.isAfter(current)) return 'Birthday cannot be in the future.';
    var age = current.year - birth.year;
    if (current.month < birth.month ||
        (current.month == birth.month && current.day < birth.day)) {
      age--;
    }
    return age >= 18 ? null : ineligibleMessage;
  }
}
