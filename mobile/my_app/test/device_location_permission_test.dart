import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/services/device_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/geolocator');
  var permission = 0, prompts = 0;
  var enabled = true;
  setUp(() {
    permission = 0;
    prompts = 0;
    enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isLocationServiceEnabled') return enabled;
          if (call.method == 'checkPermission') return permission;
          if (call.method == 'requestPermission') {
            prompts++;
            return 2;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'permission inspection never prompts and distinguishes granted from ungranted',
    () async {
      const service = DeviceLocationService();
      expect(await service.hasPermission(), isFalse);
      for (final allowed in [2, 3]) {
        permission = allowed;
        expect(await service.hasPermission(), isTrue);
      }
      expect(prompts, 0);
    },
  );
  test(
    'permanently denied access and disabled GPS produce recovery failures',
    () async {
      const service = DeviceLocationService();
      permission = 1;
      await expectLater(
        service.hasPermission(),
        throwsA(
          isA<DeviceLocationException>().having(
            (e) => e.failure,
            'failure',
            DeviceLocationFailure.permissionPermanentlyDenied,
          ),
        ),
      );
      enabled = false;
      await expectLater(
        service.hasPermission(),
        throwsA(
          isA<DeviceLocationException>().having(
            (e) => e.failure,
            'failure',
            DeviceLocationFailure.serviceDisabled,
          ),
        ),
      );
      expect(prompts, 0);
    },
  );
}
