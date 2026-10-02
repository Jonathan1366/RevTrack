import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../core/design.dart';
import '../core/fleet.dart';
import 'fleet_map.dart';
import 'glass_surface.dart';

/// Address/place search intentionally uses Geocoding v6. Mapbox Search Box's
/// documented POI geography does not include Indonesia. Results remain in memory.
/// https://docs.mapbox.com/api/search/geocoding/
/// https://docs.mapbox.com/api/search/search-box/#supported-geographies
class MapExperience extends StatefulWidget {
  const MapExperience({
    super.key,
    required this.vehicles,
    required this.selected,
  });
  final List<Vehicle> vehicles;
  final Vehicle selected;
  @override
  State<MapExperience> createState() => _MapExperienceState();
}

class MapPlace {
  const MapPlace(this.name, this.address, this.longitude, this.latitude);
  final String name, address;
  final double longitude, latitude;
  List<double> get coordinate => [longitude, latitude];
}

bool validMapCoordinate(List<dynamic> value) =>
    value.length >= 2 &&
    value[0] is num &&
    value[1] is num &&
    (value[0] as num).isFinite &&
    (value[1] as num).isFinite &&
    (value[0] as num).abs() <= 180 &&
    (value[1] as num).abs() <= 90;

class _MapExperienceState extends State<MapExperience> {
  final query = TextEditingController();
  final client = http.Client();
  Timer? debounce;
  Timer? fleetPoller;
  bool refreshingFleet = false;
  late List<Vehicle> vehicles = widget.vehicles;
  late Vehicle selected = widget.selected;
  List<MapPlace> results = [];
  List<List<double>> route = const [];
  MapPlace? destination;
  String? searchError, routeError;
  bool searching = false,
      routing = false,
      satellite = false,
      tilted = true,
      traffic = false;
  double? distanceM, durationS;
  int searchVersion = 0, routeVersion = 0, focusSerial = 0;
  static const savedPlaces = [
    MapPlace('Monas', 'Titik tujuan contoh · Jakarta Pusat', 106.8272, -6.1754),
    MapPlace(
      'Senayan',
      'Titik tujuan contoh · Jakarta Selatan',
      106.8025,
      -6.2256,
    ),
    MapPlace(
      'Kelapa Gading',
      'Titik tujuan contoh · Jakarta Utara',
      106.9050,
      -6.1575,
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (FleetApi.url.isNotEmpty && FleetApi.token.isNotEmpty) {
      fleetPoller = Timer.periodic(
        const Duration(seconds: 5),
        (_) => refreshFleet(),
      );
    }
  }

  Future<void> refreshFleet() async {
    if (refreshingFleet) return;
    refreshingFleet = true;
    try {
      final snapshot = await const FleetApi().load();
      if (!mounted) return;
      setState(() {
        vehicles = snapshot.vehicles;
        selected = vehicles.firstWhere(
          (v) => v.id == selected.id,
          orElse: () => selected,
        );
      });
    } catch (_) {
      // Preserve the last known fix; its timestamp remains visible to the user.
    } finally {
      refreshingFleet = false;
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    fleetPoller?.cancel();
    client.close();
    query.dispose();
    super.dispose();
  }

  void changed(String text) {
    debounce?.cancel();
    final version = ++searchVersion;
    if (text.trim().length < 3) {
      setState(() {
        results = [];
        searching = false;
        searchError = null;
      });
      return;
    }
    setState(() {
      searching = true;
      searchError = null;
    });
    debounce = Timer(
      const Duration(milliseconds: 500),
      () => search(text.trim(), version),
    );
  }

  Future<void> search(String text, int version) async {
    if (!mapboxToken.startsWith('pk.')) {
      if (mounted && version == searchVersion) {
        setState(() {
          searching = false;
          searchError = 'Pencarian memerlukan koneksi Mapbox yang aktif.';
        });
      }
      return;
    }
    try {
      final parameters = <String, String>{
        'q': text,
        'country': 'id',
        'language': 'id',
        'limit': '5',
        'types': 'address,street,place,locality,neighborhood,region',
        'access_token': mapboxToken,
      };
      if (validMapCoordinate([selected.lng, selected.lat])) {
        parameters['proximity'] = '${selected.lng},${selected.lat}';
      }
      final response = await client
          .get(
            Uri.https(
              'api.mapbox.com',
              '/search/geocode/v6/forward',
              parameters,
            ),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const FormatException('search unavailable');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final places = <MapPlace>[];
      for (final feature in (data['features'] as List? ?? [])) {
        if (feature is! Map) {
          continue;
        }
        final geometry = feature['geometry'];
        final coordinates = geometry is Map ? geometry['coordinates'] : null;
        if (coordinates is! List || !validMapCoordinate(coordinates)) {
          continue;
        }
        final properties = feature['properties'] as Map? ?? {};
        places.add(
          MapPlace(
            (properties['name'] ?? properties['name_preferred'] ?? 'Alamat')
                .toString(),
            (properties['full_address'] ??
                    properties['place_formatted'] ??
                    'Indonesia')
                .toString(),
            (coordinates[0] as num).toDouble(),
            (coordinates[1] as num).toDouble(),
          ),
        );
      }
      if (!mounted || version != searchVersion) {
        return;
      }
      setState(() {
        results = places;
        searching = false;
        searchError = places.isEmpty
            ? 'Alamat belum ditemukan. Coba nama jalan atau wilayah.'
            : null;
      });
    } catch (_) {
      if (mounted && version == searchVersion) {
        setState(() {
          searching = false;
          searchError =
              'Pencarian belum tersedia. Periksa koneksi atau coba lagi.';
        });
      }
    }
  }

  Future<void> choose(MapPlace place) async {
    FocusScope.of(context).unfocus();
    debounce?.cancel();
    ++searchVersion;
    query.text = place.name;
    setState(() {
      destination = place;
      results = [];
      searching = false;
      searchError = null;
    });
    await fetchRoute();
  }

  Future<void> fetchRoute() async {
    final target = destination;
    if (target == null) {
      return;
    }
    final version = ++routeVersion;
    final origin = selected;
    setState(() {
      route = const [];
      distanceM = null;
      durationS = null;
      routeError = null;
      routing = true;
    });
    if (!mapboxToken.startsWith('pk.') ||
        !validMapCoordinate([origin.lng, origin.lat]) ||
        !validMapCoordinate(target.coordinate)) {
      setState(() {
        routing = false;
        routeError =
            'Peta atau koordinat unit belum tersedia untuk menghitung rute.';
      });
      return;
    }
    try {
      // Directions is a preview. No GPS permission, navigation SDK, voice guidance,
      // vehicle dispatch or remote action is implied by requesting this route.
      final coordinates =
          '${origin.lng},${origin.lat};${target.longitude},${target.latitude}';
      final response = await client
          .get(
            Uri.https(
              'api.mapbox.com',
              '/directions/v5/mapbox/driving-traffic/$coordinates',
              {
                'geometries': 'geojson',
                'overview': 'full',
                'steps': 'false',
                'alternatives': 'false',
                'access_token': mapboxToken,
              },
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const FormatException('route unavailable');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final paths = data['routes'] as List? ?? [];
      if (data['code'] != 'Ok' || paths.isEmpty) {
        throw const FormatException('no route');
      }
      final path = paths.first as Map<String, dynamic>;
      final geometry = path['geometry'] as Map<String, dynamic>?;
      final points = geometry?['coordinates'] as List?;
      final distance = path['distance'], duration = path['duration'];
      if (geometry?['type'] != 'LineString' ||
          points == null ||
          points.length < 2 ||
          points.length > 30000 ||
          distance is! num ||
          duration is! num ||
          !distance.isFinite ||
          !duration.isFinite ||
          distance < 0 ||
          duration < 0) {
        throw const FormatException('invalid route');
      }
      final result = <List<double>>[];
      for (final point in points) {
        if (point is! List || !validMapCoordinate(point)) {
          throw const FormatException('invalid route coordinate');
        }
        result.add([
          (point[0] as num).toDouble(),
          (point[1] as num).toDouble(),
        ]);
      }
      if (!mounted || version != routeVersion) {
        return;
      }
      setState(() {
        route = result;
        distanceM = distance.toDouble();
        durationS = duration.toDouble();
        routing = false;
        focusSerial++;
      });
    } catch (_) {
      if (mounted && version == routeVersion) {
        setState(() {
          routing = false;
          routeError =
              'Rute belum dapat dihitung. Coba tujuan lain atau periksa koneksi.';
        });
      }
    }
  }

  void selectVehicle(Vehicle vehicle) {
    if (vehicle.id == selected.id) {
      return;
    }
    setState(() {
      selected = vehicle;
      focusSerial++;
    });
    if (destination != null) {
      fetchRoute();
    }
  }

  Widget panel(Widget child) => PointerInterceptor(
    child: GlassSurface(
      radius: 24,
      child: Material(color: Colors.transparent, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final minutes = durationS == null ? null : (durationS! / 60).ceil();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RevTrack Maps',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              'Jelajahi kota. Rencanakan perjalanan.',
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Fokus ke unit atau rute',
            onPressed: () => setState(() => focusSerial++),
            icon: const Icon(Icons.my_location_rounded, color: green),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 760;
          return Stack(
            children: [
              Positioned.fill(
                child: FleetMap(
                  vehicles: vehicles,
                  selected: selected,
                  onSelect: selectVehicle,
                  styleUri: satellite
                      ? 'mapbox://styles/mapbox/standard-satellite'
                      : mapboxStyle,
                  pitch: tilted ? 50 : 0,
                  route: route,
                  destination: destination?.coordinate,
                  focusSerial: focusSerial,
                  showLabel: false,
                  traffic: traffic,
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                right: wide ? null : 16,
                width: wide ? 390 : null,
                child: panel(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: query,
                        onChanged: changed,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (text) {
                          debounce?.cancel();
                          search(text.trim(), ++searchVersion);
                        },
                        decoration: InputDecoration(
                          fillColor: Colors.transparent,
                          hintText: 'Cari alamat atau wilayah',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: green,
                          ),
                          suffixIcon: searching
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : query.text.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Bersihkan pencarian',
                                  icon: const Icon(Icons.close, size: 19),
                                  onPressed: () {
                                    query.clear();
                                    changed('');
                                  },
                                )
                              : null,
                        ),
                      ),
                      if (results.isNotEmpty)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: box.maxHeight * .4,
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: results.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1, indent: 52),
                            itemBuilder: (context, index) {
                              final place = results[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.location_on_outlined,
                                  color: green,
                                ),
                                title: Text(
                                  place.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  place.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                onTap: () => choose(place),
                              );
                            },
                          ),
                        ),
                      if (searchError != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 13),
                          child: Text(
                            searchError!,
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (results.isEmpty && !keyboard)
                Positioned(
                  top: 84,
                  left: 16,
                  right: wide ? null : 16,
                  width: wide ? 420 : null,
                  child: PointerInterceptor(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Jalan'),
                            avatar: const Icon(Icons.map_outlined, size: 17),
                            selected: !satellite,
                            onSelected: (_) =>
                                setState(() => satellite = false),
                          ),
                          const SizedBox(width: 7),
                          ChoiceChip(
                            label: const Text('Satelit'),
                            avatar: const Icon(
                              Icons.satellite_alt_rounded,
                              size: 17,
                            ),
                            selected: satellite,
                            onSelected: (_) => setState(() => satellite = true),
                          ),
                          const SizedBox(width: 7),
                          FilterChip(
                            label: const Text('3D'),
                            avatar: const Icon(
                              Icons.view_in_ar_rounded,
                              size: 17,
                            ),
                            selected: tilted,
                            onSelected: (value) =>
                                setState(() => tilted = value),
                          ),
                          const SizedBox(width: 7),
                          FilterChip(
                            label: const Text('Lalu lintas'),
                            avatar: const Icon(
                              Icons.traffic_outlined,
                              size: 17,
                            ),
                            selected: traffic,
                            onSelected: (value) =>
                                setState(() => traffic = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!keyboard)
                Positioned(
                  left: 16,
                  right: wide ? null : 16,
                  width: wide ? 390 : null,
                  bottom: 48,
                  child: panel(
                    Padding(
                      padding: const EdgeInsets.all(17),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: mint,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  selected.ev
                                      ? Icons.electric_car_rounded
                                      : Icons.directions_car_rounded,
                                  color: green,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selected.plate,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '${selected.driver} · ${selected.statusLabel}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Ganti unit asal',
                                onSelected: (id) => selectVehicle(
                                  vehicles.firstWhere((v) => v.id == id),
                                ),
                                itemBuilder: (_) => vehicles
                                    .map(
                                      (v) => PopupMenuItem(
                                        value: v.id,
                                        child: Text(
                                          '${v.plate} · ${v.name}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                icon: const Icon(
                                  Icons.swap_horiz_rounded,
                                  color: green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (selected.lastSeenAt != null) ...[
                            Text(
                              'Fix terakhir ${selected.lastSeenAt!.toLocal().toString().substring(0, 19)}${DateTime.now().difference(selected.lastSeenAt!).inMinutes >= 5 ? ' · data lama' : ''}',
                              style: const TextStyle(fontSize: 9, color: muted),
                            ),
                            const SizedBox(height: 9),
                          ],
                          if (destination == null) ...[
                            const Text(
                              'TUJUAN CONTOH',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w700,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 7,
                              runSpacing: 5,
                              children: savedPlaces
                                  .map(
                                    (place) => ActionChip(
                                      label: Text(
                                        place.name,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      avatar: const Icon(
                                        Icons.north_east_rounded,
                                        size: 14,
                                      ),
                                      onPressed: () => choose(place),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.place_rounded,
                                  size: 18,
                                  color: green,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    destination!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Hapus tujuan',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    ++routeVersion;
                                    setState(() {
                                      destination = null;
                                      route = const [];
                                      distanceM = null;
                                      durationS = null;
                                      routeError = null;
                                      routing = false;
                                    });
                                  },
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ),
                            if (routing)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: LinearProgressIndicator(minHeight: 3),
                              ),
                            if (distanceM != null && minutes != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$minutes',
                                    style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      color: green,
                                      height: 1.1,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(
                                      left: 5,
                                      bottom: 4,
                                    ),
                                    child: Text(
                                      'menit',
                                      style: TextStyle(
                                        color: green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${(distanceM! / 1000).toStringAsFixed(1)} km',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: 'Hitung ulang rute',
                                    onPressed: fetchRoute,
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      color: green,
                                    ),
                                  ),
                                ],
                              ),
                            if (routeError != null)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      routeError!,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: red,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: fetchRoute,
                                    child: const Text('Coba lagi'),
                                  ),
                                ],
                              ),
                          ],
                          const SizedBox(height: 9),
                          Text(
                            destination == null
                                ? 'Asal: posisi unit DEMO · Alamat dari Mapbox'
                                : 'Pratinjau rute · asal unit DEMO · ETA estimasi sesuai cakupan lalu lintas.',
                            style: const TextStyle(
                              fontSize: 9,
                              color: muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
