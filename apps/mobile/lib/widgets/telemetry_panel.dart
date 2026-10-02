import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../core/design.dart';
import '../core/fleet.dart';
import 'operations.dart';
import 'telemetry_chart.dart';
import 'feedback.dart';

class TelemetryPanel extends StatefulWidget {
  const TelemetryPanel({
    super.key,
    required this.vehicle,
    required this.onChanged,
    this.api = const FleetApi(),
    this.pollInterval = const Duration(seconds: 5),
  });
  final Vehicle vehicle;
  final VoidCallback onChanged;
  final FleetApi api;
  final Duration pollInterval;
  @override
  State<TelemetryPanel> createState() => _TelemetryPanelState();
}

class _TelemetryPanelState extends State<TelemetryPanel> {
  List<Map<String, dynamic>> points = [];
  String? error;
  bool speed = true;
  bool loading = false, assigning = false;
  int windowMinutes = 15, generation = 0;
  Timer? poller;
  @override
  void initState() {
    super.initState();
    load();
    if (widget.pollInterval > Duration.zero) {
      poller = Timer.periodic(widget.pollInterval, (_) => load());
    }
  }

  @override
  void dispose() {
    poller?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TelemetryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle.id != widget.vehicle.id) {
      points = [];
      generation++;
      loading = false;
      error = null;
      load();
    } else if (oldWidget.vehicle.lastSeenAt != widget.vehicle.lastSeenAt) {
      load();
    }
  }

  Future<void> load() async {
    if (loading || !mounted) return;
    final vehicleId = widget.vehicle.id;
    final requestGeneration = generation;
    setState(() => loading = true);
    try {
      final result = await widget.api.request(
        '/v1/vehicles/$vehicleId/telemetry',
      );
      if (mounted && requestGeneration == generation) {
        setState(() {
          points = List<Map<String, dynamic>>.from(result['points']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted && requestGeneration == generation) {
        setState(() => error = readableError(e));
      }
    } finally {
      if (mounted && requestGeneration == generation) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> assign() async {
    if (assigning) return;
    final vehicleId = widget.vehicle.id;
    setState(() => assigning = true);
    try {
      final result = await widget.api.request('/v1/drivers');
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
      if (id == null || !mounted || vehicleId != widget.vehicle.id) return;
      await widget.api.assign(vehicleId, id);
      if (!mounted) return;
      widget.onChanged();
      showOutcome(context, 'Pengemudi berhasil ditugaskan.');
    } catch (e) {
      if (mounted) {
        showOutcome(context, readableError(e), failed: true);
      }
    } finally {
      if (mounted) setState(() => assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = speed
        ? 'speedKph'
        : widget.vehicle.ev
        ? 'batteryPercent'
        : 'fuelPercent';
    final samples = telemetrySamples(points, field);
    final cutoff = samples.isEmpty || windowMinutes == 0
        ? null
        : samples.last.time.subtract(Duration(minutes: windowMinutes));
    final visible = cutoff == null
        ? samples
        : samples.where((s) => !s.time.isBefore(cutoff)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Telemetri',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (loading && points.isNotEmpty)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const SizedBox(width: 8),
            DropdownMenu<int>(
              width: 150,
              initialSelection: windowMinutes,
              selectOnly: true,
              textStyle: const TextStyle(fontSize: 12),
              inputDecorationTheme: const InputDecorationTheme(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              dropdownMenuEntries: const [
                DropdownMenuEntry(value: 5, label: '5 menit'),
                DropdownMenuEntry(value: 15, label: '15 menit'),
                DropdownMenuEntry(value: 0, label: 'Semua data'),
              ],
              onSelected: (value) {
                if (value != null) setState(() => windowMinutes = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: true,
                label: Text('Kecepatan'),
                icon: Icon(Icons.speed_outlined, size: 18),
              ),
              ButtonSegment(
                value: false,
                label: Text(widget.vehicle.ev ? 'Baterai' : 'Bahan bakar'),
                icon: Icon(
                  widget.vehicle.ev
                      ? Icons.battery_5_bar_outlined
                      : Icons.local_gas_station_outlined,
                  size: 18,
                ),
              ),
            ],
            selected: {speed},
            onSelectionChanged: (value) => setState(() => speed = value.first),
          ),
        ),
        const SizedBox(height: 22),
        if (error != null)
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Telemetri belum bisa dimuat.',
                  style: TextStyle(color: muted),
                ),
              ),
              TextButton(onPressed: load, child: const Text('Coba lagi')),
            ],
          ),
        if (loading && points.isEmpty)
          const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (points.isNotEmpty || error == null)
          TelemetryChart(
            key: ValueKey(widget.vehicle.id),
            samples: visible,
            unit: speed ? 'km/jam' : '%',
          ),
        const SizedBox(height: 8),
        const Text(
          'Data simulasi · garis terputus saat pembacaan tidak tersedia.',
          style: TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 14),
        ActionFeedbackButton(
          label: 'Atur pengemudi',
          phase: assigning ? ActionPhase.busy : ActionPhase.ready,
          onPressed: assign,
        ),
      ],
    );
  }
}
