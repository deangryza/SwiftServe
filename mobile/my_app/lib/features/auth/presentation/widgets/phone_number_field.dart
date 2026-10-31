import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneCountry {
  const PhoneCountry({
    required this.isoCode,
    required this.name,
    required this.dialCode,
    required this.example,
    required this.minimumLength,
    required this.maximumLength,
    this.requiredPrefix,
  });

  final String isoCode;
  final String name;
  final String dialCode;
  final String example;
  final int minimumLength;
  final int maximumLength;
  final String? requiredPrefix;
}

const phoneCountries = <PhoneCountry>[
  PhoneCountry(
    isoCode: 'PH',
    name: 'Philippines',
    dialCode: '+63',
    example: '917 123 4567',
    minimumLength: 10,
    maximumLength: 10,
    requiredPrefix: '9',
  ),
  PhoneCountry(
    isoCode: 'US',
    name: 'United States / Canada',
    dialCode: '+1',
    example: '202 555 0123',
    minimumLength: 10,
    maximumLength: 10,
  ),
  PhoneCountry(
    isoCode: 'GB',
    name: 'United Kingdom',
    dialCode: '+44',
    example: '7700 900123',
    minimumLength: 10,
    maximumLength: 10,
  ),
  PhoneCountry(
    isoCode: 'AU',
    name: 'Australia',
    dialCode: '+61',
    example: '412 345 678',
    minimumLength: 9,
    maximumLength: 9,
  ),
  PhoneCountry(
    isoCode: 'SG',
    name: 'Singapore',
    dialCode: '+65',
    example: '8123 4567',
    minimumLength: 8,
    maximumLength: 8,
  ),
  PhoneCountry(
    isoCode: 'JP',
    name: 'Japan',
    dialCode: '+81',
    example: '90 1234 5678',
    minimumLength: 10,
    maximumLength: 10,
  ),
  PhoneCountry(
    isoCode: 'KR',
    name: 'South Korea',
    dialCode: '+82',
    example: '10 1234 5678',
    minimumLength: 9,
    maximumLength: 10,
  ),
  PhoneCountry(
    isoCode: 'IN',
    name: 'India',
    dialCode: '+91',
    example: '98765 43210',
    minimumLength: 10,
    maximumLength: 10,
  ),
];

PhoneCountry phoneCountryFor(String dialCode) => phoneCountries.firstWhere(
  (country) => country.dialCode == dialCode,
  orElse: () => phoneCountries.first,
);

String nationalPhoneDigits(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}

String normalizePhoneNumber(String dialCode, String value) =>
    '$dialCode${nationalPhoneDigits(value)}';

String? validatePhoneNumber(String? value, String dialCode) {
  if (value == null || value.trim().isEmpty) {
    return 'Phone number is required.';
  }
  if (RegExp(r'[^0-9\s()-]').hasMatch(value)) {
    return 'Use numbers only.';
  }
  final country = phoneCountryFor(dialCode);
  final digits = nationalPhoneDigits(value);
  final validLength =
      digits.length >= country.minimumLength &&
      digits.length <= country.maximumLength;
  final validPrefix =
      country.requiredPrefix == null ||
      digits.startsWith(country.requiredPrefix!);
  if (!validLength || !validPrefix) {
    return 'Enter a valid ${country.name} phone number.';
  }
  if (dialCode.replaceAll('+', '').length + digits.length > 15) {
    return 'Phone number is too long.';
  }
  return null;
}

class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    required this.dialCode,
    required this.onDialCodeChanged,
    required this.enabled,
    required this.fieldColor,
    required this.textColor,
    required this.mutedColor,
    required this.borderColor,
    required this.focusColor,
    this.fieldKey,
    this.errorText,
    this.suffixIcon,
  });

  final Key? fieldKey;
  final String? errorText;
  final Widget? suffixIcon;
  final TextEditingController controller;
  final String dialCode;
  final ValueChanged<String> onDialCodeChanged;
  final bool enabled;
  final Color fieldColor;
  final Color textColor;
  final Color mutedColor;
  final Color borderColor;
  final Color focusColor;

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final country = phoneCountryFor(dialCode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phone Number',
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('phone-country-code'),
                  initialValue: dialCode,
                  isExpanded: true,
                  dropdownColor: fieldColor,
                  style: TextStyle(color: textColor, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: fieldColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 15,
                    ),
                    border: _border(borderColor),
                    enabledBorder: _border(borderColor),
                    focusedBorder: _border(focusColor, 1.5),
                  ),
                  items: phoneCountries
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.dialCode,
                          child: Text('${item.isoCode} ${item.dialCode}'),
                        ),
                      )
                      .toList(),
                  onChanged: enabled
                      ? (value) {
                          if (value != null) onDialCodeChanged(value);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: fieldKey,
                  controller: controller,
                  enabled: enabled,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  maxLength: country.maximumLength,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _NationalPhoneInputFormatter(),
                  ],
                  validator: (value) => validatePhoneNumber(value, dialCode),
                  forceErrorText: errorText,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    suffixIcon: suffixIcon,
                    errorMaxLines: 3,
                    hintText: country.example,
                    counterText: '',
                    hintStyle: TextStyle(color: mutedColor),
                    filled: true,
                    fillColor: fieldColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    border: _border(borderColor),
                    enabledBorder: _border(borderColor),
                    focusedBorder: _border(focusColor, 1.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NationalPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceFirst(RegExp(r'^0+'), '');
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
