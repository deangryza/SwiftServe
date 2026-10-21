import 'package:cloud_firestore/cloud_firestore.dart';

import 'job_location.dart';

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

enum JobModality {
  onsite('On-site'),
  online('Online'),
  hybrid('Hybrid');

  const JobModality(this.label);

  final String label;

  /// Whether the job needs a physical location pinned on the map.
  bool get needsLocation => this != JobModality.online;

  // Requests posted before modality existed were all physical jobs.
  static JobModality fromWire(Object? value) => values.firstWhere(
    (modality) => modality.name == value,
    orElse: () => JobModality.onsite,
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
    this.modality = JobModality.onsite,
    this.areaLatitude,
    this.areaLongitude,
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
  final JobModality modality;
  final double? areaLatitude;
  final double? areaLongitude;
  final String? workerId;
  final String? workerName;
  final DateTime? schedule;
  final DateTime? scheduleFrom;
  final DateTime? scheduleTo;

  /// Short "where" text for cards: the area, prefixed for hybrid jobs.
  String get placeLabel => switch (modality) {
    JobModality.online => 'Online',
    JobModality.hybrid => 'Hybrid · $location',
    JobModality.onsite => location,
  };

  JobCoordinate? get areaPosition =>
      areaLatitude == null || areaLongitude == null
      ? null
      : JobCoordinate(latitude: areaLatitude!, longitude: areaLongitude!);

  factory ServiceRequest.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) => ServiceRequest.fromMap(
    document.id,
    document.data() ?? const <String, dynamic>{},
  );

  factory ServiceRequest.fromMap(String id, Map<String, dynamic> data) {
    final areaPosition = JobCoordinate.fromGeoPoint(data['areaPosition']);
    return ServiceRequest(
      id: id,
      clientId: (data['clientId'] ?? '').toString(),
      clientName: (data['clientName'] ?? 'Client').toString(),
      title: (data['title'] ?? 'Untitled request').toString(),
      category: (data['category'] ?? 'Other').toString(),
      location: (data['location'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      budget: (data['budget'] as num?)?.toDouble() ?? 0,
      status: ServiceRequestStatus.fromWire(data['status']),
      modality: JobModality.fromWire(data['modality']),
      areaLatitude: areaPosition?.latitude,
      areaLongitude: areaPosition?.longitude,
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
