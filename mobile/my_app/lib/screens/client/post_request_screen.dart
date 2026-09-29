import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PostRequestScreen extends StatefulWidget {
  const PostRequestScreen({super.key});

  @override
  State<PostRequestScreen> createState() => _PostRequestScreenState();
}

class _PostRequestScreenState extends State<PostRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _budgetController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedCategory;
  DateTime? _selectedDate;
  bool _isPosting = false;

  final List<String> _categories = [
    'Home services',
    'Academic help',
    'Repairs',
    'Errands',
    'Cleaning',
    'Beauty',
    'Other',
  ];

  static const _dark = Color(0xFF1D1E21);
  static const _border = Color(0xFFE2E5EC);
  static const _hint = Color(0xFF929AAA);

  @override
  void dispose() {
    _titleController.dispose();
    _budgetController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _hint, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFFCFCFE),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 15,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: _dark, width: 1.3),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF343840),
        ),
      ),
    );
  }

  String _displayDate(DateTime date) {
    final month = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][date.month - 1];

    return '$month ${date.day}, ${date.year}';
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );

    if (date != null && mounted) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _postJob() async {
    if (!_formKey.currentState!.validate() || _isPosting) return;

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a schedule.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in again.')),
      );
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

      await FirebaseFirestore.instance
          .collection('service_requests')
          .add({
        'clientId': user.uid,
        'clientName': clientName,
        'title': _titleController.text.trim(),
        'category': _selectedCategory,
        'budget': double.parse(_budgetController.text.trim()),
        'schedule': Timestamp.fromDate(_selectedDate!),
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post job: $error')),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 15, 20, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, size: 21),
                      ),
                      const SizedBox(width: 2),
                      const Expanded(
                        child: Text(
                          'Post need',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _dark,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 31,
                        width: 75,
                        child: FilledButton(
                          onPressed: _isPosting ? null : _postJob,
                          style: FilledButton.styleFrom(
                            backgroundColor: _dark,
                            padding: EdgeInsets.zero,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Post',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF0F1F3)),

                Expanded(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(22, 28, 22, 30),
                      children: [
                        _label('Job title'),
                        TextFormField(
                          controller: _titleController,
                          maxLength: 80,
                          decoration: _inputDecoration(
                            'e.g. Need math tutor for 2 hours',
                          ).copyWith(counterText: ''),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter a job title'
                                  : null,
                        ),
                        const SizedBox(height: 18),

                        _label('Category'),
                        DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: _inputDecoration('Select a category'),
                          icon: const Icon(Icons.keyboard_arrow_down),
                          items: _categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedCategory = value);
                          },
                          validator: (value) =>
                              value == null ? 'Select a category' : null,
                        ),
                        const SizedBox(height: 18),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  _label('Budget (₱)'),
                                  TextFormField(
                                    controller: _budgetController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d{0,2}'),
                                      ),
                                    ],
                                    decoration: _inputDecoration('e.g. 200'),
                                    validator: (value) {
                                      final amount = double.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      if (amount == null || amount <= 0) {
                                        return 'Enter a valid budget';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  _label('Schedule'),
                                  InkWell(
                                    onTap: _pickSchedule,
                                    borderRadius: BorderRadius.circular(11),
                                    child: Container(
                                      height: 51,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFCFCFE),
                                        border: Border.all(color: _border),
                                        borderRadius:
                                            BorderRadius.circular(11),
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _selectedDate == null
                                            ? 'Select date'
                                            : _displayDate(_selectedDate!),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _selectedDate == null
                                              ? _hint
                                              : _dark,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        _label('Location'),
                        TextFormField(
                          controller: _locationController,
                          decoration: _inputDecoration(
                            'Enter city and area',
                          ).copyWith(
                            prefixIcon: const Icon(
                              Icons.location_on_outlined,
                              color: Color(0xFFEE4C8B),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter a location'
                                  : null,
                        ),
                        const SizedBox(height: 18),

                        _label('Description'),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 4,
                          decoration: _inputDecoration(
                            'Describe what you need...',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Describe the job'
                                  : null,
                        ),
                        const SizedBox(height: 30),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: SizedBox(
                            height: 49,
                            child: FilledButton(
                              onPressed: _isPosting ? null : _postJob,
                              style: FilledButton.styleFrom(
                                backgroundColor: _dark,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _isPosting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Post job'),
                            ),
                          ),
                        ),
                      ],
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