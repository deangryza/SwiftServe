import 'package:flutter/material.dart';

import '../../../../shared/services/device_location_service.dart';
import '../../../../shared/services/job_geocoding_service.dart';

/// Fills the existing registration address without retaining GPS coordinates.
class UseCurrentLocationButton extends StatefulWidget {
  const UseCurrentLocationButton({
    super.key,
    required this.address,
    this.enabled = true,
    this.locationService = const DeviceLocationService(),
    this.addressResolver,
    this.onAddressResolved,
  });

  final TextEditingController address;
  final bool enabled;
  final DeviceLocationService locationService;
  final JobAddressResolver? addressResolver;
  final ValueChanged<ResolvedJobAddress>? onAddressResolved;

  @override
  State<UseCurrentLocationButton> createState() =>
      _UseCurrentLocationButtonState();
}

class _UseCurrentLocationButtonState extends State<UseCurrentLocationButton> {
  bool _loading = false;
  int _addressRevision = 0;
  DeviceLocationFailure? _failure;
  String? _message;

  void _addressChanged() => _addressRevision++;

  @override
  void initState() {
    super.initState();
    widget.address.addListener(_addressChanged);
  }

  @override
  void didUpdateWidget(covariant UseCurrentLocationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.address != widget.address) {
      oldWidget.address.removeListener(_addressChanged);
      widget.address.addListener(_addressChanged);
      _addressRevision++;
    }
  }

  @override
  void dispose() {
    widget.address.removeListener(_addressChanged);
    super.dispose();
  }

  bool _canFill(int revision) =>
      mounted && widget.enabled && revision == _addressRevision;

  Future<void> _useLocation() async {
    if (_loading || !widget.enabled) return;
    final revision = _addressRevision;
    setState(() {
      _loading = true;
      _failure = null;
      _message = null;
    });
    try {
      final position = await widget.locationService.currentPosition();
      if (!_canFill(revision)) return;
      final resolved = await (widget.addressResolver ?? JobGeocodingService())
          .resolve(position)
          .timeout(const Duration(seconds: 10));
      if (!_canFill(revision)) return;
      final address = resolved.exactAddress.trim();
      if (address.isEmpty) throw StateError('No address found.');
      widget.address.value = TextEditingValue(
        text: address,
        selection: TextSelection.collapsed(offset: address.length),
      );
      widget.onAddressResolved?.call(resolved);
      setState(() {
        _message = 'Address filled. You can edit it before continuing.';
      });
    } on DeviceLocationException catch (error) {
      if (!_canFill(revision)) return;
      setState(() {
        _failure = error.failure;
        _message = switch (error.failure) {
          DeviceLocationFailure.serviceDisabled =>
            'Turn on location services, or enter your address manually.',
          DeviceLocationFailure.permissionDenied =>
            'Location permission was denied. You can enter your address manually.',
          DeviceLocationFailure.permissionPermanentlyDenied =>
            'Allow location permission in device settings, or enter your address manually.',
          DeviceLocationFailure.timedOut =>
            'Your location took too long. Try again or enter your address manually.',
          DeviceLocationFailure.unavailable =>
            'Your location is unavailable. Try again or enter your address manually.',
        };
      });
    } catch (_) {
      if (!_canFill(revision)) return;
      setState(() {
        _message =
            'Could not find your address. Enter it manually or try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSettings() async {
    final failure = _failure;
    if (failure == null) return;
    try {
      final opened = await widget.locationService.openRecoverySettings(failure);
      if (!mounted || opened) return;
      setState(
        () => _message = 'Open device settings to enable location access.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _message = 'Open device settings to enable location access.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canOpenSettings =
        _failure == DeviceLocationFailure.serviceDisabled ||
        _failure == DeviceLocationFailure.permissionPermanentlyDenied;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: widget.enabled && !_loading ? _useLocation : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_outlined),
            label: Text(
              _loading ? 'Finding address…' : 'Use my current location',
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (canOpenSettings)
            TextButton(
              onPressed: widget.enabled && !_loading ? _openSettings : null,
              child: const Text('Open settings'),
            ),
        ],
      ),
    );
  }
}
