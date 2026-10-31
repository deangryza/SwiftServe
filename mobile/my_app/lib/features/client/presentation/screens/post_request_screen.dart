import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'client_request_details_screen.dart';
import '../../../../shared/theme/app_theme.dart';

import '../../../../shared/models/job_location.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/utils/errand_pricing.dart';
import '../../../../shared/utils/errand_location_validation.dart';
import '../../../../shared/utils/service_schedule.dart';
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

/// Errand categories default the work type to [JobModality.errand].
bool isErrandCategory(String? category) {
  final normalized = category?.trim().toLowerCase() ?? '';
  return normalized.contains('errand') || normalized.contains('deliver');
}

enum _GpsAddress { pickup, dropoff }

class PostRequestScreen extends StatefulWidget {
  const PostRequestScreen({
    super.key,
    this.initialCategory,
    this.categoryNames,
    this.existing,
    this.repostOf,
  }) : assert(existing == null || repostOf == null);

  final String? initialCategory;
  final Stream<List<String>>? categoryNames;

  /// The open post being edited. Leave null to post a new job.
  final ServiceRequest? existing;

  /// Copy editable details into a new job, keeping the expired original intact.
  final ServiceRequest? repostOf;

  @override
  State<PostRequestScreen> createState() => _PostRequestScreenState();
}

class _PostRequestScreenState extends State<PostRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _budgetController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _errandItemsController = TextEditingController();
  final _itemCostController = TextEditingController();

  String? _selectedCategory;
  DateTime? _fromDate;
  DateTime? _toDate;
  TimeOfDay? _startTime;
  String? _scheduleError;
  JobModality _modality = JobModality.onsite;
  JobLocationSelection? _selectedLocation;
  JobLocationSelection? _dropoffLocation;
  _GpsAddress? _gpsAddress;
  bool _isPosting = false;
  bool _loadingLocation = false;

  bool get _isEditing => widget.existing != null;
  bool get _isReposting => widget.repostOf != null;

  late final _categoryNames =
      widget.categoryNames ??
      FirebaseFirestore.instance
          .collection('service_categories')
          .where('status', isEqualTo: 'active')
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((document) => document.data()['name']?.toString().trim())
                .whereType<String>()
                .where((name) => name.isNotEmpty)
                .toSet()
                .toList(),
          );

  bool get _isErrand => _modality == JobModality.errand;

  bool _gpsEnabled(_GpsAddress address) =>
      !_isErrand || _gpsAddress == null || _gpsAddress == address;

  bool _requestGps(_GpsAddress address) {
    if (!_gpsEnabled(address)) return false;
    setState(() => _gpsAddress = address);
    return true;
  }

  void _releaseGps(_GpsAddress address) {
    if (_gpsAddress == address) setState(() => _gpsAddress = null);
  }

  String get _gpsRestrictionMessage =>
      'Current location is in use for ${_gpsAddress == _GpsAddress.pickup ? 'pickup' : 'drop-off'}. '
      'Enter an address or choose a map point here.';

  /// Estimated km between pickup and drop-off, once both are pinned.
  double? get _errandDistanceKm {
    final pickup = _selectedLocation;
    final dropoff = _dropoffLocation;
    if (pickup == null || dropoff == null) return null;
    return errandDistanceKm(pickup.position, dropoff.position);
  }

  static const _yellow = AppTheme.yellow;
  static const _ink = AppTheme.ink;
  static const _cream = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing ?? widget.repostOf;
    if (existing != null) {
      _prefill(existing);
      return;
    }
    _selectedCategory = widget.initialCategory?.trim();
    if (isErrandCategory(_selectedCategory)) _modality = JobModality.errand;
  }

  void _prefill(ServiceRequest request) {
    String amount(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    _titleController.text = request.title;
    _budgetController.text = amount(request.budget);
    _descriptionController.text = request.description;
    _errandItemsController.text = request.errandItems ?? '';
    if (request.itemCostEstimate != null) {
      _itemCostController.text = amount(request.itemCostEstimate!);
    }
    _selectedCategory = request.category;
    _modality = request.modality;
    final start = request.scheduleFrom ?? request.schedule;
    if (start != null && !_isReposting) {
      _fromDate = serviceCalendarDate(start);
      _toDate = serviceCalendarDate(request.scheduleTo ?? start);
      final wall = serviceWallTime(start);
      _startTime = TimeOfDay(hour: wall.hour, minute: wall.minute);
    }
    if (request.modality.needsLocation) {
      _loadingLocation = true;
      _loadSavedLocation(request);
    }
  }

  Future<void> _loadSavedLocation(ServiceRequest request) async {
    try {
      final exact = await ServiceRequestRepository().getExactLocation(
        request.id,
      );
      if (!mounted || exact == null) return;
      setState(() {
        _selectedLocation = JobLocationSelection(
          position: exact.position,
          exactAddress: exact.address,
          areaLabel: request.location,
        );
        final dropoff = exact.dropoffPosition;
        if (request.isErrand && dropoff != null) {
          _dropoffLocation = JobLocationSelection(
            position: dropoff,
            exactAddress: exact.dropoffAddress ?? '',
            areaLabel: request.dropoffLocation ?? 'Pinned service area',
          );
        }
      });
    } catch (_) {
      // The client can pin the location again.
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _budgetController.dispose();
    _descriptionController.dispose();
    _errandItemsController.dispose();
    _itemCostController.dispose();
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
    final now = serviceWallTime(DateTime.now());
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
        _revalidateSchedule();
      });
    }
  }

  Widget _dateField({
    required String label,
    DateTime? value,
    String? timeLabel,
    required VoidCallback onTap,
    required Color field,
    required Color border,
    required Color text,
    required Color muted,
  }) {
    return InkWell(
      key: ValueKey(
        label == 'START TIME'
            ? 'post-job-time'
            : 'post-job-${label.toLowerCase()}-date',
      ),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    timeLabel ??
                        (value == null ? 'Select' : _displayDate(value)),
                    style: TextStyle(
                      color: value == null && timeLabel == null ? muted : text,
                      fontSize: 15,
                      fontWeight: timeLabel == null
                          ? FontWeight.w400
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              label == 'START TIME'
                  ? Icons.schedule_outlined
                  : Icons.calendar_today_outlined,
              size: 20,
              color: text,
            ),
          ],
        ),
      ),
    );
  }

  void _revalidateSchedule() {
    _scheduleError = validateServiceSchedule(
      from: _fromDate,
      to: _toDate,
      time: _startTime,
      now: DateTime.now(),
    );
  }

  Future<void> _pickTime() async {
    final wall = serviceWallTime(DateTime.now());
    final selected = await showTimePicker(
      context: context,
      initialTime:
          _startTime ?? TimeOfDay(hour: wall.hour, minute: wall.minute),
      helpText: 'Preferred start time (PHT)',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _startTime = selected;
      _revalidateSchedule();
    });
  }

  Future<void> _postJob() async {
    if (_loadingLocation || _isPosting) return;
    final invalidFields = _formKey.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete the highlighted fields.'),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          invalidFields.first.context,
          duration: const Duration(milliseconds: 250),
          alignment: 0.15,
        );
      });
      return;
    }

    _revalidateSchedule();
    final errandError = _isErrand
        ? validateErrandLocations(_selectedLocation, _dropoffLocation)
        : null;
    if (errandError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errandError)));
      return;
    }
    if (_scheduleError != null) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_scheduleError!)));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in again.')));
      return;
    }

    if (_isEditing) {
      await _saveChanges();
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

      final newRequestId = await ServiceRequestRepository().createRequest(
        clientId: user.uid,
        clientName: clientName,
        repostSourceId: widget.repostOf?.id,
        title: _titleController.text.trim(),
        category: _selectedCategory!,
        budget: _jobBudget(),
        scheduleFrom: serviceStartInstant(_fromDate!, _startTime!),
        scheduleTo: serviceStartInstant(_toDate!, _startTime!),
        description: _descriptionController.text.trim(),
        modality: _modality,
        location: _modality.needsLocation ? _selectedLocation : null,
        errand: _errandDetails(),
      );

      if (!mounted) return;
      if (_isReposting) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job reposted. Your original post is preserved.'),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ClientRequestDetailsScreen(requestId: newRequestId),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not post job: $error')));
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isPosting = true);
    try {
      await ServiceRequestRepository().updateRequest(
        requestId: widget.existing!.id,
        title: _titleController.text.trim(),
        category: _selectedCategory!,
        budget: _jobBudget(),
        scheduleFrom: serviceStartInstant(_fromDate!, _startTime!),
        scheduleTo: serviceStartInstant(_toDate!, _startTime!),
        description: _descriptionController.text.trim(),
        modality: _modality,
        location: _modality.needsLocation ? _selectedLocation : null,
        errand: _errandDetails(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post updated.')));
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save changes: $error')));
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  double _jobBudget() {
    final distanceKm = _isErrand ? _errandDistanceKm! : null;
    return distanceKm != null
        ? errandDeliveryFee(distanceKm)
        : double.parse(_budgetController.text.trim());
  }

  ErrandDetails? _errandDetails() {
    if (!_isErrand) return null;
    final distanceKm = _errandDistanceKm!;
    final itemCost = double.tryParse(_itemCostController.text.trim());
    return ErrandDetails(
      dropoff: _dropoffLocation!,
      items: _errandItemsController.text.trim(),
      distanceKm: double.parse(distanceKm.toStringAsFixed(2)),
      itemCostEstimate: itemCost != null && itemCost > 0 ? itemCost : null,
    );
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
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: border),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: muted, fontSize: 15),
      filled: true,
      fillColor: field,
      prefixIcon: prefixIcon,
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: text, width: 1.2),
      ),
      errorBorder: outline.copyWith(
        borderSide: const BorderSide(color: AppTheme.ink),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: const BorderSide(color: AppTheme.ink, width: 1.2),
      ),
    );
  }

  Widget _formSection({required Widget child}) =>
      Semantics(container: true, child: child);

  Widget _label(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : _cream;
    final surface = dark ? const Color(0xFF303030) : Colors.white;
    final field = dark ? const Color(0xFF303030) : const Color(0xFFFFFFFF);
    final text = dark ? const Color(0xFFF4F4F4) : _ink;
    final muted = dark ? const Color(0xFFB5B5B5) : AppTheme.muted;
    final border = dark ? const Color(0xFF777777) : AppTheme.line;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: text,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Center(
            child: SizedBox.square(
              dimension: 48,
              child: IconButton.outlined(
                key: const ValueKey('post-request-back'),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(side: BorderSide(color: border)),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ),
        ),
        title: Text(
          _isEditing
              ? 'Edit post'
              : _isReposting
              ? 'Repost Job'
              : 'Post need',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: text,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        toolbarHeight: 80,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                // Keep every form field registered, including map selections,
                // when it scrolls off screen.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isReposting)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text(
                          'Review the details and choose new dates and a start time. '
                          'Reposting creates a new job and preserves the original.',
                        ),
                      ),
                    _formSection(
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
                    const SizedBox(height: 24),
                    _formSection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Category', text),
                          StreamBuilder<List<String>>(
                            stream: _categoryNames,
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
                                        errorText: 'Could not load categories',
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

                              final categories = [...snapshot.data!]
                                ..sort(
                                  (left, right) => left.toLowerCase().compareTo(
                                    right.toLowerCase(),
                                  ),
                                );
                              final selectedCategory = resolvePostCategory(
                                categories,
                                _selectedCategory,
                              );
                              if (selectedCategory != null) {
                                _selectedCategory = selectedCategory;
                              }

                              return DropdownButtonFormField<String>(
                                isExpanded: true,
                                key: ValueKey(selectedCategory),
                                initialValue: selectedCategory,
                                dropdownColor: surface,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: text, fontSize: 15),
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
                                    : (value) => setState(() {
                                        _selectedCategory = value;
                                        if (isErrandCategory(value)) {
                                          _modality = JobModality.errand;
                                        }
                                      }),
                                validator: (value) =>
                                    value == null ? 'Select a category' : null,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _formSection(
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
                                _gpsAddress = null;
                              }
                              if (modality != JobModality.errand) {
                                _dropoffLocation = null;
                                if (_gpsAddress == _GpsAddress.dropoff) {
                                  _gpsAddress = null;
                                }
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _formSection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Schedule', text),
                          Row(
                            key: const ValueKey('post-job-schedule'),
                            children: [
                              Expanded(
                                child: _dateField(
                                  label: 'FROM',
                                  value: _fromDate,
                                  onTap: () => _pickSchedule(pickingFrom: true),
                                  field: field,
                                  border: border,
                                  text: text,
                                  muted: muted,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _dateField(
                                  label: 'TO',
                                  value: _toDate,
                                  onTap: () =>
                                      _pickSchedule(pickingFrom: false),
                                  field: field,
                                  border: border,
                                  text: text,
                                  muted: muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _dateField(
                            label: 'START TIME',
                            timeLabel: _startTime == null
                                ? null
                                : serviceTimeLabel(_startTime!),
                            onTap: _pickTime,
                            field: field,
                            border: border,
                            text: text,
                            muted: muted,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Preferred start time for the selected dates (PHT).',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          if (_scheduleError != null)
                            Text(
                              _scheduleError!,
                              key: const ValueKey('post-job-schedule-error'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _formSection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(_isErrand ? 'Delivery fee' : 'Budget', text),
                          if (_isErrand)
                            _ErrandFeePreview(
                              distanceKm: _errandDistanceKm,
                              text: text,
                              muted: muted,
                            )
                          else
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
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 16,
                                    right: 8,
                                  ),
                                  child: Text(
                                    '\u20b1',
                                    style: TextStyle(
                                      color: text,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
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
                    if (_modality.needsLocation) ...[
                      const SizedBox(height: 24),
                      _formSection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label(_isErrand ? 'Pickup' : 'Location', text),
                            if (_loadingLocation)
                              const _SavedLocationLoader()
                            else
                              FormField<JobLocationSelection>(
                                key: const ValueKey('post-job-location'),
                                initialValue: _selectedLocation,
                                validator: (value) {
                                  if (value == null) {
                                    return _isErrand
                                        ? 'Choose the pickup point on the map.'
                                        : 'Choose the service location on the map.';
                                  }
                                  if (value.exactAddress.trim().isEmpty) {
                                    return _isErrand
                                        ? 'Enter the pickup address.'
                                        : 'Enter the exact service address.';
                                  }
                                  return null;
                                },
                                builder: (field) => JobLocationPicker(
                                  initialValue: _selectedLocation,
                                  currentLocationEnabled: _gpsEnabled(
                                    _GpsAddress.pickup,
                                  ),
                                  currentLocationDisabledReason:
                                      _gpsRestrictionMessage,
                                  onCurrentLocationRequested: () =>
                                      _requestGps(_GpsAddress.pickup),
                                  onCurrentLocationReleased: () =>
                                      _releaseGps(_GpsAddress.pickup),
                                  errorText: field.errorText,
                                  onChanged: (value) {
                                    setState(() => _selectedLocation = value);
                                    field.didChange(value);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (_isErrand) ...[
                      const SizedBox(height: 24),
                      _formSection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Drop-off', text),
                            if (_loadingLocation)
                              const _SavedLocationLoader()
                            else
                              FormField<JobLocationSelection>(
                                key: const ValueKey('post-job-dropoff'),
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                initialValue: _dropoffLocation,
                                validator: (value) {
                                  if (value == null) {
                                    return 'Choose the drop-off point on the map.';
                                  }
                                  if (value.exactAddress.trim().isEmpty) {
                                    return 'Enter the drop-off address.';
                                  }
                                  return validateErrandLocations(
                                    _selectedLocation,
                                    value,
                                  );
                                },
                                builder: (field) => JobLocationPicker(
                                  initialValue: _dropoffLocation,
                                  currentLocationEnabled: _gpsEnabled(
                                    _GpsAddress.dropoff,
                                  ),
                                  currentLocationDisabledReason:
                                      _gpsRestrictionMessage,
                                  onCurrentLocationRequested: () =>
                                      _requestGps(_GpsAddress.dropoff),
                                  onCurrentLocationReleased: () =>
                                      _releaseGps(_GpsAddress.dropoff),
                                  errorText: field.errorText,
                                  onChanged: (value) {
                                    setState(() => _dropoffLocation = value);
                                    field.didChange(value);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _formSection(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('What to buy or pick up', text),
                            TextFormField(
                              key: const ValueKey('post-job-errand-items'),
                              controller: _errandItemsController,
                              style: TextStyle(color: text),
                              minLines: 2,
                              maxLines: 4,
                              maxLength: 500,
                              decoration: _inputDecoration(
                                hint: 'e.g. 2 kg rice and 1 dozen eggs',
                                field: field,
                                border: border,
                                text: text,
                                muted: muted,
                              ).copyWith(counterText: ''),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'List the items or package'
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            _label('Item cost estimate (₱, optional)', text),
                            TextFormField(
                              key: const ValueKey('post-job-item-cost'),
                              controller: _itemCostController,
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
                                hint: 'Paid back to the rider on delivery',
                                field: field,
                                border: border,
                                text: text,
                                muted: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _formSection(
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
                          elevation: 0,
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
                            : Text(
                                _isEditing
                                    ? 'Save changes'
                                    : _isReposting
                                    ? 'Repost Job'
                                    : 'Post job',
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
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

  static const _yellow = AppTheme.yellow;

  static IconData _icon(JobModality modality) => switch (modality) {
    JobModality.onsite => Icons.home_repair_service_outlined,
    JobModality.online => Icons.laptop_mac_outlined,
    JobModality.hybrid => Icons.sync_alt,
    JobModality.errand => Icons.delivery_dining_outlined,
  };

  static String _hintFor(JobModality modality) => switch (modality) {
    JobModality.onsite => 'The worker needs to be there in person.',
    JobModality.online => 'Can be done remotely. No location needed.',
    JobModality.hybrid => 'Partly in person, partly remote.',
    JobModality.errand =>
      'A rider picks something up and delivers it. Track them live.',
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
                child: Semantics(
                  selected: modality == value,
                  button: true,
                  child: InkWell(
                    key: ValueKey('post-job-modality-${modality.name}'),
                    onTap: () => onChanged(modality),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      constraints: const BoxConstraints(minHeight: 84),
                      decoration: BoxDecoration(
                        color: modality == value
                            ? _yellow.withValues(alpha: 0.18)
                            : field,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: modality == value ? _yellow : border,
                          width: modality == value ? 1.8 : 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Center(
                                  child: Icon(
                                    _icon(modality),
                                    size: 24,
                                    color: text,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  modality.label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: text,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (modality == value)
                            Positioned(
                              top: 5,
                              right: 5,
                              child: Icon(
                                Icons.check_circle,
                                color: text,
                                size: 15,
                              ),
                            ),
                        ],
                      ),
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

class _ErrandFeePreview extends StatelessWidget {
  const _ErrandFeePreview({
    required this.distanceKm,
    required this.text,
    required this.muted,
  });

  final double? distanceKm;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final km = distanceKm;
    return SizedBox(
      key: const ValueKey('post-job-errand-fee'),
      height: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: km == null
            ? [
                Text(
                  'Pin pickup and drop-off',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ]
            : [
                Text(
                  '₱${errandDeliveryFee(km).toStringAsFixed(0)}',
                  style: TextStyle(
                    color: text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '~${km.toStringAsFixed(1)} km',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
      ),
    );
  }
}

class _SavedLocationLoader extends StatelessWidget {
  const _SavedLocationLoader();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 120,
    child: Center(child: CircularProgressIndicator()),
  );
}
