import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import '../core/design.dart';
import '../core/fleet.dart';
import 'web_map_stub.dart'
    if (dart.library.js_interop) 'web_map.dart'
    as webmap;

const mapboxToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
const mapboxStyle = String.fromEnvironment(
  'MAPBOX_STYLE_URI',
  defaultValue: 'mapbox://styles/mapbox/standard',
);
bool get supportsNativeMap =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
bool get usesMapbox => supportsNativeMap && mapboxToken.startsWith('pk.');
bool get usesWebMap => kIsWeb && mapboxToken.startsWith('pk.');

class FleetMap extends StatelessWidget {
  const FleetMap({
    super.key,
    required this.vehicles,
    required this.selected,
    required this.onSelect,
    this.styleUri = mapboxStyle,
    this.pitch = 36,
    this.route = const [],
    this.destination,
    this.focusSerial = 0,
    this.showLabel = true,
    this.traffic = false,
  });
  final List<Vehicle> vehicles;
  final Vehicle selected;
  final ValueChanged<Vehicle> onSelect;
  final String styleUri;
  final double pitch;
  final List<List<double>> route;
  final List<double>? destination;
  final int focusSerial;
  final bool showLabel, traffic;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(17),
    child: Stack(
      children: [
        Positioned.fill(
          child: usesMapbox
              ? NativeFleetMap(
                  key: ValueKey(styleUri),
                  styleUri: styleUri,
                  pitch: pitch,
                  route: route,
                  destination: destination,
                  focusSerial: focusSerial,
                  traffic: traffic,
                  vehicles: vehicles,
                  selected: selected,
                  onSelect: onSelect,
                )
              : usesWebMap
              ? webmap.buildWebMap(
                  vehicles: vehicles,
                  selected: selected,
                  onSelect: onSelect,
                  token: mapboxToken,
                  style: styleUri,
                  pitch: pitch,
                  route: route,
                  destination: destination,
                  focusSerial: focusSerial,
                  traffic: traffic,
                )
              : SchematicMap(
                  vehicles: vehicles,
                  selected: selected,
                  onSelect: onSelect,
                ),
        ),
        if (showLabel)
          Positioned(
            top: 17,
            left: 17,
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x0B000000), blurRadius: 12),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.layers_outlined, size: 17, color: green),
                  const SizedBox(width: 9),
                  Text(
                    (usesMapbox || usesWebMap)
                        ? 'Mapbox · telemetri DEMO'
                        : 'Peta skematik · DEMO',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!usesMapbox && !usesWebMap)
          Positioned(
            bottom: 13,
            left: 13,
            right: 13,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                kIsWeb
                    ? 'Mapbox belum aktif. Konfigurasikan token publik pk. untuk peta asli.'
                    : 'Mapbox belum aktif. Atur MAPBOX_ACCESS_TOKEN dengan token publik pk.',
                style: const TextStyle(fontSize: 9, color: muted),
              ),
            ),
          ),
      ],
    ),
  );
}

class NativeFleetMap extends StatefulWidget {
  const NativeFleetMap({
    super.key,
    required this.vehicles,
    required this.selected,
    required this.onSelect,
    this.styleUri = mapboxStyle,
    this.pitch = 36,
    this.route = const [],
    this.destination,
    this.focusSerial = 0,
    this.showLabel = true,
    this.traffic = false,
  });
  final List<Vehicle> vehicles;
  final Vehicle selected;
  final ValueChanged<Vehicle> onSelect;
  final String styleUri;
  final double pitch;
  final List<List<double>> route;
  final List<double>? destination;
  final int focusSerial;
  final bool showLabel, traffic;
  @override
  State<NativeFleetMap> createState() => _NativeFleetMapState();
}

class _NativeFleetMapState extends State<NativeFleetMap> {
  mb.MapboxMap? map;
  mb.Cancelable? taps;
  bool failed = false;
  mb.CircleAnnotationManager? manager;
  final annotations = <String, mb.CircleAnnotation>{};
  bool syncing = false;
  bool syncAgain = false;
  mb.PolylineAnnotationManager? routeManager;
  mb.PolylineAnnotation? routeAnnotation;
  mb.CircleAnnotation? destinationAnnotation;
  @override
  void didUpdateWidget(covariant NativeFleetMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncAnnotations();
    if (oldWidget.route != widget.route ||
        oldWidget.destination != widget.destination) {
      syncRoute();
    }
    if (oldWidget.traffic != widget.traffic) syncTraffic();
    if (oldWidget.pitch != widget.pitch) {
      map?.setCamera(mb.CameraOptions(pitch: widget.pitch));
    }
    if (oldWidget.selected.id != widget.selected.id ||
        oldWidget.focusSerial != widget.focusSerial) {
      focus();
    }
  }

  Future<void> focus() async {
    final controller = map;
    if (controller == null || !mounted) return;
    final serial = widget.focusSerial;
    final duration = MediaQuery.disableAnimationsOf(context) ? 0 : 700;
    try {
      var camera = mb.CameraOptions(
        center: mb.Point(
          coordinates: mb.Position(widget.selected.lng, widget.selected.lat),
        ),
        zoom: 13,
        pitch: widget.pitch,
      );
      if (widget.route.length > 1) {
        camera = await controller.cameraForCoordinatesPadding(
          widget.route
              .map((p) => mb.Point(coordinates: mb.Position(p[0], p[1])))
              .toList(),
          mb.CameraOptions(pitch: widget.pitch),
          mb.MbxEdgeInsets(top: 140, left: 36, bottom: 240, right: 36),
          14,
          null,
        );
      }
      if (mounted && serial == widget.focusSerial) {
        await controller.flyTo(
          camera,
          mb.MapAnimationOptions(duration: duration),
        );
      }
    } catch (_) {
      // A camera transition can be cancelled when the user closes the map.
    }
  }

  Future<void> setup(mb.MapboxMap controller) async {
    map = controller;
    try {
      manager = await controller.annotations.createCircleAnnotationManager();
      if (!mounted) return;
      taps = manager!.tapEvents(
        onTap: (annotation) {
          for (final entry in annotations.entries) {
            if (entry.value.id == annotation.id) {
              for (final vehicle in widget.vehicles) {
                if (vehicle.id == entry.key && mounted) {
                  widget.onSelect(vehicle);
                }
              }
            }
          }
        },
      );
      routeManager = await controller.annotations
          .createPolylineAnnotationManager();
      await syncAnnotations();
      await syncRoute();
      await syncTraffic();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> syncAnnotations() async {
    if (manager == null || !mounted) return;
    if (syncing) {
      syncAgain = true;
      return;
    }
    syncing = true;
    try {
      do {
        syncAgain = false;
        final vehicles = List<Vehicle>.of(widget.vehicles);
        final ids = vehicles.map((v) => v.id).toSet();
        for (final id in annotations.keys.toList()) {
          if (!ids.contains(id)) await manager!.delete(annotations.remove(id)!);
        }
        for (final vehicle in vehicles) {
          if (!mounted) return;
          final geometry = mb.Point(
            coordinates: mb.Position(vehicle.lng, vehicle.lat),
          );
          final color = statusColor(vehicle.status).toARGB32();
          if (annotations.containsKey(vehicle.id)) {
            final annotation = annotations[vehicle.id]!;
            annotation.geometry = geometry;
            annotation.circleColor = color;
            annotation.circleRadius = widget.selected.id == vehicle.id
                ? 15
                : 11;
            await manager!.update(annotation);
          } else {
            annotations[vehicle.id] = await manager!.create(
              mb.CircleAnnotationOptions(
                geometry: geometry,
                circleRadius: 12,
                circleColor: color,
                circleStrokeColor: Colors.white.toARGB32(),
                circleStrokeWidth: 3,
              ),
            );
          }
        }
      } while (syncAgain && mounted);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      syncing = false;
    }
  }

  Future<void> syncRoute() async {
    if (routeManager == null || manager == null || !mounted) return;
    try {
      if (widget.route.length < 2) {
        if (routeAnnotation != null) {
          await routeManager!.delete(routeAnnotation!);
          routeAnnotation = null;
        }
      } else {
        final geometry = mb.LineString(
          coordinates: widget.route
              .map((p) => mb.Position(p[0], p[1]))
              .toList(),
        );
        if (routeAnnotation == null) {
          routeAnnotation = await routeManager!.create(
            mb.PolylineAnnotationOptions(
              geometry: geometry,
              lineColor: green.toARGB32(),
              lineWidth: 6,
              lineBorderColor: Colors.white.toARGB32(),
              lineBorderWidth: 2,
              lineJoin: mb.LineJoin.ROUND,
            ),
          );
        } else {
          routeAnnotation!.geometry = geometry;
          await routeManager!.update(routeAnnotation!);
        }
      }
      if (destinationAnnotation != null) {
        await manager!.delete(destinationAnnotation!);
        destinationAnnotation = null;
      }
      if (widget.destination != null) {
        destinationAnnotation = await manager!.create(
          mb.CircleAnnotationOptions(
            geometry: mb.Point(
              coordinates: mb.Position(
                widget.destination![0],
                widget.destination![1],
              ),
            ),
            circleColor: ink.toARGB32(),
            circleRadius: 10,
            circleStrokeColor: Colors.white.toARGB32(),
            circleStrokeWidth: 3,
          ),
        );
      }
    } catch (_) {
      /* Route overlay is optional; base map remains usable. */
    }
  }

  Future<void> syncTraffic() async {
    if (map == null || !mounted) return;
    try {
      final hasLayer = await map!.style.styleLayerExists('revtrack-traffic');
      if (!widget.traffic) {
        if (hasLayer) await map!.style.removeStyleLayer('revtrack-traffic');
        return;
      }
      if (!await map!.style.styleSourceExists('revtrack-traffic-source')) {
        await map!.style.addSource(
          mb.VectorSource(
            id: 'revtrack-traffic-source',
            url: 'mapbox://mapbox.mapbox-traffic-v1',
          ),
        );
      }
      if (!hasLayer) {
        await map!.style.addLayer(
          mb.LineLayer(
            id: 'revtrack-traffic',
            sourceId: 'revtrack-traffic-source',
            sourceLayer: 'traffic',
            lineWidth: 2,
            lineOpacity: .75,
          ),
        );
        await map!.style.setStyleLayerProperty(
          'revtrack-traffic',
          'line-color',
          [
            'match',
            ['get', 'congestion'],
            'low',
            '#51b88a',
            'moderate',
            '#f4b447',
            'heavy',
            '#ea7657',
            'severe',
            '#c7445b',
            '#9ab4ce',
          ],
        );
      }
    } catch (_) {
      /* Coverage and layer availability vary; route ETA is separate. */
    }
  }

  @override
  void dispose() {
    taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return const ColoredBox(
        color: mint,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Peta tidak dapat dimuat. Periksa koneksi, token, dan akses style Mapbox.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return mb.MapWidget(
      styleUri: widget.styleUri,
      viewport: mb.CameraViewportState(
        center: mb.Point(coordinates: mb.Position(106.821, -6.214)),
        zoom: 11.8,
        pitch: widget.pitch,
      ),
      onMapCreated: setup,
      onMapLoadErrorListener: (_) {
        if (mounted) setState(() => failed = true);
      },
    );
  }
}

class SchematicMap extends StatelessWidget {
  const SchematicMap({
    super.key,
    required this.vehicles,
    required this.selected,
    required this.onSelect,
  });
  final List<Vehicle> vehicles;
  final Vehicle selected;
  final ValueChanged<Vehicle> onSelect;
  Offset relative(Vehicle v) => Offset(
    ((v.lng - 106.775) / .08).clamp(.12, .88),
    ((-6.175 - v.lat) / .075).clamp(.16, .84),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: CityPainter())),
        ...[
          ('MENTENG', .66, .18),
          ('TANAH ABANG', .21, .30),
          ('SETIABUDI', .73, .59),
          ('SENAYAN', .32, .80),
          ('JAKARTA', .50, .39),
        ].map(
          (place) => Positioned(
            left: constraints.maxWidth * place.$2 - 35,
            top: constraints.maxHeight * place.$3,
            child: Text(
              place.$1,
              style: TextStyle(
                fontSize: place.$1 == 'JAKARTA' ? 18 : 9,
                fontWeight: FontWeight.w700,
                letterSpacing: place.$1 == 'JAKARTA' ? 4 : 1.3,
                color: const Color(0xFF9AA8A0),
              ),
            ),
          ),
        ),
        for (final v in vehicles)
          Positioned(
            left: constraints.maxWidth * relative(v).dx - 19,
            top: constraints.maxHeight * relative(v).dy - 20,
            child: Semantics(
              label: 'Pilih ${v.plate}',
              button: true,
              child: Tooltip(
                message: '${v.plate} · ${v.name}',
                child: GestureDetector(
                  key: ValueKey('map-${v.id}'),
                  onTap: () => onSelect(v),
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected.id == v.id ? green : Colors.white,
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: green.withValues(
                            alpha: selected.id == v.id ? .3 : .1,
                          ),
                          blurRadius: selected.id == v.id ? 0 : 12,
                          spreadRadius: selected.id == v.id ? 7 : 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      v.ev
                          ? Icons.electric_car_rounded
                          : Icons.directions_car_rounded,
                      size: 20,
                      color: selected.id == v.id
                          ? Colors.white
                          : statusColor(v.status),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class CityPainter extends CustomPainter {
  const CityPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEAF0E7),
    );
    final random = math.Random(24);
    for (var y = -1; y < 12; y++) {
      for (var x = -1; x < 13; x++) {
        final rect = Rect.fromLTWH(
          x * w / 11 + (y.isEven ? 12 : 0),
          y * h / 10,
          w / 11 - 7,
          h / 10 - 8,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          Paint()
            ..color = random.nextInt(7) == 1
                ? const Color(0xFFD5E5C6)
                : const Color(0xFFE0E7DD),
        );
      }
    }
    final river = Path()
      ..moveTo(w * .84, -20)
      ..cubicTo(w * .68, h * .2, w * .96, h * .36, w * .73, h * .56)
      ..cubicTo(w * .57, h * .73, w * .86, h * .84, w * .77, h + 20);
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFFCEE0E2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12,
    );
    final roads = [
      Path()
        ..moveTo(-20, h * .65)
        ..cubicTo(w * .32, h * .6, w * .6, h * .21, w + 20, h * .3),
      Path()
        ..moveTo(w * .46, -20)
        ..cubicTo(w * .39, h * .38, w * .60, h * .58, w * .34, h + 20),
      Path()
        ..moveTo(-20, h * .2)
        ..lineTo(w * .25, h * .32)
        ..lineTo(w * .8, h * .8)
        ..lineTo(w + 20, h * .76),
      Path()
        ..moveTo(w * .14, -20)
        ..lineTo(w * .18, h * .62)
        ..lineTo(w * .09, h + 20),
    ];
    for (final path in roads) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFD0DCCB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFCFDF9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9,
      );
    }
    final zone = Path()
      ..moveTo(w * .30, h * .16)
      ..lineTo(w * .72, h * .22)
      ..lineTo(w * .82, h * .66)
      ..lineTo(w * .42, h * .85)
      ..lineTo(w * .24, h * .48)
      ..close();
    canvas.drawPath(zone, Paint()..color = green.withValues(alpha: .035));
    for (final metric in zone.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 13) {
        canvas.drawPath(
          metric.extractPath(d, d + 6),
          Paint()
            ..color = green.withValues(alpha: .4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
    final route = Path()
      ..moveTo(w * .36, h * .75)
      ..lineTo(w * .46, h * .62)
      ..lineTo(w * .49, h * .51)
      ..lineTo(w * .575, h * .52);
    canvas.drawPath(
      route,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CityPainter oldDelegate) => false;
}
