import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_strings.dart';
import '../services/noah_awareness.dart';
import '../theme/app_palette.dart';

const _disclaimer =
    'Modeled 5-year rainfall scenario. Does not confirm current flooding or road passability.';
const _authority =
    'Barangay verification determines recorded road conditions. NOAH does not approve reports or change navigation decisions.';
String noahLevelLabel(int level) => switch (level) {
  3 => 'High hazard',
  2 => 'Medium hazard',
  _ => 'Low hazard',
};
Color noahLevelColor(int level) => switch (level) {
  3 => const Color(0xFFC63A46),
  2 => const Color(0xFFCA7000),
  _ => const Color(0xFFAD8000),
};

Future<void> showNoahInfo(
  BuildContext context, {
  VoidCallback? onViewCoverage,
  NoahMapController? controller,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: AppPalette.of(context).surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (sheet) =>
      _NoahInfoSheet(controller: controller, onViewCoverage: onViewCoverage),
);

class _NoahInfoSheet extends StatelessWidget {
  final NoahMapController? controller;
  final VoidCallback? onViewCoverage;
  const _NoahInfoSheet({this.controller, this.onViewCoverage});
  Widget _card(BuildContext context, Widget child, {Color? color}) {
    final p = AppPalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .5)),
      ),
      child: child,
    );
  }

  Widget _body(BuildContext context) {
    final p = AppPalette.of(context), control = controller;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.layers_outlined, color: p.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr(context, 'NOAH flood awareness'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: p.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Close'),
                  color: p.onSurfaceVariant,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (control?.failed == true)
                    _card(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.error_outline, color: p.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr(context, switch (control!.failureStage) {
                                    NoahFailureStage.asset =>
                                      'NOAH data is missing from this app build.',
                                    NoahFailureStage.render =>
                                      'NOAH could not draw on the map.',
                                    _ => 'NOAH data could not be read.',
                                  }),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: p.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(
                              context,
                              'SafePaths road conditions and reporting remain available.',
                            ),
                          ),
                          if (control.failureStage == NoahFailureStage.asset &&
                              kDebugMode)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                tr(
                                  context,
                                  'Stop Flutter completely and run the app again to include the map data.',
                                ),
                              ),
                            ),
                          TextButton.icon(
                            onPressed: control.loading ? null : control.retry,
                            icon: const Icon(Icons.refresh),
                            label: Text(tr(context, 'Retry')),
                          ),
                        ],
                      ),
                      color: p.error.withValues(alpha: .05),
                    ),
                  _card(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, '5-year rainfall scenario'),
                          style: TextStyle(
                            color: p.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            context,
                            'The 5-year label describes a rainfall return period, not the map age or a forecast for the next five years.',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr(context, _disclaimer),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: p.onSurface,
                          ),
                        ),
                      ],
                    ),
                    color: p.primary.withValues(alpha: .05),
                  ),
                  _card(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, 'What the colors mean'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final level in [3, 2, 1])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: noahLevelColor(
                                      level,
                                    ).withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.square_rounded,
                                    size: 15,
                                    color: noahLevelColor(level),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    tr(context, noahLevelLabel(level)),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: p.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            context,
                            'Hazard classes consider flood depth and flow. They are not current water-depth readings.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: p.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _card(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.map_outlined,
                              color: p.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tr(context, 'Where this data applies'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: p.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr(
                            context,
                            'Prepared data covers Marulas and a surrounding buffer only. Unshaded areas are not proven safe; study coverage is not established by this file.',
                          ),
                        ),
                        const Divider(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              color: p.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tr(context, _authority),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.45,
                                  color: p.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: p.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: p.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      title: Text(
                        tr(context, 'Source and licence'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.primary,
                        ),
                      ),
                      subtitle: const Text(
                        'Project NOAH · BetterGov.PH ? ODbL 1.0',
                        style: TextStyle(fontSize: 11),
                      ),
                      children: [
                        Text(
                          tr(
                            context,
                            'Project NOAH and contributors ? BetterGov.PH mirror. Original model date unavailable. Adapted by SafePaths through geometry repair and cropping.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const SelectableText(
                          'https://noah.up.edu.ph/\nhttps://opendatacommons.org/licenses/odbl/1.0/\nhttps://huggingface.co/datasets/bettergovph/project-noah-hazard-maps',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            context,
                            'The adapted open hazard database and source notices are included with this app. No resident data is part of this dataset.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onViewCoverage != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(
                  top: BorderSide(
                    color: p.outlineVariant.withValues(alpha: .5),
                  ),
                ),
              ),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: p.primary,
                  foregroundColor: p.onPrimary,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onViewCoverage!();
                },
                icon: const Icon(Icons.map_outlined),
                label: Text(tr(context, 'View Marulas coverage')),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => controller == null
      ? _body(context)
      : ListenableBuilder(
          listenable: controller!,
          builder: (context, _) => _body(context),
        );
}

class NoahLayerControls extends StatelessWidget {
  final NoahMapController controller;
  final VoidCallback onViewCoverage, onRoadLegend;
  const NoahLayerControls({
    super.key,
    required this.controller,
    required this.onViewCoverage,
    required this.onRoadLegend,
  });
  Widget _toggle(
    BuildContext context,
    String label,
    IconData icon,
    bool selected,
    ValueChanged<bool> onChanged,
  ) {
    final p = AppPalette.of(context);
    return Semantics(
      toggled: selected,
      child: TextButton.icon(
        onPressed: () => onChanged(!selected),
        style: TextButton.styleFrom(
          backgroundColor: selected ? p.primary : Colors.transparent,
          foregroundColor: selected ? p.onPrimary : p.onSurfaceVariant,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        icon: Icon(icon, size: 17),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final p = AppPalette.of(context);
      final status = controller.loading
          ? 'Loading NOAH...'
          : controller.failed
          ? 'NOAH unavailable'
          : controller.centerInside == false
          ? 'Outside prepared coverage'
          : 'Modeled hazard ? Not live flooding';
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Material(
              color: p.surfaceContainerLowest,
              elevation: 3,
              shadowColor: Colors.black.withValues(alpha: .12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: p.outlineVariant.withValues(alpha: .5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Wrap(
                  spacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _toggle(
                      context,
                      'SafePaths',
                      Icons.route_outlined,
                      controller.safePaths,
                      controller.setSafePaths,
                    ),
                    _toggle(
                      context,
                      'NOAH',
                      Icons.layers_outlined,
                      controller.enabled,
                      controller.setEnabled,
                    ),
                    IconButton(
                      tooltip: tr(context, 'Road conditions'),
                      onPressed: onRoadLegend,
                      color: p.primary,
                      iconSize: 20,
                      icon: const Icon(Icons.info_outline),
                    ),
                  ],
                ),
              ),
            ),
            if (controller.enabled)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  color: p.surfaceContainerLowest,
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Tooltip(
                        message: tr(context, 'Legend and coverage'),
                        child: TextButton.icon(
                          onPressed: () => showNoahInfo(
                            context,
                            onViewCoverage: onViewCoverage,
                            controller: controller,
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: controller.failed
                                ? p.error
                                : p.primary,
                            minimumSize: const Size(48, 40),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          icon: controller.loading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  controller.failed
                                      ? Icons.error_outline
                                      : Icons.info_outline,
                                  size: 15,
                                ),
                          label: Text(
                            tr(context, status),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      if (controller.failed)
                        IconButton(
                          tooltip: tr(context, 'Retry'),
                          onPressed: controller.loading
                              ? null
                              : controller.retry,
                          color: p.primary,
                          iconSize: 18,
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class NoahAwarenessCard extends StatefulWidget {
  final Map<String, dynamic>? geometry;
  final Future<NoahDataset> Function()? loader;
  final VoidCallback? onViewMap;
  const NoahAwarenessCard({
    super.key,
    required this.geometry,
    this.loader,
    this.onViewMap,
  });
  @override
  State<NoahAwarenessCard> createState() => _NoahAwarenessCardState();
}

class _NoahAwarenessCardState extends State<NoahAwarenessCard> {
  late Future<NoahAssessment> _assessment;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NoahAwarenessCard old) {
    super.didUpdateWidget(old);
    if (!mapEquals(old.geometry, widget.geometry) ||
        old.loader != widget.loader)
      _load();
  }

  void _load() {
    final geometry = widget.geometry;
    _assessment = () async {
      final data = await (widget.loader ?? NoahRepository.load)();
      return compute((input) => input.$1.assess(input.$2), (data, geometry));
    }();
  }

  Widget _notice(
    BuildContext context,
    String text,
    IconData icon, {
    bool caution = false,
  }) {
    final p = AppPalette.of(context);
    final color = caution ? p.warning : p.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(context, text),
              style: TextStyle(fontSize: 12, height: 1.45, color: p.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hazard(BuildContext context, int level) {
    final p = AppPalette.of(context), color = noahLevelColor(level);
    return Container(
      key: ValueKey('noah-mapped-level-$level'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? .10 : .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.waves_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, noahLevelLabel(level)),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(context, 'Mapped on a portion of this road.'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lengths(BuildContext context, NoahAssessment assessment) {
    final p = AppPalette.of(context), data = assessment.lengthBreakdown!;
    String label(NoahLengthCategory c) => switch (c) {
      NoahLengthCategory.high => 'High hazard',
      NoahLengthCategory.medium => 'Medium hazard',
      NoahLengthCategory.low => 'Low hazard',
      NoahLengthCategory.noMappedHazard => 'No mapped hazard intersection',
      NoahLengthCategory.outsidePrepared => 'Outside prepared data',
    };
    int? level(NoahLengthCategory c) => switch (c) {
      NoahLengthCategory.high => 3,
      NoahLengthCategory.medium => 2,
      NoahLengthCategory.low => 1,
      _ => null,
    };
    Color color(NoahLengthCategory c) => level(c) != null
        ? noahLevelColor(level(c)!)
        : c == NoahLengthCategory.outsidePrepared
        ? p.primary.withValues(alpha: .45)
        : p.outlineVariant;
    String percent(NoahLengthCategory c) =>
        '${(data.tenthsPercent[c]! / 10).toStringAsFixed(1)}%';
    final visible = NoahLengthCategory.values
        .where(
          (c) =>
              data.meters[c]! > 0 ||
              level(c) != null && assessment.levels.contains(level(c)),
        )
        .toList();
    return Container(
      key: const ValueKey('noah-road-length-breakdown'),
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, 'Share of the whole mapped road'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: visible
                .map((c) => '${tr(context, label(c))}: ${percent(c)}')
                .join(', '),
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      for (final c in NoahLengthCategory.values)
                        if (data.tenthsPercent[c]! > 0)
                          Expanded(
                            flex: data.tenthsPercent[c]!,
                            child: ColoredBox(
                              color: color(c),
                              child: const SizedBox.expand(),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final c in visible)
            Padding(
              key: level(c) == null
                  ? ValueKey('noah-length-${c.name}')
                  : ValueKey('noah-mapped-level-${level(c)}'),
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color(c).withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      level(c) != null
                          ? Icons.waves_rounded
                          : c == NoahLengthCategory.outsidePrepared
                          ? Icons.crop_free
                          : Icons.remove_circle_outline,
                      size: 17,
                      color: level(c) != null ? color(c) : p.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      tr(context, label(c)),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: p.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    percent(c),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 20),
          Text(
            tr(context, 'Road-length shares, not a chance of flooding.'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: p.onSurfaceVariant,
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                tr(context, 'How these percentages are calculated'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.primary,
                ),
              ),
              iconColor: p.primary,
              collapsedIconColor: p.primary,
              children: [
                Text(
                  tr(
                    context,
                    'SafePaths calculates these percentages from the whole unique mapped road length and NOAH polygons, using the 5-year rainfall scenario. They are not percentages published directly by NOAH.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: p.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    context,
                    'Where polygons overlap, a road portion is counted once under the highest mapped class. Repeated road segments are counted once. Point-only boundary contacts have zero length.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: p.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    context,
                    'No mapped hazard intersection means no polygon overlaps that length in our dataset. It does not establish safety or full study coverage. Outside prepared data means the portion is beyond our cropped dataset.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: p.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    context,
                    'Shares are rounded to 0.1% and total 100.0%. Very small intersections may round to 0.0%.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.outlineVariant.withValues(alpha: .6)),
      ),
      child: FutureBuilder<NoahAssessment>(
        future: _assessment,
        builder: (context, snapshot) {
          // FutureBuilder retains old data during a future change. Never show a
          // previous road's hazard classes while assessing a newly selected road.
          final complete = snapshot.connectionState == ConnectionState.done;
          final failed = complete && snapshot.hasError;
          final a = complete ? snapshot.data : null;
          final levels = a?.levels.toList()?..sort((a, b) => b.compareTo(a));
          final summary = failed
              ? 'NOAH information could not load.'
              : a == null
              ? 'Checking mapped hazard...'
              : !a.available
              ? 'NOAH information unavailable for this road.'
              : a.levels.isEmpty
              ? 'No mapped hazard intersects this road in the prepared dataset.'
              : 'Portions of this road intersect mapped flood-hazard zones.';
          return ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.layers_outlined, color: p.primary, size: 22),
            ),
            title: Text(
              tr(context, 'NOAH flood awareness'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: p.primary,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr(context, '5-year scenario · Not live flooding'),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: p.onSurfaceVariant,
                ),
              ),
            ),
            iconColor: p.primary,
            collapsedIconColor: p.primary,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(context, 'Mapped hazard along this road'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (levels != null && levels.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, summary),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                ),
                if (a?.lengthBreakdown == null)
                  for (final level in levels) _hazard(context, level),
              ] else
                _notice(
                  context,
                  summary,
                  failed
                      ? Icons.cloud_off_outlined
                      : a == null
                      ? Icons.hourglass_top_rounded
                      : Icons.location_searching,
                  caution: failed,
                ),
              if (a?.lengthBreakdown != null) _lengths(context, a!),
              if (complete && !failed && a?.lengthBreakdown == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr(
                      context,
                      'Unable to calculate road-length percentages from the available geometry.',
                    ),
                    style: TextStyle(fontSize: 12, color: p.onSurfaceVariant),
                  ),
                ),
              if (a?.partial == true)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _notice(
                    context,
                    'Part of this road is outside the prepared dataset. The remaining section is unassessed.',
                    Icons.crop_free,
                    caution: true,
                  ),
                ),
              const SizedBox(height: 14),
              _notice(
                context,
                'This is modeled hazard, not current flooding. Check the latest barangay road update before travel.',
                Icons.verified_user_outlined,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(
                    context,
                    'Unshaded areas are not proven safe. NOAH does not change report reviews or navigation decisions.',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ),
              if (failed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(_load),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(tr(context, 'Retry')),
                  ),
                ),
              if (widget.onViewMap != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onViewMap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.primary,
                        backgroundColor: p.primary.withValues(alpha: .04),
                        minimumSize: const Size(48, 48),
                        side: BorderSide(
                          color: p.primary.withValues(alpha: .35),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.map_outlined, size: 20),
                      label: Text(tr(context, 'View NOAH on map')),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: p.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  title: Text(
                    tr(context, 'Source and limitations'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                    ),
                  ),
                  subtitle: Text(
                    'Project NOAH · BetterGov.PH',
                    style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                  ),
                  iconColor: p.primary,
                  collapsedIconColor: p.onSurfaceVariant,
                  children: [
                    Text(
                      tr(context, _disclaimer),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: p.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        'Source: Project NOAH, via the BetterGov.PH mirror. Original model date unavailable.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: p.onSurfaceVariant,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showNoahInfo(context),
                      icon: const Icon(Icons.info_outline, size: 17),
                      label: Text(tr(context, 'About this data')),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
