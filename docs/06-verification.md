# Catatan verifikasi RevTrack

Catatan ini membedakan pemeriksaan software lokal dengan validasi produksi dan kendaraan fisik. Data workspace adalah simulasi. Diperbarui 2 Oktober 2026.

## Hasil pemeriksaan

| Pemeriksaan | Hasil saat ini |
|---|---|
| Go API: `go test -race ./...` | Lulus pada pemeriksaan ulang: 20 fungsi test, mencakup isolasi tenant, replay, persistence, rental/maintenance, report dan CSV |
| Go API: `go vet ./...` | Lulus pada pemeriksaan ulang |
| Smoke HTTP API | Flow fleet, telemetry, assignment, alert, rental→return, work order→complete serta persistence restart telah diperiksa |
| Launcher Python | Help lulus pada Python 3.14.8; mode native sudah dijalankan dengan Go API, simulator fleet dan Android `emulator-5554`; API health HTTP 200 |
| Flutter `analyze` dan tests | Analyze: tidak ada isu. Sebelas tests lulus: tujuh widget tests termasuk layout ponsel 390×844/peta/Operasi, empat tests data/API |
| Android APK build | Lulus `flutter build apk --debug --dart-define-from-file=../../.local/mobile.json`; APK lokal di `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk` |
| Android emulator/perangkat runtime | Aplikasi dibuka pada Pixel_10_Pro, Android 17/API 37 arm64 dengan page size 16 KB; dashboard dan peta Mapbox native dirender. Ini smoke test startup, bukan pemeriksaan semua workflow native |
| iOS build | Belum dijalankan: Xcode lengkap belum terpasang; CocoaPods 1.17.0 sudah tersedia dan halaman Xcode App Store sudah dibuka |
| Flutter web build | Lulus setelah upgrade Flutter dan Mapbox; verifikasi browser lama tidak diklaim sebagai pengujian ulang semua interaksi web |
| Mapbox browser | Style, tiles dan marker asli sudah diamati pada QA; bukan verifikasi SDK Android/iOS |
| PostgreSQL/PostGIS migration | Belum dijalankan; service demo memakai snapshot JSON, bukan SQL |
| GitHub Actions | Workflow Go/Flutter disediakan dengan referensi action SHA; hasil CI remote belum diklaim |

## Yang diuji dan maknanya

Backend menjaga pemisahan kredensial pengguna/perangkat, binding tenant/device server-side, batas payload, validasi telemetry, ring history terbatas, penolakan replay/out-of-order, unknown sensor, konflik assignment, interval booking, return, service, audit dan ekspor tenant. Race tests memeriksa akses concurrent yang dicakup pengujian; bukan benchmark kapasitas 10.000 unit.

Snapshot lokal memakai file private dan atomic rename untuk satu proses. Pengujian restart/rollback tidak membuktikan failover, enkripsi-at-rest aplikasi atau recovery power loss produksi. Reports menyimpulkan sampel tersimpan, tidak mengklaim trip lengkap, kWh/consumption atau pembuktian fraud.

Toolchain diperbarui ke Flutter 3.47.6/Dart 3.13.5, JDK 27, AGP 9.4.1, Gradle 9.8.0, Kotlin 2.4.20, Mapbox Flutter 3.0.0, serta compile/target SDK 37. Backend diuji dengan Go 1.27.1. Gradle Wrapper juga diregenerasi. Terminal zsh/bash baru memakai JDK, Go dan Python Homebrew; konfigurasi Flutter menunjuk JDK 27.

Kegagalan awal `Failed to exec spawn helper` direproduksi: daemon Java 21 masih berjalan setelah JDK bawaan Android Studio diperbarui ke Java 25. Daemon lama dihentikan, kemudian toolchain diperbarui bersama. Gradle 9.8 mendukung JDK 27 menurut [matriks resmi](https://docs.gradle.org/current/userguide/compatibility.html).

Flutter Gradle Plugin tetap memerlukan `android.newDsl=false`; `android.builtInKotlin=true` sudah aktif dan plugin Kotlin Android tidak diterapkan pada modul aplikasi. Build dapat menampilkan peringatan KGP untuk `mapbox_maps_flutter_mobile`: pemeriksa Flutter membaca script melalui regex, termasuk deklarasi plugin di dalam kondisi AGP < 9; Mapbox melewati penerapan plugin tersebut pada AGP 9. Analyzer bersih setelah migrasi pemanggilan API style Mapbox 3.0. Dua dependency transitif (`material_color_utilities` dan `test_api`) tetap mengikuti versi yang dipin SDK Flutter. Build debug memakai signing development, bukan paket rilis toko.

## Belum tervalidasi

- GNSS dan CAN/SOC/fuel dari kendaraan nyata, setiap model/tahun/varian.
- Power cut, tow, jamming, reconnect storm, buffer hardware, OTA dan installer commissioning.
- Kontrol kendaraan/interkom: tidak ada endpoint atau koneksi aktuator/audio pada demo.
- Auth produksi, signing release, multi-tenant SaaS, load test, backup/restore cloud dan billing.
- AI generatif/agent execution: UI memakai analisis deterministik, tanpa model eksternal.
- Navigasi suara/offline Mapbox, katalog POI Indonesia lengkap, dan seluruh fitur Google Maps.
- Full workflow kontrak, deposit, inspeksi, invoice, settlement dan aplikasi driver/penumpang marketplace.

## Perintah untuk mengulang pemeriksaan

```bash
cd services/api
go test -race ./...
go vet ./...
cd ../../apps/mobile
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=../../.local/mobile.json
cd ../..
python3 scripts/dev.py --help
python3 scripts/dev.py --mobile <device-id>
```

Pemeriksaan fisik dan gerbang peluncuran dijelaskan di [pilot dan backlog](05-pilot-delivery.md) dan [IoT/security](02-iot-security.md). Tidak ada klaim kesiapan komersial sebelum gerbang tersebut lulus.
