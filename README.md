# Sistem Akuntansi Petty Cash KJA

## Deskripsi

Aplikasi web untuk mengelola akun kas kecil, pengajuan pengisian dana, persetujuan Manager, pencatatan pengeluaran, saldo, dan laporan sederhana. Data aplikasi disimpan di Supabase dan akses tabel dilindungi dengan Row Level Security (RLS).

## Teknologi

- Frontend: HTML, CSS, dan JavaScript.
- Database dan autentikasi: Supabase PostgreSQL dan Supabase Auth.
- Akses data: Supabase JavaScript client v2 dari browser, dengan kebijakan RLS.
- Server web: `backend/app.js` memakai modul bawaan Node.js untuk menyajikan file frontend.

## Struktur Folder

```text
project/
├── frontend/
│   ├── index.html
│   ├── style.css
│   └── script.js
├── backend/
│   ├── app.js
│   └── sql/
│       └── schema.sql
└── README.md
```

## Role Pengguna

- **ADMIN** mengelola akun kas kecil, membuat dan mengubah pengajuan yang masih pending, serta mencatat dan mengelola transaksi kas keluar.
- **MANAGER** melihat data pengajuan, menyetujui atau menolak pengajuan, dan memantau saldo, transaksi, serta laporan.

Pengguna harus memiliki akun di Supabase Auth dan profil dengan role yang sesuai di `public.users`. Aplikasi hanya menampilkan dashboard setelah autentikasi berhasil.

## Entitas dan Relasi

Database aplikasi menggunakan empat tabel:

| Entitas | Fungsi |
| --- | --- |
| `users` | Profil pengguna dan role `ADMIN` atau `MANAGER`; ID merujuk ke `auth.users` Supabase. |
| `petty_cash_accounts` | Akun kas kecil, saldo awal, dan status aktif. |
| `petty_cash_requests` | Pengajuan pengisian kas, akun tujuan, nominal, status, dan informasi review. |
| `petty_cash_transactions` | Pencatatan transaksi kas keluar. |

Relasi berdasarkan foreign key:

- `users.id` → `petty_cash_requests.requester_id`: satu pengguna dapat membuat banyak pengajuan.
- `users.id` → `petty_cash_requests.reviewed_by`: pengguna yang mereview pengajuan.
- `users.id` → `petty_cash_accounts.created_by`: pengguna yang membuat akun.
- `users.id` → `petty_cash_transactions.created_by`: pengguna yang mencatat transaksi.
- `petty_cash_accounts.id` → `petty_cash_requests.account_id`: setiap pengajuan baru memilih akun tujuan.
- `petty_cash_accounts.id` → `petty_cash_transactions.account_id`: transaksi keluar dicatat pada satu akun kas.
- `petty_cash_requests.id` → `petty_cash_transactions.request_id`: foreign key opsional di database; form transaksi saat ini tidak mengisi relasi ini.

Tidak ada tabel aplikasi tambahan. `auth.users` adalah tabel autentikasi milik Supabase.

## Alur Sistem

1. Pengguna masuk menggunakan email dan kata sandi Supabase Auth.
2. Aplikasi memeriksa profil dan role pengguna pada `public.users`.
3. Dashboard dan menu ditampilkan untuk Admin atau Manager.
4. Data akun, pengajuan, transaksi, dan laporan dimuat dari Supabase sesuai kebijakan RLS.
5. Pengguna keluar melalui tombol logout.

## Pengajuan dan Approval

1. Admin memilih akun kas tujuan, mengisi tujuan pengisian dan nominal, lalu membuat pengajuan.
2. Pengajuan baru berstatus `pending` dan belum memengaruhi saldo.
3. Manager memproses pengajuan melalui fungsi database `review_petty_cash_request`.
4. Jika disetujui, nominal pengajuan menambah saldo akun tujuan. Jika ditolak, saldo tidak berubah dan alasan penolakan wajib diisi.
5. Saldo pengajuan dihitung menggunakan status `approved`, bukan dibuat sebagai transaksi kas masuk.

## Transaksi Kas Keluar

Admin mencatat pengeluaran dengan memilih akun, tanggal, uraian, dan nominal. Form hanya menyediakan data kas keluar. Database juga membatasi transaksi baru agar `transaction_type` bernilai `OUT`. Pengisian atau replenishment kas tidak dicatat di menu transaksi.

## Perhitungan Saldo

Untuk setiap akun:

```text
Saldo = saldo awal akun
      + total pengajuan approved untuk akun tersebut
      - total transaksi kas keluar pada akun tersebut
```

Akun baru dibuat dengan saldo awal Rp0. Saldo awal akun yang sudah ada tetap dipertahankan; trigger database mencegah saldo awal akun diubah atau akun baru diberi saldo nonzero. Dana tambahan harus melalui pengajuan dan approval.

## Aturan Bisnis Utama

- Hanya Admin yang dapat membuat dan mengelola data operasional.
- Hanya Manager yang dapat memproses approval atau penolakan; penolakan memerlukan alasan.
- Pengajuan harus memiliki akun tujuan. Pengajuan `pending` atau `rejected` tidak menambah saldo.
- Semua kas masuk, termasuk pengisian awal dan replenishment, dicatat melalui pengajuan yang disetujui.
- Menu transaksi hanya untuk kas keluar; database menolak transaksi kas masuk baru.
- Akun baru dimulai dengan saldo Rp0 dan saldo awal yang ada tidak dapat diubah lewat aplikasi.
- RLS membatasi akses data berdasarkan autentikasi dan role di database, bukan hanya dari tampilan frontend.