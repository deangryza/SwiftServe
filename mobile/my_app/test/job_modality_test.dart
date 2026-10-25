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

  test('errands parse pickup, drop-off and stage', () {
    final errand = _request({
      'modality': 'errand',
      'location': 'Malolos',
      'areaPosition': const GeoPoint(14.84, 120.81),
      'dropoffLocation': 'Bulakan',
      'dropoffAreaPosition': const GeoPoint(14.79, 120.88),
      'errandItems': '2 kg rice',
      'distanceKm': 5.1,
      'itemCostEstimate': 120,
      'errandStage': 'pickedUp',
    });
    expect(errand.isErrand, isTrue);
    expect(JobModality.errand.needsLocation, isTrue);
    expect(errand.placeLabel, 'Malolos → Bulakan');
    expect(errand.dropoffAreaPosition?.latitude, 14.79);
    expect(errand.errandItems, '2 kg rice');
    expect(errand.distanceKm, 5.1);
    expect(errand.itemCostEstimate, 120);
    expect(errand.errandStage, ErrandStage.pickedUp);
    expect(_request({'errandStage': 'teleporting'}).errandStage, isNull);
  });

  test('errand stages advance in order and end before delivery', () {
    expect(ErrandStage.headingToPickup.next, ErrandStage.pickedUp);
    expect(ErrandStage.pickedUp.next, ErrandStage.delivering);
    expect(ErrandStage.delivering.next, isNull);
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
