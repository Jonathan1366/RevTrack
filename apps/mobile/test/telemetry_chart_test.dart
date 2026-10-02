import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revtrack/core/design.dart';
import 'package:revtrack/widgets/telemetry_chart.dart';

void main() {
  test(
    'chart uses elapsed time, keeps zero, and breaks on missing data or long gaps',
    () {
      final samples = telemetrySamples([
        {'recordedAt': '2026-10-02T00:06:00Z', 'speedKph': 140},
        {'recordedAt': '2026-10-02T00:00:10Z', 'speedKph': null},
        {'recordedAt': '2026-10-02T00:00:00Z', 'speedKph': 0},
        {'recordedAt': '2026-10-02T00:00:30Z', 'speedKph': 15},
        {'recordedAt': 'invalid', 'speedKph': 20},
        {'recordedAt': '2026-10-02T00:00:30Z', 'speedKph': 18},
      ], 'speedKph');
      expect(samples.length, 4);
      expect(telemetrySpots(samples), [
        const FlSpot(0, 0),
        FlSpot.nullSpot,
        const FlSpot(30, 18),
        FlSpot.nullSpot,
        const FlSpot(360, 140),
      ]);
    },
  );

  test('invalid readings do not become plausible telemetry', () {
    final samples = telemetrySamples([
      {'recordedAt': '2026-10-02T00:00:00Z', 'speedKph': -2},
      {'recordedAt': '2026-10-02T00:00:10Z', 'speedKph': double.infinity},
    ], 'speedKph');
    expect(samples.every((sample) => sample.value == null), isTrue);
  });

  testWidgets(
    'sample controls expose missing readings and work without motion',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: revTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: TelemetryChart(
                  samples: [
                    TelemetrySample(DateTime.utc(2026, 10, 2), 0),
                    TelemetrySample(DateTime.utc(2026, 10, 2, 0, 0, 10), null),
                    TelemetrySample(DateTime.utc(2026, 10, 2, 0, 0, 30), 42),
                  ],
                  unit: 'km/jam',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('telemetry-readout')))
            .data,
        '42.0 km/jam',
      );
      await tester.tap(find.byTooltip('Sampel sebelumnya'));
      await tester.pumpAndSettle();
      expect(find.text('Data tidak tersedia'), findsOneWidget);
      await tester.tap(find.byTooltip('Sampel sebelumnya'));
      await tester.pumpAndSettle();
      expect(find.text('0.0 km/jam'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
