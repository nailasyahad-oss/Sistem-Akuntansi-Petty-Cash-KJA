# Sistem Akuntansi Petty Cash KJA

## Deskripsi

Aplikasi web untuk mengelola akun kas kecil, pengajuan pengisian dana, persetujuan Manager, pencatatan transaksi kas keluar, kas opname, tutup buku bulanan, dan laporan. Data disimpan di Supabase PostgreSQL dan akses tabel dilindungi dengan Row Level Security (RLS).

## Teknologi

- **Frontend:** HTML, CSS (`style.new.css`), dan JavaScript (`script.js`).
- **Database & Auth:** Supabase PostgreSQL dan Supabase Auth (email/password).
- **Akses data:** Supabase JavaScript client v2 dari browser, dengan kebijakan RLS.
- **Ekspor (lazy-load via CDN):** SheetJS `xlsx@0.18.5` (Excel) dan `jspdf@2.5.1` + `jspdf-autotable@3.5.3` (PDF). Pustaka dimuat hanya ketika diekspor dan memerlukan koneksi internet.
- **Server lokal (opsional):** `app.js` — server statis sederhana berbasis modul `node:http`. Berguna bila ingin menghindari batasan `file://`, namun aplikasi juga dapat dibuka langsung via `file://`.

## Struktur Project

```text
project/
├── index.html          Halaman utama; login screen, workspace, dialog, toast
├── script.js           Logika aplikasi lengkap (autentikasi, state, render, RPC, ekspor)
├── style.new.css       Gaya maroon-cream, responsif
├── schema.sql          Skema database lengkap (tabel, trigger, fungsi, view, RLS, grant)
├── app.js             Server statik Node.js (opsional, port 4173)
├── README.md           Dokumentasi ini
└── Sistem Petty Cash KJA.pdf   Panduan penggunaan (PDF)
```

File lama `style.css` dan `style.clean.css` tidak dipakai lagi — tidak direferensi oleh `index.html`.

## Role Pengguna

| Role | Hak |
|---|---|
| **ADMIN** | Membuat/mengelola akun kas, kategori pengeluaran, pengajuan, transaksi, kas opname, dan tutup buku. Dapat membatalkan (void) transaksi. |
| **MANAGER** | Menyetujui/menolak pengajuan. Memantau saldo, transaksi, laporan, dan semua menu tampilan (read-only). |

Akun dibuat di Supabase Auth, kemudian profil ditambahkan secara manual ke tabel `public.users` dengan kolom `role` bernilai `'ADMIN'` atau `'MANAGER'`. Aplikasi menampilkan dashboard hanya setelah profil ditemukan.

## Entitas dan Relasi

| Tabel | Fungsi |
|---|---|
| `users` | Profil pengguna; `id` FK ke `auth.users`, kolom `role` (`ADMIN`/`MANAGER`). |
| `petty_cash_accounts` | Akun kas kecil; saldo awal (tetap Rp0), `min_balance`, status aktif. |
| `petty_cash_requests` | Pengajuan pengisian dana; status `pending`/`approved`/`rejected`. |
| `petty_cash_transactions` | Transaksi kas keluar (`transaction_type = 'OUT'`). Kolom void untuk koreksi. |
| `expense_categories` | Kategori pengeluaran (ATK, Transportasi, Konsumsi, dsb.). |
| `cash_counts` | Catatan kas opname (hanya mencatat selisih, tidak mengubah saldo). |
| `monthly_closings` | Rekaman tutup buku bulanan per akun. |

**Fungsi database (RPC):**

| Fungsi | Keterangan |
|---|---|
| `current_app_role()` | Mengembalikan role pengguna saat ini dari tabel `users`. |
| `review_petty_cash_request(id, decision, reason)` | Disetujui oleh MANAGER — atomic approve/reject. |
| `validate_petty_cash_transaction()` | Trigger — memastikan `transaction_type = 'OUT'`. |
| `validate_petty_cash_balance()` | Trigger — mencegah transaksi keluar melebihi saldo. |
| `void_petty_cash_transaction(id, reason)` | Disetujui oleh ADMIN — menandai transaksi sebagai `void` (bukan hapus/reversal). |

**View (Tahap 7):** `transaction_details`, `category_summary`, `account_transaction_summary`.

## Alur Kerja

```
1. Login (email/password) → verifikasi profil & role di public.users
2. Dashboard → lihat saldo, peringatan batas minimum, ringkasan masuk/keluar
3. ADMIN membuat pengajuan kas → nominal + alasan → status pending
4. MANAGER menyetujui/menolak via review_petty_cash_request (RPC)
   - Disetujui = saldo akun bertambah; ditolak = saldo tak berubah
5. ADMIN mencatat transaksi kas keluar (pilih akun, kategori, tanggal, uraian, nominal)
   - Bila saldo tidak cukup → ditolak; notifikasi saldo saat ini
6. ADMIN mencatat kas opname → mencatat selisih fisik vs sistem (tidak ubah saldo)
7. ADMIN menutup buku bulanan → rekam saldo akhir per akun per bulan (terkunci)
8. Laporan → pilih periode/akun/kategori/pembuat → buka buku kas / rekap
   → ekspor Excel (.xlsx) atau PDF
9. Koreksi: ADMIN bisa void transaksi (strikethrough + badge "VOID", dikecualikan dari saldo)
10. Logout
```

## Fitur Utama

### Login & Role
- Autentikasi via Supabase Auth (email/password).
- Role `ADMIN` atau `MANAGER` ditentukan oleh profil di `public.users`.
- `app.js` tidak menyimpan kredensial; semua akses melalui `SUPABASE_URL` dan `SUPABASE_ANON_KEY` di `script.js`.

### Dashboard
- Metric grid: total saldo semua akun, pengajuan menunggu, kas masuk, kas keluar.
- Peringatan saldo di bawah `min_balance`: jika saldo akun < minimum yang ditetapkan, muncul banner biru-krem.
- Transaksi terakhir dan pengajuan terbaru (maks 5).

### Pengajuan & Persetujuan
- ADMIN membuat pengajuan: pilih akun kas, isi tujuan, nominal. Status otomatis `pending`.
- Manager menyetujui/menolak lewat tombol di tabel (RPC `review_petty_cash_request`).
- Penolakan wajib sertakan alasan via prompt.
- Pengajuan yang disetujui bertambah saldo akun; yang ditolak tidak.

### Transaksi Kas Keluar
- Hanya tipe `OUT` yang bisa dicatat (dibatasi oleh trigger di DB).
- Wajib pilih akun kas dan kategori pengeluaran.
- Saldo tidak cukup → ditolak oleh trigger `validate_petty_cash_balance` di DB; notifikasi saldo saat ini muncul.

### Kategori Pengeluaran
- 6 kategori default: ATK, Transportasi, Konsumsi, Listrik & Air, Kebersihan, Lain-lain.
- ADMIN dapat menambah dan menonaktifkan kategori dari halaman Transaksi (panel kategori).

### Koreksi Transaksi (Void)
- ADMIN dapat membatalkan transaksi lewat tombol "Batalkan" → RPC `void_petty_cash_transaction`.
- Alasan wajib, minimal 5 karakter.
- Transaksi yang dibatalkan ditampilkan dengan strikethrough + badge "VOID"/"Dibatalkan".
- Transaksi void **dikecualikan** dari perhitungan saldo dan laporan.
- Nilai tidak bisa diedit atau dihapus — jejak audit tetap utuh.

### Kas Opname
- ADMIN mencatat hasil penghitungan fisik vs sistem.
- Hanya pencatatan: `difference = physical_amount - system_balance`.
- Riwayat tidak bisa diubah atau dihapus (hanya SELECT + INSERT via RLS).

### Tutup Buku Bulanan
- ADMIN menutup buku per akun per bulan — rekam `starting_balance`, `inflows`, `outflows`, `adjustment`, `ending_balance`.
- Bulan yang sudah ditutup terkunci; tidak ada tombol "buka kembali" di UI.
- Riwayat tutup buku hanya baca di UI.

### Ringkasan Laporan Bulanan
- Tab "Ringkasan" di menu Laporan: pilih bulan → total kas masuk/keluar dan saldo seluruh akun untuk bulan itu, plus tabel rincian aktivitas.

### Buku Kas
- Tab "Buku kas" di menu Laporan: muat data dari server, tampilkan sebagai tabel harian atau bulanan.
- Mode "Hari" (harian) atau "Bulan" (rilapan per bulan).
- Kolom: tanggal, uraian, kategori, masuk, keluar, jenis, saldo berjalan.
- Filter: rentang tanggal, akun, pembuat, kategori.

### Rekap
- Tab "Rekap": rekap pengeluaran per kategori dan per akun kas.
- Data otomatis dari hasil filter yang sudah dimuat.

### Ekspor
- Tab "Ekspor": export buku kas + rekap ke Excel (.xlsx) atau PDF.
- Pustaka dimuat lazy dari CDN: `xlsx@0.18.5`, `jspdf@2.5.1`, `jspdf-autotable@3.5.3`.
- Nama file: `buku-kas_${start}-${end}.{xlsx|pdf}` (sanitized).
- Perlu koneksi internet untuk memuat pustaka; jika offline, notifikasi error.

## Cara Menjalankan

### 1. Setup Supabase
1. Buat project di [supabase.com](https://supabase.com).
2. Buka **SQL Editor** dan jalankan isi `schema.sql` (aman dijalankan ulang — memakai `IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP ... IF EXISTS`).
3. Pastikan semua tabel, fungsi, trigger, view, dan kebijakan RLS terpasang.

### 2. Konfigurasi
Di `script.js`, ganti placeholder berikut:
```js
const SUPABASE_URL = 'SUPABASE_URL';
const SUPABASE_ANON_KEY = 'SUPABASE_ANON_KEY';
```
Dapatkan nilainya dari **Project Settings → API** di dashboard Supabase.

### 3. Buat Pengguna & Role
1. Di **Authentication → Users**, buat akun (email/password).
2. Di **SQL Editor**, masukkan profil:
   ```sql
   insert into public.users (id, full_name, role)
   values ('USER_AUTH_UUID', 'Nama Lengkap', 'ADMIN');
   ```
3. Ulangi untuk Manager dengan role `'MANAGER'`.

### 4. Buka Aplikasi
- Buka `index.html` langsung di browser (via `file://`), **atau**
- Jalankan `node app.js` di terminal, lalu buka `http://127.0.0.1:4173`.

> Ekspor Excel/PDF membutuhkan koneksi internet karena pustaka dimuat dari CDN.

## Catatan untuk Pemilik Database

### Menguplod perubahan skema
- `schema.sql` dirancang **idempoten** — aman dijalankan berulang kali.
- Selalu **backup database** sebelum menambah kolom atau trigger baru.
- Setelah menambah kolom (mis. Tahap 1 `min_balance`), jalankan kueri verifikasi di komentar `schema.sql` untuk memastikan saldo akun tidak berubah.

### Membuka kembali periode tutup buku
Aplikasi tidak menyediakan UI untuk membuka kembali periode yang sudah ditutup. Hanya melalui SQL langsung:

```sql
-- Hapus rekaman tutup buku untuk akun dan bulan tertentu
delete from public.monthly_closings
where account_id = 'ACCOUNT_UUID'
  and closing_month = '2025-01-01';  -- gunakan 01 di akhir bulan

-- Verifikasi
select * from public.monthly_closings where account_id = 'ACCOUNT_UUID';
```

> **Peringatan:** Hapus rekaman tutup buku hanya bila yakin saldo sudah tidak lagi dibutuhkan. Transaksi kas keluar pada bulan tersebut tetap ada dan tidak bisa dibatalkan.

### Void / reversal
- Transaksi yang sudah di-void tidak bisa di-void lagi (cek `status = 'posted'` pada WHERE clause).
- Untuk mengembalikan efek void, ubah status via SQL:
  ```sql
  update public.petty_cash_transactions
  set status = 'posted', void_reason = null, voided_by = null, voided_at = null
  where id = 'TRANSACTION_UUID' and status = 'void';
  ```

## Panduan Kontribusi

- Jangan menghapus data lama di database; semua perubahan skema harus **menambah** (kolom nullable, trigger baru).
- Setiap fitur dikerjakan per tahap, di-commit terpisah.
- Format commit: `Tahap N: <deskripsi>`, `style: <deskripsi>`, `fix: <deskripsi>`.

## Status Pengembangan

| Tahap | Fitur | Status |
|---|---|---|
| 1 | Batas saldo minimum (`min_balance`) + peringatan di dashboard | Selesai |
| 2 | Kategori pengeluaran + filter di transaksi | Selesai |
| 3 | Pencegahan saldo minus (trigger `validate_petty_cash_balance`) | Selesai |
| 4 | Koreksi transaksi via void (RPC `void_petty_cash_transaction`, kolom status/void_*) | Selesai |
| 5 | Kas opname (`cash_counts`, hanya mencatat selisih) | Selesai |
| 6 | Tutup buku bulanan (`monthly_closings`) | Selesai |
| 7 | Laporan: buku kas, rekap per kategori/akun, ekspor Excel/PDF | Selesai |
