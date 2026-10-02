import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../core/design.dart';
import '../core/fleet.dart';
import 'reports.dart';
import 'feedback.dart';

String readableError(Object error) =>
    error.toString().replaceFirst('Bad state: ', '');
String shortTime(String? text) {
  final date = DateTime.tryParse(text ?? '')?.toLocal();
  if (date == null) return '—';
  return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class OperationsPage extends StatefulWidget {
  const OperationsPage({
    super.key,
    required this.vehicles,
    required this.connected,
  });
  final List<Vehicle> vehicles;
  final bool connected;
  @override
  State<OperationsPage> createState() => _OperationsPageState();
}

class _OperationsPageState extends State<OperationsPage> {
  int tab = 0;
  List<Map<String, dynamic>> bookings = [], orders = [], audit = [];
  bool busy = false;
  String? error;
  final pendingMutations = <String>{};
  @override
  void initState() {
    super.initState();
    if (widget.connected) load();
  }

  @override
  void didUpdateWidget(covariant OperationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.connected && widget.connected) load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        const FleetApi().request('/v1/bookings'),
        const FleetApi().request('/v1/work-orders'),
        const FleetApi().request('/v1/audit'),
      ]);
      if (mounted) {
        setState(() {
          bookings = List<Map<String, dynamic>>.from(results[0]['bookings']);
          orders = List<Map<String, dynamic>>.from(results[1]['workOrders']);
          audit = List<Map<String, dynamic>>.from(results[2]['events']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String vehicleName(String id) {
    for (final vehicle in widget.vehicles) {
      if (vehicle.id == id) return '${vehicle.plate} · ${vehicle.name}';
    }
    return id;
  }

  Future<void> mutate(String path) async {
    if (pendingMutations.contains(path)) return;
    setState(() => pendingMutations.add(path));
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => PointerInterceptor(
          child: AlertDialog(
            title: const Text('Konfirmasi pembaruan'),
            content: Text(
              path.endsWith('return')
                  ? 'Catat pengembalian unit ini? Catatan akan tersimpan dalam audit server.'
                  : 'Tandai pekerjaan servis ini selesai?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Konfirmasi'),
              ),
            ],
          ),
        ),
      );
      if (approved != true || !mounted) return;
      try {
        await const FleetApi().request(path, body: {});
        if (mounted) {
          showOutcome(
            context,
            path.endsWith('return')
                ? 'Pengembalian kendaraan tercatat.'
                : 'Servis ditandai selesai.',
          );
        }
        await load();
      } catch (e) {
        if (mounted) {
          showOutcome(context, readableError(e), failed: true);
        }
      }
    } finally {
      if (mounted) setState(() => pendingMutations.remove(path));
    }
  }

  Future<void> create() async {
    if (widget.vehicles.isEmpty) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PointerInterceptor(
        child: _CreateOperation(vehicles: widget.vehicles, service: tab == 1),
      ),
    );
    if (result == true && mounted) {
      showOutcome(
        context,
        tab == 0 ? 'Booking tersimpan.' : 'Jadwal servis tersimpan.',
      );
      load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'REV RENTAL · JAKARTA',
        style: TextStyle(
          color: green,
          fontSize: 10,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 9),
      Text('Operasi', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 10),
      const Text(
        'Kelola rental, jadwal servis, dan catatan aktivitas.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          for (var i = 0; i < 4; i++)
            ChoiceChip(
              label: Text(['Rental', 'Servis', 'Audit', 'Laporan'][i]),
              selected: tab == i,
              onSelected: (_) => setState(() => tab = i),
            ),
        ],
      ),
      const SizedBox(height: 20),
      if (!widget.connected)
        const Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.link, color: green),
              SizedBox(height: 12),
              Text('Data operasional belum tersedia'),
              SizedBox(height: 6),
              Text(
                'Hubungkan layanan RevTrack untuk mengelola rental dan jadwal servis.',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        )
      else ...[
        Row(
          children: [
            Expanded(
              child: Text(
                tab == 0
                    ? '${bookings.where((b) => b['status'] == 'booked').length} booking aktif'
                    : tab == 1
                    ? '${orders.where((o) => o['status'] == 'open').length} pekerjaan terbuka'
                    : '${audit.length} aktivitas tercatat',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Muat ulang operasi',
            ),
            if (tab < 2)
              FilledButton.icon(
                onPressed: busy ? null : create,
                icon: const Icon(Icons.add, size: 18),
                label: Text(tab == 0 ? 'Booking baru' : 'Jadwalkan servis'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!, style: const TextStyle(color: red)),
          ),
        if (tab == 0) ...[
          if (bookings.isEmpty && !busy)
            const _Empty(
              icon: Icons.event_available_outlined,
              title: 'Belum ada booking',
              body:
                  'Buat booking pertama. Sistem memeriksa bentrok jadwal dan kesiapan servis unit.',
            ),
          for (final booking in bookings.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            booking['customerName'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Tag(
                          booking['status'] == 'booked' ? 'BOOKED' : 'KEMBALI',
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      vehicleName(booking['vehicleId']),
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '${shortTime(booking['startAt'])} → ${shortTime(booking['endAt'])}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (booking['status'] == 'booked')
                      Align(
                        alignment: Alignment.centerRight,
                        child: ActionFeedbackButton(
                          onPressed: () =>
                              mutate('/v1/bookings/${booking['id']}/return'),
                          phase:
                              pendingMutations.contains(
                                '/v1/bookings/${booking['id']}/return',
                              )
                              ? ActionPhase.busy
                              : ActionPhase.ready,
                          label: 'Catat pengembalian',
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (tab == 1) ...[
          if (orders.isEmpty && !busy)
            const _Empty(
              icon: Icons.build_circle_outlined,
              title: 'Belum ada jadwal servis',
              body:
                  'Buat pekerjaan servis dengan unit dan tugas yang jelas. Selesaikan ketika pemeriksaan sudah dilakukan.',
            ),
          for (final order in orders.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order['title'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Tag(order['status'] == 'open' ? 'TERBUKA' : 'SELESAI'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      vehicleName(order['vehicleId']),
                      style: const TextStyle(color: muted),
                    ),
                    if (order['status'] == 'open')
                      Align(
                        alignment: Alignment.centerRight,
                        child: ActionFeedbackButton(
                          onPressed: () =>
                              mutate('/v1/work-orders/${order['id']}/complete'),
                          phase:
                              pendingMutations.contains(
                                '/v1/work-orders/${order['id']}/complete',
                              )
                              ? ActionPhase.busy
                              : ActionPhase.ready,
                          label: 'Selesaikan pekerjaan',
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (tab == 2) ...[
          if (audit.isEmpty && !busy)
            const _Empty(
              icon: Icons.history,
              title: 'Belum ada aktivitas',
              body:
                  'Perubahan pengemudi, peringatan, rental, dan servis akan muncul di sini.',
            ),
          for (final item in audit.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Surface(
                padding: const EdgeInsets.all(17),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, color: green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['action'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${item['vehicleId'] ?? item['alertId'] ?? ''} · ${shortTime(item['createdAt'])}',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (tab == 3) const ReportsPanel(),
      ],
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: green, size: 32),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        const SizedBox(height: 10),
        Text(body, style: const TextStyle(color: muted, height: 1.7)),
      ],
    ),
  );
}

class _CreateOperation extends StatefulWidget {
  const _CreateOperation({required this.vehicles, required this.service});
  final List<Vehicle> vehicles;
  final bool service;
  @override
  State<_CreateOperation> createState() => _CreateOperationState();
}

class _CreateOperationState extends State<_CreateOperation> {
  late String vehicleId = widget.vehicles.first.id;
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  DateTime start = DateTime.now();
  int days = 1;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await const FleetApi().request(
        widget.service ? '/v1/work-orders' : '/v1/bookings',
        body: widget.service
            ? {'vehicleId': vehicleId, 'title': name.text.trim()}
            : {
                'vehicleId': vehicleId,
                'customerName': name.text.trim(),
                'startAt': start.toUtc().toIso8601String(),
                'endAt': start
                    .add(Duration(days: days))
                    .toUtc()
                    .toIso8601String(),
              },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.service ? 'Jadwalkan servis' : 'Booking rental'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownMenuFormField<String>(
                initialSelection: vehicleId,
                expandedInsets: EdgeInsets.zero,
                enabled: !saving,
                enableFilter: true,
                label: const Text('Kendaraan'),
                menuHeight: 260,
                dropdownMenuEntries: widget.vehicles
                    .map(
                      (v) => DropdownMenuEntry(
                        value: v.id,
                        label: '${v.plate} · ${v.name}',
                        labelWidget: Text(
                          '${v.plate} · ${v.name}',
                          maxLines: 2,
                        ),
                      ),
                    )
                    .toList(),
                onSelected: (v) {
                  if (v != null) setState(() => vehicleId = v);
                },
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: name,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: widget.service
                      ? 'Pekerjaan yang diperlukan'
                      : 'Nama pelanggan',
                ),
                validator: (v) => v == null || v.trim().length < 3
                    ? 'Isi minimal 3 karakter.'
                    : null,
              ),
              if (!widget.service) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Mulai ${shortTime(start.toIso8601String())}'),
                  onPressed: saving
                      ? null
                      : () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: start,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (date == null || !context.mounted) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(start),
                          );
                          if (time != null && mounted) {
                            setState(
                              () => start = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              ),
                            );
                          }
                        },
                ),
                DropdownButtonFormField<int>(
                  initialValue: days,
                  decoration: const InputDecoration(labelText: 'Durasi'),
                  items: [1, 2, 3, 7, 14, 30]
                      .map(
                        (d) =>
                            DropdownMenuItem(value: d, child: Text('$d hari')),
                      )
                      .toList(),
                  onChanged: saving ? null : (v) => setState(() => days = v!),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kendaraan harus tersedia pada jadwal yang dipilih.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(error!, style: const TextStyle(color: red)),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Batal'),
      ),
      ActionFeedbackButton(
        label: 'Simpan',
        busyLabel: 'Menyimpan…',
        phase: saving ? ActionPhase.busy : ActionPhase.ready,
        onPressed: save,
      ),
    ],
  );
}
