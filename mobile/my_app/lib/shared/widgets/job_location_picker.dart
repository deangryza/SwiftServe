import 'dart:async';

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
    this.initialValue,
    this.errorText,
    this.locationService = const DeviceLocationService(),
    this.geocodingService,
    this.mapBuilder,
    this.currentLocationEnabled = true,
    this.currentLocationDisabledReason,
    this.onCurrentLocationRequested,
    this.onCurrentLocationReleased,
  });

  final ValueChanged<JobLocationSelection?> onChanged;

  /// A pin to start from, such as the saved location of a post being edited.
  final JobLocationSelection? initialValue;
  final String? errorText;
  final DeviceLocationService locationService;
  final JobAddressResolver? geocodingService;
  final JobLocationMapBuilder? mapBuilder;
  final bool currentLocationEnabled;
  final String? currentLocationDisabledReason;

  /// A synchronous reservation lets a parent coordinate multiple GPS buttons,
  /// including requests that are still waiting for permission or a GPS fix.
  final bool Function()? onCurrentLocationRequested;
  final VoidCallback? onCurrentLocationReleased;

  @override
  State<JobLocationPicker> createState() => _JobLocationPickerState();
}

class _JobLocationPickerState extends State<JobLocationPicker> {
  static const _philippinesCenter = LatLng(12.8797, 121.7740);

  final _addressController = TextEditingController();
  final _searchController = TextEditingController();
  final _mapController = MapController();
  late final JobAddressResolver _geocodingService;
  JobCoordinate? _position;
  String _areaLabel = 'Pinned service area';
  String? _statusMessage;
  DeviceLocationFailure? _failure;
  bool _loading = false;
  bool _locating = false;
  bool _searchUnresolved = false;
  bool _usesCurrentLocation = false;
  Timer? _searchDebounce;
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
    final initial = widget.initialValue;
    if (initial != null) {
      _position = initial.position;
      _areaLabel = initial.areaLabel;
      _addressController.text = initial.exactAddress;
      _statusMessage = 'Exact address is shared only with the accepted worker.';
    }
    _addressController.addListener(_notifySelection);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _addressController
      ..removeListener(_notifySelection)
      ..dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _notifySelection() {
    final position = _position;
    final address = _addressController.text.trim();
    if (position == null || _searchUnresolved || address.isEmpty) {
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

  int _beginLookup() {
    _searchDebounce?.cancel();
    _pendingCameraPosition = null;
    return ++_lookupVersion;
  }

  void _searchChanged(String text) {
    final version = _beginLookup();
    _releaseCurrentLocation();
    final query = text.trim();
    setState(() {
      _searchUnresolved = true;
      _loading = false;
      _locating = false;
      _failure = null;
      _statusMessage = query.length < 3
          ? 'Enter at least 3 characters, or choose a point on the map.'
          : 'Pause typing to find this location.';
    });
    _notifySelection();
    if (query.length < 3) return;
    _searchDebounce = Timer(
      const Duration(milliseconds: 650),
      () => _searchAddress(query, version),
    );
  }

  Future<void> _searchAddress(String query, int version) async {
    setState(() {
      _loading = true;
      _statusMessage = 'Finding this location…';
    });
    try {
      final selection = await _geocodingService
          .search(query)
          .timeout(const Duration(seconds: 15));
      if (!mounted || version != _lookupVersion) return;
      setState(() {
        _position = selection.position;
        _areaLabel = selection.areaLabel;
        _searchUnresolved = false;
        _loading = false;
        _searchController.text = selection.exactAddress;
        _addressController.text = selection.exactAddress;
        _statusMessage = 'Location found. Check the pin before posting.';
      });
      _showPosition(selection.position);
      _notifySelection();
    } catch (_) {
      if (!mounted || version != _lookupVersion) return;
      setState(() {
        _loading = false;
        _statusMessage =
            'Could not find this location. Add a city or nearby landmark, '
            'check your connection, or choose a point on the map.';
      });
      // Keep the last marker, but never associate unresolved text with it.
      _notifySelection();
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_locating || !widget.currentLocationEnabled) return;
    final alreadyUsingCurrentLocation = _usesCurrentLocation;
    if (widget.onCurrentLocationRequested?.call() == false) return;
    _usesCurrentLocation = true;
    final version = _beginLookup();
    setState(() {
      _loading = true;
      _locating = true;
      _failure = null;
      _statusMessage = 'Finding your location…';
    });
    try {
      final position = await widget.locationService.currentPosition();
      if (!mounted || version != _lookupVersion) return;
      await _selectPosition(
        position,
        moveCamera: true,
        fromCurrentLocation: true,
      );
    } on DeviceLocationException catch (error) {
      if (!mounted || version != _lookupVersion) return;
      if (!alreadyUsingCurrentLocation) _releaseCurrentLocation();
      setState(() {
        _loading = false;
        _locating = false;
        _failure = error.failure;
        _statusMessage = error.userMessage;
      });
    } catch (_) {
      if (!mounted || version != _lookupVersion) return;
      if (!alreadyUsingCurrentLocation) _releaseCurrentLocation();
      setState(() {
        _loading = false;
        _locating = false;
        _failure = DeviceLocationFailure.unavailable;
        _statusMessage = const DeviceLocationException(
          DeviceLocationFailure.unavailable,
        ).userMessage;
      });
    }
  }

  Future<void> _selectPosition(
    JobCoordinate position, {
    bool moveCamera = false,
    bool fromCurrentLocation = false,
  }) async {
    final version = _beginLookup();
    if (!fromCurrentLocation) _releaseCurrentLocation();
    _searchUnresolved = false;
    _areaLabel = 'Pinned service area';
    _searchController.clear();
    _addressController.clear();
    setState(() {
      _position = position;
      _loading = true;
      _locating = false;
      _failure = null;
      _statusMessage = 'Looking up the pinned address…';
    });
    _notifySelection();
    if (moveCamera) {
      _showPosition(position);
    }

    try {
      final address = await _geocodingService
          .resolve(position)
          .timeout(const Duration(seconds: 10));
      if (!mounted || version != _lookupVersion) return;
      _areaLabel = address.areaLabel.isEmpty
          ? 'Pinned service area'
          : address.areaLabel;
      _addressController.text = address.exactAddress;
      _searchController.text = address.exactAddress;
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

  void _releaseCurrentLocation() {
    if (!_usesCurrentLocation) return;
    _usesCurrentLocation = false;
    widget.onCurrentLocationReleased?.call();
  }

  void _manualAddressChanged(String address) {
    // A manual edit wins over GPS/reverse lookups that are still in flight.
    _beginLookup();
    _releaseCurrentLocation();
    setState(() {
      _loading = false;
      _locating = false;
      _failure = null;
      _statusMessage = address.trim().isEmpty
          ? 'Enter the address for the selected pin.'
          : 'Exact address is shared only with the accepted worker.';
    });
  }

  void _showPosition(JobCoordinate position) {
    if (_mapReady) {
      _moveMapTo(position);
    } else {
      _pendingCameraPosition = position;
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
        TextField(
          key: const ValueKey('job-location-search'),
          controller: _searchController,
          onChanged: _searchChanged,
          textInputAction: TextInputAction.done,
          minLines: 1,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Find a location',
            hintText: 'Address, street, landmark or place',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading && !_locating
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
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
                        // Open straight on a saved pin; moving the camera
                        // after the map loads can leave it blank.
                        initialCenter: widget.initialValue == null
                            ? _philippinesCenter
                            : LatLng(
                                widget.initialValue!.position.latitude,
                                widget.initialValue!.position.longitude,
                              ),
                        initialZoom: widget.initialValue == null ? 5.3 : 16,
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
            key: const ValueKey('job-location-gps'),
            onPressed: _locating || !widget.currentLocationEnabled
                ? null
                : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_outlined),
            label: Text(_locating ? 'Locating…' : 'Use my current location'),
          ),
        ),
        if (!widget.currentLocationEnabled &&
            widget.currentLocationDisabledReason != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.currentLocationDisabledReason!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('job-location-exact-address'),
          controller: _addressController,
          onChanged: _manualAddressChanged,
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
