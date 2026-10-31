import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../theme/app_theme.dart';
import 'live_profile_avatar.dart';
import 'sos_button.dart';

const bookingMapPreviewHeight = 210.0;
const bookingMapPreviewRadius = 20.0;

class BookingDetailsHeader extends StatelessWidget {
  const BookingDetailsHeader({
    super.key,
    required this.request,
    required this.backButton,
    this.showSos = true,
    this.actions = const [],
  });
  final ServiceRequest request;
  final Widget backButton;
  final bool showSos;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    child: Row(
      children: [
        backButton,
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Booking Details',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        ...actions,
        if (showSos) SosButton(request: request, compact: true),
      ],
    ),
  );
}

class BookingSectionCard extends StatelessWidget {
  const BookingSectionCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
}

class BookingPartyCard extends StatelessWidget {
  const BookingPartyCard({
    super.key,
    required this.userId,
    required this.name,
    required this.role,
    required this.profileKey,
    required this.messageKey,
    required this.onViewProfile,
    this.onMessage,
    this.details,
  });
  final String userId;
  final String name;
  final String role;
  final Key profileKey;
  final Key messageKey;
  final VoidCallback? onViewProfile;
  final VoidCallback? onMessage;
  final Widget? details;

  @override
  Widget build(BuildContext context) => BookingSectionCard(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onMessage != null) ...[
              IconButton.outlined(
                key: messageKey,
                tooltip: 'Message $role',
                onPressed: onMessage,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
              const SizedBox(width: 8),
            ],
            IconButton.outlined(
              key: profileKey,
              tooltip: 'View $role profile',
              onPressed: onViewProfile,
              icon: const Icon(Icons.person_outline_rounded),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                LiveProfileAvatar(
                  userId: userId,
                  fallbackName: name,
                  radius: 25,
                  backgroundColor: AppTheme.softYellow,
                  foregroundColor: AppTheme.ink,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(role, style: Theme.of(context).textTheme.bodySmall),
                      ?details,
                    ],
                  ),
                ),
                if (constraints.maxWidth >= 300) ...[
                  const SizedBox(width: 8),
                  actions,
                ],
              ],
            ),
            if (constraints.maxWidth < 300) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          ],
        );
      },
    ),
  );
}

/// Presentation only: no new status or transition is introduced.
int bookingProgressIndex(ServiceRequest request) {
  if (request.status == ServiceRequestStatus.completed) return 2;
  if (request.status == ServiceRequestStatus.expired ||
      request.status == ServiceRequestStatus.cancelled ||
      request.status == ServiceRequestStatus.pending) {
    return -1;
  }
  if (request.isErrand) {
    if (request.status != ServiceRequestStatus.ongoing) return -1;
    return switch (request.errandStage) {
      ErrandStage.pickedUp => 0,
      ErrandStage.delivering => 1,
      _ => -1,
    };
  }
  return request.status == ServiceRequestStatus.ongoing ? 1 : 0;
}

class BookingFeeProgressCard extends StatelessWidget {
  const BookingFeeProgressCard({super.key, required this.request});
  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = request.status == ServiceRequestStatus.completed;
    final highlight = completed ? Colors.green.shade700 : AppTheme.yellow;
    final stage = bookingProgressIndex(request);
    final labels = request.isErrand
        ? ['Picked up', 'On the way', 'Delivered']
        : ['Accepted', 'In progress', 'Completed'];
    final status = request.status.name;
    return BookingSectionCard(
      key: const ValueKey('booking-fee-progress'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.isErrand ? 'Delivery fee' : 'Budget',
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    '₱${request.budget.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: completed
                          ? highlight.withValues(alpha: .12)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${status[0].toUpperCase()}${status.substring(1)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (request.distanceKm != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '~${request.distanceKm!.toStringAsFixed(1)} km trip',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (request.isErrand &&
              request.status == ServiceRequestStatus.ongoing &&
              request.errandStage == ErrandStage.headingToPickup) ...[
            const SizedBox(height: 8),
            Text(request.errandStage!.label, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 18),
          Semantics(
            label: 'Booking progress: $status',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < 3; index++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: index == 2 ? 0 : 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            key: ValueKey(
                              'booking-progress-$index-${index <= stage ? 'active' : 'waiting'}',
                            ),
                            height: 6,
                            decoration: BoxDecoration(
                              color: index <= stage
                                  ? highlight
                                  : theme.dividerColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labels[index],
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: index == stage
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BookingRouteCard extends StatelessWidget {
  const BookingRouteCard({
    super.key,
    required this.request,
    this.pickupAddress,
    this.dropoffAddress,
    this.approximate = true,
  });
  final ServiceRequest request;
  final String? pickupAddress;
  final String? dropoffAddress;
  final bool approximate;

  @override
  Widget build(BuildContext context) => BookingSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BookingAddress(
          icon: Icons.location_on_outlined,
          label: request.isErrand
              ? (approximate ? 'Pickup area' : 'Pickup')
              : 'Service location',
          address: pickupAddress ?? request.location,
        ),
        if (request.isErrand) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _BookingAddress(
            icon: Icons.flag_outlined,
            label: approximate ? 'Drop-off area' : 'Drop-off',
            address: dropoffAddress ?? request.dropoffLocation ?? 'Not set',
          ),
        ],
      ],
    ),
  );
}

class _BookingAddress extends StatelessWidget {
  const _BookingAddress({
    required this.icon,
    required this.label,
    required this.address,
  });
  final IconData icon;
  final String label;
  final String address;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(address.isEmpty ? 'Location unavailable' : address),
          ],
        ),
      ),
    ],
  );
}

class BookingInformationCard extends StatelessWidget {
  const BookingInformationCard({
    super.key,
    required this.request,
    required this.dateLabel,
  });
  final ServiceRequest request;
  final String dateLabel;

  @override
  Widget build(BuildContext context) => BookingSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          request.isErrand ? 'ERRAND' : 'SERVICE',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        Text(
          request.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        if (request.errandItems?.isNotEmpty ?? false)
          _row(context, 'Item', request.errandItems!),
        _row(context, 'Category', request.category),
        _row(
          context,
          'Type',
          request.modality.needsLocation
              ? request.modality.label
              : 'Online · done remotely',
        ),
        _row(context, 'Date', dateLabel),
        if (request.itemCostEstimate != null)
          _row(
            context,
            'Item cost estimate',
            '₱${request.itemCostEstimate!.toStringAsFixed(0)} (paid back on delivery)',
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1),
        ),
        Text('Client note', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(request.description),
      ],
    ),
  );

  Widget _row(BuildContext context, String label, String value) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ],
  );
}
