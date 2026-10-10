import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import 'client_sections.dart';

class ClientRequestDetailsScreen extends StatefulWidget {
  const ClientRequestDetailsScreen({super.key, required this.request});

  final ServiceRequest request;

  @override
  State<ClientRequestDetailsScreen> createState() =>
      _ClientRequestDetailsScreenState();
}

class _ClientRequestDetailsScreenState
    extends State<ClientRequestDetailsScreen> {
  bool _saving = false;

  String _dateRange(ServiceRequest request) {
    String format(DateTime date) => '${date.month}/${date.day}/${date.year}';
    final from = request.scheduleFrom ?? request.schedule;
    final to = request.scheduleTo ?? from;
    if (from == null) return 'Flexible';
    if (to == null || DateUtils.isSameDay(from, to)) return format(from);
    return '${format(from)} – ${format(to)}';
  }

  Future<void> _cancel() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(widget.request.id)
          .update({
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
          });
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _acceptApplicant(ServiceApplication application) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accept this worker?'),
        content: Text(
          'Choose ${application.workerName} for this request? '
          'Other applications will be declined.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Accept worker'),
          ),
        ],
      ),
    );
    if (confirmed != true || _saving) return;

    setState(() => _saving = true);
    try {
      await ServiceRequestRepository().acceptApplicant(
        request: widget.request,
        application: application,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${application.workerName} was selected.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not select worker: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openWorkerChat() async {
    final request = widget.request;
    final pairConversationId = conversationIdFor(
      clientId: request.clientId,
      workerId: request.workerId!,
    );
    final pairConversation = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(pairConversationId)
        .get();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientChatScreen(
          conversationId: pairConversation.exists
              ? pairConversationId
              : request.id,
          otherPersonName: request.workerName ?? 'Service provider',
        ),
      ),
    );
  }

  Future<void> _rate() async {
    var rating = 5;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate this service'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              5,
              (index) => IconButton(
                onPressed: () => setDialogState(() => rating = index + 1),
                icon: Icon(index < rating ? Icons.star : Icons.star_border),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, rating),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await FirebaseFirestore.instance
        .collection('reviews')
        .doc(widget.request.id)
        .set({
          'requestId': widget.request.id,
          'clientId': FirebaseAuth.instance.currentUser!.uid,
          'workerId': widget.request.workerId,
          'rating': selected,
          'createdAt': FieldValue.serverTimestamp(),
        });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Thanks for your review.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final canCancel =
        request.status == ServiceRequestStatus.pending ||
        request.status == ServiceRequestStatus.accepted;
    final canMessage =
        request.workerId != null &&
        request.status != ServiceRequestStatus.cancelled;
    return Scaffold(
      appBar: AppBar(title: const Text('Request details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(request.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Chip(label: Text(request.status.name.toUpperCase())),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(request.category),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: Text(_dateRange(request)),
            subtitle: const Text('Requested date range'),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(request.location),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text('₱${request.budget.toStringAsFixed(0)}'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(request.description),
          ),
          if (request.status == ServiceRequestStatus.pending) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Worker applications',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            StreamBuilder<List<ServiceApplication>>(
              stream: ServiceRequestRepository().watchApplications(request.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not load applications: ${snapshot.error}',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final applications = snapshot.data!;
                if (applications.isEmpty) {
                  return const Card(
                    margin: EdgeInsets.symmetric(horizontal: 8),
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'No workers have applied yet. Applications will '
                        'appear here.',
                      ),
                    ),
                  );
                }
                return Column(
                  children: applications.map((application) {
                    final initial = application.workerName.trim().isEmpty
                        ? 'W'
                        : application.workerName.trim()[0].toUpperCase();
                    return Card(
                      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: ListTile(
                        leading: CircleAvatar(child: Text(initial)),
                        title: Text(application.workerName),
                        subtitle: Text(
                          application.appliedAt == null
                              ? 'Application received'
                              : 'Applied ${_formatDate(application.appliedAt!)}',
                        ),
                        trailing: FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _acceptApplicant(application),
                          child: const Text('Accept'),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          if (canMessage)
            FilledButton.icon(
              onPressed: _openWorkerChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Message worker'),
            ),
          if (canCancel)
            OutlinedButton(
              onPressed: _saving ? null : _cancel,
              child: const Text('Cancel request'),
            ),
          if (request.status == ServiceRequestStatus.completed)
            OutlinedButton.icon(
              onPressed: _rate,
              icon: const Icon(Icons.star_outline),
              label: const Text('Rate worker'),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';
}
