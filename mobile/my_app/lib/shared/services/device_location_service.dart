import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/job_location.dart';

enum DeviceLocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  timedOut,
  unavailable,
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.failure);

  final DeviceLocationFailure failure;

  String get userMessage => switch (failure) {
    DeviceLocationFailure.serviceDisabled =>
      'Turn on location services, then try again.',
    DeviceLocationFailure.permissionDenied =>
      'Location permission was denied. You can try again or choose a pin manually.',
    DeviceLocationFailure.permissionPermanentlyDenied =>
      'Location permission is blocked. Enable it in your device settings.',
    DeviceLocationFailure.timedOut =>
      'Your location took too long to load. Try again or choose a pin manually.',
    DeviceLocationFailure.unavailable =>
      'Your location is unavailable right now. Try again or choose a pin manually.',
  };

  @override
  String toString() => userMessage;
}

class DeviceLocationService {
  const DeviceLocationService();

  Future<JobCoordinate> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
        DeviceLocationFailure.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(
        DeviceLocationFailure.permissionDenied,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        DeviceLocationFailure.permissionPermanentlyDenied,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return JobCoordinate(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on TimeoutException {
      throw const DeviceLocationException(DeviceLocationFailure.timedOut);
    } on DeviceLocationException {
      rethrow;
    } catch (_) {
      throw const DeviceLocationException(DeviceLocationFailure.unavailable);
    }
  }

  Future<bool> openRecoverySettings(DeviceLocationFailure failure) =>
      switch (failure) {
        DeviceLocationFailure.serviceDisabled =>
          Geolocator.openLocationSettings(),
        DeviceLocationFailure.permissionPermanentlyDenied =>
          Geolocator.openAppSettings(),
        _ => Future.value(false),
      };
}
