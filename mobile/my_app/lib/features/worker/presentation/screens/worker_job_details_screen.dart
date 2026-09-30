import 'package:flutter/material.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
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

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final canAcceptJobs =
        widget.worker.verificationStatus == VerificationStatus.verified;
    return Scaffold(
      appBar: AppBar(title: const Text('Job details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          JobSummaryCard(
            service: request.title,
            client: request.clientName,
            location: request.location,
            schedule: request.schedule?.toLocal().toString() ?? 'Flexible',
            price: '₱${request.budget.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 12),
          Text(request.description),
          const SizedBox(height: 24),
          if (request.status == ServiceRequestStatus.pending)
            FilledButton(
              onPressed: _saving
                  ? null
                  : canAcceptJobs
                  ? () => _run(
                      () => ServiceRequestRepository().accept(
                        request: request,
                        workerId: widget.worker.id,
                        workerName: widget.worker.fullName,
                      ),
                    )
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            WorkerVerificationScreen(profile: widget.worker),
                      ),
                    ),
              child: Text(
                canAcceptJobs ? 'Accept request' : 'Verify to accept jobs',
              ),
            ),
          if (request.status == ServiceRequestStatus.accepted)
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
          if (request.status == ServiceRequestStatus.ongoing)
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
