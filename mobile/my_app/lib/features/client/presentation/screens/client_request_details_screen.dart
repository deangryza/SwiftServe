import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/models/service_request.dart';
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
          if (canMessage)
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClientChatScreen(
                    conversationId: request.id,
                    otherPersonName: request.workerName ?? 'Service provider',
                  ),
                ),
              ),
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
}
