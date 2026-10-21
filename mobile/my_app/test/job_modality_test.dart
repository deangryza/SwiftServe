import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/service_request.dart';

ServiceRequest _request(Map<String, dynamic> overrides) =>
    ServiceRequest.fromMap('request-1', {
      'clientId': 'client-1',
      'title': 'Fix sink',
      'location': 'Malolos, Bulacan',
      'budget': 500,
      'status': 'pending',
      ...overrides,
    });

void main() {
  test(
    'modality parses from Firestore and defaults legacy jobs to on-site',
    () {
      expect(_request({'modality': 'online'}).modality, JobModality.online);
      expect(_request({'modality': 'hybrid'}).modality, JobModality.hybrid);
      expect(_request({}).modality, JobModality.onsite);
      expect(_request({'modality': 'remote'}).modality, JobModality.onsite);
    },
  );

  test('only online jobs skip the physical location', () {
    expect(JobModality.onsite.needsLocation, isTrue);
    expect(JobModality.hybrid.needsLocation, isTrue);
    expect(JobModality.online.needsLocation, isFalse);
  });

  test('place label reflects the work type', () {
    expect(_request({'modality': 'onsite'}).placeLabel, 'Malolos, Bulacan');
    expect(
      _request({'modality': 'hybrid'}).placeLabel,
      'Hybrid · Malolos, Bulacan',
    );
    expect(
      _request({'modality': 'online', 'location': 'Online'}).placeLabel,
      'Online',
    );
  });

  test('online jobs have no map position', () {
    final online = _request({'modality': 'online', 'location': 'Online'});
    final onsite = _request({
      'modality': 'onsite',
      'areaPosition': const GeoPoint(14.84, 120.81),
    });
    expect(online.areaPosition, isNull);
    expect(onsite.areaPosition, isNotNull);
  });
}
