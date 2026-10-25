import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

const openStreetMapTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class SwiftServeMapTiles extends StatelessWidget {
  const SwiftServeMapTiles({super.key, this.onError});

  final ErrorTileCallBack? onError;

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: openStreetMapTileUrl,
      userAgentPackageName: 'com.example.my_app',
      maxNativeZoom: 19,
      errorTileCallback: onError,
    );
  }
}

class SwiftServeMapAttribution extends StatelessWidget {
  const SwiftServeMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleAttributionWidget(
      source: Text('OpenStreetMap contributors'),
    );
  }
}

class SwiftServeMapPin extends StatelessWidget {
  const SwiftServeMapPin({
    super.key,
    this.label = 'Selected job location',
    this.isDragging = false,
  });

  final String label;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      image: true,
      child: AnimatedScale(
        scale: isDragging ? 1.12 : 1,
        duration: const Duration(milliseconds: 120),
        child: Icon(
          Icons.location_pin,
          size: 48,
          color: colorScheme.primary,
          shadows: const [
            Shadow(
              color: Color(0x66000000),
              offset: Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

class MapUnavailableOverlay extends StatelessWidget {
  const MapUnavailableOverlay({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, size: 36),
                const SizedBox(height: 8),
                Text(
                  'Map unavailable',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Check your internet connection, then try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry map'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
