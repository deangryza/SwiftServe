import 'package:cloud_firestore/cloud_firestore.dart';

import 'job_location.dart';

enum ServiceRequestStatus {
  pending,
  accepted,
  ongoing,
  completed,
  cancelled,
  expired;

  static ServiceRequestStatus fromWire(Object? value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () => ServiceRequestStatus.pending,
  );
}

enum JobModality {
  onsite('On-site'),
  online('Online'),
  hybrid('Hybrid'),
  errand('Errand');

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

/// Where the rider is within an ongoing errand. Delivery is the request's
/// `completed` status, so it has no stage of its own.
enum ErrandStage {
  headingToPickup('Heading to pickup'),
  pickedUp('Picked up'),
  delivering('On the way');

  const ErrandStage(this.label);

  final String label;

  /// Whether the rider's next stop is the drop-off rather than the pickup.
  bool get headsToDropoff => this != headingToPickup;

  ErrandStage? get next {
    final nextIndex = index + 1;
    return nextIndex < values.length ? values[nextIndex] : null;
  }

  static ErrandStage? fromWire(Object? value) {
    for (final stage in values) {
      if (stage.name == value) return stage;
    }
    return null;
  }
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
    this.createdAt,
    this.expiredAt,
    this.dropoffLocation,
    this.dropoffLatitude,
    this.dropoffLongitude,
    this.errandItems,
    this.itemCostEstimate,
    this.distanceKm,
    this.errandStage,
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
  final DateTime? createdAt;
  final DateTime? expiredAt;

  // Errand-only fields. For errands, [location] and [areaPosition] are the
  // pickup point, so code that only knows about one place keeps working.
  final String? dropoffLocation;
  final double? dropoffLatitude;
  final double? dropoffLongitude;
  final String? errandItems;
  final double? itemCostEstimate;
  final double? distanceKm;
  final ErrandStage? errandStage;

  bool get isErrand => modality == JobModality.errand;

  /// Unknown ownership must never become an application opportunity.
  bool get hasKnownCreator =>
      clientId.trim().isNotEmpty && clientId.length <= 128;

  /// A stored start is an absolute instant, including Philippine midnight.
  /// Legacy posts without any schedule retain their existing availability.
  DateTime? get applicationDeadline => scheduleFrom ?? schedule;

  bool applicationDeadlineReached({DateTime? now}) {
    final start = applicationDeadline;
    return start != null && !start.isAfter(now ?? DateTime.now());
  }

  bool isAvailableToWorker(String? uid, {DateTime? now}) =>
      uid != null &&
      uid.isNotEmpty &&
      hasKnownCreator &&
      clientId != uid &&
      status == ServiceRequestStatus.pending &&
      !applicationDeadlineReached(now: now);

  /// Short "where" text for cards: the area, prefixed for hybrid jobs.
  String get placeLabel => switch (modality) {
    JobModality.online => 'Online',
    JobModality.hybrid => 'Hybrid · $location',
    JobModality.onsite => location,
    JobModality.errand => '$location → ${dropoffLocation ?? 'Drop-off'}',
  };

  JobCoordinate? get areaPosition =>
      areaLatitude == null || areaLongitude == null
      ? null
      : JobCoordinate(latitude: areaLatitude!, longitude: areaLongitude!);

  JobCoordinate? get dropoffAreaPosition =>
      dropoffLatitude == null || dropoffLongitude == null
      ? null
      : JobCoordinate(latitude: dropoffLatitude!, longitude: dropoffLongitude!);

  factory ServiceRequest.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) => ServiceRequest.fromMap(
    document.id,
    document.data() ?? const <String, dynamic>{},
  );

  factory ServiceRequest.fromMap(String id, Map<String, dynamic> data) {
    final areaPosition = JobCoordinate.fromGeoPoint(data['areaPosition']);
    final dropoffAreaPosition = JobCoordinate.fromGeoPoint(
      data['dropoffAreaPosition'],
    );
    return ServiceRequest(
      id: id,
      clientId: data['clientId'] is String ? data['clientId'] as String : '',
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
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      expiredAt: (data['expiredAt'] as Timestamp?)?.toDate(),
      dropoffLocation: data['dropoffLocation']?.toString(),
      dropoffLatitude: dropoffAreaPosition?.latitude,
      dropoffLongitude: dropoffAreaPosition?.longitude,
      errandItems: data['errandItems']?.toString(),
      itemCostEstimate: (data['itemCostEstimate'] as num?)?.toDouble(),
      distanceKm: (data['distanceKm'] as num?)?.toDouble(),
      errandStage: ErrandStage.fromWire(data['errandStage']),
    );
  }
}
