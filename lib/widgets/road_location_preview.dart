import '../utils/geo_utils.dart';
import 'report_submission_preview.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/road_status.dart';
import '../services/road_location_preview.dart';
import '../theme/app_palette.dart';

class RoadLocationPreview extends StatefulWidget {
  final List<RoadStatus> roads;
  final GeoCoord? reportedPoint;
  final double height;
  final RoadPreviewCapture Function()? capture;
  const RoadLocationPreview({
    super.key,
    required this.roads,
    this.capture,
    this.reportedPoint,
    this.height = 180,
  });
  @override
  State<RoadLocationPreview> createState() => _RoadLocationPreviewState();
}

class _RoadLocationPreviewState extends State<RoadLocationPreview> {
  RoadPreviewCapture? _capture;
  Uint8List? _bytes;
  String? _identity;
  int _generation = 0;
  bool _failed = false;
  @override
  void dispose() {
    _generation++;
    unawaited(_capture?.cancel() ?? Future.value());
    super.dispose();
  }

  void _load(RoadPreviewRequest request) {
    final generation = ++_generation;
    unawaited(_capture?.cancel() ?? Future.value());
    _capture = null;
    _bytes = null;
    _failed = false;
    _identity = request.identity;
    if (!request.available) return;
    final capture = (widget.capture ?? MapboxRoadPreviewCapture.new)();
    _capture = capture;
    Future<Uint8List>.sync(() => capture.render(request)).then(
      (bytes) {
        if (mounted && generation == _generation)
          setState(() => _bytes = bytes);
      },
      onError: (Object e) {
        if (mounted && generation == _generation)
          setState(() => _failed = true);
      },
    );
  }

  Widget _unavailable(BuildContext context, RoadPreviewRequest request) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.map_outlined, color: p.onSurfaceVariant, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    context,
                    request.available
                        ? widget.reportedPoint != null
                              ? 'Map preview could not be loaded. Use the recorded coordinates or retry.'
                              : 'Map preview could not be loaded. You can still complete the check.'
                        : 'Map location is unavailable for the selected road.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: p.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (request.available)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _load(request)),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(tr(context, 'Retry map')),
              ),
            ),
        ],
      ),
    );
  }

  void _enlarge(
    BuildContext context,
    Uint8List bytes, {
    bool hasRoad = true,
  }) => showDialog<void>(
    context: context,
    builder: (context) => ReportPhotoViewer(
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              tr(
                context,
                widget.reportedPoint == null
                    ? 'Selected road location'
                    : 'Reported location',
              ),
            ),
            leading: IconButton(
              tooltip: tr(context, 'Close'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr(
                    context,
                    widget.reportedPoint == null
                        ? 'Blue highlights the selected road. Pinch to zoom.'
                        : hasRoad
                        ? 'Orange marks the reported point. Blue highlights the selected road. Pinch to zoom.'
                        : 'Orange marks the reported point. Pinch to zoom.',
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          Text(tr(context, 'Map preview could not be loaded.')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    {
      final request = RoadPreviewRequest(
        widget.roads,
        width: (MediaQuery.sizeOf(context).width - 72).clamp(160.0, 520.0),
        dark: p.isDark,
        reportedPoint: widget.reportedPoint,
        height: widget.height,
      );
      if (_identity != request.identity) _load(request);
      return SizedBox(
        width: request.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                context,
                widget.reportedPoint == null
                    ? 'Selected road location'
                    : 'Reported location',
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: p.primary,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: p.surfaceContainerLow,
                child: !request.available || _failed
                    ? _unavailable(context, request)
                    : _bytes == null
                    ? SizedBox(
                        height: request.height,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                tr(context, 'Loading road location...'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: p.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Semantics(
                        button: true,
                        label: tr(context, 'Enlarge map'),
                        child: InkWell(
                          onTap: () => _enlarge(
                            context,
                            _bytes!,
                            hasRoad: request.mappedRoadIds.isNotEmpty,
                          ),
                          child: Image.memory(
                            _bytes!,
                            height: request.height,
                            width: request.width,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                _unavailable(context, request),
                          ),
                        ),
                      ),
              ),
            ),
            if (_bytes != null)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    tr(
                      context,
                      widget.reportedPoint == null
                          ? 'Selected road in blue'
                          : request.mappedRoadIds.isEmpty
                          ? 'Orange: reported point.'
                          : 'Orange: reported point. Blue: selected road.',
                    ),
                    style: TextStyle(fontSize: 11, color: p.onSurfaceVariant),
                  ),
                  TextButton.icon(
                    onPressed: () => _enlarge(
                      context,
                      _bytes!,
                      hasRoad: request.mappedRoadIds.isNotEmpty,
                    ),
                    icon: const Icon(Icons.open_in_full, size: 16),
                    label: Text(tr(context, 'Enlarge map')),
                  ),
                ],
              ),
            if (request.mappedRoadIds.length < request.requestedCount &&
                request.available)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${tr(context, 'Roads shown on map')}: ${request.mappedRoadIds.length}/${request.requestedCount}',
                  style: TextStyle(fontSize: 12, color: p.warning),
                ),
              ),
          ],
        ),
      );
    }
  }
}
