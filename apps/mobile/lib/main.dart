import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'widgets/operations.dart';
import 'widgets/copilot.dart';
import 'widgets/telemetry_panel.dart';
import 'widgets/map_experience.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'core/design.dart';
import 'core/fleet.dart';
import 'widgets/fleet_map.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  if (usesMapbox) mb.MapboxOptions.setAccessToken(mapboxToken);
  runApp(const RevTrackApp());
}

class RevTrackApp extends StatelessWidget {
  const RevTrackApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RevTrack · Fleet intelligence',
    debugShowCheckedModeBanner: false,
    theme: revTheme(),
    home: const FleetHome(),
  );
}

class FleetHome extends StatefulWidget {
  const FleetHome({super.key});
  @override
  State<FleetHome> createState() => _FleetHomeState();
}

class _FleetHomeState extends State<FleetHome> {
  int page = 0;
  String query = '', filter = 'Semua';
  List<Vehicle> vehicles = demoVehicles;
  List<FleetAlert> alerts = demoAlerts;
  Vehicle selected = demoVehicles.first;
  final acknowledged = <String>{};
  bool loading = false, fromApi = false;
  String? apiError;
  Timer? poller;
  final pendingAlerts = <String>{};
  static const pageNames = [
    'Ringkasan',
    'Armada',
    'Peringatan',
    'Rev AI',
    'Operasi',
  ];
  static const pageIcons = [
    Icons.space_dashboard_outlined,
    Icons.directions_car_outlined,
    Icons.notifications_none_rounded,
    Icons.auto_awesome_outlined,
    Icons.calendar_month_outlined,
  ];

  @override
  void initState() {
    super.initState();
    if (FleetApi.url.isNotEmpty) {
      refresh();
      poller = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    }
  }

  @override
  void dispose() {
    poller?.cancel();
    super.dispose();
  }

  Future<void> acknowledge(FleetAlert alert) async {
    if (pendingAlerts.contains(alert.id)) return;
    if (!fromApi) {
      setState(() => acknowledged.add(alert.id));
      return;
    }
    setState(() => pendingAlerts.add(alert.id));
    try {
      await const FleetApi().acknowledge(alert.id);
      await refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(readableError(e))));
      }
    } finally {
      if (mounted) setState(() => pendingAlerts.remove(alert.id));
    }
  }

  bool reviewed(FleetAlert alert) =>
      alert.status == 'acknowledged' || acknowledged.contains(alert.id);
  List<Vehicle> get filtered => vehicles.where((v) {
    final matches = '${v.plate} ${v.name} ${v.driver}'.toLowerCase().contains(
      query.toLowerCase(),
    );
    return matches &&
        (filter == 'Semua' ||
            (filter == 'EV' && v.ev) ||
            (filter == 'Bensin' && v.powertrain == 'ice') ||
            (filter == 'Diesel' && v.powertrain == 'diesel') ||
            v.statusLabel == filter);
  }).toList();
  int get openAlerts =>
      alerts.where((a) => a.status != 'acknowledged' && !reviewed(a)).length;
  Future<void> refresh() async {
    if (loading || !mounted) return;
    if (FleetApi.url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Data contoh statis. Hubungkan API_URL dan DEMO_API_TOKEN untuk demo API.',
          ),
        ),
      );
      return;
    }
    setState(() {
      loading = true;
      apiError = null;
    });
    try {
      final snapshot = await FleetApi().load();
      if (!mounted) return;
      setState(() {
        vehicles = snapshot.vehicles;
        alerts = snapshot.alerts;
        fromApi = true;
        if (vehicles.isNotEmpty) {
          selected = vehicles.firstWhere(
            (v) => v.id == selected.id,
            orElse: () => vehicles.first,
          );
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => apiError =
              'API tidak terhubung. Menampilkan ${fromApi ? 'snapshot demo terakhir' : 'data contoh lokal'}. Periksa URL, token, dan server.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void selectVehicle(Vehicle v, {bool detail = false}) {
    setState(() => selected = v);
    if (detail) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: canvasColor,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 660),
        builder: (context) => PointerInterceptor(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: VehicleDetail(
                vehicle: v,
                expanded: true,
                connected: fromApi,
                onChanged: refresh,
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1100;
      final compact = constraints.maxWidth < 650;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (desktop) sidebar(),
              Expanded(
                child: Column(
                  children: [
                    topbar(compact, desktop),
                    if (apiError != null)
                      Material(
                        color: const Color(0xFFFFF2E0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.cloud_off_outlined,
                                size: 17,
                                color: amber,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  apiError!,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              TextButton(
                                onPressed: loading ? null : refresh,
                                child: const Text('Coba lagi'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: ValueKey('page-$page'),
                        padding: EdgeInsets.all(compact ? 18 : 30),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1500),
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              child: switch (page) {
                                0 => dashboard(compact, desktop),
                                1 => fleetPage(compact),
                                2 => alertsPage(compact),
                                3 => CopilotPanel(
                                  vehicles: vehicles,
                                  alerts: alerts,
                                  onNavigate: (value) =>
                                      setState(() => page = value),
                                ),
                                _ => OperationsPage(
                                  vehicles: vehicles,
                                  connected: fromApi,
                                ),
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                height: 70,
                selectedIndex: page,
                backgroundColor: Colors.white,
                indicatorColor: mint,
                onDestinationSelected: (value) => setState(() => page = value),
                destinations: List.generate(
                  pageNames.length,
                  (i) => NavigationDestination(
                    icon: Icon(pageIcons[i]),
                    label: pageNames[i],
                  ),
                ),
              ),
      );
    },
  );

  Widget sidebar() => Container(
    width: 214,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Brand(),
        const SizedBox(height: 40),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Text(
            'WORKSPACE',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
        ),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: mint,
                child: Text(
                  'R',
                  style: TextStyle(
                    color: green,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rev Rental',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Jakarta operations',
                      style: TextStyle(fontSize: 9, color: muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.unfold_more_rounded, size: 16, color: muted),
            ],
          ),
        ),
        const SizedBox(height: 30),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Material(
              color: page == i ? mint : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => setState(() => page = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        pageIcons[i],
                        size: 20,
                        color: page == i ? green : muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          pageNames[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: page == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: page == i ? green : muted,
                          ),
                        ),
                      ),
                      if (i == 2 && openAlerts > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEEE8),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '$openAlerts',
                            style: const TextStyle(
                              color: red,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      if (i == 3)
                        const Icon(Icons.north_east, size: 12, color: green),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome, color: lime, size: 22),
              const SizedBox(height: 13),
              const Text(
                'Less busywork.\nMore possibilities.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Jelajahi asisten operasi\ndalam mode simulasi.',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: Color(0xFFA9C4BB),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () => setState(() => page = 3),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Kenali Rev AI',
                        style: TextStyle(
                          color: lime,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 15, color: lime),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 10),
        const Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFFF2E9DA),
              child: Text(
                'JF',
                style: TextStyle(
                  color: ink,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fleet administrator',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Demo workspace',
                    style: TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget topbar(bool compact, bool desktop) => Container(
    height: 73,
    padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 30),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (!desktop)
          const SizedBox(width: 132, child: Brand(small: true))
        else ...[
          const Icon(Icons.grid_view_rounded, size: 15, color: muted),
          const SizedBox(width: 10),
          const Text('Workspace', style: TextStyle(color: muted, fontSize: 11)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('/', style: TextStyle(color: line)),
          ),
          Text(
            pageNames[page],
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
        const Spacer(),
        Tag(
          'DEMO',
          color: amber,
          background: const Color(0xFFFFF3DC),
          icon: Icons.science_outlined,
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          Text(
            fromApi ? 'API · data simulasi' : 'Data contoh · tanpa IoT',
            style: const TextStyle(fontSize: 10, color: muted),
          ),
        ],
        const SizedBox(width: 10),
        IconButton(
          tooltip: 'Muat ulang data demo',
          onPressed: loading ? null : refresh,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 19),
        ),
      ],
    ),
  );

  Widget heading(
    String eyebrow,
    String title,
    String subtitle,
    bool compact, {
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: green,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                style: compact
                    ? Theme.of(context).textTheme.headlineMedium
                    : Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: muted, height: 1.6),
              ),
            ],
          ),
        ),
        if (!compact && trailing != null) ...[
          const SizedBox(width: 15),
          trailing,
        ],
      ],
    ),
  );

  Widget mobileDashboard() => Column(
    key: const ValueKey('mobile-dashboard'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REV RENTAL · JAKARTA',
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Armada Anda,\ndalam kendali.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Tinjau peringatan',
            onPressed: () => setState(() => page = 2),
            icon: Badge(
              label: Text('$openAlerts'),
              child: const Icon(Icons.notifications_outlined, size: 25),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          for (final item in [
            ('Unit', '${vehicles.length}', Icons.directions_car_outlined),
            (
              'Berjalan',
              '${vehicles.where((v) => v.status == 'moving').length}',
              Icons.route_outlined,
            ),
            ('Perhatian', '$openAlerts', Icons.radar_rounded),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Surface(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.$3, color: green, size: 18),
                      const SizedBox(height: 8),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$1,
                        style: const TextStyle(color: muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Surface(
        padding: const EdgeInsets.all(7),
        child: Column(
          children: [
            SizedBox(
              height: 290,
              child: FleetMap(
                vehicles: vehicles,
                selected: selected,
                onSelect: (v) => selectVehicle(v),
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 10),
                const Icon(Icons.location_on_outlined, size: 14, color: green),
                const SizedBox(width: 5),
                const Expanded(
                  child: Text(
                    'Posisi unit · data simulasi',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ),
                TextButton(
                  key: const ValueKey('open-map'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MapExperience(vehicles: vehicles, selected: selected),
                    ),
                  ),
                  child: const Text(
                    'Buka peta',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Surface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${selected.plate} · ${selected.driver}',
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ),
                Tag(selected.statusLabel),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${selected.energy == null ? '—' : '${selected.energy}%'} ${selected.ev ? 'baterai' : 'BBM'} · ${selected.speed ?? '—'} km/jam',
                    style: const TextStyle(
                      fontSize: 12,
                      color: green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => selectVehicle(selected, detail: true),
                  child: const Text(
                    'Detail unit →',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => page = 3),
        child: Surface(
          color: mint,
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: green),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mulai dengan langkah yang tepat.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Lihat prioritas workspace bersama Rev AI.',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: green),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Demo workspace · tanpa koneksi ke kendaraan fisik.',
        style: TextStyle(color: muted, fontSize: 10),
      ),
    ],
  );

  Widget dashboard(bool compact, bool desktop) => compact
      ? mobileDashboard()
      : Column(
          key: const ValueKey('dashboard'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading(
              'YOUR FLEET, CONNECTED.',
              'Semua bergerak. Anda memegang kendali.',
              'Satu ruang untuk armada, perjalanan, dan keputusan yang lebih baik.',
              compact,
              trailing: OutlinedButton.icon(
                onPressed: () => setState(() => page = 1),
                icon: const Icon(Icons.north_east, size: 15),
                label: const Text(
                  'Kelola armada',
                  style: TextStyle(fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  side: const BorderSide(color: line),
                  padding: const EdgeInsets.all(18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
            stats(compact),
            const SizedBox(height: 24),
            if (desktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: mapPanel()),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: fleetPanel()),
                ],
              )
            else ...[
              mapPanel(),
              const SizedBox(height: 18),
            ],
            const SizedBox(height: 22),
            if (desktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: VehicleDetail(
                      vehicle: selected,
                      connected: fromApi,
                      onChanged: refresh,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: aiCard()),
                ],
              )
            else ...[
              VehicleDetail(
                vehicle: selected,
                connected: fromApi,
                onChanged: refresh,
              ),
              const SizedBox(height: 18),
              fleetPanel(),
              const SizedBox(height: 18),
              aiCard(),
            ],
            const SizedBox(height: 24),
            const Text(
              'DEMO WORKSPACE  /  Semua posisi, perjalanan, energi, dan insight merupakan simulasi.',
              style: TextStyle(color: muted, fontSize: 9, letterSpacing: .4),
            ),
          ],
        );

  Widget stats(bool compact) {
    final statsData = [
      (
        'Total armada',
        vehicles.length.toString().padLeft(2, '0'),
        'Unit dalam workspace',
        Icons.directions_car_outlined,
        green,
      ),
      (
        'Sedang berjalan',
        vehicles
            .where((v) => v.status == 'moving')
            .length
            .toString()
            .padLeft(2, '0'),
        'Status pada data contoh',
        Icons.route_outlined,
        green,
      ),
      (
        'Perlu perhatian',
        openAlerts.toString().padLeft(2, '0'),
        'Peringatan belum ditinjau',
        Icons.radar_rounded,
        amber,
      ),
      (
        'Jarak hari ini',
        vehicles
            .fold<double>(0, (s, v) => s + (v.distance ?? 0))
            .toStringAsFixed(0),
        'km · perjalanan simulasi',
        Icons.show_chart_rounded,
        green,
      ),
    ];
    Widget card(int i) {
      final data = statsData[i];
      return Surface(
        padding: EdgeInsets.all(compact ? 15 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data.$1,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ),
                Icon(data.$4, size: 18, color: data.$5),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  data.$2,
                  style: const TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 48,
                  height: 24,
                  alignment: Alignment.bottomCenter,
                  child: CustomPaint(
                    size: const Size(48, 24),
                    painter: MiniTrend(color: data.$5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(data.$3, style: const TextStyle(fontSize: 9, color: muted)),
          ],
        ),
      );
    }

    return compact
        ? Column(
            children: [
              Row(
                children: [
                  Expanded(child: card(0)),
                  const SizedBox(width: 12),
                  Expanded(child: card(1)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: card(2)),
                  const SizedBox(width: 12),
                  Expanded(child: card(3)),
                ],
              ),
            ],
          )
        : Row(
            children: List.generate(
              7,
              (i) => i.isOdd
                  ? const SizedBox(width: 16)
                  : Expanded(child: card(i ~/ 2)),
            ),
          );
  }

  Widget mapPanel() => Surface(
    padding: const EdgeInsets.all(8),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 17),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Peta operasional',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Jakarta & sekitarnya',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              Tag(
                '${vehicles.length} titik contoh',
                icon: Icons.location_on_outlined,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('open-map'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    MapExperience(vehicles: vehicles, selected: selected),
              ),
            ),
            icon: const Icon(Icons.open_in_full, size: 16),
            label: const Text('Jelajahi peta', style: TextStyle(fontSize: 11)),
          ),
        ),
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 650 ? 310 : 360,
          child: FleetMap(
            vehicles: vehicles,
            selected: selected,
            onSelect: (v) => selectVehicle(v),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 13, 14, 7),
          child: Row(
            children: [
              LegendDot('Berjalan', green),
              SizedBox(width: 15),
              LegendDot('Berhenti', amber),
              SizedBox(width: 15),
              LegendDot('Offline', muted),
              Spacer(),
              Icon(Icons.touch_app_outlined, size: 14, color: muted),
              SizedBox(width: 4),
              Text('Pilih unit', style: TextStyle(fontSize: 9, color: muted)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget fleetPanel() => Surface(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Armada Anda',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            Text(
              '${vehicles.length} unit',
              style: const TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 16),
        searchField(),
        const SizedBox(height: 14),
        filters(),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(25),
            child: Text(
              'Tidak ada unit yang cocok. Coba pencarian lain.',
              style: TextStyle(color: muted),
            ),
          ),
        for (final v in filtered.take(4)) vehicleRow(v),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => setState(() => page = 1),
            child: const Text(
              'Lihat seluruh armada  →',
              style: TextStyle(
                color: green,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget searchField() => TextField(
    key: const ValueKey('fleet-search'),
    onChanged: (value) => setState(() => query = value),
    decoration: const InputDecoration(
      hintText: 'Cari unit, plat, atau pengemudi',
      prefixIcon: Icon(Icons.search_rounded, size: 18, color: muted),
    ),
  );
  Widget filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children:
          [
                'Semua',
                'EV',
                'Bensin',
                if (vehicles.any((v) => v.powertrain == 'diesel')) 'Diesel',
                'Offline',
              ]
              .map(
                (label) => Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 10)),
                    selected: filter == label,
                    showCheckmark: false,
                    selectedColor: mint,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: filter == label ? mint : line),
                    labelStyle: TextStyle(
                      color: filter == label ? green : muted,
                      fontWeight: FontWeight.w600,
                    ),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => filter = label),
                  ),
                ),
              )
              .toList(),
    ),
  );

  Widget vehicleRow(Vehicle v) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: ValueKey('vehicle-${v.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => selectVehicle(v, detail: true),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
        ),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: v.ev ? mint : canvasColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                v.ev
                    ? Icons.electric_car_rounded
                    : Icons.directions_car_rounded,
                color: v.ev ? green : muted,
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.plate,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    v.name,
                    style: const TextStyle(fontSize: 10, color: muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  v.statusLabel,
                  style: TextStyle(
                    fontSize: 9,
                    color: statusColor(v.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      v.ev
                          ? Icons.battery_5_bar_rounded
                          : Icons.local_gas_station_outlined,
                      size: 12,
                      color: muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      v.energy == null ? '—' : '${v.energy}%',
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 5),
            const Icon(Icons.chevron_right_rounded, size: 17, color: muted),
          ],
        ),
      ),
    ),
  );

  Widget fleetPage(bool compact) => Column(
    key: const ValueKey('fleet-page'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'FLEET DIRECTORY',
        'Kenali setiap unit.',
        'Cari armada dan buka detail energi, pengemudi, serta aktivitasnya.',
        compact,
      ),
      Surface(
        child: Column(
          children: [
            searchField(),
            const SizedBox(height: 16),
            filters(),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(35),
                child: Text('Tidak ada unit yang cocok. Coba pencarian lain.'),
              ),
            for (final v in filtered) vehicleRow(v),
          ],
        ),
      ),
    ],
  );

  Widget alertsPage(bool compact) => Column(
    key: const ValueKey('alerts-page'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'ATTENTION CENTER',
        'Lebih cepat tahu. Lebih tepat bertindak.',
        '$openAlerts peringatan perlu ditinjau. Seluruh event di halaman ini adalah simulasi.',
        compact,
      ),
      const Surface(
        color: mint,
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined, color: green),
            SizedBox(width: 13),
            Expanded(
              child: Text(
                'Tinjau bukti dan hubungi tim lapangan sebelum mengambil tindakan. Dalam mode API, keputusan tersimpan pada server dan audit.',
                style: TextStyle(fontSize: 12, color: green),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      for (final a in alerts)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1E7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        a.severity == 'critical' || a.severity == 'high'
                            ? Icons.sensors_off_rounded
                            : Icons.warning_amber_rounded,
                        color: amber,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        a.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Tag(
                      'DEMO',
                      color: amber,
                      background: Color(0xFFFFF3DC),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  a.description,
                  style: const TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reviewed(a)
                            ? (fromApi
                                  ? '✓ Ditinjau · tersimpan'
                                  : '✓ Ditinjau · sesi lokal')
                            : 'Menunggu tinjauan',
                        style: TextStyle(
                          fontSize: 11,
                          color: reviewed(a) ? green : amber,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: reviewed(a) || pendingAlerts.contains(a.id)
                          ? null
                          : () => acknowledge(a),
                      child: const Text(
                        'Tandai ditinjau',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget aiCard() => Surface(
    color: const Color(0xFFEDF3FF),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_awesome, color: green, size: 20),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Selangkah lebih siap.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            Tag('SIMULASI', background: Colors.white, color: green),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Prioritas yang jelas.\nOperasi yang lebih tenang.',
          style: TextStyle(
            fontSize: 24,
            height: 1.25,
            letterSpacing: -.7,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 13),
        const Text(
          'Rev AI membantu menyusun langkah berikutnya, dengan kendali tetap di tangan Anda.',
          style: TextStyle(fontSize: 11, height: 1.8, color: muted),
        ),
        const SizedBox(height: 19),
        for (final title in [
          'Tinjau koneksi unit offline',
          'Rencanakan pengisian energi',
          'Verifikasi pengecualian perjalanan',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 15, color: green),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 9),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => page = 3),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Buka Rev AI', style: TextStyle(fontSize: 12)),
                SizedBox(width: 10),
                Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.small = false});
  final bool small;
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: small ? 28 : 32,
          height: small ? 28 : 32,
          decoration: BoxDecoration(
            color: green,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.near_me_rounded, color: lime, size: 21),
        ),
        const SizedBox(width: 9),
        Text(
          'revtrack',
          style: TextStyle(
            fontSize: small ? 21 : 25,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class LegendDot extends StatelessWidget {
  const LegendDot(this.label, this.color, {super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 9, color: muted)),
    ],
  );
}

class MiniTrend extends CustomPainter {
  const MiniTrend({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 19)
      ..lineTo(8, 14)
      ..lineTo(16, 17)
      ..lineTo(25, 8)
      ..lineTo(33, 11)
      ..lineTo(40, 5)
      ..lineTo(48, 1);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant MiniTrend oldDelegate) =>
      color != oldDelegate.color;
}

class VehicleDetail extends StatelessWidget {
  const VehicleDetail({
    super.key,
    required this.vehicle,
    this.expanded = false,
    this.connected = false,
    this.onChanged,
  });
  final Vehicle vehicle;
  final bool expanded, connected;
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'UNIT TERPILIH · DEMO',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: muted,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(v.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      v.plate,
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
              Tag(
                v.energyLabel,
                icon: v.ev ? Icons.bolt : Icons.local_gas_station_outlined,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: green),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  v.location,
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: detailMetric(
                  v.energy == null ? '—' : '${v.energy}%',
                  v.ev ? 'Baterai · contoh' : 'Bahan bakar · contoh',
                  v.ev
                      ? Icons.battery_charging_full
                      : Icons.local_gas_station_outlined,
                ),
              ),
              Expanded(
                child: detailMetric(
                  v.speed?.toString() ?? '—',
                  'km/jam · contoh',
                  Icons.speed_rounded,
                ),
              ),
              Expanded(
                child: detailMetric(
                  v.range == null ? '—' : '${v.range} km',
                  'Estimasi jarak · contoh',
                  Icons.route_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 21),
          const Divider(),
          const SizedBox(height: 15),
          if (connected)
            TelemetryPanel(vehicle: v, onChanged: onChanged ?? () {})
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    v.ev ? 'Profil energi' : 'Profil bahan bakar',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Text(
                  'Ilustrasi · bukan histori IoT',
                  style: TextStyle(fontSize: 9, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 80,
              width: double.infinity,
              child: CustomPaint(painter: EnergyPainter(ev: v.ev)),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('06.00', style: TextStyle(color: muted, fontSize: 9)),
                Text('09.00', style: TextStyle(color: muted, fontSize: 9)),
                Text('12.00', style: TextStyle(color: muted, fontSize: 9)),
                Text('15.00', style: TextStyle(color: muted, fontSize: 9)),
                Text('18.00', style: TextStyle(color: muted, fontSize: 9)),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (v.lastSeenAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Laporan terakhir: ${shortTime(v.lastSeenAt!.toIso8601String())} · ${DateTime.now().difference(v.lastSeenAt!).inSeconds > 120 ? 'data lama' : 'baru diterima'}',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: canvasColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: mint,
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 20,
                    color: green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.driver,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Pengemudi · profil contoh',
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.star_rounded, color: amber, size: 15),
                const SizedBox(width: 4),
                Text(
                  v.rating?.toStringAsFixed(1) ?? '—',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (expanded && !connected) ...[
            const SizedBox(height: 24),
            const Text(
              'Linimasa perjalanan · ilustrasi',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            for (final stop in [
              ('08.00', 'Check-in pengemudi', 'Pool Jakarta'),
              ('09.20', 'Perjalanan dimulai', 'Pemeriksaan awal selesai'),
              ('10.45', v.statusLabel, v.location),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 50,
                      child: Text(
                        stop.$1,
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                    const Icon(
                      Icons.radio_button_checked_rounded,
                      size: 15,
                      color: green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.$2,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            stop.$3,
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'Tidak ada perintah ke kendaraan dari prototipe ini.',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget detailMetric(String value, String label, IconData icon) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: green),
      const SizedBox(height: 8),
      Text(
        value,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
        ),
      ),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 9, color: muted)),
    ],
  );
}

class EnergyPainter extends CustomPainter {
  const EnergyPainter({required this.ev});
  final bool ev;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(0, i * size.height / 2),
        Offset(size.width, i * size.height / 2),
        Paint()
          ..color = line
          ..strokeWidth = 1,
      );
    }
    final points = ev
        ? [1.0, .97, .96, .84, .84, .77, .76, .70, .68, .60, .60, .54]
        : [.68, .63, .61, .57, .56, .49, .95, .94, .85, .80, .77, .72];
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i * size.width / (points.length - 1);
      final y = size.height * (1 - points[i] * .75);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [green.withValues(alpha: .15), green.withValues(alpha: .005)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant EnergyPainter oldDelegate) =>
      oldDelegate.ev != ev;
}

String wibTimestamp(DateTime time) {
  final t = time.toUtc().add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}.${two(t.minute)} WIB';
}
