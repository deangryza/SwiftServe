import 'package:flutter/material.dart';

import '../../../../shared/utils/registration_birthday.dart';

class RegistrationBirthdayField extends StatefulWidget {
  const RegistrationBirthdayField({
    super.key,
    required this.controller,
    this.enabled = true,
  });
  final TextEditingController controller;
  final bool enabled;

  @override
  State<RegistrationBirthdayField> createState() =>
      _RegistrationBirthdayFieldState();
}

class _RegistrationBirthdayFieldState extends State<RegistrationBirthdayField> {
  final _field = GlobalKey<FormFieldState<String>>();

  Future<void> _pick() async {
    final today = RegistrationBirthday.today();
    final existing = RegistrationBirthday.parse(widget.controller.text);
    final selected = await showDatePicker(
      context: context,
      helpText: 'Select your birthday',
      initialDate: existing != null && !existing.isAfter(today)
          ? existing
          : DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (!mounted || selected == null) return;
    widget.controller.text = RegistrationBirthday.encode(selected);
    _field.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      key: _field,
      controller: widget.controller,
      readOnly: true,
      enabled: widget.enabled,
      onTap: _pick,
      validator: RegistrationBirthday.validate,
      decoration: const InputDecoration(
        labelText: 'Birthday',
        hintText: 'Select your date of birth',
        helperText: 'You must be at least 18 years old.',
        errorMaxLines: 5,
        filled: true,
        suffixIcon: Icon(Icons.calendar_today_outlined),
      ),
    ),
  );
}
