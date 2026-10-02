# Skema database RevTrack

`migrations/001_foundation.sql` adalah **fondasi target PostgreSQL + PostGIS**, belum tersambung ke API demo Go. Demo menggunakan ring buffer dan opsional snapshot JSON. ID demo seperti `veh-001` adalah fixture; database memakai UUID.

Migrasi menyediakan 16 tabel: tenant, membership, vehicle, driver, assignment, device, installation, session perangkat, telemetry, latest position, geofence, relasi geofence-unit, alert, audit, proposal AI, dan outbox. Rental, customer, trip summary, energy session, maintenance, invoice, pembayaran dan modul komersial pada ERD masih rancangan lanjutan.

Prasyarat: PostgreSQL 18 atau versi kompatibel yang diuji tim, extension PostGIS dan `btree_gist`. Jalankan hanya pada **database pengembangan kosong** menggunakan migration role:

```sh
psql "$REVTRACK_DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/001_foundation.sql
```

Tidak ada `DROP`, runtime grant, seed pribadi, ataupun database connection otomatis. Migrasi satu kali memakai schema `revtrack`; rerun terhadap schema yang sudah ada akan gagal dan rollback. Belum dilakukan integration test PostgreSQL/PostGIS di sesi awal ini karena extension PostGIS tidak tersedia di lingkungan kerja. Sebelum pilot, jalankan migrasi dan tes RLS, foreign key lintas tenant, overlapping assignment, replay constraint, spatial boundary serta restore backup pada database disposable.

Runtime role wajib `NOSUPERUSER NOBYPASSRLS`, bukan pemilik schema. Beri izin per tabel/aksi; audit dan raw telemetry tidak boleh mendapat `UPDATE`/`DELETE` dari API biasa. Membership + RBAC/ABAC diputuskan server; policy RLS hanya menjadi lapisan tambahan untuk batas tenant. Gunakan transaksi per request:

```sql
BEGIN;
-- $1 berasal dari membership yang diverifikasi server, bukan payload pengguna.
SELECT set_config('app.tenant_id', $1, true);
SELECT * FROM revtrack.vehicles ORDER BY id LIMIT 100;
COMMIT;
```

Semua referensi domain membawa `tenant_id`. Foreign key mengikat telemetry ke **installation + device + vehicle** yang sama, dan session perangkat yang sama. Service tetap wajib memvalidasi waktu pemasangan dan masa berlaku session: FK tidak menegakkan interval bisnis tersebut. `vehicle_latest` diperbarui dengan compare-and-set timestamp/cursor; constraint FK sendiri tidak mencegah rollback waktu.

Simpan telemetry lama secara sah ke history; jangan menurunkan cursor/latest. Sebelum partisi bulanan, desain ulang deduplikasi global: PostgreSQL membatasi unique constraint tabel partitioned agar mencakup partition key. Pilihan: dedup ledger ber-retensi berdasarkan `(tenant, device, session, sequence)` terpisah dari partisi telemetry. Jangan sekadar menambahkan `PARTITION BY` dan kehilangan sifat idempoten. Lihat [PostgreSQL partitioning limitations](https://www.postgresql.org/docs/current/ddl-partitioning.html#DDL-PARTITIONING-DECLARATIVE-LIMITATIONS).

Retensi diusulkan (keputusan produk/privasi, bukan kewajiban universal): raw telemetry hot 30–90 hari, aggregate lebih lama sesuai kontrak, evidence insiden sesuai legal hold. Database operasional tidak menggantikan append-only audit archive terenkripsi dengan kontrol akses terpisah.
