import 'package:flutter/foundation.dart';

/// Registration state; resolved service names fit the existing skills schema.
class WorkerServiceSelection extends ChangeNotifier {
  final Set<String> _selected = {};
  String _customService = '';

  bool contains(String category) => _selected.any(
    (item) => item.toLowerCase() == category.trim().toLowerCase(),
  );
  bool get hasOther => _selected.any((value) => value.toLowerCase() == 'other');
  String get customService => _customService;

  /// Preserve existing custom service names as individually removable choices.
  void loadServices(Iterable<String> services) {
    _selected.clear();
    _customService = '';
    for (final value in services) {
      final name = value.trim();
      if (name.isNotEmpty &&
          !_selected.any((item) => item.toLowerCase() == name.toLowerCase())) {
        _selected.add(name);
      }
    }
    notifyListeners();
  }

  void toggle(String category) {
    final name = category.trim();
    if (name.isEmpty) return;
    final existing = _selected
        .where((item) => item.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (existing == null) {
      _selected.add(name);
    } else {
      _selected.remove(existing);
    }
    notifyListeners();
  }

  void specifyOther(String value) {
    _customService = value;
    notifyListeners();
  }

  List<String> get services {
    final result = <String>[];
    for (final category in _selected) {
      final label = category.toLowerCase() == 'other'
          ? _customService.trim()
          : category;
      if (label.isNotEmpty &&
          !result.any((item) => item.toLowerCase() == label.toLowerCase())) {
        result.add(label);
      }
    }
    return result;
  }

  String? get validationError {
    if (_selected.isEmpty) return 'Select at least one service category.';
    if (hasOther && _customService.trim().isEmpty) {
      return 'Please specify your service.';
    }
    if (hasOther && _customService.trim().toLowerCase() == 'other') {
      return 'Enter the actual service you provide.';
    }
    if (hasOther && _customService.length > 80) {
      return 'Use 80 characters or fewer for your service.';
    }
    if (services.length > 50) return 'Select up to 50 services.';
    if (services.any((name) => name.length > 80)) {
      return 'Service names must be 80 characters or fewer.';
    }
    return null;
  }
}
