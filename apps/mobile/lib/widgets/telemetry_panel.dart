import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../core/design.dart';
import '../core/fleet.dart';
import 'operations.dart';

class TelemetryPanel extends StatefulWidget {
  const TelemetryPanel({
    super.key,
    required this.vehicle,
    required this.onChanged,
  });
  final Vehicle vehicle;
  final VoidCallback onChanged;
  @override
  State<TelemetryPanel> createState() => _TelemetryPanelState();
}

class _TelemetryPanelState extends State<TelemetryPanel> {
  List<Map<String, dynamic>> points = [];
  String? error;
  int? selected;
  bool speed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant TelemetryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle.id != widget.vehicle.id) {
      points = [];
      selected = null;
      load();
    } else if (oldWidget.vehicle.lastSeenAt != widget.vehicle.lastSeenAt) {
      load();
    }
  }

  Future<void> load() async {
    final vehicleId = widget.vehicle.id;
    try {
      final result = await const FleetApi().request(
        '/v1/vehicles/$vehicleId/telemetry',
      );
      if (mounted && vehicleId == widget.vehicle.id) {
        setState(() {
          points = List<Map<String, dynamic>>.from(result['points']);
          error = null;
          if (selected != null && selected! >= points.length) selected = null;
        });
      }
    } catch (e) {
      if (mounted && vehicleId == widget.vehicle.id) {
        setState(() => error = readableError(e));
      }
    }
  }

  Future<void> assign() async {
    try {
      final result = await const FleetApi().request('/v1/drivers');
      if (!mounted) return;
      final id = await showDialog<String>(
        context: context,
        builder: (context) => PointerInterceptor(
          child: SimpleDialog(
            title: const Text('Pilih pengemudi'),
            children: [
              for (final d in result['drivers'] as List)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, d['id']),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, color: green),
                      const SizedBox(width: 12),
                      Expanded(child: Text(d['name'])),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
      if (id == null || !mounted) return;
      await const FleetApi().assign(widget.vehicle.id, id);
      if (!mounted) return;
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Penugasan tersimpan. Perubahan tercatat di audit.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(readableError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = speed
        ? 'speedKph'
        : widget.vehicle.ev
        ? 'batteryPercent'
        : 'fuelPercent';
    final values = points.map((p) => (p[field] as num?)?.toDouble()).toList();
    final index = selected ?? (points.isEmpty ? 0 : points.length - 1);
    final value = points.isEmpty ? null : points[index][field];
    final stamp = points.isEmpty
        ? 'Belum ada sampel'
        : shortTime(points[index]['recordedAt']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                speed
                    ? 'Kecepatan GNSS'
                    : '${widget.vehicle.ev ? 'Energi baterai' : 'Level bahan bakar'} · %',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => speed = !speed),
              child: Text(
                speed ? 'Lihat energi' : 'Lihat kecepatan',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        Text(
          '${value == null ? '—' : (value as num).toStringAsFixed(1)}${speed ? ' km/jam' : '%'} · $stamp',
          style: const TextStyle(
            color: green,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        if (error != null)
          Text(error!, style: const TextStyle(color: red, fontSize: 11))
        else if (points.isEmpty)
          const SizedBox(
            height: 90,
            child: Center(
              child: Text(
                'Menunggu sampel telemetri…',
                style: TextStyle(color: muted),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => setState(
                () => selected =
                    ((details.localPosition.dx / c.maxWidth) *
                            (points.length - 1))
                        .round()
                        .clamp(0, points.length - 1),
              ),
              onHorizontalDragUpdate: (details) => setState(
                () => selected =
                    ((details.localPosition.dx / c.maxWidth) *
                            (points.length - 1))
                        .round()
                        .clamp(0, points.length - 1),
              ),
              child: SizedBox(
                height: 100,
                width: double.infinity,
                child: CustomPaint(
                  painter: TelemetryPainter(
                    values: values,
                    times: points
                        .map(
                          (p) =>
                              DateTime.tryParse(p['recordedAt']) ??
                              DateTime(2000),
                        )
                        .toList(),
                    selected: index,
                    maximum: speed ? 140 : 100,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Geser grafik untuk melihat sampel · data simulator/fixture dari server.',
          style: TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: assign,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
          label: const Text('Atur pengemudi'),
        ),
      ],
    );
  }
}

class TelemetryPainter extends CustomPainter {
  const TelemetryPainter({
    required this.values,
    required this.times,
    required this.selected,
    required this.maximum,
  });
  final List<double?> values;
  final List<DateTime> times;
  final int selected;
  final double maximum;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        Paint()..color = line,
      );
    }
    if (values.isEmpty) return;
    Offset point(int i) => Offset(
      values.length == 1
          ? size.width / 2
          : i * size.width / (values.length - 1),
      size.height -
          (values[i]!.clamp(0, maximum) / maximum) * (size.height - 8) -
          4,
    );
    final paint = Paint()
      ..color = green
      ..strokeWidth = 2.7
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < values.length; i++) {
      if (values[i] == null) continue;
      canvas.drawCircle(point(i), 2, paint);
      if (i > 0 &&
          values[i - 1] != null &&
          times[i].difference(times[i - 1]).inMinutes < 5) {
        canvas.drawLine(point(i - 1), point(i), paint);
      }
    }
    if (selected < values.length && values[selected] != null) {
      final p = point(selected);
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()..color = green.withValues(alpha: .2),
      );
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4, paint);
    }
  }

  @override
  bool shouldRepaint(TelemetryPainter old) =>
      old.values != values ||
      old.selected != selected ||
      old.maximum != maximum;
}
