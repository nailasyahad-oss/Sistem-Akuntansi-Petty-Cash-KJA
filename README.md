# Sistem Akuntansi Petty Cash KJA

[![Demo](https://img.shields.io/badge/Demo-Buka_Aplikasi-59171b)](https://nailasyahad-oss.github.io/Sistem-Akuntansi-Petty-Cash-KJA/frontend/)

**Coba demo:** https://nailasyahad-oss.github.io/Sistem-Akuntansi-Petty-Cash-KJA/frontend/

## Deskripsi

Aplikasi web untuk mengelola akun kas kecil, pengajuan pengisian dana, persetujuan Manager, pencatatan transaksi kas keluar (dengan kategori dan pemetaan Chart of Accounts), koreksi transaksi (void), kas opname, tutup buku bulanan, serta laporan dan ekspor. Data disimpan di Supabase PostgreSQL; akses data dibatasi oleh Row Level Security (RLS) dan fungsi database.

## Teknologi

- **Frontend:** HTML, CSS (`frontend/style.new.css`), dan JavaScript modular (`frontend/script.js` + modul pendukung).
- **Database & Auth:** Supabase PostgreSQL dan Supabase Auth (email/password).
- **Akses data:** Supabase JavaScript client v2 dari browser (`@supabase/supabase-js@2` via CDN).
- **Ekspor (lazy-load via CDN):** SheetJS `xlsx@0.18.5` (Excel) dan `jspdf@2.5.1` + `jspdf-autotable@3.5.3` (PDF). Pustaka dimuat saat aksi ekspor dan memerlukan koneksi internet.
- **Hosting demo:** GitHub Pages dari branch `main` (root).
- **Server lokal (opsional):** `backend/app.js` — server statis sederhana berbasis `node:http` (port 4173). Aplikasi juga dapat dibuka langsung dari `frontend/index.html`.

## Struktur Project

```text
project/
├── frontend/
│   ├── index.html            Halaman utama (login, workspace, dialog, toast)
│   ├── script.js             Logika utama (auth, state, render, CRUD/RPC, laporan, ekspor)
│   ├── account-minimum.js    UI Manager untuk mengubah batas saldo minimum akun
│   ├── coa-journal.js        Panel/aksi CoA & pemetaan kategori, dukungan jurnal
│   ├── void-transaction.js   Dialog pembatalan (void) transaksi
│   ├── style.new.css         Gaya aktif (maroon-cream), responsif
│   ├── style.css             CSS lama (tidak direferensi)
│   └── style.clean.css       CSS lama (tidak direferensi)
├── backend/
│   ├── schema.sql            Skema database lengkap (tabel, trigger, fungsi, view, RLS, grant)
│   └── app.js                Server statis Node.js (opsional, port 4173)
├── README.md                 Dokumentasi ini
└── Sistem Petty Cash KJA.pdf Panduan penggunaan (PDF)
```

File CSS lama (`style.css`, `style.clean.css`) tidak direferensi oleh `frontend/index.html`.

## Role Pengguna

| Role | Hak |
|---|---|
| **ADMIN** | Mengelola akun kas, kategori pengeluaran, pengajuan, transaksi kas keluar, kas opname, dan tutup buku. Dapat membatalkan transaksi (void). Dapat mengelola CoA/kategori sesuai fitur yang tersedia di UI. |
| **MANAGER** | Menyetujui/menolak pengajuan. Memantau dashboard, transaksi, laporan, kas opname, dan tutup buku (read-only pada menu tersebut). Dapat mengubah batas saldo minimum akun kas. |

Akun dibuat di Supabase Auth, lalu profil ditambahkan ke tabel `public.users` dengan kolom `role` bernilai `'ADMIN'` atau `'MANAGER'`. Dashboard hanya tampil setelah profil valid ditemukan.

## Entitas dan Relasi (ringkas)

| Tabel / objek | Fungsi |
|---|---|
| `users` | Profil pengguna (`id` FK ke `auth.users`, `role`). |
| `petty_cash_accounts` | Akun kas kecil; saldo awal (Rp0), `min_balance`, status aktif. |
| `petty_cash_requests` | Pengajuan pengisian dana; status `pending`/`approved`/`rejected`. |
| `petty_cash_transactions` | Transaksi kas keluar (`OUT`); kategori, referensi CoA, status `posted`/`void`, metadata void. |
| `expense_categories` | Kategori pengeluaran; dapat dipetakan ke akun CoA beban. |
| `chart_of_accounts` | Chart of Accounts (aset/liabilitas/ekuitas/pendapatan/beban). |
| `journal_entries` / `journal_details` | Jurnal append-only untuk pencatatan otomatis terkait kas kecil. |
| `cash_counts` | Kas opname (selisih fisik vs sistem); tidak mengubah saldo. |
| `monthly_closings` | Rekaman tutup buku bulanan per akun. |

**Fungsi/trigger penting (contoh):** `current_app_role()`, `review_petty_cash_request(...)` (RPC MANAGER), `void_petty_cash_transaction(...)` (RPC ADMIN), trigger validasi transaksi/saldo, trigger proteksi nominal transaksi (koreksi melalui void), trigger/logic auto-journaling dan pemetaan CoA transaksi.

**View laporan:** `transaction_details`, `category_summary`, `account_transaction_summary` (digunakan untuk kebutuhan laporan/filter).

## Alur Kerja

```
1. Login (email/password) → verifikasi profil & role di public.users
2. Dashboard → saldo, peringatan batas minimum, ringkasan kas masuk/keluar, aktivitas terbaru
3. ADMIN membuat pengajuan → pilih akun, tujuan, nominal → status pending
4. MANAGER menyetujui/menolak via review_petty_cash_request (RPC)
   - Disetujui = saldo akun bertambah (melalui perhitungan berbasis request approved)
   - Ditolak = saldo tidak berubah (alasan wajib)
5. ADMIN mencatat transaksi kas keluar (OUT): akun, tanggal, kategori, uraian, nominal
   - Kategori wajib/terpetakan sesuai aturan aplikasi & schema
   - Saldo tidak cukup → ditolak oleh trigger validasi saldo
6. Koreksi: ADMIN membatalkan transaksi (void) dengan alasan (min. 5 karakter)
   - Transaksi void dikecualikan dari saldo/laporan; nominal transaksi tidak diubah
7. ADMIN mencatat kas opname → selisih fisik vs sistem (tidak mengubah saldo)
8. ADMIN menutup buku bulanan per akun → rekam ringkasan bulan (terkunci di UI)
9. Laporan → Ringkasan bulanan, Buku kas, Rekap, Ekspor (Excel/PDF)
10. Logout
```

## Fitur Utama

### Login & Peran
- Autentikasi Supabase Auth (email/password).
- UI dan aksi dibatasi berdasarkan role (`ADMIN`/`MANAGER`) dan kebijakan RLS/RPC di database.

### Dashboard
- Metrik: total saldo seluruh akun, pengajuan menunggu, total kas masuk/keluar.
- Peringatan jika saldo akun di bawah `min_balance`.
- Pengajuan terbaru dan transaksi terakhir.

### Akun Kas
- ADMIN dapat menambah/mengelola akun kas (saldo awal akun baru Rp0).
- MANAGER dapat mengubah batas saldo minimum akun (aksi tersedia di halaman Akun kas).

### Pengajuan & Persetujuan
- ADMIN membuat pengajuan ke akun kas.
- MANAGER menyetujui/menolak (penolakan memerlukan alasan).
- Persetujuan memengaruhi saldo melalui request berstatus `approved`.

### Transaksi Kas Keluar, Kategori, dan Jurnal
- Pencatatan transaksi hanya untuk kas keluar (`OUT`).
- Transaksi memilih akun kas dan kategori pengeluaran.
- Kategori dapat dipetakan ke akun CoA beban; aplikasi menampilkan informasi jurnal (D/K) pada tabel transaksi sesuai data yang tersedia.
- Validasi saldo mencegah pengeluaran melebihi saldo.

### Koreksi Transaksi (Void)
- ADMIN membatalkan transaksi melalui dialog pembatalan (alasan wajib, minimal 5 karakter).
- Transaksi void ditandai di UI dan dikecualikan dari perhitungan saldo/laporan.
- Transaksi yang sudah dicatat tidak diedit/hapus sebagai koreksi nominal; koreksi dilakukan lewat void sesuai aturan sistem.

### Kas Opname
- ADMIN mencatat saldo sistem, uang fisik, selisih, dan keterangan.
- Bersifat pencatatan (tidak mengubah saldo). Riwayat tidak diubah/dihapus melalui UI.

### Tutup Buku Bulanan
- ADMIN menutup buku per akun per bulan (saldo awal, total masuk/keluar, penyesuaian, saldo akhir).
- Rekaman yang sudah ditutup ditampilkan sebagai riwayat/terkunci di UI.

### Laporan
- **Ringkasan:** ringkasan bulanan (kas masuk/keluar periode, saldo seluruh akun, rincian aktivitas).
- **Buku kas:** memuat data dari server; tampilan harian/bulanan, filter rentang tanggal/akun/pembuat/kategori, saldo berjalan.
- **Rekap:** rekap per kategori dan per akun.
- **Ekspor:** ekspor ke Excel (`.xlsx`) atau PDF berdasarkan data/filter yang dimuat. Ekspor memerlukan koneksi internet (CDN).

## Cara Menjalankan

### Opsi Cepat (Demo)
Buka: **https://nailasyahad-oss.github.io/Sistem-Akuntansi-Petty-Cash-KJA/frontend/**  
Memerlukan koneksi internet dan akun yang disediakan administrator sistem.

### Setup Sendiri (Self-Host)

#### 1. Setup Supabase
1. Buat project di [Supabase](https://supabase.com).
2. Buka **SQL Editor** dan jalankan isi `backend/schema.sql` (dirancang idempoten: `IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP ... IF EXISTS`).
3. Pastikan tabel, fungsi, trigger, view, dan RLS terpasang.

#### 2. Konfigurasi Frontend
Di `frontend/script.js`, set nilai:
```js
const SUPABASE_URL = 'https://YOUR_PROJECT_REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```
Ambil dari **Project Settings → API** di dashboard Supabase. Gunakan hanya **anon/publishable key** di frontend; jangan pernah menaruh `service_role` key di frontend.

#### 3. Buat Pengguna & Role
1. Di **Authentication → Users**, buat akun (email/password).
2. Di **SQL Editor**, tambahkan profil:
   ```sql
   insert into public.users (id, full_name, role)
   values ('USER_AUTH_UUID', 'Nama Lengkap', 'ADMIN');
   ```
3. Ulangi untuk Manager dengan role `'MANAGER'`.

> README tidak berisi kredensial akses.

#### 4. Buka Aplikasi
- Buka `frontend/index.html` di browser, **atau**
- Jalankan server lokal:
  ```bash
  node backend/app.js
  ```
  lalu buka `http://127.0.0.1:4173`.

> Ekspor Excel/PDF membutuhkan koneksi internet untuk memuat pustaka CDN.

#### 5. Deploy ke GitHub Pages
1. Commit perubahan ke branch `main`.
2. Repo GitHub → **Settings → Pages** → branch `main`, folder `/ (root)`.
3. Demo akan tersedia di URL GitHub Pages repo.

## Catatan untuk Pemilik Database

### Database demo online
Jika demo terhubung ke project Supabase yang sama dengan `frontend/script.js`, **jangan menjalankan SQL percobaan/migrasi eksploratif pada database demo**. Uji perubahan pada project/staging terpisah.

### Perubahan skema
- `backend/schema.sql` ditujukan aman dijalankan ulang (idempoten).
- **Backup database** sebelum perubahan struktural.
- Periksa komentar verifikasi saldo di `backend/schema.sql` bila menambah kolom/trigger yang terkait saldo.

### Tutup buku
Pembukaan kembali periode tutup buku tidak disediakan di UI. Jika diperlukan, lakukan perubahan terkontrol via SQL dengan pemahaman dampaknya.

### Void
- Void dilakukan melalui mekanisme aplikasi/RPC dengan alasan.
- Koreksi manual langsung di database berisiko merusak jejak audit/jurnal; hindari kecuali pemeliharaan darurat oleh pemilik database.

## Panduan Kontribusi

- Jangan menghapus data historis di database; perubahan skema sebaiknya bersifat aditif/aman.
- Kerjakan fitur per tahap dan commit terpisah.
- Format commit yang disarankan: `Tahap N: <deskripsi>`, `style: <deskripsi>`, `fix: <deskripsi>`.

## Status Pengembangan

| Area | Status |
|---|---|
| Akun kas & batas saldo minimum | Tersedia |
| Pengajuan & persetujuan Manager | Tersedia |
| Transaksi kas keluar, kategori, validasi saldo | Tersedia |
| Chart of Accounts & auto-journaling (sesuai schema/UI saat ini) | Tersedia |
| Void/koreksi transaksi | Tersedia |
| Kas opname | Tersedia |
| Tutup buku bulanan | Tersedia |
| Laporan (Ringkasan/Buku kas/Rekap) & ekspor Excel/PDF | Tersedia |
