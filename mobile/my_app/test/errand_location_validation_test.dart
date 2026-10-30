import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/utils/errand_location_validation.dart';

JobLocationSelection place(
  double lat, {
  double lon = 120.8119,
  String address = 'Bulihan, Malolos, Bulacan',
}) => JobLocationSelection(
  position: JobCoordinate(latitude: lat, longitude: lon),
  exactAddress: address,
  areaLabel: 'Bulihan, Malolos',
);

void main() {
  test(
    'rejects identical coordinates despite differently formatted addresses',
    () {
      expect(
        validateErrandLocations(
          place(14.8441),
          place(14.8441, address: '123 Street, Bulacan'),
        ),
        errandSameLocationMessage,
      );
    },
  );
  test(
    'absorbs GPS noise within 20 metres, including the distance boundary',
    () {
      expect(
        validateErrandLocations(place(14.8441), place(14.8442)),
        errandSameLocationMessage,
      );
      // One degree of latitude is about 111 km; these straddle 20 metres.
      expect(
        validateErrandLocations(place(0), place(0.000179)),
        errandSameLocationMessage,
      );
      expect(validateErrandLocations(place(0), place(0.000181)), isNull);
    },
  );
  test(
    'accepts different pins in the same barangay even with identical area text',
    () {
      expect(validateErrandLocations(place(14.8441), place(14.8451)), isNull);
      // Exact points can differ even when public area points round to the same value.
      expect(validateErrandLocations(place(14.8441), place(14.8445)), isNull);
    },
  );
  test('requires both resolved coordinates and nonempty exact addresses', () {
    expect(
      validateErrandLocations(null, place(14.8441)),
      contains('pickup point'),
    );
    expect(
      validateErrandLocations(place(14.8441), null),
      contains('drop-off point'),
    );
    expect(
      validateErrandLocations(place(14.8441, address: '  '), place(14.845)),
      contains('pickup address'),
    );
    expect(
      validateErrandLocations(place(14.8441), place(14.845, address: '')),
      contains('drop-off address'),
    );
  });
  test(
    'invalid and non-finite coordinates cannot bypass distance validation',
    () {
      for (final point in [
        place(double.nan),
        place(double.infinity),
        place(91),
        place(14, lon: -181),
      ]) {
        expect(
          validateErrandLocations(place(14.8441), point),
          contains('valid pickup and drop-off'),
        );
      }
    },
  );
}
