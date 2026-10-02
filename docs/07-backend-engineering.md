# RevTrack — engineering backend Go, Rust, Python, dan C/C++

Rancangan: **2 Oktober 2026, Asia/Jakarta**. Dokumen ini menjelaskan arsitektur target dan kriteria kualitas; bukan klaim seluruh komponen sudah berjalan. Implementasi starter, cara menjalankan, serta batasnya mengikuti README dan source repo. Diagram direktori di bawah adalah target bertahap.

## 1. Pembagian bahasa yang punya alasan operasional

**Go menjadi pusat aplikasi bisnis, Rust menangani batas protokol perangkat, Python menjalankan analitik/AI, dan C/C++ dipakai ketika kita benar-benar mengembangkan firmware atau gateway.** Empat bahasa bukan empat backend bisnis yang saling menyalin aturan. Setiap bahasa mempunyai owner, kontrak, dan gate aktivasi.

| Bahasa | Tanggung jawab | Alasan dipilih | Tidak menjadi tanggung jawabnya |
|---|---|---|---|
| Go | REST API, otorisasi tenant, fleet/rental/dispatch, rules deterministik, workflow, ingestion API internal, realtime fanout | Deployment sederhana, tipe statis, dukungan concurrency dan tooling yang cocok untuk layanan I/O | Melatih model ML atau firmware MCU |
| Rust | Parser binary tracker, validasi frame, buffering koneksi, normalisasi protokol; optional compute hotspot setelah profiling | Ownership membantu keselamatan memori untuk input tak terpercaya; kontrol alokasi dan performa | Menyalin billing, assignment, atau policy tenant dari Go |
| Python | Simulator, data quality, offline analytics, feature pipelines, fraud review suggestions, agent orchestration dan eksperimen optimizer | Ekosistem analitik dan iterasi model; batch/job terisolasi dari live tracking | Menentukan akses final, menulis tabel bisnis bebas, atau mengontrol aktuator |
| C++ | Aplikasi edge/gateway, filter sensor, ring buffer, protokol pada target embedded yang mendukung toolchain | Ekosistem hardware, kontrol resource, library vendor | Backend CRUD tambahan hanya untuk memakai C++ |
| C | BSP/HAL, driver vendor, integrasi modem/RTOS/bootloader bila SDK mensyaratkan | Kompatibilitas interface hardware dan SDK | Pilihan default semua service internet |
| Dart | Flutter UI, presentasi state, cache lokal terkontrol | Android/iOS dari satu produk | Sumber kebenaran posisi armada, izin, atau transaksi |
| Kotlin / Swift | Bridge Android/iOS bila plugin yang tersedia belum memenuhi kebutuhan BLE/audio/background/native Mapbox | Akses API platform yang diperlukan | Menulis ulang seluruh aplikasi Flutter |
| SQL | Constraints, transaksi, indeks spasial, query yang terukur | Integritas data dan query planner | Tempat menyembunyikan seluruh logika produk dalam trigger |

Dasar bahasa: [Go concurrency](https://go.dev/doc/effective_go#concurrency), [Rust ownership](https://doc.rust-lang.org/book/ch04-01-what-is-ownership.html), [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines), [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels). Pemilihan peran di atas merupakan keputusan desain RevTrack, bukan jaminan bahwa suatu bahasa otomatis lebih cepat atau lebih aman untuk semua masalah.

### Aktivasi bertahap

1. **Starter:** satu proses Go dengan modul domain jelas, fixture/simulator, API stabil, dan Flutter. Simulasi boleh in-memory dengan batas yang terlihat. Ini belum ingestion tracker produksi.
2. **Pilot:** PostgreSQL/PostGIS, auth produksi, outbox dalam transaksi, job worker Go, backup, telemetry storage, dan satu parser protokol. Rust diaktifkan ketika sample tracker/protokol dan corpus test tersedia. Python pertama kali membantu simulator dan laporan offline.
3. **Commercial:** pisahkan Rust ingress agar paparan socket/protokol tidak berada dalam proses bisnis; hidupkan Python jobs dengan queue, budget, evaluasi, dan owner. NATS JetStream menjadi opsi setelah kebutuhan durable backlog/independent consumption dibuktikan; outbox PostgreSQL tetap cukup untuk banyak workflow awal.
4. **Hardware program:** C/C++ atau embedded Rust baru masuk setelah MCU/modem, HAL, RTOS, sertifikasi, power budget, dan service lifecycle dipilih. Tracker vendor dapat langsung dipakai tanpa firmware custom RevTrack.

Ekstraksi modul menjadi service membutuhkan salah satu alasan terukur: scaling yang berbeda, isolasi kegagalan, owner/team yang berbeda, atau batas keamanan. Jumlah bahasa tidak boleh memaksa distributed monolith dengan puluhan panggilan sinkron untuk satu halaman.

## 2. Struktur target dan kepemilikan data

```text
apps/mobile/                         # Flutter/Dart
contracts/
  openapi/revtrack-v1.yaml            # API mobile/operator
  events/telemetry-observed-v1.json   # schema event lintas bahasa
  fixtures/                          # input/output golden bersama
services/api/                        # Go modular core
  cmd/server/
  cmd/worker/
  internal/
    identity/  fleet/  rental/  dispatch/
    telemetry/ geofence/ alerts/ cases/
    maintenance/ billing/ audit/ workflow/
    platform/postgres/ platform/http/ platform/outbox/
services/ingest/                     # Rust; tahap tracker nyata
  crates/protocol/                   # pure parser, tanpa network/database
  crates/normalizer/                 # units, quality, schema mapping
  crates/gateway/                    # Tokio socket lifecycle/backpressure
services/agents/                     # Python; job/analysis terpisah
  revtrack_agents/tools/ policies/ evaluations/ jobs/
firmware/                           # tahap hardware custom
  common/                           # kontrak, fixed-width types
  bsp/                              # C + vendor HAL
  telemetry/ storage/ power/        # C++ atau Rust target yang tervalidasi
tools/simulator/                     # Python event/corpus generation
db/migrations/                      # SQL; owner schema eksplisit
ops/                                # deploy, dashboards, runbooks
docs/adr/                           # keputusan dengan tradeoff dan bukti
```

Nama direktori komponen mendatang dapat disesuaikan ketika dibangun. `internal/demo` pada starter adalah adapter demonstrasi yang kelak digantikan store produksi; jangan menganggap data memory sebagai database customer.

| Owner logis | Data yang dapat ditulis | Konsumen lain |
|---|---|---|
| Identity / tenant | Membership, role, policy, service identity | Meminta keputusan izin melalui interface core |
| Fleet / device registry | Asset, capability, installation interval, binding credential | Ingress mendapat view binding minimum, versioned dan cepat direvoke |
| Telemetry | Raw references, normalized observations, dedup ledger, current projection | Reports/rules/AI membaca lewat view atau event terbatas tenant |
| Dispatch / rental | Assignment, reservation, contract, lifecycle | AI mengirim proposal; core memvalidasi dan mengeksekusi |
| Geofence / alerts / cases | Polygon version, rule version, alert lifecycle, evidence | Mobile operator, notifications, AI triage |
| Finance | Invoice, payment status, credits, reconciliation | Provider callback masuk melalui handler idempotent |
| AI jobs | Feature snapshot, model/prompt version, recommendation, evaluation | Tidak memiliki direct write ke assignment/finance/control |

Modul dapat berbagi satu PostgreSQL pada fase awal. Satu owner menulis tabelnya; modul lain memakai application interface. Foreign key tenant-aware, unique constraints, dan transaksi melindungi invariant. `tenant_id` wajib pada row pelanggan, filter query, cache key, job, object path, event, dan subscription. RLS menjadi defense in depth, bukan pengganti pemeriksaan izin aplikasi.

Invariants penting: assignment aktif tidak boleh menggandakan kendaraan/driver secara tidak sah; payment callback berulang tidak menggandakan kredit; current location tidak mundur oleh replay; perangkat yang dipindah kendaraan dikaitkan menurut installation interval waktu kejadian; satu tenant tidak dapat memperoleh posisi tenant lain melalui ID yang ditebak.

## 3. Kontrak sebelum transport

REST JSON untuk mobile dan integrasi eksternal. Event JSON Schema untuk pipeline awal. Protobuf/gRPC boleh dipakai pada interface internal yang throughput dan manfaat codegen-nya terbukti; jangan menambahkan serialisasi berbeda tanpa kebutuhan.

Envelope event memiliki `schema_version`, `event_id`, `event_type`, `tenant_id` hasil binding tepercaya, `device_id`, `installation_id`, `observed_at`, `received_at`, `producer`, `trace_id`, dan `payload`. Tambahkan `boot_session_id`/sequence hanya ketika sumbernya tervalidasi; protokol legacy tidak boleh diberi sequence palsu yang diklaim berasal dari perangkat.

- Gunakan UTC untuk waktu pertukaran; Asia/Jakarta adalah zona presentasi sesuai pengguna. Simpan durasi sebagai integer dengan unit jelas.
- Koordinat GeoJSON adalah longitude–latitude; payload bernama `lat`/`lon` tidak memakai urutan array ambigu. SRID dan satuan wajib ditetapkan.
- Uang memakai integer minor unit/decimal dengan currency, bukan binary floating point. SOC/fuel unavailable adalah `null`, bukan 0.
- Tambahan field optional dapat kompatibel; mengubah arti, unit, atau nullability memerlukan versi baru. Consumer menolak major version tak dikenal secara terukur dan menaruh bukti ke quarantine.
- Batas payload, jumlah event/batch, panjang string, enum, numeric finite/range, dan ukuran polygon masuk schema dan server validation.
- API mutasi memakai idempotency key scoped tenant + actor + operasi. Simpan request fingerprint dan response: key sama dengan payload berbeda menghasilkan conflict.
- Error stabil: `code`, pesan aman, `trace_id`, field violations bila ada. Jangan mengembalikan stack trace, credential, raw tracker payload, atau token.
- Contract tests lintas Go/Rust/Python menjalankan fixture sama: byte input, decoded canonical event, quality flags, expected errors.

Batas kepercayaan berada pada decoder → binding registry → normalized observation. `tenant_id` dari radio/device tidak otoritatif. Binding cache harus memiliki TTL pendek, version, dan invalidation agar pencabutan perangkat tidak menunggu cache berjam-jam.

## 4. Concurrency, backpressure, dan budget resource

### Go

Setiap request memiliki `context` dengan deadline dan cancellation yang diteruskan ke SQL, HTTP vendor, dan worker. Task yang harus tetap hidup setelah request selesai dimasukkan ke durable job, bukan goroutine tanpa owner.

Gunakan worker pool/semaphore untuk pekerjaan mahal; channel mempunyai capacity; batasi connection, body bytes, parallel export, query duration, dan per-tenant in-flight work. Mutex sederhana untuk state pendek sering lebih mudah diverifikasi daripada desain lock-free. Jangan menahan mutex ketika menunggu HTTP/SQL. Pilih satu owner untuk menutup channel; setiap goroutine mempunyai kondisi berhenti yang dapat diuji. Race detector dijalankan pada test yang memicu concurrency nyata. [Go race detector](https://go.dev/doc/articles/race_detector).

### Rust ingress

Parser berupa fungsi atas byte slice dengan hasil `Complete`, `NeedMoreData`, atau `Invalid`. Frame mempunyai batas maksimal sebelum alokasi; cek overflow panjang/offset; tidak `unwrap()` pada input perangkat. Core parser dimulai dengan larangan `unsafe`; dependensi dan boundary FFI yang membutuhkan `unsafe` ditinjau terpisah.

Tokio menangani socket yang dibatasi jumlahnya; channel bounded dan semaphore membatasi pending frame/byte. Timer handshake, read idle, write, dan total processing melindungi koneksi lambat. CPU-heavy decode/compression tidak memblokir executor I/O; pool blocking juga harus dibatasi. Satu task memiliki koneksi dan lifecycle cancellation yang jelas. Memory safety tidak mencegah logical bug, DoS alokasi, deadlock, atau autentikasi lemah. [Tokio bounded channels dan backpressure](https://tokio.rs/tokio/tutorial/channels).

### Python

Task I/O memakai `TaskGroup`, timeout, queue `maxsize`, dan semaphore untuk tool/model call. Cancellation tidak ditelan. CPU-intensive jobs dipindah ke process/worker terpisah atau library native yang profilnya diketahui; jangan mengasumsikan `asyncio` membuat komputasi CPU menjadi paralel. Set memory/time/token budgets, retry ceiling, dan checkpoint untuk job panjang. [Python TaskGroup](https://docs.python.org/3/library/asyncio-task.html), [Python queue](https://docs.python.org/3/library/asyncio-queue.html).

### Kebijakan saat overload

| Jalur | Ketika kapasitas penuh | Yang tidak boleh terjadi |
|---|---|---|
| Telemetry ingress | Perlambat read, gunakan spool durable terbatas jika tersedia, atau disconnect menurut protokol agar retry; ACK hanya setelah persist yang dijanjikan | ACK lalu membuang record secara diam-diam |
| Current position fanout | Coalesce update per kendaraan; kirim versi terbaru, drop intermediate UI-only updates | Menghapus history/evidence karena UI lambat |
| Alert/case | Persist dulu, dedup alert, retry notification secara terukur | Flood notifikasi dari satu perangkat menutup alert tenant lain |
| Export/report | Job queue, kuota, admission control, signed download URL saat selesai | Menahan ribuan HTTP request sambil query tak berbatas |
| AI analysis | Turunkan prioritas, batch, expire proposal yang kedaluwarsa | Kegagalan model menghentikan live tracking |

Tetapkan batas berdasarkan byte dan record; 1.000 message kecil berbeda dari 1.000 frame besar. Contoh kalkulasi budget, bukan konfigurasi final: `queue_capacity × max_item_bytes + per_connection_state × connections + worker_scratch`. Benchmark RSS aktual karena object overhead dan allocator belum termasuk rumus.

## 5. DSA yang langsung berguna untuk fleet

Gunakan `N` untuk jumlah item, `G` geofence tenant, `V` vertex polygon, `W` ukuran window, dan `k` jumlah kandidat. Kompleksitas adalah model analitis; distribusi data, query plan, cache, I/O, dan ukuran geometry menentukan latency nyata.

| Masalah | Struktur/algoritma | Biaya dan batas | Keputusan implementasi |
|---|---|---|---|
| Lookup device/asset | Hash map/cache bounded | Rata-rata O(1), memory O(N); collision/worst-case bergantung implementasi | Registry SQL tetap otoritatif; cache tenant-aware dengan invalidation |
| Timeline terbaru | Ring buffer fixed capacity | Append/evict O(1), memory O(W) | Cocok demo atau cache; bukan penyimpanan history komersial |
| Replay dedup cepat | Hash set + FIFO/expiry heap | Lookup rata-rata O(1); expiry heap O(log W) | Cache hanya akselerator; durable uniqueness mencegah replay setelah restart |
| Fuel/speed rolling stats | Running sum/EWMA/deque | Sum/EWMA O(1) per event; deque rolling min/max amortized O(1) | Window event-time, quality gate, reset/late correction eksplisit |
| Heartbeat timeout | Min-heap deadline atau timing wheel | Heap O(log N); wheel amortized bergantung resolusi | Hindari satu polling SQL penuh per detik untuk semua unit |
| Geofence candidate | GiST/R-tree + exact polygon test | Selektif umumnya jauh lebih sedikit dari G; worst case overlap luas mendekati scan | Filter tenant/assignment, bbox prefilter, exact test, dwell/hysteresis |
| Nearby assets | Spatial KNN/radius query, lalu ETA ranking | Index-assisted; worst case bisa O(N); top-k heap atas scan O(N log k) | Kandidat geografis dahulu, road ETA kemudian |
| Dispatch | Constraint filtering + matching/VRP solver | Kompleksitas meningkat tajam dengan constraints; tidak menjanjikan optimum global cepat | Deadline solver, feasible fallback, explainable objective, human review |
| Rate limit | Token bucket per principal/tenant | State/update O(1) | Atomik per instance; shared quota perlu primitive atomik lintas replica |
| History pagination | Composite B-tree + keyset cursor | Seek dan page terbatas; biaya index/update perlu diukur | `(tenant, asset, observed_at, event_id)`; hindari OFFSET besar |

### Geofence yang benar sebelum cepat

PostGIS memakai spatial index melalui GiST dan fungsi yang index-aware. [PostGIS spatial indexes](https://postgis.net/documentation/faq/spatial-indexes/). Hindari klaim “semua query geofence O(log N)”: polygon tumpang tindih, tenant besar, dan bounding box buruk dapat memberi banyak kandidat.

Pipeline: ambil rule yang berlaku untuk asset dan waktu event → filter index bounding box → exact inclusion dengan semantics boundary yang dinyatakan → margin kualitas GPS → state machine `inside / pending_exit / outside / pending_enter` → dwell timer → alert idempotent. `ST_Covers` cocok ketika titik pada boundary harus dianggap masih di dalam; pilih semantics lalu uji, jangan mencampurnya dengan `ST_Contains` tanpa sengaja.

Jangan memakai jarak derajat latitude/longitude sebagai meter. Pilih `geography` untuk operasi geodesik yang sesuai atau transformasi projected CRS lokal yang tervalidasi. Uji polygon invalid, holes, area sangat kecil, lintas antimeridian, perubahan geofence saat trip aktif, dan titik tanpa fix. Simpan polygon/rule version bersama bukti alert.

### Nearest driver bukan sekadar jarak garis lurus

PostGIS menyediakan KNN operator `<->` dengan dukungan indeks. Gunakan `EXPLAIN (ANALYZE, BUFFERS)` pada dataset realistis untuk memastikan query menggunakan plan yang diinginkan. [PostGIS nearest-neighbour](https://postgis.net/workshops/postgis-intro/knn.html).

Saring driver/vehicle berdasarkan assignment, shift, kapasitas, capability, maintenance lock, baterai/range confidence, geofence, dan izin wilayah. Ambil kandidat geografis, lalu minta road ETA untuk kandidat terbatas. Mapbox Matrix memberi durasi/jarak dan dapat berbeda menurut arah; API tidak mengembalikan geometry rute. Limit saat riset adalah 25 koordinat untuk profil umum dan 10 untuk driving-traffic; letakkan limit sebagai konfigurasi yang divalidasi terhadap kontrak vendor sebelum deploy. [Mapbox Matrix](https://docs.mapbox.com/api/navigation/matrix/).

Untuk ribuan unit jangan membuat full matrix setiap perubahan posisi: N×N berarti satu juta pasangan pada 1.000 titik. Gunakan radius, shortlist k, cache sesuai ketentuan vendor, time bucket yang sesuai, batching, dan refresh hanya ketika perubahan memengaruhi keputusan. Kandidat yang tidak punya ETA valid diberi status unavailable; jangan mengarang ETA dari nilai nol.

Single-job dispatch dapat memakai deterministic scoring setelah hard constraints lolos. Multi-job memakai assignment/VRP dengan time windows, service duration, kapasitas, breaks, pickup-before-dropoff, biaya, dan charging constraints yang bisa dipertanggungjawabkan. OR-Tools merupakan opsi solver lokal lewat Python/C++, tetap memakai Mapbox untuk peta/ETA. Dokumentasi solver menjelaskan solusi besar dapat bersifat baik tanpa optimum dan menyediakan time limits. [OR-Tools routing](https://developers.google.com/optimization/routing), [search limits](https://developers.google.com/optimization/routing/routing_tasks). Ini tidak menambahkan Google Maps ke produk.

Snapshot posisi/assignment/version disimpan saat optimisasi. Sebelum menyetujui hasil, Go mengecek ulang availability dan expected version dalam transaksi; rencana yang sudah basi harus dioptimalkan ulang, bukan memaksa double assignment.

## 6. Deduplication, ordering, TTL, dan watermark

Record waktu yang sama tidak selalu duplikat: event ignition dan fuel dapat sah pada satu timestamp. Identitas dedup berasal dari protocol packet identity/sequence/session yang tersedia, posisi record dalam batch, atau fingerprint canonical yang dirancang untuk protokol. Random UUID baru pada setiap retry tidak memberi idempotensi.

Replay set bounded hanya mengurangi kerja decode/lookup. **TTL bukan jaminan antireplay permanen.** Ketika cache dibuang, proses restart, atau tracker mengirim backlog lama, unique constraint/dedup ledger durable tetap menentukan. Retensi ledger minimal mempertimbangkan retry horizon, device offline buffer, dan kebutuhan replay backfill; simpan kebijakan dan biaya. Jangan menyimpan semua event selamanya dalam RAM.

High-water sequence perlu scope device + boot/session epoch yang bisa dipercaya. Banyak tracker legacy hanya memiliki timestamp atau reset counter; high-water tunggal tidak boleh membuat semua event baru setelah reboot ditolak. Timestamp masa depan yang tidak masuk akal masuk quarantine dan tidak menaikkan watermark; waktu server menerima tidak membuktikan waktu pengukuran benar.

Pisahkan tiga state:

1. **History:** semua observasi valid yang baru, termasuk event terlambat, dengan observed/received time dan kualitas.
2. **Current:** diperbarui hanya oleh event yang memenuhi ordering policy dan freshness; tie-breaker deterministik.
3. **Derived window:** watermark `max_valid_observed_at − allowed_lateness` per partition/device group dengan penanganan idle partition. Watermark adalah kebijakan kapan hasil dianggap cukup lengkap, bukan bukti tak ada event lama lagi.

Event melampaui allowed lateness tetap disimpan. Ia dapat mengoreksi laporan/trip melalui versioned recomputation; jangan mengirim ulang alert lama sebagai keadaan darurat saat ini. Dwell/geofence dan fuel window dihitung berdasarkan event time; notifikasi incident realtime mempertimbangkan received time dan freshness.

```text
process(observation):
  binding = resolve_installation(device, observation.observed_at)
  validate_schema_and_quality(observation, binding)
  begin_transaction()
    if durable_dedup_key_exists(key): return previous_outcome
    insert_history_and_dedup_key(observation)
    if ordering_and_freshness_allow(observation, current_version):
      update_current_with_compare_and_swap(observation)
    insert_outbox_event(observation.event_id, binding.tenant_id)
  commit_transaction()
  acknowledge_ingress_after_durability_contract_is_met()
```

Ini pseudocode desain, bukan kode produksi. Perlu detail failure mode untuk commit berhasil tetapi ACK hilang, transaction rollback, retry bersamaan, dan message outbox diterbitkan dua kali. Consumer wajib idempotent meskipun broker menyediakan dedup window.

## 7. Fault tolerance tanpa klaim “exactly once” lintas jaringan

Transaksi bisnis + outbox commit bersama. Publisher dapat crash sesudah publish sebelum menandai selesai; itu menghasilkan duplicate dan harus aman bagi consumer. Retry memakai exponential backoff, jitter, batas upaya, deadline, dan idempotency. Poison message masuk quarantine dengan reason/version; operator dapat memperbaiki lalu replay tanpa mengubah bukti asli.

Pisahkan availability class: live monitoring tetap berjalan ketika report/AI/Maps ETA bermasalah. Maps gagal → list posisi dan status tetap tersedia; AI gagal → deterministic rules tetap berjalan; notification provider gagal → case tersimpan dan retry; device offline → posisi terakhir berlabel stale.

Satu writer order per device/partition menyederhanakan state, tetapi rebalance harus memakai lease/fencing atau durable compare-and-swap agar dua worker tidak menganggap diri owner. Stateless API dapat diskalakan terpisah. Go instance memory/mutex tidak mengoordinasikan replica; invariant akhirnya berada di database/primitive distributed yang tepat.

Backup mencakup DB, object evidence, schema, key access procedure, dan konfigurasi perangkat. Uji restore dengan data terisolasi. RPO/RTO ditetapkan setelah mengukur dan disesuaikan paket pelanggan; jangan mengiklankan SLA dari uptime satu container demo. Command, jika kelak ada, mempunyai control plane terpisah dengan safety case sebagaimana [rancangan IoT](02-iot-security.md).

## 8. Engineering C/C++ dan embedded Rust

Firmware telemetry adalah state machine `boot → self_test → acquire → buffer → transmit → sleep/recover`. Driver/modem callbacks mengirim event bounded; hindari blocking network di interrupt handler. Monitor stack high-water, watchdog, brownout, flash wear, buffer corruption, clock drift, dan battery budget.

Untuk C++: gunakan RAII, ownership jelas, fixed-width integer, bounds-checked interface, `span` jika toolchain mendukung, dan fixed-capacity container pada jalur deterministik. Heap allocation setelah startup di jalur kritis hanya bila analisis worst case mengizinkan. Exception/RTTI policy ditentukan sesuai RTOS/toolchain; jangan mematikan fitur tanpa mengganti jalur error/cleanup. Jangan memakai `volatile` sebagai sinkronisasi thread. Pedoman resource dan concurrency: [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines).

C dipakai untuk SDK/HAL/RTOS yang mengharuskannya; wrapper sempit membatasi pointer/buffer dan tanggung jawab ownership. Static analysis, compiler warnings, sanitizers pada host simulator, dan hardware-in-the-loop melengkapi review. Hindari transplantasi library desktop yang mengalokasikan bebas ke MCU dengan RAM kecil.

Embedded Rust layak dipertimbangkan bila MCU target, peripheral HAL, modem stack, bootloader, debugging, signing, dan tim support benar-benar tersedia. `no_std` dan linker/memory layout membawa kebutuhan khusus; penggunaan Rust di server tidak otomatis membuat SKU MCU siap dipakai. [Embedded Rust tooling](https://doc.rust-lang.org/stable/embedded-book/intro/tooling.html), [no_std](https://doc.rust-lang.org/stable/embedded-book/intro/no-std.html).

Python membantu serial test harness, replay GPS/CAN synthetic, calibration tooling, dan production fixture orchestration. C/C++/Rust firmware tidak boleh menyentuh traction, rem, steering, atau memutus mesin bergerak. Firmware custom tetap memerlukan program keamanan/sertifikasi/installer; pilihan bahasa bukan pengganti pengujian kendaraan.

## 9. Pengujian yang mengukur risiko nyata

| Lapisan | Test penting | Bukti lulus |
|---|---|---|
| Domain Go | Tenant boundaries, assignment concurrent, idempotency, time zones, stale telemetry, capability null | Invariant tetap benar pada parallel/retry/reordered scenarios |
| Rust parser | Golden vendor frames; fragmented/coalesced input; bad CRC, oversized length, invalid UTF-8, overflow; random bytes | Tidak panic/hang/unbounded allocate; hasil canonical sesuai fixture |
| Cross-language | Same schema fixture dan unknown-field/version behavior | Go/Rust/Python menghasilkan interpretation yang sama |
| Database | Constraint, migration upgrade, rollback strategy, lock/contention, outbox crash window | Tidak ada duplicate billing/assignment atau kehilangan durable event |
| Geospatial | Boundary, holes, jitter, antimeridian, invalid polygon, meter-vs-degree, huge overlap | Semantics dan alert stable; query plan tervalidasi |
| Python AI | False positives, stale evidence, prompt injection dari struk/catatan, tool scope, denied action, cost budget | AI tidak melampaui izin dan recommendation dapat diaudit |
| Firmware | Power-cycle/brownout, offline buffer penuh, sensor failure, bad OTA, parked battery drain | Recovery deterministik dan tidak memengaruhi sistem keselamatan |
| End-to-end | Disconnect/reconnect storm, outage replay, slow client, revoked device/tenant, key rotation | Loss/delay terukur; no cross-tenant exposure |

Go mempunyai fuzzing bawaan; Rust parser dapat memakai `cargo-fuzz` dengan corpus error yang disimpan menjadi regression test. [Go fuzz tutorial](https://go.dev/doc/tutorial/fuzz), [Rust Fuzz Book](https://rust-fuzz.github.io/book/). Fuzzing dan race detector menemukan kelas bug tertentu; keduanya bukan bukti sistem sudah aman sepenuhnya.

Benchmark wajib mencatat commit, hardware, toolchain, payload mix, batch size, connection count, database size, query plan, p50/p95/p99, allocations/event, RSS, CPU, queue depth/age, dan error rate. Jangan melaporkan hanya “requests per second” tanpa latency dan kehilangan data. Uji dengan open-loop arrival rate yang diketahui agar antrean/overload terlihat; pisahkan koneksi TLS setup dari steady state.

Angka sizing awal: 1.000 kendaraan semuanya bergerak pada interval 10 detik menghasilkan 100 event/detik; 10.000 menghasilkan 1.000 event/detik sebelum sensor/event tambahan. Bursty reconnect dapat jauh lebih tinggi. Usulkan test steady state 1×/3× kebutuhan, burst 10× selama periode terbatas, serta soak 24–72 jam dengan backlog/reconnect. Angka ini input benchmark, bukan kapasitas yang sudah dibuktikan oleh starter.

Untuk AI dan dispatch, kualitas juga diuji: precision/recall per jenis anomali, false alerts per vehicle-day, assignment feasibility, missed constraints, accepted recommendations, cost per completed job, dan override manusia. Ukuran keberhasilan adalah dampak operasi dengan bukti, bukan banyaknya agent atau bahasa.

## 10. Standar delivery dan ADR

Toolchain/dependency dipin dan diperbarui melalui PR terukur; gunakan supported release yang lulus CI, bukan label “latest” tanpa kompatibilitas. Go `gofmt`/vet/tests/race, Rust fmt/clippy/tests/fuzz target, Python lint/type checks/tests, C/C++ warnings/static analysis/host sanitizers menjadi gate sesuai komponen yang benar-benar ada. Jangan menambahkan test kosong hanya untuk badge.

Secret scanning, dependency/license review, SBOM, signed release artifact bila deployment mendukung, dan least-privilege runtime menjadi bagian pipeline. Traces mengikuti request/event/job, tetapi metric label tidak memuat setiap VIN/IMEI/coordinate karena cardinality dan privasi. Log tidak berisi token, raw voice, atau lokasi massal secara default.

ADR awal yang harus diputuskan beserta alasan dan acceptance evidence:

1. Go modular core dan aturan kapan modul diekstrak.
2. PostgreSQL/PostGIS ownership, tenant isolation, telemetry partition/retention, durable dedup.
3. Rust ingress protocol pertama dan dukungan autentikasi/TLS tracker.
4. Outbox awal dan gate adopsi NATS JetStream.
5. Event-time ordering, late data, watermark, reprocessing, dan aturan alert historis.
6. Dispatch objective/constraints, ETA provider limits, solver deadline, stale-plan invalidation.
7. Python agent tool permissions, human approval boundaries, eval dataset dan cost budget.
8. C/C++/Rust embedded target, memory policy, OTA/recovery, dan safety exclusions.
9. SLO, kapasitas yang diuji, backup/restore, retention, dan escalation runbook.

Setiap ADR berisi konteks, pilihan, keputusan, konsekuensi, owner, tanggal, dan kondisi untuk meninjau ulang. Kualitas engineering RevTrack harus dapat dibuktikan melalui invariant, test, observability, incident learning, dan kemampuan tim merawat sistem—tanpa klaim afiliasi atau standar internal perusahaan teknologi lain yang tidak dapat diverifikasi.
