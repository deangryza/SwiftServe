import 'package:cloud_firestore/cloud_firestore.dart';

enum ServiceRequestStatus {
  pending,
  accepted,
  ongoing,
  completed,
  cancelled;

  static ServiceRequestStatus fromWire(Object? value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () => ServiceRequestStatus.pending,
  );
}

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.title,
    required this.category,
    required this.location,
    required this.description,
    required this.budget,
    required this.status,
    this.workerId,
    this.workerName,
    this.schedule,
    this.scheduleFrom,
    this.scheduleTo,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String title;
  final String category;
  final String location;
  final String description;
  final double budget;
  final ServiceRequestStatus status;
  final String? workerId;
  final String? workerName;
  final DateTime? schedule;
  final DateTime? scheduleFrom;
  final DateTime? scheduleTo;

  factory ServiceRequest.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return ServiceRequest(
      id: document.id,
      clientId: (data['clientId'] ?? '').toString(),
      clientName: (data['clientName'] ?? 'Client').toString(),
      title: (data['title'] ?? 'Untitled request').toString(),
      category: (data['category'] ?? 'Other').toString(),
      location: (data['location'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      budget: (data['budget'] as num?)?.toDouble() ?? 0,
      status: ServiceRequestStatus.fromWire(data['status']),
      workerId: data['workerId']?.toString(),
      workerName: data['workerName']?.toString(),
      schedule: (data['schedule'] as Timestamp?)?.toDate(),
      scheduleFrom:
          (data['scheduleFrom'] as Timestamp?)?.toDate() ??
          (data['schedule'] as Timestamp?)?.toDate(),
      scheduleTo:
          (data['scheduleTo'] as Timestamp?)?.toDate() ??
          (data['schedule'] as Timestamp?)?.toDate(),
    );
  }
}
