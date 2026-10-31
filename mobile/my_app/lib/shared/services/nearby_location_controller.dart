import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/job_location.dart';
import '../utils/job_location_utils.dart';
import 'device_location_service.dart';

/// One-shot, screen-local location state. No profile writes or background stream.
class NearbyLocationController extends ChangeNotifier {
  NearbyLocationController({this.service = const DeviceLocationService()});

  final DeviceLocationService service;
  // A disposed dashboard cannot cancel the plugin's pending one-shot request.
  // Serialize Nearby requests even across recreated dashboard instances.
  static Future<void>? _nativeRequest;
  JobCoordinate? position;
  DeviceLocationException? error;
  bool loading = false;
  bool permissionRequired = true;
  Future<void>? _active;
  int _generation = 0;
  int _activeGeneration = 0;
  bool _disposed = false;

  Future<void> refresh({bool requestPermission = false}) {
    if (_disposed) return Future.value();
    final active = _active;
    if (active != null) {
      if (_activeGeneration == _generation) return active;
      // A previous screen's GPS lookup cannot be cancelled by the plugin.
      // Wait before starting a fresh one rather than overlapping native calls.
      final requestedGeneration = _generation;
      loading = true;
      notifyListeners();
      return active.then<void>((_) async {
        if (!_current(requestedGeneration)) return;
        await refresh(requestPermission: requestPermission);
      });
    }
    final generation = ++_generation;
    _activeGeneration = generation;
    loading = true;
    position = null;
    error = null;
    permissionRequired = false;
    notifyListeners();
    final operation = _refresh(generation, requestPermission);
    _active = operation.whenComplete(() => _active = null);
    return _active!;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> _refresh(int generation, bool requestPermission) async {
    try {
      if (!requestPermission && !await service.hasPermission()) {
        if (_current(generation)) permissionRequired = true;
        return;
      }
      if (!_current(generation)) return;
      final found = await _currentPosition(generation);
      if (!_current(generation) || found == null) return;
      if (!isValidJobCoordinate(found)) {
        throw const DeviceLocationException(DeviceLocationFailure.unavailable);
      }
      position = found;
    } on DeviceLocationException catch (failure) {
      if (_current(generation)) error = failure;
    } catch (_) {
      if (_current(generation)) {
        error = const DeviceLocationException(
          DeviceLocationFailure.unavailable,
        );
      }
    } finally {
      if (_current(generation)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<JobCoordinate?> _currentPosition(int generation) async {
    while (_nativeRequest != null) {
      await _nativeRequest;
      if (!_current(generation)) return null;
    }
    if (!_current(generation)) return null;
    final gate = Completer<void>();
    _nativeRequest = gate.future;
    try {
      return await service.currentPosition();
    } finally {
      _nativeRequest = null;
      gate.complete();
    }
  }

  void invalidate() {
    if (_disposed) return;
    _generation++;
    position = null;
    error = null;
    loading = false;
    permissionRequired = true;
    notifyListeners();
  }

  Future<void> openSettings() async {
    final failure = error?.failure;
    if (failure == null || _disposed) return;
    try {
      if (await service.openRecoverySettings(failure)) return;
      throw const DeviceLocationException(DeviceLocationFailure.unavailable);
    } catch (_) {
      if (!_disposed) {
        error = const DeviceLocationException(
          DeviceLocationFailure.unavailable,
        );
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
