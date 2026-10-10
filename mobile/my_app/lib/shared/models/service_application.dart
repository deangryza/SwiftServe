import 'package:cloud_firestore/cloud_firestore.dart';

enum ServiceApplicationStatus {
  pending,
  accepted,
  rejected;

  static ServiceApplicationStatus fromWire(Object? value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () => ServiceApplicationStatus.pending,
  );
}

class ServiceApplication {
  const ServiceApplication({
    required this.workerId,
    required this.workerName,
    required this.requestId,
    required this.clientId,
    required this.status,
    this.appliedAt,
  });

  final String workerId;
  final String workerName;
  final String requestId;
  final String clientId;
  final ServiceApplicationStatus status;
  final DateTime? appliedAt;

  factory ServiceApplication.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return ServiceApplication(
      workerId: (data['workerId'] ?? document.id).toString(),
      workerName: (data['workerName'] ?? 'Worker').toString(),
      requestId: (data['requestId'] ?? '').toString(),
      clientId: (data['clientId'] ?? '').toString(),
      status: ServiceApplicationStatus.fromWire(data['status']),
      appliedAt: (data['appliedAt'] as Timestamp?)?.toDate(),
    );
  }
}
