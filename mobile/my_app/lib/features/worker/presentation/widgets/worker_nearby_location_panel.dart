import 'package:flutter/material.dart';

import '../../../../shared/services/device_location_service.dart';
import '../../../../shared/services/nearby_location_controller.dart';

class WorkerNearbyLocationPanel extends StatelessWidget {
  const WorkerNearbyLocationPanel({super.key, required this.controller});
  final NearbyLocationController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final failure = controller.error?.failure;
      final settings =
          failure == DeviceLocationFailure.permissionPermanentlyDenied ||
          failure == DeviceLocationFailure.serviceDisabled;
      final message = switch (failure) {
        DeviceLocationFailure.permissionDenied =>
          'Location permission was denied. Allow access to find jobs near you, then retry.',
        DeviceLocationFailure.permissionPermanentlyDenied =>
          'Location access is blocked. Allow it in app settings, then return here.',
        DeviceLocationFailure.serviceDisabled =>
          'Turn on device location services to find nearby jobs.',
        DeviceLocationFailure.timedOut =>
          'Getting your location timed out. Check your GPS signal and retry.',
        DeviceLocationFailure.unavailable =>
          'Your current location is unavailable. Check location services and retry.',
        null =>
          controller.loading
              ? 'Getting your current location…'
              : controller.position == null
              ? 'Use your current location to find jobs within 10 km. Your saved address will stay unchanged.'
              : 'Within 10 km of your current location · Approximate distances',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (controller.loading)
            const LinearProgressIndicator()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (settings)
                  TextButton.icon(
                    onPressed: controller.openSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open settings'),
                  ),
                TextButton.icon(
                  key: const ValueKey('worker-nearby-refresh'),
                  onPressed: () => controller.refresh(requestPermission: true),
                  icon: Icon(
                    controller.position == null
                        ? Icons.my_location
                        : Icons.refresh,
                  ),
                  label: Text(
                    controller.position != null
                        ? 'Refresh nearby jobs'
                        : controller.error != null
                        ? 'Retry location'
                        : 'Use My Current Location',
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );
}
