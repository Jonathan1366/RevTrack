import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revtrack/core/fleet.dart';

void main() {
  test('unknown energy and parked diesel data stay distinct', () {
    final vehicle = Vehicle.fromJson({
      'id': 'heavy-1',
      'plate': 'HE 007',
      'name': 'Excavator',
      'status': 'parked',
      'powertrain': 'diesel',
      'location': {'latitude': -6.2, 'longitude': 106.8},
      'lastSeenAt': '2026-10-02T05:00:00Z',
    });
    expect(vehicle.energy, isNull);
    expect(vehicle.speed, isNull);
    expect(vehicle.distance, isNull);
    expect(vehicle.rating, isNull);
    expect(vehicle.powertrain, 'diesel');
    expect(vehicle.statusLabel, 'Parkir');
    expect(vehicle.driver, 'Belum ditugaskan');
    expect(vehicle.lastSeenAt!.isUtc, isTrue);
  });

  test('API mutations authenticate and surface assignment conflicts', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/vehicles/v1/assignment');
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer test-credential');
      expect(jsonDecode(request.body), {'driverId': 'd1'});
      return http.Response(
        jsonEncode({
          'error': {'message': 'Pengemudi sudah ditugaskan.'},
        }),
        409,
      );
    });
    addTearDown(client.close);
    final api = FleetApi(
      client: client,
      baseUrl: 'http://localhost:8080',
      accessToken: 'test-credential',
    );
    await expectLater(
      api.assign('v1', 'd1'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Pengemudi sudah ditugaskan.',
        ),
      ),
    );
  });

  test('non-demo responses are rejected by the demo workspace', () async {
    final client = MockClient(
      (_) async => http.Response('{"mode":"live"}', 200),
    );
    addTearDown(client.close);
    final api = FleetApi(
      client: client,
      baseUrl: 'http://localhost:8080',
      accessToken: 'test-credential',
    );
    await expectLater(api.request('/v1/fleet'), throwsStateError);
  });

  test(
    'CSV export requires correct response type and authentication',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/reports/telemetry.csv');
        expect(request.headers['Authorization'], 'Bearer test-credential');
        return http.Response(
          '<html>not a report</html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      addTearDown(client.close);
      final api = FleetApi(
        client: client,
        baseUrl: 'http://localhost:8080',
        accessToken: 'test-credential',
      );
      await expectLater(api.csv(), throwsStateError);
    },
  );
}
