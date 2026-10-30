import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/models/worker_service_selection.dart';
import '../../../../shared/theme/app_theme.dart';

const registrationServiceCategories = [
  'Academic Help',
  'Beauty',
  'Cleaning',
  'Errands',
  'Home Services',
  'Repairs',
];

class WorkerServiceSelector extends StatelessWidget {
  const WorkerServiceSelector({
    super.key,
    required this.selection,
    required this.categories,
    this.enabled = true,
    this.referenceLayout = false,
    this.compact = false,
  });

  final WorkerServiceSelection selection;
  final List<String> categories;
  final bool enabled;
  final bool referenceLayout;
  final bool compact;

  static IconData iconFor(String category) {
    final value = category.toLowerCase();
    if (value.contains('electric')) return Icons.electrical_services_outlined;
    if (value.contains('repair')) return Icons.handyman_outlined;
    if (value.contains('tutor')) return Icons.school_outlined;
    if (value.contains('clean')) return Icons.cleaning_services_outlined;
    if (value.contains('plumb')) return Icons.plumbing_outlined;
    if (value.contains('deliver') || value.contains('errand')) {
      return Icons.delivery_dining_outlined;
    }
    if (value == 'other') return Icons.add;
    return Icons.work_outline;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selection,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final options = <String>[];
      for (final item in [...categories, 'Other']) {
        final name = item.trim();
        if (name.isEmpty ||
            options.any((value) => value.toLowerCase() == name.toLowerCase())) {
          continue;
        }
        options.add(name);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose your services',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select all services you provide.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          if (referenceLayout) ...[
            LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent:
                      ((constraints.maxWidth - 12) / 2 / 1.52).clamp(116, 240) *
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: registrationServiceCategories.length,
                itemBuilder: (context, index) => _ReferenceServiceCard(
                  category: registrationServiceCategories[index],
                  selection: selection,
                  enabled: enabled,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _ReferenceServiceCard(
              category: 'Other',
              selection: selection,
              enabled: enabled,
            ),
          ] else if (compact)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in options)
                  FilterChip(
                    key: ValueKey('worker-category-$category'),
                    label: Text(category),
                    selected: selection.contains(category),
                    showCheckmark: false,
                    selectedColor: colors.primaryContainer,
                    side: BorderSide(
                      color: selection.contains(category)
                          ? colors.primary
                          : colors.outlineVariant,
                    ),
                    onSelected: enabled
                        ? (_) => selection.toggle(category)
                        : null,
                  ),
              ],
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth < 260 ? 1 : 2,
                  mainAxisExtent:
                      118 *
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final category = options[index];
                  final selected = selection.contains(category);
                  return Semantics(
                    label: category,
                    selected: selected,
                    button: true,
                    child: Material(
                      color: selected
                          ? colors.primaryContainer
                          : colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        key: ValueKey('worker-category-$category'),
                        onTap: enabled
                            ? () => selection.toggle(category)
                            : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? colors.primary
                                  : (theme.brightness == Brightness.dark
                                        ? colors.outline
                                        : AppTheme.line),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Align(
                                alignment: Alignment.topRight,
                                child: Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 18,
                                  color: selected
                                      ? colors.onPrimaryContainer
                                      : colors.outline,
                                ),
                              ),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        iconFor(category),
                                        size: 28,
                                        color: colors.onSurface,
                                      ),
                                      const SizedBox(height: 9),
                                      Text(
                                        category,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (selection.hasOther) ...[
            const SizedBox(height: 18),
            TextFormField(
              key: const ValueKey('worker-custom-service'),
              initialValue: selection.customService,
              enabled: enabled,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Specify your service',
                hintText: 'e.g. Pet grooming',
              ),
              onChanged: selection.specifyOther,
              validator: (_) =>
                  selection.hasOther ? selection.validationError : null,
            ),
          ],
        ],
      );
    },
  );
}

/// Outline artwork follows the reference: cap, sparkles, drop, bag, house, wrench.
class _ReferenceServiceCard extends StatelessWidget {
  const _ReferenceServiceCard({
    required this.category,
    required this.selection,
    required this.enabled,
  });

  final String category;
  final WorkerServiceSelection selection;
  final bool enabled;

  static const _paths = {
    'Academic Help':
        '<path d="m2 8 10-5 10 5-10 5-10-5Z M6 10v6c3 3 9 3 12 0v-6"/>',
    'Beauty':
        '<path d="m11 2 2.5 6.5L20 11l-6.5 2.5L11 20l-2.5-6.5L2 11l6.5-2.5L11 2Z M20 16l1 2 2 1-2 1-1 2-1-2-2-1 2-1 1-2Z"/>',
    'Cleaning': '<path d="M12 2C9 6 5 10 5 15a7 7 0 0 0 14 0c0-5-4-9-7-13Z"/>',
    'Errands': '<path d="M4 7h16l-1.5 15h-13L4 7Z M8 7V5a4 4 0 0 1 8 0v2"/>',
    'Home Services': '<path d="m2 10 10-8 10 8 M5 8v14h14V8 M10 22v-8h4v8"/>',
    'Repairs':
        '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76Z"/>',
    'Other':
        '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = selection.contains(category);
    final other = category == 'Other';
    final circleColor = selected
        ? colors.primary
        : colors.surfaceContainerHighest;
    final icon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: SvgPicture.string(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${_paths[category]}</svg>',
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(colors.onSurface, BlendMode.srcIn),
        semanticsLabel: '$category icon',
      ),
    );
    final label = Text(
      other ? 'Others' : category,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
      maxLines: 2,
    );
    return Semantics(
      label: other ? 'Others' : category,
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey('worker-category-$category'),
          onTap: enabled ? () => selection.toggle(category) : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: 1.5,
              ),
            ),
            child: other
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 14),
                      Expanded(child: label),
                      if (selected) _check(colors),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          icon,
                          const Spacer(),
                          if (selected) _check(colors),
                        ],
                      ),
                      const Spacer(),
                      label,
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _check(ColorScheme colors) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(color: colors.onSurface, shape: BoxShape.circle),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: SvgPicture.string(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 4 4 10-10"/></svg>',
        colorFilter: ColorFilter.mode(colors.surface, BlendMode.srcIn),
        excludeFromSemantics: true,
      ),
    ),
  );
}
