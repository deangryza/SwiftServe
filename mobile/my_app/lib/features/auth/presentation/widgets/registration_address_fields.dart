import 'package:flutter/material.dart';

import '../../../../shared/services/job_geocoding_service.dart';
import 'use_current_location_button.dart';

/// Keeps the profile's existing address string while requiring its three parts.
class RegistrationAddressFields extends StatefulWidget {
  const RegistrationAddressFields({
    super.key,
    required this.address,
    required this.enabled,
    required this.fieldColor,
    required this.textColor,
    required this.mutedColor,
    required this.borderColor,
    required this.focusColor,
  });

  final TextEditingController address;
  final bool enabled;
  final Color fieldColor;
  final Color textColor;
  final Color mutedColor;
  final Color borderColor;
  final Color focusColor;

  @override
  State<RegistrationAddressFields> createState() =>
      _RegistrationAddressFieldsState();
}

class _RegistrationAddressFieldsState extends State<RegistrationAddressFields> {
  String _barangayName(String value) => value
      .trim()
      .replaceFirst(
        RegExp(r'^(?:brgy\.?|barangay)(?:\s+|$)', caseSensitive: false),
        '',
      )
      .trim();
  final _street = TextEditingController();
  final _barangay = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Addresses composed by this form always end in these three components.
    // Older single-part addresses still need the missing components filled in.
    final parts = widget.address.text
        .split(',')
        .map((part) => part.trim())
        .toList();
    if (parts.length >= 3) {
      _province.text = parts.removeLast();
      _city.text = parts.removeLast();
      _barangay.text = _barangayName(parts.removeLast());
      _street.text = parts.join(', ');
    } else {
      _street.text = widget.address.text;
    }
    for (final field in [_street, _barangay, _city, _province]) {
      field.addListener(_syncAddress);
    }
  }

  void _syncAddress() {
    // Retain empty required components so moving back through signup cannot
    // reinterpret the street as a barangay when an address is incomplete.
    widget.address.text = [
      if (_street.text.trim().isNotEmpty) _street.text.trim(),
      if (_barangayName(_barangay.text).isNotEmpty)
        'Brgy. ${_barangayName(_barangay.text)}'
      else
        '',
      _city.text.trim(),
      _province.text.trim(),
    ].join(', ');
  }

  void _fillAddress(ResolvedJobAddress address) {
    _street.text =
        address.street.isEmpty &&
            address.barangay.isEmpty &&
            address.cityMunicipality.isEmpty &&
            address.province.isEmpty
        ? address.exactAddress
        : address.street;
    _barangay.text = _barangayName(address.barangay);
    _city.text = address.cityMunicipality;
    _province.text = address.province;
    _syncAddress();
  }

  @override
  void dispose() {
    for (final field in [_street, _barangay, _city, _province]) {
      field.removeListener(_syncAddress);
      field.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String label,
    String hint,
    TextEditingController controller, {
    bool required = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: widget.textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          key: ValueKey(label),
          controller: controller,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          validator: (value) =>
              required &&
                  (value == null ||
                      value.trim().isEmpty ||
                      (label == 'Barangay' && _barangayName(value).isEmpty))
              ? '$label is required.'
              : null,
          style: TextStyle(color: widget.textColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: widget.mutedColor),
            filled: true,
            fillColor: widget.fieldColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: widget.focusColor, width: 1.5),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Barangay, city / municipality, and province are required. Review any details filled by GPS.',
        style: TextStyle(color: widget.mutedColor, fontSize: 12),
      ),
      const SizedBox(height: 12),
      _field(
        'Street / House No. (optional)',
        'House number, street, or building',
        _street,
        required: false,
      ),
      _field('Barangay', 'e.g. Bulihan', _barangay),
      _field('City / Municipality', 'e.g. Malolos', _city),
      _field('Province', 'e.g. Bulacan', _province),
      UseCurrentLocationButton(
        address: widget.address,
        enabled: widget.enabled,
        onAddressResolved: _fillAddress,
      ),
    ],
  );
}
