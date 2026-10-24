import 'package:flutter/material.dart';

import '../evidence_provenance.dart';
import '../l10n/app_localizations.dart';
import '../models.dart';
import '../theme.dart';

/// Describes record origin independently of cloud upload status.
class DataSourceBadge extends StatelessWidget {
  const DataSourceBadge({
    super.key,
    required this.source,
    required this.recordId,
    this.isDemo = false,
  });

  final SignalSource source;
  final String recordId;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final palette = TonyoPalette.of(context);
    final demo =
        isDemo ||
        recordId.toLowerCase().startsWith('syn-') ||
        EvidenceProvenance.hasDemoMarker([recordId]);
    final (label, description, icon, color) = demo
        ? (
            'Demo',
            'Example data for demonstration.',
            Icons.science_outlined,
            palette.muted,
          )
        : switch (source) {
            SignalSource.manual => (
              'Manual',
              'Added in Tonyo.',
              Icons.edit_outlined,
              palette.primary,
            ),
            SignalSource.healthKit => (
              'Apple Health',
              'Imported from Apple Health.',
              Icons.favorite_outline_rounded,
              palette.success,
            ),
            SignalSource.model => (
              'Estimated',
              'Calculated from your recorded data.',
              Icons.auto_graph_rounded,
              palette.warning,
            ),
          };
    final translatedLabel = context.tr(label);
    final translatedDescription = context.tr(description);
    return Semantics(
      label: context.tr(
        'Data source: {source}. {description}',
        args: {'source': translatedLabel, 'description': translatedDescription},
      ),
      excludeSemantics: true,
      child: Tooltip(
        message: translatedDescription,
        excludeFromSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: .3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  translatedLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
