# RevTrack Go API — workspace simulasi lokal

Backend **Go standard library**, tanpa dependency pihak ketiga. Data adalah fixture fiktif Jakarta; belum terhubung ke tracker fisik. Mendukung fleet, riwayat posisi/energi, alert, assignment pengemudi, acknowledge alert, booking/pengembalian rental, work order bengkel, audit dan simulator telemetry. Tidak ada endpoint immobilizer, kendali kendaraan, panggilan atau mikrofon.

## Menjalankan

Go 1.25+ diperlukan. Dari root repository:

```sh
cd services/api
export REVTRACK_DEMO_TOKEN="$(openssl rand -hex 24)"
export REVTRACK_DEVICE_TOKEN="$(openssl rand -hex 24)"
export REVTRACK_DATA_FILE=/private/tmp/revtrack-demo/state.json
go run ./cmd/server
```

Server hanya bind `127.0.0.1:8080`; `PORT` dapat diubah. Dua token wajib berbeda dan minimal 24 karakter. Nilai `.env.example` adalah placeholder, bukan kredensial siap pakai; Go tidak otomatis membaca `.env`. Jangan commit token. Token pengguna diberikan ke `DEMO_API_TOKEN` Flutter khusus demo. Token perangkat hanya untuk simulator, **tidak masuk aplikasi mobile**.

Jika filesystem sandbox menolak cache Go, gunakan `GOCACHE=/private/tmp/revtrack-go-build` sebelum perintah Go. Untuk perangkat Android melalui USB gunakan `adb reverse tcp:8080 tcp:8080`; akses ponsel fisik melalui jaringan memerlukan konfigurasi HTTPS backend yang terpisah. Demo ini sengaja tidak membuka listener ke LAN.

`REVTRACK_DATA_FILE` opsional. Jika diisi, snapshot private `0600` menyimpan data dan replay cursor dengan temp file + flush + atomic rename. Jika tidak diisi, semua perubahan hilang saat restart. **Satu proses saja**, tidak ada penguncian file antarproses, enkripsi-at-rest aplikasi, failover atau jaminan recovery power loss. Jangan jalankan dua server pada snapshot yang sama. Untuk reset demo, hentikan server lalu pilih path snapshot baru; jangan memakai data rental sungguhan.

CORS hanya mengizinkan `http://localhost:7357` dan `http://127.0.0.1:7357`. Tambahkan satu origin HTTP loopback persis melalui `REVTRACK_WEB_ORIGIN` bila port preview berbeda. CORS bukan autentikasi.

## Simulator

Dari terminal lain dengan **nilai `REVTRACK_DEVICE_TOKEN` yang sama**:

```sh
cd services/api
go run ./cmd/simulator -count 20 -interval 3s
```

`-count 0` berjalan hingga Ctrl-C. Default endpoint `http://127.0.0.1:8080`, dapat diubah melalui `REVTRACK_API_URL` ke HTTP loopback. Simulator mengirim lokasi sekitar Sudirman, kecepatan, akurasi GNSS dan persentase baterai untuk `dev-001 → veh-001`. Semua output menyebut `SIMULATION`. Ini tidak membaca GPS ponsel, CAN bus atau mobil sungguhan. Sequence menggunakan timestamp milliseconds agar restart simulator tidak kembali ke sequence pertama.

## Kontrak HTTP

Semua data response menyertakan `mode: "demo"`; `/health` publik. Endpoint lainnya memakai `Authorization: Bearer <token>`. Tenant berasal dari kredensial server, bukan query atau JSON pengguna.

| Method dan path | Kredensial | Hasil |
|---|---|---|
| `GET /health` | Publik | `status`, `mode`, `persistence`, `hardwareCommands:false` |
| `GET /v1/fleet` | Pengguna | `{vehicles:[Vehicle],summary:{total,moving,idle,offline,alerts},generatedAt}` |
| `GET /v1/vehicles/:id` | Pengguna | `{vehicle:Vehicle}` |
| `GET /v1/vehicles/:id/telemetry` | Pengguna | `{vehicleId,limit:500,points:[Point]}` tertua ke terbaru |
| `GET /v1/alerts` | Pengguna | `{alerts:[Alert]}` terbaru ke terlama |
| `GET /v1/drivers` | Pengguna | `{drivers:[{id,name,rating}]}` |
| `GET /v1/audit` | Pengguna | `{events:[{id,action,vehicleId,alertId?,driverId?,actor,createdAt}]}` |
| `GET /v1/reports/summary` | Pengguna | Ringkasan status armada, rental, maintenance dan sampel telemetry tersimpan |
| `GET /v1/reports/telemetry.csv` | Pengguna | CSV attachment titik posisi/energi tenant saat ini; bearer token wajib |
| `POST /v1/alerts/:id/acknowledge` | Pengguna | `{alert:Alert}`; pengulangan tidak menambah audit |
| `POST /v1/vehicles/:id/assignment` | Pengguna | JSON `{driverId}` → `{vehicle,assignment:{id,vehicleId,driverId,assignedAt}}` |
| `GET /v1/bookings` | Pengguna | `{bookings:[Booking]}` |
| `POST /v1/bookings` | Pengguna | JSON `{vehicleId,customerName,startAt,endAt}` → HTTP 201 `{booking:Booking}` |
| `POST /v1/bookings/:id/return` | Pengguna | `{booking:Booking}`, idempoten |
| `GET /v1/work-orders` | Pengguna | `{workOrders:[WorkOrder]}` |
| `POST /v1/work-orders` | Pengguna | JSON `{vehicleId,title}` → HTTP 201 `{workOrder:WorkOrder}` |
| `POST /v1/work-orders/:id/complete` | Pengguna | `{workOrder:WorkOrder}`, idempoten |
| `POST /v1/telemetry` | Perangkat | HTTP 202 `{accepted:true,vehicleId,eventId,alerts:[Alert]}` |

`Vehicle`: `id`, `plate`, `name`, `powertrain` (`ev/ice/diesel`), `status` (`moving/idle/parked/charging/offline`), `driver:{id,name,rating}`, `location:{latitude,longitude,label}`, `speedKph`, `batteryPercent`, `fuelPercent`, `odometerKm`, `rangeKm`, `lastSeenAt`, `lastPositionAt`, `energyAt`, `signal` (`good/weak/offline`), `tripTodayKm`, `source` (`fixture/simulator`), `ignition`. Field energi/range bisa `null`: **unknown, bukan nol**. `tripTodayKm` masih ringkasan fixture, bukan hasil trip engine. `charging` hanya fixture karena ingest belum memodelkan charging state. Umur `lastSeenAt >5 menit` ditampilkan offline pada read.

`Point`: `recordedAt`, `latitude`, `longitude`, `speedKph`, `accuracyM`, `batteryPercent`, `fuelPercent`, `odometerKm`, `source`; data simulator menambah `eventId`, `sequence`, `receivedAt`. `Alert`: `id`, `vehicleId`, `title`, `description`, `severity`, `type`, `createdAt`, `status`, `source`, opsional `evidenceEventId`.

`GET /v1/reports/summary` memberi `{mode,generatedAt,scope:"retained_samples",pointsLimitPerVehicle:500,fleet:{total,moving,idle,parked,charging,offline,alerts},rental:{active,upcoming,overdue,returned},maintenance:{open,completed},telemetrySamples,vehicles:[VehicleReport]}`. Rental aktif berarti sudah mulai, belum mencapai `endAt` dan belum dikembalikan; overdue berarti melewati `endAt` namun belum dikembalikan. `VehicleReport` berisi `vehicleId`, `plate`, `powertrain`, `status`, `samples`, `fixtureSamples`, `simulatorSamples`, `firstRecordedAt`, `lastRecordedAt`, `maxObservedSpeedKph`, `energyKind` (`battery/fuel`), `firstEnergyPercent`, `lastEnergyPercent`. Nilai awal/akhir adalah sampel pertama/terakhir dalam ring, bukan nilai sensor known terakhir; unknown tetap `null`. Kecepatan maksimum adalah observasi window, bukan batas jalan atau bukti fraud. Tidak ada klaim konsumsi energi, biaya atau trip lengkap.

CSV menyertakan kolom `mode,vehicle_id,plate,recorded_at,source,latitude,longitude,speed_kph,accuracy_m,battery_percent,fuel_percent,odometer_km`. Nilai unknown menjadi cell kosong; teks yang dapat ditafsirkan formula spreadsheet diberi prefix apostrophe. Hasil dibatasi jumlah unit demo ×500 points/unit, diurutkan ID unit lalu waktu sampel. Endpoint mengambil snapshot konsisten sebelum menulis ke client dan tetap memerlukan autentikasi pengguna. Kredensial perangkat, token, nama pelanggan dan data tenant lain tidak diekspor. Contoh dari shell yang sudah memuat token lokal:

```sh
curl --fail --silent --show-error \
  -H "Authorization: Bearer $REVTRACK_DEMO_TOKEN" \
  http://127.0.0.1:8080/v1/reports/telemetry.csv \
  -o /private/tmp/revtrack-telemetry-demo.csv
```

Pengemudi bebas awal: `drv-006` (Nadia Rahma). Assignment ke pengemudi yang sudah bertugas di unit lain ditolak `409 driver_already_assigned`. Assignment valid memperbarui kendaraan dan menyimpan audit. Acknowledge menyatakan operator melihat alert, **bukan menyatakan insiden selesai**. Riwayat assignment disimpan dalam snapshot; belum ada endpoint timeline assignment khusus.

`Booking`: `id`, `vehicleId`, `customerName`, `startAt`, `endAt`, `status` (`booked/returned`), `createdAt`, opsional `returnedAt`. Waktu menerima ISO timestamp dengan timezone lalu dinormalisasi UTC milliseconds. Interval `[startAt,endAt)` tidak boleh overlap booking yang belum dikembalikan pada unit sama (`409 booking_overlap`). Durasi >0 dan maksimal 366 hari. Booking lampau yang melewati jadwal tetapi belum dikembalikan memblokir reservasi baru (`409 return_overdue`). Pengembalian sebelum tanggal mulai ditolak (`409 booking_not_started`). Ini belum workflow kontrak/deposit/inspection/invoice; `booked` mencakup reservasi yang sedang berjalan. Tidak ada aksi cancel/extend/refund pada versi ini.

`WorkOrder`: `id`, `vehicleId`, `title`, `status` (`open/completed`), `createdAt`, opsional `completedAt`. Work order terbuka memblokir booking baru (`409 unit_unavailable`). Pekerjaan bengkel ditolak bila unit sedang/masih dalam rental (`409 vehicle_on_rental`). Booking masa depan yang sudah ada tetap tersimpan; operator harus memastikan pekerjaan selesai sebelum handover. Seluruh aksi ini menghasilkan audit tanpa menyalin nama pelanggan. Contoh flow: buat booking mulai sekarang → pengembalian → buat pekerjaan inspeksi → selesai → booking berikutnya. Gunakan nama pelanggan fiktif.

Contoh telemetry (ganti `recordedAt` dengan waktu UTC sekarang):

```json
{
  "eventId": "device-event-0001",
  "sequence": 1,
  "recordedAt": "2026-10-02T03:00:00.000Z",
  "latitude": -6.2088,
  "longitude": 106.8229,
  "speedKph": 42,
  "ignition": true,
  "accuracyM": 8,
  "batteryPercent": 77,
  "odometerKm": 18421
}
```

`eventId`, `sequence`, `recordedAt`, koordinat, speed, ignition dan accuracy wajib; energi serta odometer opsional. Unknown field termasuk `tenantId`, `vehicleId` dan `deviceId` ditolak. Waktu harus ISO UTC dengan milliseconds, tidak lebih dari 24 jam lama atau 30 detik ke depan. Lokasi lama/equal ditolak `409 out_of_order` agar latest tidak mundur. Sequence positif yang meningkat, ID event terbaru serta cursor mencegah replay; setelah restart perlindungan hanya berlanjut jika snapshot diaktifkan. Null sensor opsional dibaca unknown; data yang hilang tidak dibuat-buat.

Range demo: lat `-90..90`, lon `-180..180`, speed `0..250 km/h`, accuracy `0..10000 m`, energi `0..100%`, odometer `0..10.000.000 km` tanpa penurunan. Fuel pada unit EV dan battery pada unit bensin/diesel demo ditolak. Field battery di sini adalah traction state-of-charge, bukan tegangan backup tracker.

Error: `{error:{code,message,requestId}}`, status `401/403/404/409/413/415/422/500`. Payload telemetry maksimal 16 KiB, assignment 1 KiB, booking/work order 4 KiB. Batas mencakup trailing bytes setelah object JSON. Geofence demo adalah persegi sekitar Jakarta: latitude `-6.38..-6.05`, longitude `106.68..106.98`; dua fix berurutan dengan accuracy ≤50 m di luar area menghasilkan alert. Overspeed memakai batas kebijakan 80 km/jam, bukan data batas kecepatan jalan. Tidak ada tindakan terhadap kendaraan dari alert.

## Validasi dan batas implementasi

```sh
go test -race ./...
go vet ./...
```

Tests menguji isolasi tenant, privilege user/device, binding identitas perangkat, replay concurrent, timestamp/koordinat, penolakan rollback odometer, geofence, buffer bounded, CORS, unknown energy, assignment conflict, audit acknowledge, concurrent booking overlap, batas interval, rental→return→maintenance→complete, future return, report rental/maintenance, CSV tenant isolation dan spreadsheet formula escaping, konsistensi HTTP payload caps, serta restart snapshot dan rollback saat penyimpanan gagal.

Map lookup rata-rata O(1); append ring O(1); history dibatasi 500 titik/unit, alert 200/tenant, audit/assignment 500/tenant, replay ID 500/device. Sequence high-water tetap menolak pesan sequence lama setelah eviction. Booking dan work order maksimal 500 record masing-masing/tenant: saat penuh aksi create ditolak agar reservasi aktif tidak pernah terhapus. Konflik booking memindai O(B+W), bounded pada demo. Read fleet O(V log V) karena sort; satu mutex menjaga atomic mutation. Snapshot menyalin dan menulis seluruh dataset sehingga O(N), cocok demo kecil. Ini **bukan benchmark ribuan unit**. Produksi mengganti dengan transaksi PostgreSQL + outbox/durable queue, pagination, OIDC, service/device identity, rate limit, tenant quota, observability, backup/restore serta integration test hardware.
