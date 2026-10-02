import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/design.dart';
import 'operations.dart' show shortTime;

class TelemetrySample {
  const TelemetrySample(this.time, this.value);
  final DateTime time;
  final double? value;
}

/// Missing readings and interruptions remain visible instead of becoming zeroes.
List<TelemetrySample> telemetrySamples(
  List<Map<String, dynamic>> points,
  String field,
) {
  final byTime = <DateTime, double?>{};
  for (final point in points) {
    final time = DateTime.tryParse('${point['recordedAt'] ?? ''}');
    if (time == null) continue;
    final value = point[field];
    byTime[time] = value is num && value.toDouble().isFinite && value >= 0
        ? value.toDouble()
        : null;
  }
  final times = byTime.keys.toList()..sort();
  return [for (final time in times) TelemetrySample(time, byTime[time])];
}

List<FlSpot> telemetrySpots(List<TelemetrySample> samples) {
  if (samples.isEmpty) return [];
  final result = <FlSpot>[];
  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i];
    if (i > 0 &&
        sample.time.difference(samples[i - 1].time) >=
            const Duration(minutes: 5)) {
      result.add(FlSpot.nullSpot);
    }
    result.add(
      sample.value == null
          ? FlSpot.nullSpot
          : FlSpot(
              sample.time.difference(samples.first.time).inMilliseconds / 1000,
              sample.value!,
            ),
    );
  }
  return result;
}

class TelemetryChart extends StatefulWidget {
  const TelemetryChart({super.key, required this.samples, required this.unit});
  final List<TelemetrySample> samples;
  final String unit;
  @override
  State<TelemetryChart> createState() => _TelemetryChartState();
}

class _TelemetryChartState extends State<TelemetryChart> {
  DateTime? selectedTime;

  @override
  void didUpdateWidget(covariant TelemetryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unit != widget.unit) selectedTime = null;
  }

  @override
  Widget build(BuildContext context) {
    final samples = widget.samples;
    if (samples.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'Belum ada telemetri untuk kendaraan ini.',
            style: TextStyle(color: muted),
          ),
        ),
      );
    }
    final found = samples.indexWhere((sample) => sample.time == selectedTime);
    final index = found < 0 ? samples.length - 1 : found;
    final sample = samples[index];
    final lastX =
        samples.last.time.difference(samples.first.time).inMilliseconds / 1000;
    final maxX = math.max(1.0, lastX);
    final valid = samples.where((s) => s.value != null).map((s) => s.value!);
    final peak = valid.fold<double>(0, math.max);
    final readings = valid.toList();
    final average = readings.isEmpty
        ? null
        : readings.reduce((a, b) => a + b) / readings.length;
    final maxY = widget.unit == '%'
        ? math.max(100.0, peak)
        : math.max(50.0, (peak / 25).ceil() * 25.0);
    final readout = sample.value == null
        ? 'Data tidak tersedia'
        : '${sample.value!.toStringAsFixed(1)} ${widget.unit}';
    final start = samples.first.time;
    String timeLabel(double x) {
      final date = start
          .add(Duration(milliseconds: (x * 1000).round()))
          .toLocal();
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          label: '$readout, ${shortTime(sample.time.toIso8601String())}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                readout,
                key: const ValueKey('telemetry-readout'),
                style: numericStyle.copyWith(
                  fontSize: 26,
                  color: ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                shortTime(sample.time.toIso8601String()),
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (valid.isEmpty)
          const SizedBox(
            height: 160,
            child: Center(child: Text('Tidak ada pembacaan pada rentang ini.')),
          )
        else
          SizedBox(
            height: 170,
            child: LineChart(
              duration: Duration.zero,
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: 0,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: line,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          '${value.round()}',
                          style: const TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: maxX / 3,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData(
                          enabled: true,
                          axisPosition: meta.axisPosition,
                          parentAxisSize: meta.parentAxisSize,
                          distanceFromEdge: 0,
                        ),
                        child: Text(
                          timeLabel(value),
                          style: const TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: telemetrySpots(samples),
                    isCurved: false,
                    color: green,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: samples.length < 3),
                    belowBarData: BarAreaData(
                      show: true,
                      color: mint.withValues(alpha: .6),
                    ),
                  ),
                ],
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: sample.time.difference(start).inMilliseconds / 1000,
                      color: green.withValues(alpha: .3),
                      strokeWidth: 1,
                      dashArray: [3, 3],
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  touchCallback: (event, response) {
                    final spots = response?.lineBarSpots;
                    if (!event.isInterestedForInteractions ||
                        spots == null ||
                        spots.isEmpty) {
                      return;
                    }
                    final x = spots.first.x;
                    final nearest = samples.reduce(
                      (a, b) =>
                          (a.time.difference(start).inMilliseconds / 1000 - x)
                                  .abs() <
                              (b.time.difference(start).inMilliseconds / 1000 -
                                      x)
                                  .abs()
                          ? a
                          : b,
                    );
                    if (selectedTime != nearest.time) {
                      setState(() => selectedTime = nearest.time);
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => ink,
                    getTooltipItems: (spots) => spots
                        .map(
                          (s) => LineTooltipItem(
                            '${s.y.toStringAsFixed(1)} ${widget.unit}\n${timeLabel(s.x)}',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Sentuh grafik untuk melihat nilainya.',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ),
            IconButton(
              tooltip: 'Sampel sebelumnya',
              onPressed: index > 0
                  ? () => setState(() => selectedTime = samples[index - 1].time)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Sampel berikutnya',
              onPressed: index < samples.length - 1
                  ? () => setState(() => selectedTime = samples[index + 1].time)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: canvasColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      'Rata-rata sampel',
                      average == null
                          ? '—'
                          : '${average.toStringAsFixed(1)} ${widget.unit}',
                    ),
                  ),
                  Expanded(
                    child: _stat(
                      'Tertinggi',
                      readings.isEmpty
                          ? '—'
                          : '${peak.toStringAsFixed(1)} ${widget.unit}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: readings.length / samples.length,
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: line,
                color: success,
              ),
              const SizedBox(height: 8),
              Text(
                '${readings.length} dari ${samples.length} sampel memiliki pembacaan.',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: muted)),
      const SizedBox(height: 4),
      Text(
        value,
        style: numericStyle.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
    ],
  );
}
