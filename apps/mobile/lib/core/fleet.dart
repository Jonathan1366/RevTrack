import 'dart:convert';
import 'package:http/http.dart' as http;

class Vehicle {
  const Vehicle({
    required this.id,
    required this.plate,
    required this.name,
    required this.driver,
    required this.status,
    required this.ev,
    required this.energy,
    required this.speed,
    required this.location,
    required this.lat,
    required this.lng,
    required this.range,
    required this.distance,
    this.rating = 4.9,
    this.fuelType = 'ice',
    this.lastSeenAt,
  });
  final String id, plate, name, driver, status, location;
  final bool ev;
  final int? energy, speed, range;
  final double lat, lng;
  final double? distance, rating;
  final String fuelType;
  final DateTime? lastSeenAt;
  String get powertrain => ev ? "ev" : fuelType;
  String get energyLabel => switch (powertrain) {
    "ev" => "ELECTRIC",
    "ice" => "BENSIN",
    "diesel" => "DIESEL",
    _ => "BELUM DIKETAHUI",
  };
  String get statusLabel => switch (status) {
    'moving' => 'Berjalan',
    'idle' => 'Berhenti',
    'parked' => 'Parkir',
    'charging' => 'Mengisi daya',
    'offline' => 'Offline',
    _ => 'Belum diketahui',
  };
  factory Vehicle.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>;
    final driver = json['driver'] as Map<String, dynamic>?;
    final ev = json['powertrain'].toString().toLowerCase() == 'ev';
    return Vehicle(
      id: json['id'],
      plate: json['plate'],
      name: json['name'],
      driver: driver?['name'] ?? 'Belum ditugaskan',
      status: json['status'],
      ev: ev,
      energy: ((ev ? json['batteryPercent'] : json['fuelPercent']) as num?)
          ?.round(),
      speed: (json['speedKph'] as num?)?.round(),
      location: location['label'] ?? 'Lokasi perangkat',
      lat: (location['latitude'] as num).toDouble(),
      lng: (location['longitude'] as num).toDouble(),
      range: (json['rangeKm'] as num?)?.round(),
      distance: (json['tripTodayKm'] as num?)?.toDouble(),
      rating: (driver?['rating'] as num?)?.toDouble(),
      fuelType: json['powertrain']?.toString().toLowerCase() ?? 'unknown',
      lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
    );
  }
}

class FleetAlert {
  const FleetAlert({
    required this.id,
    required this.vehicleId,
    required this.title,
    required this.description,
    required this.severity,
    this.status = 'open',
  });
  final String id, vehicleId, title, description, severity, status;
  factory FleetAlert.fromJson(Map<String, dynamic> j) => FleetAlert(
    id: j['id'],
    vehicleId: j['vehicleId'],
    title: j['title'],
    description: j['description'],
    severity: j['severity'],
    status: j['status'] ?? 'open',
  );
}

const demoVehicles = <Vehicle>[
  Vehicle(
    id: 'veh-001',
    plate: 'B 1248 REV',
    name: 'Hyundai IONIQ 5',
    driver: 'Andi Pratama',
    status: 'moving',
    ev: true,
    energy: 78,
    speed: 42,
    location: 'Jl. Jenderal Sudirman, Jakarta',
    lat: -6.214,
    lng: 106.821,
    range: 312,
    distance: 86.4,
  ),
  Vehicle(
    id: 'veh-002',
    plate: 'B 2086 REV',
    name: 'Toyota Avanza',
    driver: 'Budi Santoso',
    status: 'moving',
    ev: false,
    energy: 64,
    speed: 36,
    location: 'Kuningan, Jakarta Selatan',
    lat: -6.227,
    lng: 106.832,
    range: 286,
    distance: 104.8,
    rating: 4.8,
  ),
  Vehicle(
    id: 'veh-003',
    plate: 'B 3019 REV',
    name: 'BYD Atto 3',
    driver: 'Citra Wulandari',
    status: 'idle',
    ev: true,
    energy: 26,
    speed: 0,
    location: 'Menteng, Jakarta Pusat',
    lat: -6.195,
    lng: 106.838,
    range: 96,
    distance: 128.6,
  ),
  Vehicle(
    id: 'veh-004',
    plate: 'B 4172 REV',
    name: 'Toyota Innova Zenix',
    driver: 'Dimas Saputra',
    status: 'moving',
    ev: false,
    energy: 83,
    speed: 48,
    location: 'Senayan, Jakarta Selatan',
    lat: -6.232,
    lng: 106.804,
    range: 418,
    distance: 62.1,
    rating: 4.7,
  ),
  Vehicle(
    id: 'veh-005',
    plate: 'B 5820 REV',
    name: 'Wuling Air ev',
    driver: 'Eka Putri',
    status: 'idle',
    ev: true,
    energy: 91,
    speed: 0,
    location: 'Setiabudi, Jakarta Selatan',
    lat: -6.213,
    lng: 106.84,
    range: 246,
    distance: 43.5,
  ),
  Vehicle(
    id: 'veh-006',
    plate: 'B 6931 REV',
    name: 'Mitsubishi Xpander',
    driver: 'Fajar Hidayat',
    status: 'offline',
    ev: false,
    energy: 42,
    speed: 0,
    location: 'Palmerah • posisi terakhir simulasi',
    lat: -6.205,
    lng: 106.79,
    range: 189,
    distance: 91.2,
    rating: 4.6,
  ),
];

const demoAlerts = <FleetAlert>[
  FleetAlert(
    id: 'alert-001',
    vehicleId: 'veh-006',
    title: 'Periksa koneksi tracker',
    description:
        'B 6931 REV • Tidak ada data baru pada skenario demo. Periksa daya dan jaringan sebelum mengambil tindakan.',
    severity: 'critical',
  ),
  FleetAlert(
    id: 'alert-002',
    vehicleId: 'veh-003',
    title: 'Rencanakan pengisian daya',
    description:
        'B 3019 REV • Baterai contoh 26%. Cocokkan jadwal berikutnya dengan waktu pengisian.',
    severity: 'warning',
  ),
  FleetAlert(
    id: 'alert-003',
    vehicleId: 'veh-002',
    title: 'Tinjau batas area operasional',
    description:
        'B 2086 REV • Contoh event geofence. Verifikasi lokasi, waktu, dan konteks perjalanan.',
    severity: 'warning',
  ),
];

class FleetSnapshot {
  const FleetSnapshot(this.vehicles, this.alerts);
  final List<Vehicle> vehicles;
  final List<FleetAlert> alerts;
}

class FleetApi {
  static const url = String.fromEnvironment('API_URL');
  static const token = String.fromEnvironment('DEMO_API_TOKEN');
  final http.Client? client;
  final String baseUrl, accessToken;
  const FleetApi({this.client, this.baseUrl = url, this.accessToken = token});
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (baseUrl.isEmpty || accessToken.isEmpty) {
      throw StateError('Hubungkan API untuk menjalankan operasi ini.');
    }
    final connection = client ?? http.Client();
    try {
      final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path');
      final headers = {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };
      final response =
          await (body == null
                  ? connection.get(uri, headers: headers)
                  : connection.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 8));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          json['error']?['message']?.toString() ??
              'Operasi gagal (${response.statusCode}).',
        );
      }
      if (json['mode'] != 'demo') {
        throw StateError('Workspace ini hanya menerima data demo.');
      }
      return json;
    } finally {
      if (client == null) connection.close();
    }
  }

  Future<FleetSnapshot> load() async {
    final results = await Future.wait([
      request('/v1/fleet'),
      request('/v1/alerts'),
    ]);
    return FleetSnapshot(
      (results[0]['vehicles'] as List).map((v) => Vehicle.fromJson(v)).toList(),
      (results[1]['alerts'] as List)
          .map((a) => FleetAlert.fromJson(a))
          .toList(),
    );
  }

  Future<String> csv() async {
    if (baseUrl.isEmpty || accessToken.isEmpty) {
      throw StateError('Hubungkan API terlebih dahulu.');
    }
    final connection = client ?? http.Client();
    try {
      final response = await connection
          .get(
            Uri.parse(
              '${baseUrl.replaceAll(RegExp(r'/$'), '')}/v1/reports/telemetry.csv',
            ),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').startsWith('text/csv')) {
        throw StateError('Ekspor belum tersedia. Coba lagi.');
      }
      return response.body;
    } finally {
      if (client == null) connection.close();
    }
  }

  Future<void> acknowledge(String id) async {
    await request('/v1/alerts/$id/acknowledge', body: {});
  }

  Future<void> assign(String vehicleId, String driverId) async {
    await request(
      '/v1/vehicles/$vehicleId/assignment',
      body: {'driverId': driverId},
    );
  }
}
