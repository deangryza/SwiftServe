/// Public residential location. Never falls back to an unrecognized address.
/// Legacy strings require explicit barangay/city labels; comma positions alone
/// cannot distinguish a barangay from a street, subdivision or landmark.
class PublicProfileLocation {
  const PublicProfileLocation({this.barangay = '', this.cityMunicipality = ''});

  final String barangay;
  final String cityMunicipality;

  String get label => cityMunicipality.isEmpty
      ? ''
      : barangay.isEmpty
      ? cityMunicipality
      : 'Brgy. $barangay, $cityMunicipality';

  String get displayLabel => label.isEmpty ? 'Location not provided' : label;

  factory PublicProfileLocation.fromProfile(Map<String, dynamic> data) {
    // New backend projections carry explicit components. Do not let an empty
    // authoritative projection revive an old full-address fallback.
    if (data.containsKey('cityMunicipality')) {
      final city = _name(_city(data['cityMunicipality']), digits: false);
      return PublicProfileLocation(
        barangay: city.isEmpty
            ? ''
            : _name(_barangay(data['barangay']), digits: true),
        cityMunicipality: city,
      );
    }
    return PublicProfileLocation.fromAddress(data['location']);
  }

  factory PublicProfileLocation.fromAddress(Object? value) {
    if (value is! String ||
        value.length > 300 ||
        value.contains(RegExp(r'[\r\n\x00-\x1f]'))) {
      return const PublicProfileLocation();
    }
    final parts = value.split(',').map((p) => p.trim()).toList();
    for (var i = 0; i + 1 < parts.length; i++) {
      if (!_barangayPrefix.hasMatch(parts[i])) continue;
      final city = _name(_city(parts[i + 1]), digits: false);
      if (city.isNotEmpty) {
        return PublicProfileLocation(
          barangay: _name(_barangay(parts[i]), digits: true),
          cityMunicipality: city,
        );
      }
    }
    // A labeled city can be retained even if no usable barangay was stored.
    for (final part in parts) {
      if (!_cityPrefix.hasMatch(part) && !_citySuffix.hasMatch(part)) continue;
      final city = _name(_city(part), digits: false);
      if (city.isNotEmpty) return PublicProfileLocation(cityMunicipality: city);
    }
    return const PublicProfileLocation();
  }
}

final _barangayPrefix = RegExp(
  r'^(?:brgy\.?|barangay)\s+',
  caseSensitive: false,
);
final _cityPrefix = RegExp(
  r'^(?:city\s*/\s*municipality\s*:|(?:city|municipality)\s+of\s+)',
  caseSensitive: false,
);
final _citySuffix = RegExp(r'\s+(?:city|municipality)$', caseSensitive: false);
final _details = RegExp(
  r'\b(?:street|st|road|rd|avenue|ave|house|lot|block|blk|unit|building|bldg|subdivision|subd|village|villas|landmark|sitio|purok|phase|tower|condo|floor|compound|near|beside|across|highway|hwy|lane|drive|barangay|brgy)\b',
  caseSensitive: false,
);
String _barangay(Object? value) => value is String
    ? value.trim().replaceFirst(_barangayPrefix, '').trim()
    : '';
String _city(Object? value) => value is String
    ? value
          .trim()
          .replaceFirst(_cityPrefix, '')
          .replaceFirst(_citySuffix, '')
          .trim()
    : '';

String _name(String value, {required bool digits}) {
  if (value.isEmpty ||
      value.length > 80 ||
      value.contains(RegExp(r'[\r\n\x00-\x1f]')) ||
      _details.hasMatch(value)) {
    return '';
  }
  // Explicit barangay components can have identifiers such as 183 or 1-A.
  final pattern = digits
      ? r"^[A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF][A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF .'-]*$"
      : r"^[A-Za-z\u00C0-\u024F\u1E00-\u1EFF][A-Za-z\u00C0-\u024F\u1E00-\u1EFF .'-]*$";
  if (!RegExp(pattern).hasMatch(value)) {
    return '';
  }
  return value.replaceAll(RegExp(r'\s+'), ' ');
}
