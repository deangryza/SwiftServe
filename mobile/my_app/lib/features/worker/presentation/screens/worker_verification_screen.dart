import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/repositories/verification_repository.dart';
import '../models/worker_verification_ui_state.dart';

class WorkerVerificationScreen extends StatefulWidget {
  const WorkerVerificationScreen({super.key, required this.profile});

  final AppUser profile;

  @override
  State<WorkerVerificationScreen> createState() =>
      _WorkerVerificationScreenState();
}

class _WorkerVerificationScreenState extends State<WorkerVerificationScreen> {
  final _idNumber = TextEditingController();
  final _picker = ImagePicker();
  final VerificationRepository _repository = VerificationRepository();
  String _idType = 'Philippine National ID';
  File? _governmentId;
  File? _facePhoto;
  bool _uploading = false;

  Future<void> _pickId() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null && mounted) {
      setState(() => _governmentId = File(file.path));
    }
  }

  Future<void> _pickFace() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _facePhoto = File(file.path));
  }

  Future<void> _submit() async {
    if (_governmentId == null ||
        _facePhoto == null ||
        _idNumber.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an ID number, ID image, and face photo.'),
        ),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      await _repository.submit(
        uid: widget.profile.id,
        idType: _idType,
        idNumber: _idNumber.text,
        governmentId: _governmentId!,
        facePhoto: _facePhoto!,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submission failed: $error')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _idNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker verification'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: FirebaseAuth.instance.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<VerificationStatus?>(
        stream: _repository.watchStatus(widget.profile.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Could not load verification status.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              widget.profile.verificationStatus !=
                  VerificationStatus.verified) {
            return const Center(child: CircularProgressIndicator());
          }
          final state = WorkerVerificationUiState.resolve(
            profileStatus: widget.profile.verificationStatus,
            submissionStatus: snapshot.data,
          );
          return _VerificationContent(
            state: state,
            idType: _idType,
            idNumber: _idNumber,
            governmentIdSelected: _governmentId != null,
            facePhotoSelected: _facePhoto != null,
            uploading: _uploading,
            onIdTypeChanged: (value) =>
                setState(() => _idType = value ?? _idType),
            onPickId: _pickId,
            onPickFace: _pickFace,
            onSubmit: _submit,
          );
        },
      ),
    );
  }
}

class _VerificationContent extends StatelessWidget {
  const _VerificationContent({
    required this.state,
    required this.idType,
    required this.idNumber,
    required this.governmentIdSelected,
    required this.facePhotoSelected,
    required this.uploading,
    required this.onIdTypeChanged,
    required this.onPickId,
    required this.onPickFace,
    required this.onSubmit,
  });

  final WorkerVerificationUiState state;
  final String idType;
  final TextEditingController idNumber;
  final bool governmentIdSelected;
  final bool facePhotoSelected;
  final bool uploading;
  final ValueChanged<String?> onIdTypeChanged;
  final VoidCallback onPickId;
  final VoidCallback onPickFace;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Center(
    child: ListView(
      padding: const EdgeInsets.all(24),
      shrinkWrap: true,
      children: [
        Icon(
          state.isVerified
              ? Icons.verified
              : state.isAwaitingReview
              ? Icons.hourglass_top
              : Icons.verified_user_outlined,
          size: 64,
          color: state.isVerified ? Colors.green : null,
        ),
        const SizedBox(height: 16),
        Text(
          state.isVerified
              ? 'Account verified'
              : state.isAwaitingReview
              ? state.statusLabel
              : 'Submit your identity documents',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(state.description, textAlign: TextAlign.center),
        if (state.shouldShowForm) ...[
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: idType,
            items:
                const [
                      'Philippine National ID',
                      "Driver's License",
                      'UMID',
                      'Postal ID',
                      "Voter's ID",
                    ]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: onIdTypeChanged,
            decoration: const InputDecoration(labelText: 'ID type'),
          ),
          TextField(
            controller: idNumber,
            decoration: const InputDecoration(labelText: 'ID number'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onPickId,
            icon: const Icon(Icons.badge_outlined),
            label: Text(
              governmentIdSelected
                  ? 'Government ID selected'
                  : 'Choose government ID',
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickFace,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(
              facePhotoSelected ? 'Face photo selected' : 'Take face photo',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: uploading ? null : onSubmit,
            child: uploading
                ? const CircularProgressIndicator()
                : Text(
                    state.hasSubmission
                        ? 'Resubmit for review'
                        : 'Submit for review',
                  ),
          ),
        ],
      ],
    ),
  );
}
