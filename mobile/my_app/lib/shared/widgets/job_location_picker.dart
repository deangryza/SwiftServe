import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';

import '../models/job_location.dart';
import '../services/device_location_service.dart';
import '../services/job_geocoding_service.dart';
import 'open_street_map_layers.dart';

typedef JobLocationMapBuilder =
    Widget Function(
      BuildContext context,
      JobCoordinate? position,
      ValueChanged<JobCoordinate> onSelected,
    );

class JobLocationPicker extends StatefulWidget {
  const JobLocationPicker({
    super.key,
    required this.onChanged,
    this.errorText,
    this.locationService = const DeviceLocationService(),
    this.geocodingService,
    this.mapBuilder,
  });

  final ValueChanged<JobLocationSelection?> onChanged;
  final String? errorText;
  final DeviceLocationService locationService;
  final JobAddressResolver? geocodingService;
  final JobLocationMapBuilder? mapBuilder;

  @override
  State<JobLocationPicker> createState() => _JobLocationPickerState();
}

class _JobLocationPickerState extends State<JobLocationPicker> {
  static const _philippinesCenter = LatLng(12.8797, 121.7740);

  final _addressController = TextEditingController();
  final _mapController = MapController();
  late final JobAddressResolver _geocodingService;
  JobCoordinate? _position;
  String _areaLabel = 'Pinned service area';
  String? _statusMessage;
  DeviceLocationFailure? _failure;
  bool _loading = false;
  bool _mapReady = false;
  bool _mapFailed = false;
  int _mapErrorCount = 0;
  int _mapReloadVersion = 0;
  int _lookupVersion = 0;
  JobCoordinate? _pendingCameraPosition;

  @override
  void initState() {
    super.initState();
    _geocodingService = widget.geocodingService ?? JobGeocodingService();
    _addressController.addListener(_notifySelection);
  }

  @override
  void dispose() {
    _addressController
      ..removeListener(_notifySelection)
      ..dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _notifySelection() {
    final position = _position;
    final address = _addressController.text.trim();
    if (position == null) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(
      JobLocationSelection(
        position: position,
        exactAddress: address,
        areaLabel: _areaLabel,
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _loading = true;
      _failure = null;
      _statusMessage = 'Finding your location…';
    });
    try {
      final position = await widget.locationService.currentPosition();
      if (!mounted) return;
      await _selectPosition(position, moveCamera: true);
    } on DeviceLocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = error.failure;
        _statusMessage = error.userMessage;
      });
    }
  }

  Future<void> _selectPosition(
    JobCoordinate position, {
    bool moveCamera = false,
  }) async {
    final version = ++_lookupVersion;
    _areaLabel = 'Pinned service area';
    _addressController.clear();
    setState(() {
      _position = position;
      _loading = true;
      _failure = null;
      _statusMessage = 'Looking up the pinned address…';
    });
    _notifySelection();
    if (moveCamera) {
      if (_mapReady) {
        _moveMapTo(position);
      } else {
        _pendingCameraPosition = position;
      }
    }

    try {
      final address = await _geocodingService.resolve(position);
      if (!mounted || version != _lookupVersion) return;
      _areaLabel = address.areaLabel.isEmpty
          ? 'Pinned service area'
          : address.areaLabel;
      _addressController.text = address.exactAddress;
      setState(() {
        _loading = false;
        _statusMessage = address.exactAddress.isEmpty
            ? 'Enter a recognizable address for this pin.'
            : 'Exact address is shared only with the accepted worker.';
      });
      _notifySelection();
    } catch (_) {
      if (!mounted || version != _lookupVersion) return;
      _areaLabel = 'Pinned service area';
      setState(() {
        _loading = false;
        _statusMessage =
            'Address lookup failed. Keep the pin and enter the address manually.';
      });
      _notifySelection();
    }
  }

  Future<void> _openSettings() async {
    final failure = _failure;
    if (failure == null) return;
    await widget.locationService.openRecoverySettings(failure);
  }

  void _moveMapTo(JobCoordinate position) {
    _mapController.move(LatLng(position.latitude, position.longitude), 16);
  }

  void _handleMapReady() {
    _mapReady = true;
    final pendingPosition = _pendingCameraPosition;
    _pendingCameraPosition = null;
    if (pendingPosition != null) _moveMapTo(pendingPosition);
  }

  void _handleMapTileError(Object error) {
    if (_mapFailed || !mounted) return;
    _mapErrorCount += 1;
    if (_mapErrorCount < 3) return;
    setState(() => _mapFailed = true);
  }

  void _retryMap() {
    setState(() {
      _mapFailed = false;
      _mapErrorCount = 0;
      _mapReloadVersion += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canOpenSettings =
        _failure == DeviceLocationFailure.serviceDisabled ||
        _failure == DeviceLocationFailure.permissionPermanentlyDenied;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.mapBuilder != null)
          widget.mapBuilder!(context, _position, _selectPosition)
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 230,
              child: Stack(
                children: [
                  Semantics(
                    label:
                        'Job location map. Tap the map or drag the marker to choose the service location.',
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _philippinesCenter,
                        initialZoom: 5.3,
                        minZoom: 3,
                        maxZoom: 18,
                        onMapReady: _handleMapReady,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        onTap: (_, position) => _selectPosition(
                          JobCoordinate(
                            latitude: position.latitude,
                            longitude: position.longitude,
                          ),
                        ),
                      ),
                      children: [
                        SwiftServeMapTiles(
                          key: ValueKey(_mapReloadVersion),
                          onError: (_, error, _) => _handleMapTileError(error),
                        ),
                        if (_position != null)
                          DragMarkers(
                            markers: [
                              DragMarker(
                                point: LatLng(
                                  _position!.latitude,
                                  _position!.longitude,
                                ),
                                size: const Size(48, 48),
                                alignment: Alignment.bottomCenter,
                                scrollMapNearEdge: true,
                                builder: (_, _, isDragging) =>
                                    SwiftServeMapPin(isDragging: isDragging),
                                onDragEnd: (_, position) => _selectPosition(
                                  JobCoordinate(
                                    latitude: position.latitude,
                                    longitude: position.longitude,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SwiftServeMapAttribution(),
                      ],
                    ),
                  ),
                  if (_mapFailed) MapUnavailableOverlay(onRetry: _retryMap),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _useCurrentLocation,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_outlined),
            label: Text(_loading ? 'Locating…' : 'Use my current location'),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _addressController,
          enabled: _position != null,
          minLines: 1,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Exact service address',
            hintText: _position == null
                ? 'Choose a pin first'
                : 'Enter the address for the selected pin',
            prefixIcon: const Icon(Icons.location_on_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _statusMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _failure == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
        if (canOpenSettings)
          TextButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            label: Text(
              _failure == DeviceLocationFailure.serviceDisabled
                  ? 'Open location settings'
                  : 'Open app settings',
            ),
          ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              widget.errorText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
