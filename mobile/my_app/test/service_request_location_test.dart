// Firestore's query types are sealed for application code. These test-only
// doubles record the real repository's batched writes without a live backend.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/repositories/service_request_repository.dart';
import 'package:my_app/shared/utils/service_schedule.dart';
import 'package:my_app/shared/utils/errand_location_validation.dart';

class _Firestore extends Fake implements FirebaseFirestore {
  final writes = <String, Map<String, dynamic>>{};
  int commits = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(path);

  @override
  WriteBatch batch() => _Batch(this);
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.path);
  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document('${this.path}/${path ?? 'new-request'}');
}

class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.path);
  @override
  final String path;
  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection('$path/$collectionPath');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot();
}

class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  Map<String, dynamic> data() => {'status': 'pending'};
}

class _Batch extends Fake implements WriteBatch {
  _Batch(this.firestore);
  final _Firestore firestore;

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    firestore.writes[document.path] = Map.of(data as Map<String, dynamic>);
  }

  @override
  void update<T>(DocumentReference<T> document, T data) {
    firestore.writes[document.path] = Map.of(data as Map<String, dynamic>);
  }

  @override
  Future<void> commit() async {
    firestore.commits++;
  }
}

void main() {
  const pickup = JobLocationSelection(
    position: JobCoordinate(latitude: 14.5532, longitude: 121.0214),
    exactAddress: 'Greenbelt, Makati',
    areaLabel: 'Makati',
  );
  const dropoff = JobLocationSelection(
    position: JobCoordinate(latitude: 14.5831, longitude: 121.0554),
    exactAddress: 'Example building, Mandaluyong',
    areaLabel: 'Mandaluyong',
  );
  for (final editing in [false, true]) {
    test(
      '${editing ? 'edit' : 'create'} rejects duplicate errand pins before any Firestore writes',
      () async {
        final firestore = _Firestore();
        final repository = ServiceRequestRepository(firestore: firestore);
        final duplicate = ErrandDetails(
          dropoff: pickup.copyWith(
            exactAddress: 'Same building, different spelling',
          ),
          items: 'Package',
          distanceKm: 0,
        );
        final action = editing
            ? repository.updateRequest(
                requestId: 'existing',
                title: 'Job',
                category: 'Errands',
                budget: 50,
                scheduleFrom: DateTime(2026, 10, 30),
                scheduleTo: DateTime(2026, 10, 30),
                description: 'Example',
                modality: JobModality.errand,
                location: pickup,
                errand: duplicate,
              )
            : repository.createRequest(
                clientId: 'client',
                clientName: 'Client',
                title: 'Job',
                category: 'Errands',
                budget: 50,
                scheduleFrom: DateTime(2026, 10, 30),
                scheduleTo: DateTime(2026, 10, 30),
                description: 'Example',
                modality: JobModality.errand,
                location: pickup,
                errand: duplicate,
              );
        await expectLater(
          action,
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              errandSameLocationMessage,
            ),
          ),
        );
        expect(firestore.commits, 0);
        expect(firestore.writes, isEmpty);
      },
    );
  }
  for (final editing in [false, true]) {
    test(
      '${editing ? 'editing' : 'posting'} preserves selected date and time in stored timestamps',
      () async {
        final firestore = _Firestore();
        final repository = ServiceRequestRepository(firestore: firestore);
        final from = serviceStartInstant(
          DateTime(2026, 10, 30),
          const TimeOfDay(hour: 17, minute: 45),
        );
        final to = serviceStartInstant(
          DateTime(2026, 10, 31),
          const TimeOfDay(hour: 17, minute: 45),
        );
        if (editing) {
          await repository.updateRequest(
            requestId: 'new-request',
            title: 'Job',
            category: 'Other',
            budget: 100,
            scheduleFrom: from,
            scheduleTo: to,
            description: 'Example',
            modality: JobModality.onsite,
            location: pickup,
          );
        } else {
          await repository.createRequest(
            clientId: 'client',
            clientName: 'Client',
            title: 'Job',
            category: 'Other',
            budget: 100,
            scheduleFrom: from,
            scheduleTo: to,
            description: 'Example',
            modality: JobModality.onsite,
            location: pickup,
          );
        }
        final written = firestore.writes['service_requests/new-request']!;
        expect(written['schedule'], Timestamp.fromDate(from));
        expect(written['scheduleFrom'], Timestamp.fromDate(from));
        expect(written['scheduleTo'], Timestamp.fromDate(to));
        final restored = ServiceRequest.fromMap('new-request', {
          for (final key in ['schedule', 'scheduleFrom', 'scheduleTo'])
            key: written[key],
        });
        expect(restored.scheduleFrom!.isAtSameMomentAs(from), isTrue);
        expect(restored.scheduleTo!.isAtSameMomentAs(to), isTrue);
        expect(serviceScheduleLabel(restored), contains('5:45 PM PHT'));
      },
    );
  }
  for (final errand in [false, true]) {
    test(
      'saves selected ${errand ? 'pickup/drop-off' : 'job'} coordinates in the correct documents',
      () async {
        final firestore = _Firestore();
        await ServiceRequestRepository(firestore: firestore).createRequest(
          clientId: 'client-1',
          clientName: 'Client',
          title: 'Example job',
          category: 'Other',
          budget: 100,
          scheduleFrom: DateTime(2026, 10, 25),
          scheduleTo: DateTime(2026, 10, 26),
          description: 'Example description',
          modality: errand ? JobModality.errand : JobModality.onsite,
          location: pickup,
          errand: errand
              ? const ErrandDetails(
                  dropoff: dropoff,
                  items: 'Package',
                  distanceKm: 5,
                )
              : null,
        );
        final public = firestore.writes['service_requests/new-request']!;
        final private =
            firestore.writes['service_requests/new-request/private/location']!;
        expect(firestore.commits, 1);
        expect(public['areaPosition'], const GeoPoint(14.55, 121.02));
        expect(public['location'], 'Makati');
        expect(private['position'], const GeoPoint(14.5532, 121.0214));
        expect(private['address'], pickup.exactAddress);
        if (errand) {
          expect(public['dropoffAreaPosition'], const GeoPoint(14.58, 121.06));
          expect(private['dropoffPosition'], const GeoPoint(14.5831, 121.0554));
          expect(private['dropoffAddress'], dropoff.exactAddress);
        }
      },
    );
  }
}
