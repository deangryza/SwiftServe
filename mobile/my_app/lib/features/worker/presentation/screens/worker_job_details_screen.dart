import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/service_application.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../client/presentation/screens/client_sections.dart';
import '../widgets/legacy/job_summary_card.dart';
import 'worker_verification_screen.dart';

class WorkerJobDetailsScreen extends StatefulWidget {
  const WorkerJobDetailsScreen({
    super.key,
    required this.request,
    required this.worker,
  });

  final ServiceRequest request;
  final AppUser worker;

  @override
  State<WorkerJobDetailsScreen> createState() => _WorkerJobDetailsScreenState();
}

class _WorkerJobDetailsScreenState extends State<WorkerJobDetailsScreen> {
  bool _saving = false;

  String _dateRange(ServiceRequest request) {
    String format(DateTime date) => '${date.month}/${date.day}/${date.year}';
    final from = request.scheduleFrom ?? request.schedule;
    final to = request.scheduleTo ?? from;
    if (from == null) return 'Flexible';
    if (to == null || DateUtils.isSameDay(from, to)) return format(from);
    return '${format(from)} – ${format(to)}';
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openClientChat() async {
    final request = widget.request;
    final pairConversationId = conversationIdFor(
      clientId: request.clientId,
      workerId: widget.worker.id,
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
          otherPersonName: request.clientName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final canAcceptJobs =
        widget.worker.verificationStatus == VerificationStatus.verified;
    final isAssignedWorker = request.workerId == widget.worker.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Job details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          JobSummaryCard(
            service: request.title,
            client: request.clientName,
            location: request.location,
            schedule: _dateRange(request),
            price: '₱${request.budget.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 12),
          Text(request.description),
          const SizedBox(height: 24),
          if (request.status == ServiceRequestStatus.pending && !canAcceptJobs)
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      WorkerVerificationScreen(profile: widget.worker),
                ),
              ),
              child: const Text('Verify to apply'),
            ),
          if (request.status == ServiceRequestStatus.pending && canAcceptJobs)
            StreamBuilder<ServiceApplication?>(
              stream: ServiceRequestRepository().watchApplication(
                requestId: request.id,
                workerId: widget.worker.id,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Could not load application: ${snapshot.error}');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final application = snapshot.data;
                if (application == null) {
                  return FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _run(
                            () => ServiceRequestRepository().apply(
                              request: request,
                              worker: widget.worker,
                            ),
                          ),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Apply for this request'),
                  );
                }
                final accepted =
                    application.status == ServiceApplicationStatus.accepted;
                final rejected =
                    application.status == ServiceApplicationStatus.rejected;
                return Card(
                  color: accepted
                      ? Colors.green.shade50
                      : rejected
                      ? Colors.red.shade50
                      : Colors.orange.shade50,
                  child: ListTile(
                    leading: Icon(
                      accepted
                          ? Icons.check_circle_outline
                          : rejected
                          ? Icons.cancel_outlined
                          : Icons.schedule_outlined,
                    ),
                    title: Text(
                      accepted
                          ? 'Your application was accepted'
                          : rejected
                          ? 'Another worker was selected'
                          : 'Application sent',
                    ),
                    subtitle: Text(
                      accepted
                          ? 'This request is now in My jobs.'
                          : rejected
                          ? 'You were not selected for this request.'
                          : 'Wait for the client to choose a worker.',
                    ),
                  ),
                );
              },
            ),
          if (isAssignedWorker &&
              request.status != ServiceRequestStatus.pending &&
              request.status != ServiceRequestStatus.cancelled) ...[
            FilledButton.icon(
              onPressed: _openClientChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Message client'),
            ),
            const SizedBox(height: 10),
          ],
          if (isAssignedWorker &&
              request.status == ServiceRequestStatus.accepted)
            FilledButton(
              onPressed: _saving
                  ? null
                  : () => _run(
                      () => ServiceRequestRepository().transition(
                        requestId: request.id,
                        from: ServiceRequestStatus.accepted,
                        to: ServiceRequestStatus.ongoing,
                        workerId: widget.worker.id,
                      ),
                    ),
              child: const Text('Start work'),
            ),
          if (isAssignedWorker &&
              request.status == ServiceRequestStatus.ongoing)
            FilledButton(
              onPressed: _saving
                  ? null
                  : () => _run(
                      () => ServiceRequestRepository().transition(
                        requestId: request.id,
                        from: ServiceRequestStatus.ongoing,
                        to: ServiceRequestStatus.completed,
                        workerId: widget.worker.id,
                      ),
                    ),
              child: const Text('Mark completed'),
            ),
        ],
      ),
    );
  }
}
