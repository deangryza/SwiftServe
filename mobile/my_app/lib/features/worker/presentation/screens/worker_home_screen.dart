import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/repositories/verification_repository.dart';
import '../../../client/presentation/screens/client_sections.dart';
import '../models/worker_verification_ui_state.dart';
import '../widgets/legacy/job_offer_card.dart';
import '../widgets/legacy/profile_header.dart';
import 'worker_job_details_screen.dart';
import 'worker_verification_screen.dart';

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key, required this.profile});

  final AppUser profile;

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  final VerificationRepository _verificationRepository =
      VerificationRepository();
  int _index = 0;

  @override
  Widget build(BuildContext context) => StreamBuilder<VerificationStatus?>(
    stream: _verificationRepository.watchStatus(widget.profile.id),
    builder: (context, verificationSnapshot) {
      final verificationState = WorkerVerificationUiState.resolve(
        profileStatus: widget.profile.verificationStatus,
        submissionStatus: verificationSnapshot.data,
      );
      final pages = [
        _WorkerDashboard(
          worker: widget.profile,
          verificationState: verificationState,
        ),
        _WorkerJobs(worker: widget.profile),
        _WorkerMessages(worker: widget.profile),
        _WorkerProfile(
          worker: widget.profile,
          verificationState: verificationState,
        ),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(['Dashboard', 'My jobs', 'Messages', 'Profile'][_index]),
          actions: [
            if (_index == 0)
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _WorkerNotifications(workerId: widget.profile.id),
                  ),
                ),
                icon: const Icon(Icons.notifications_outlined),
              ),
          ],
        ),
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.work_outline),
              label: 'Jobs',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Messages',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      );
    },
  );
}

class _WorkerDashboard extends StatelessWidget {
  const _WorkerDashboard({
    required this.worker,
    required this.verificationState,
  });

  final AppUser worker;
  final WorkerVerificationUiState verificationState;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ServiceRequest>>(
    stream: ServiceRequestRepository().watchAvailable(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final requests = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Hello, ${worker.fullName}!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${requests.length} open request${requests.length == 1 ? '' : 's'} available.',
          ),
          if (!verificationState.isVerified) ...[
            const SizedBox(height: 16),
            _VerificationBanner(
              state: verificationState,
              onTap: () => _openVerification(context, worker),
            ),
          ],
          const SizedBox(height: 20),
          if (requests.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No open requests right now.'),
              ),
            ),
          for (final request in requests)
            JobOfferCard(
              service: request.title,
              client: request.clientName,
              location: request.location,
              price: '₱${request.budget.toStringAsFixed(0)}',
              onTap: () => _openJob(context, request, worker),
            ),
        ],
      );
    },
  );
}

class _WorkerJobs extends StatelessWidget {
  const _WorkerJobs({required this.worker});

  final AppUser worker;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ServiceRequest>>(
    stream: ServiceRequestRepository().watchWorkerJobs(worker.id),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final jobs = snapshot.data!;
      if (jobs.isEmpty) {
        return const Center(child: Text('No accepted jobs yet.'));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: jobs.length,
        itemBuilder: (context, index) {
          final job = jobs[index];
          return Card(
            child: ListTile(
              title: Text(job.title),
              subtitle: Text('${job.clientName} • ${job.status.name}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openJob(context, job, worker),
            ),
          );
        },
      );
    },
  );
}

void _openJob(BuildContext context, ServiceRequest request, AppUser worker) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => WorkerJobDetailsScreen(request: request, worker: worker),
    ),
  );
}

void _openVerification(BuildContext context, AppUser worker) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => WorkerVerificationScreen(profile: worker),
    ),
  );
}

class _WorkerMessages extends StatelessWidget {
  const _WorkerMessages({required this.worker});

  final AppUser worker;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('conversations')
            .where('participantIds', arrayContains: worker.id)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No conversations yet.'));
          }
          return ListView(
            children: snapshot.data!.docs.map((conversation) {
              final data = conversation.data();
              final clientName = (data['clientName'] ?? 'Client').toString();
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(clientName),
                subtitle: Text((data['lastMessage'] ?? '').toString()),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClientChatScreen(
                      conversationId: conversation.id,
                      otherPersonName: clientName,
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      );
}

class _WorkerProfile extends StatelessWidget {
  const _WorkerProfile({required this.worker, required this.verificationState});

  final AppUser worker;
  final WorkerVerificationUiState verificationState;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      ProfileHeader(
        name: worker.fullName,
        verified: verificationState.isVerified,
        verificationLabel: verificationState.statusLabel,
        onEdit: () {},
      ),
      ListTile(
        leading: Icon(
          verificationState.isVerified
              ? Icons.verified
              : Icons.verified_user_outlined,
          color: verificationState.isVerified ? Colors.green : Colors.orange,
        ),
        title: Text(verificationState.actionLabel),
        subtitle: Text(verificationState.description),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openVerification(context, worker),
      ),
      ListTile(
        leading: const Icon(Icons.email_outlined),
        title: Text(worker.email),
      ),
      ListTile(
        leading: const Icon(Icons.phone_outlined),
        title: Text(worker.phoneNumber),
      ),
      ListTile(
        leading: const Icon(Icons.location_on_outlined),
        title: Text(worker.address),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: FirebaseAuth.instance.signOut,
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
  );
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.state, required this.onTap});

  final WorkerVerificationUiState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: const Icon(Icons.verified_user_outlined),
      title: Text(state.bannerTitle),
      subtitle: Text(state.description),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _WorkerNotifications extends StatelessWidget {
  const _WorkerNotifications({required this.workerId});

  final String workerId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientId', isEqualTo: workerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No notifications.'));
        }
        return ListView(
          children: snapshot.data!.docs.map((document) {
            final data = document.data();
            return ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text((data['title'] ?? 'Update').toString()),
              subtitle: Text((data['body'] ?? '').toString()),
            );
          }).toList(),
        );
      },
    ),
  );
}
