-- Rollback Tahap 1 saja: hapus kolom batas saldo minimum yang ditambahkan.
-- Nilai min_balance yang sudah diatur akan ikut terhapus. Saldo kas lama
-- (saldo awal + pengajuan approved - transaksi OUT) tidak berubah.
alter table public.petty_cash_accounts
  drop column if exists min_balance;