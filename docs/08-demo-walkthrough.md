# Menjalankan dan menunjukkan RevTrack

RevTrack adalah aplikasi **mobile Flutter Android/iOS** dengan backend Go. Launcher menyiapkan API, persistence JSON dan simulator tracker, lalu menjalankan aplikasi native di perangkat yang dipilih. Seluruh kendaraan, driver, energi dan transaksi contoh adalah **data simulasi**, bukan armada pelanggan.

## Jalankan aplikasi ponsel

Prasyarat: Flutter, Go 1.25+, Python 3, Android SDK dan platform-tools; untuk iOS diperlukan Xcode lengkap. Dari root:

```bash
cd apps/mobile
flutter pub get
cd ../..
flutter devices
python3 scripts/dev.py --mobile <device-id>
```

Contoh emulator pada mesin pengembangan:

```bash
flutter emulators --launch Pixel_10_Pro
python3 scripts/dev.py --mobile emulator-5554
```

Gunakan ID persis dari `flutter devices`, bukan nama tampilan. Android emulator atau ponsel Android terhubung USB menggunakan `adb reverse tcp:8080 tcp:8080` yang diatur launcher untuk perangkat itu saja. API tetap bind loopback laptop; debug Android mengizinkan HTTP development. iOS simulator dapat memakai loopback. Launcher menolak iPhone fisik pada mode lokal ini karena memerlukan signing dan API development HTTPS tersendiri.

Pengujian runtime emulator/perangkat diserahkan kepada Anda sesuai permintaan. Perintah di atas adalah panduan pengujian manual; hasil build dan pemeriksaan software dicatat terpisah dari pengujian native Mapbox.

Launcher membangun Go API/simulator, membuat token demo lokal, dan memanggil `flutter run` dengan konfigurasi file. Token perangkat hanya diberikan ke backend/simulator, tidak ke aplikasi. Ctrl-C menghentikan proses milik launcher; log API/simulator berada di `.local/`. Restart mempertahankan state `.local/fleet-state.json`. `--no-simulator` mempertahankan posisi statis. Port terpakai ditolak tanpa menghentikan server lain.

Untuk sesi demo baru tanpa menghapus snapshot sebelumnya, pilih file lain:

```bash
REVTRACK_DATA_FILE="$PWD/.local/fleet-state-manual.json" \
  python3 scripts/dev.py --mobile emulator-5554
```

Jalankan dari root repo. Gunakan satu proses API per snapshot; file ini hanya berisi data demo.

## Konfigurasi Mapbox

Simpan public token `pk.` pada `.local/mobile.json` sebagai `MAPBOX_ACCESS_TOKEN`. `MAPBOX_STYLE_URI` boleh menggunakan style akun Anda atau `mapbox://styles/mapbox/standard`. Launcher membuat file ini jika belum ada dan mempertahankan nilai Mapbox yang sudah diisi. Gunakan editor agar token tidak masuk riwayat command. Jangan memasukkan secret token `sk.`. `.local/` diabaikan Git dan konfigurasi lokal diberi permission `0600`.

Dengan token valid, aplikasi native memakai Mapbox SDK. Tanpa token, peta skematik diberi label demo. Attribution Mapbox tetap terlihat. Public token dan token **demo lokal** berada dalam app binary; konfigurasi ini bukan kredensial release produksi.

## Alur presentasi mobile

1. Buka Ringkasan: lihat jumlah unit, peringatan, peta, unit terpilih dan indikator data simulasi.
2. Sentuh marker BYD. Simulator mengubah posisi unit ini; timestamp dan grafik membaca sampel server.
3. Sentuh Buka peta: coba jalan/satelit, tilt 3D, layer lalu lintas, titik tujuan contoh dan preview rute/ETA. Pencarian memakai Geocoding untuk alamat/place Indonesia, bukan katalog POI lengkap Google Maps. Tidak ada navigasi suara saat ini.
4. Buka Armada, cari nopol/nama/driver, filter EV/bensin/diesel/offline, lalu buka detail unit.
5. Geser grafik energi/kecepatan untuk membaca sampel. Nilai yang tidak tersedia tampil `—`; umur data tetap terlihat.
6. Sentuh Atur pengemudi dan pilih driver bebas. Server menolak driver yang masih ditugaskan ke unit lain.
7. Buka Peringatan dan tandai kejadian ditinjau. Buka ulang aplikasi untuk memeriksa state dari backend; acknowledgement bukan penutupan insiden.
8. Buka Operasi → Rental, buat booking mulai sekarang lalu catat pengembalian. Booking bertumpuk ditolak server; booking masa depan tidak bisa langsung dikembalikan.
9. Buka Servis, buat dan selesaikan work order. Rental aktif/overdue memblokir servis; work order terbuka memblokir booking baru.
10. Buka Audit untuk melihat jejak perubahan, lalu Laporan untuk ringkasan status, rental/maintenance dan sampel telemetry. Pada native tombol Salin CSV menyalin ekspor ke clipboard.
11. Buka RevAI, pilih topik prioritas/energi/pengemudi atau ketik pertanyaan. Insight dihitung dengan aturan deterministik dari workspace; belum model generatif atau agen otonom produksi.

## Preview browser untuk QA tambahan

Aplikasi utama tetap Android/iOS. Preview browser tersedia untuk pemeriksaan layout dan interaksi tambahan:

```bash
python3 scripts/dev.py --web
```

Buka `http://127.0.0.1:7357`. Mapbox GL JS menampilkan peta ketika token valid. `--web --no-build` memakai build terakhir; bangun ulang bila kode/konfigurasi berubah. Ekspor CSV browser mengunduh file. Jangan mempublikasikan build preview ini sebagai layanan produksi.

## Batas sebelum rilis

Belum ada tracker fisik/CAN/OEM yang terhubung, voice/interkom, aktuator kendaraan, billing/payment/settlement, inspeksi lengkap, ataupun LLM eksternal. PostgreSQL/PostGIS merupakan skema fondasi yang belum dipakai service demo. Rust gateway, Python AI dan firmware C++/C tercakup dalam blueprint berikutnya.

Build store/komersial memerlukan auth pengguna OIDC/MFA, HTTPS, database produksi, signing, multi-tenant hardening, observability, backup/restore, pengujian perangkat nyata dan commissioning IoT. Hasil build/test yang benar-benar dijalankan tersedia di [catatan verifikasi](06-verification.md).
