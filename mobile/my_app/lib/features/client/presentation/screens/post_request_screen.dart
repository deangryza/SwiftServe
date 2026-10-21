import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/models/job_location.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/widgets/job_location_picker.dart';

String? resolvePostCategory(
  List<String> categories,
  String? requestedCategory,
) {
  final requested = requestedCategory?.trim().toLowerCase();
  if (requested == null || requested.isEmpty) return null;

  for (final category in categories) {
    if (category.toLowerCase() == requested) return category;
  }

  final aliases = switch (requested) {
    'home services' => ['home', 'household'],
    'academic help' => ['academic', 'tutor', 'education'],
    'repairs' => ['repair', 'handyman'],
    'errands' => ['errand', 'delivery'],
    'cleaning' => ['cleaning', 'cleaner'],
    'beauty' => ['beauty', 'salon', 'grooming'],
    _ => [requested],
  };

  for (final category in categories) {
    final normalized = category.toLowerCase();
    if (aliases.any(normalized.contains)) return category;
  }
  return null;
}

class PostRequestScreen extends StatefulWidget {
  const PostRequestScreen({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  State<PostRequestScreen> createState() => _PostRequestScreenState();
}

class _PostRequestScreenState extends State<PostRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _budgetController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedCategory;
  DateTime? _fromDate;
  DateTime? _toDate;
  JobModality _modality = JobModality.onsite;
  JobLocationSelection? _selectedLocation;
  bool _isPosting = false;

  static const _yellow = Color(0xFFFFC72C);
  static const _ink = Color(0xFF242424);
  static const _cream = Color(0xFFFFF9E9);

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory?.trim();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _budgetController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _displayDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Future<void> _pickSchedule({required bool pickingFrom}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = pickingFrom ? today : (_fromDate ?? today);
    final initialDate = pickingFrom
        ? (_fromDate ?? today)
        : (_toDate ?? _fromDate ?? today);
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2),
      helpText: pickingFrom ? 'Select FROM date' : 'Select TO date',
    );

    if (selectedDate != null && mounted) {
      setState(() {
        if (pickingFrom) {
          _fromDate = selectedDate;
          if (_toDate != null && _toDate!.isBefore(selectedDate)) {
            _toDate = null;
          }
        } else {
          _toDate = selectedDate;
        }
      });
    }
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    required Color field,
    required Color border,
    required Color text,
    required Color muted,
  }) {
    return InkWell(
      key: ValueKey('post-job-${label.toLowerCase()}-date'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: muted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value == null ? 'Select' : _displayDate(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: value == null ? muted : text,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _postJob() async {
    if (!_formKey.currentState!.validate() || _isPosting) return;

    if (_fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose both FROM and TO dates.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in again.')));
      return;
    }

    setState(() => _isPosting = true);
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final fullName = profile.data()?['fullName'];
      final clientName = fullName is String && fullName.trim().isNotEmpty
          ? fullName.trim()
          : 'Client';

      await ServiceRequestRepository().createRequest(
        clientId: user.uid,
        clientName: clientName,
        title: _titleController.text.trim(),
        category: _selectedCategory!,
        budget: double.parse(_budgetController.text.trim()),
        scheduleFrom: _fromDate!,
        scheduleTo: _toDate!,
        description: _descriptionController.text.trim(),
        modality: _modality,
        location: _modality.needsLocation ? _selectedLocation : null,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not post job: $error')));
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    required Color field,
    required Color border,
    required Color text,
    required Color muted,
    Widget? prefixIcon,
  }) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: border),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: muted, fontSize: 13),
      filled: true,
      fillColor: field,
      prefixIcon: prefixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: text, width: 1.2),
      ),
      errorBorder: outline.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
    );
  }

  Widget _sectionCard({
    required Widget child,
    required Color surface,
    required bool dark,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.28 : 0.18),
            blurRadius: 5,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _label(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : _cream;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final field = dark ? const Color(0xFF303030) : const Color(0xFFFCFCFE);
    final text = dark ? const Color(0xFFF4F4F4) : _ink;
    final muted = dark ? const Color(0xFFB5B5B5) : const Color(0xFF9AA1AE);
    final border = dark ? const Color(0xFF777777) : const Color(0xFFB8BBC2);

    return Scaffold(
      backgroundColor: _yellow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                Container(
                  height: 112,
                  padding: const EdgeInsets.fromLTRB(20, 25, 20, 18),
                  color: _yellow,
                  child: Row(
                    children: [
                      Material(
                        color: const Color(0xFFFFF7D9),
                        shape: const CircleBorder(),
                        child: IconButton(
                          key: const ValueKey('post-request-back'),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: _ink,
                            size: 21,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      const Text(
                        'Post need',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(46),
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                        children: [
                          _sectionCard(
                            surface: surface,
                            dark: dark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('Job title', text),
                                TextFormField(
                                  key: const ValueKey('post-job-title'),
                                  controller: _titleController,
                                  maxLength: 80,
                                  style: TextStyle(color: text),
                                  decoration: _inputDecoration(
                                    hint: 'e.g. Need math tutor for 2 hours',
                                    field: field,
                                    border: border,
                                    text: text,
                                    muted: muted,
                                  ).copyWith(counterText: ''),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Enter a job title'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _sectionCard(
                            surface: surface,
                            dark: dark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('Category', text),
                                StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream: FirebaseFirestore.instance
                                      .collection('service_categories')
                                      .where('status', isEqualTo: 'active')
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) {
                                      return InputDecorator(
                                        decoration:
                                            _inputDecoration(
                                              hint: 'Could not load categories',
                                              field: field,
                                              border: border,
                                              text: text,
                                              muted: muted,
                                            ).copyWith(
                                              errorText:
                                                  'Could not load categories',
                                            ),
                                        child: Text(
                                          'Try again shortly.',
                                          style: TextStyle(color: text),
                                        ),
                                      );
                                    }
                                    if (!snapshot.hasData) {
                                      return InputDecorator(
                                        decoration: _inputDecoration(
                                          hint: 'Loading categories...',
                                          field: field,
                                          border: border,
                                          text: text,
                                          muted: muted,
                                        ),
                                        child: const LinearProgressIndicator(),
                                      );
                                    }

                                    final categories =
                                        snapshot.data!.docs
                                            .map(
                                              (document) => document
                                                  .data()['name']
                                                  ?.toString()
                                                  .trim(),
                                            )
                                            .whereType<String>()
                                            .where((name) => name.isNotEmpty)
                                            .toSet()
                                            .toList()
                                          ..sort(
                                            (left, right) => left
                                                .toLowerCase()
                                                .compareTo(right.toLowerCase()),
                                          );
                                    final selectedCategory =
                                        resolvePostCategory(
                                          categories,
                                          _selectedCategory,
                                        );
                                    if (selectedCategory != null) {
                                      _selectedCategory = selectedCategory;
                                    }

                                    return DropdownButtonFormField<String>(
                                      key: ValueKey(selectedCategory),
                                      initialValue: selectedCategory,
                                      dropdownColor: surface,
                                      style: TextStyle(
                                        color: text,
                                        fontSize: 14,
                                      ),
                                      decoration: _inputDecoration(
                                        hint: categories.isEmpty
                                            ? 'No active categories'
                                            : 'Select category',
                                        field: field,
                                        border: border,
                                        text: text,
                                        muted: muted,
                                      ),
                                      icon: Icon(
                                        Icons.keyboard_arrow_down,
                                        color: muted,
                                      ),
                                      items: categories
                                          .map(
                                            (category) => DropdownMenuItem(
                                              value: category,
                                              child: Text(category),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: categories.isEmpty
                                          ? null
                                          : (value) => setState(
                                              () => _selectedCategory = value,
                                            ),
                                      validator: (value) => value == null
                                          ? 'Select a category'
                                          : null,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 9,
                                child: _sectionCard(
                                  surface: surface,
                                  dark: dark,
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _label('Budget (₱)', text),
                                      TextFormField(
                                        key: const ValueKey('post-job-budget'),
                                        controller: _budgetController,
                                        style: TextStyle(color: text),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d{0,2}'),
                                          ),
                                        ],
                                        decoration: _inputDecoration(
                                          hint: 'e.g. 200',
                                          field: field,
                                          border: border,
                                          text: text,
                                          muted: muted,
                                        ),
                                        validator: (value) {
                                          final amount = double.tryParse(
                                            value?.trim() ?? '',
                                          );
                                          return amount == null || amount <= 0
                                              ? 'Invalid budget'
                                              : null;
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 10,
                                child: _sectionCard(
                                  surface: surface,
                                  dark: dark,
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _label('Schedule', text),
                                      Row(
                                        key: const ValueKey(
                                          'post-job-schedule',
                                        ),
                                        children: [
                                          Expanded(
                                            child: _dateField(
                                              label: 'FROM',
                                              value: _fromDate,
                                              onTap: () => _pickSchedule(
                                                pickingFrom: true,
                                              ),
                                              field: field,
                                              border: border,
                                              text: text,
                                              muted: muted,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: _dateField(
                                              label: 'TO',
                                              value: _toDate,
                                              onTap: () => _pickSchedule(
                                                pickingFrom: false,
                                              ),
                                              field: field,
                                              border: border,
                                              text: text,
                                              muted: muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _sectionCard(
                            surface: surface,
                            dark: dark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('Work type', text),
                                _ModalitySelector(
                                  value: _modality,
                                  field: field,
                                  border: border,
                                  text: text,
                                  muted: muted,
                                  onChanged: (modality) => setState(() {
                                    _modality = modality;
                                    // The picker is rebuilt empty when it
                                    // reappears.
                                    if (!modality.needsLocation) {
                                      _selectedLocation = null;
                                    }
                                  }),
                                ),
                              ],
                            ),
                          ),
                          if (_modality.needsLocation) ...[
                            const SizedBox(height: 12),
                            _sectionCard(
                              surface: surface,
                              dark: dark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Location', text),
                                  FormField<JobLocationSelection>(
                                    key: const ValueKey('post-job-location'),
                                    validator: (value) {
                                      if (value == null) {
                                        return 'Choose the service location on the map.';
                                      }
                                      if (value.exactAddress.trim().isEmpty) {
                                        return 'Enter the exact service address.';
                                      }
                                      return null;
                                    },
                                    builder: (field) => JobLocationPicker(
                                      errorText: field.errorText,
                                      onChanged: (value) {
                                        _selectedLocation = value;
                                        field.didChange(value);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _sectionCard(
                            surface: surface,
                            dark: dark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('Description', text),
                                TextFormField(
                                  key: const ValueKey('post-job-description'),
                                  controller: _descriptionController,
                                  style: TextStyle(color: text),
                                  minLines: 3,
                                  maxLines: 5,
                                  decoration: _inputDecoration(
                                    hint: 'Describe what you need...',
                                    field: field,
                                    border: border,
                                    text: text,
                                    muted: muted,
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Describe the job'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 54,
                            child: FilledButton(
                              key: const ValueKey('post-job-submit'),
                              onPressed: _isPosting ? null : _postJob,
                              style: FilledButton.styleFrom(
                                backgroundColor: _yellow,
                                foregroundColor: _ink,
                                disabledBackgroundColor: _yellow.withValues(
                                  alpha: 0.55,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 3,
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: _isPosting
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: _ink,
                                      ),
                                    )
                                  : const Text('Post job'),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalitySelector extends StatelessWidget {
  const _ModalitySelector({
    required this.value,
    required this.onChanged,
    required this.field,
    required this.border,
    required this.text,
    required this.muted,
  });

  final JobModality value;
  final ValueChanged<JobModality> onChanged;
  final Color field;
  final Color border;
  final Color text;
  final Color muted;

  static const _yellow = Color(0xFFFFC72C);
  static const _pink = Color(0xFFFF4F9A);

  static IconData _icon(JobModality modality) => switch (modality) {
    JobModality.onsite => Icons.home_repair_service_outlined,
    JobModality.online => Icons.laptop_mac_outlined,
    JobModality.hybrid => Icons.sync_alt,
  };

  static String _hintFor(JobModality modality) => switch (modality) {
    JobModality.onsite => 'The worker needs to be there in person.',
    JobModality.online => 'Can be done remotely. No location needed.',
    JobModality.hybrid => 'Partly in person, partly remote.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final modality in JobModality.values) ...[
              if (modality != JobModality.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  key: ValueKey('post-job-modality-${modality.name}'),
                  onTap: () => onChanged(modality),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 64,
                    decoration: BoxDecoration(
                      color: modality == value
                          ? _yellow.withValues(alpha: 0.22)
                          : field,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: modality == value ? _yellow : border,
                        width: modality == value ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _icon(modality),
                          size: 20,
                          color: modality == value ? _pink : text,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          modality.label,
                          style: TextStyle(
                            color: text,
                            fontSize: 12,
                            fontWeight: modality == value
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(_hintFor(value), style: TextStyle(color: muted, fontSize: 12)),
      ],
    );
  }
}
