import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/emergency_config.dart';
import '../models/job_location.dart';
import '../models/service_request.dart';
import 'api_service.dart';
import 'device_location_service.dart';

/// SOS is offered while someone is physically with the other party.
bool sosAvailableFor(ServiceRequest request) =>
    request.modality.needsLocation &&
    (request.status == ServiceRequestStatus.accepted ||
        request.status == ServiceRequestStatus.ongoing);

class SosService {
  SosService({
    ApiService? api,
    this.location = const DeviceLocationService(),
    Future<bool> Function(Uri)? launch,
    Future<String> Function()? idToken,
    this.dialNumber = emergencyNumber,
  }) : _api = api ?? ApiService(),
       _launch = launch ?? _launchDialer,
       _idToken = idToken ?? _currentIdToken;

  final ApiService _api;
  final DeviceLocationService location;

  /// The number to dial; see `emergency_config.dart` for demo vs live builds.
  final String dialNumber;
  final Future<bool> Function(Uri) _launch;
  final Future<String> Function() _idToken;

  static const _locationTimeout = Duration(seconds: 8);

  static Future<bool> _launchDialer(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static Future<String> _currentIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Your session has expired.');
    return (await user.getIdToken())!;
  }

  /// Opens the phone dialer with [dialNumber] filled in. Returns false without
  /// dialing when no number is configured (a demo build with no contact).
  Future<bool> callEmergency() async {
    if (dialNumber.isEmpty) return false;
    try {
      return await _launch(Uri(scheme: 'tel', path: dialNumber));
    } catch (_) {
      return false;
    }
  }

  /// Sends (or refreshes) the SOS alert and returns its id. A missing location
  /// never blocks the alert; admins still get the job address.
  Future<String> raiseAlert(String requestId) async {
    JobCoordinate? position;
    try {
      position = await location.currentPosition().timeout(_locationTimeout);
    } catch (_) {
      position = null;
    }
    return _api.raiseSos(
      idToken: await _idToken(),
      requestId: requestId,
      latitude: position?.latitude,
      longitude: position?.longitude,
    );
  }

  Future<void> markSafe(String alertId) async =>
      _api.markSosSafe(idToken: await _idToken(), alertId: alertId);
}
