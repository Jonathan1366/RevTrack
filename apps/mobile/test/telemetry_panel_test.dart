import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revtrack/core/design.dart';
import 'package:revtrack/core/fleet.dart';
import 'package:revtrack/widgets/telemetry_panel.dart';

void main() {
  http.Response points(int speed) => http.Response(
    jsonEncode({
      'mode': 'demo',
      'points': [
        {
          'recordedAt': '2026-10-02T00:00:00Z',
          'speedKph': speed,
          'fuelPercent': 64,
        },
      ],
    }),
    200,
  );

  Widget panel(FleetApi api, Vehicle vehicle) => MaterialApp(
    theme: revTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: TelemetryPanel(
            vehicle: vehicle,
            api: api,
            onChanged: () {},
            pollInterval: Duration.zero,
          ),
        ),
      ),
    ),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a late response cannot replace the newly selected vehicle', (
    tester,
  ) async {
    phone(tester);
    final oldResponse = Completer<http.Response>();
    final api = FleetApi(
      baseUrl: 'https://demo.invalid',
      accessToken: 'test',
      client: MockClient((request) async {
        return request.url.path.contains('veh-001')
            ? oldResponse.future
            : points(13);
      }),
    );
    await tester.pumpWidget(panel(api, demoVehicles.first));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(panel(api, demoVehicles[1]));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('telemetry-readout'))).data,
      '13.0 km/jam',
    );
    oldResponse.complete(points(42));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('telemetry-readout'))).data,
      '13.0 km/jam',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('telemetry failure can be retried without fabricated readings', (
    tester,
  ) async {
    phone(tester);
    var requests = 0;
    final api = FleetApi(
      baseUrl: 'https://demo.invalid',
      accessToken: 'test',
      client: MockClient((request) async {
        requests++;
        return requests == 1
            ? http.Response('{"error":{"message":"unavailable"}}', 503)
            : points(36);
      }),
    );
    await tester.pumpWidget(panel(api, demoVehicles[1]));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('telemetry-readout')), findsNothing);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('telemetry-readout'))).data,
      '36.0 km/jam',
    );
    expect(tester.takeException(), isNull);
  });
}
