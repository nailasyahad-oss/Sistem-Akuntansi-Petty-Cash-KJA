-- Sistem Akuntansi Petty Cash KJA
-- Tahap 1: batas saldo minimum akun kas kecil.
-- Jalankan query VERIFIKASI SEBELUM sebelum migrasi, simpan hasilnya,
-- lalu jalankan migrasi ini dan bandingkan dengan query SESUDAH.
-- Migrasi ini hanya menambah kolom; tidak mengubah saldo maupun RLS lama.

-- VERIFIKASI SEBELUM MIGRASI
select
  a.id as account_id,
  a.name as nama_akun,
  coalesce(a.initial_balance, 0)
    + coalesce((
      select sum(r.requested_amount)
      from public.petty_cash_requests r
      where r.account_id = a.id and r.status = 'approved'
    ), 0)
    - coalesce((
      select sum(t.amount)
      from public.petty_cash_transactions t
      where t.account_id = a.id and t.transaction_type = 'OUT'
    ), 0) as saldo_kas
from public.petty_cash_accounts a
order by a.name;

-- TAHAP 1: DEFAULT 0 memberi semua akun lama batas awal Rp0;
-- batas minimum tidak boleh bernilai negatif.
alter table public.petty_cash_accounts
  add column if not exists min_balance numeric(14, 2) not null default 0
  check (min_balance >= 0);

-- VERIFIKASI SESUDAH MIGRASI
-- Hasil account_id, nama_akun, dan saldo_kas harus sama dengan hasil sebelum.
select
  a.id as account_id,
  a.name as nama_akun,
  coalesce(a.initial_balance, 0)
    + coalesce((
      select sum(r.requested_amount)
      from public.petty_cash_requests r
      where r.account_id = a.id and r.status = 'approved'
    ), 0)
    - coalesce((
      select sum(t.amount)
      from public.petty_cash_transactions t
      where t.account_id = a.id and t.transaction_type = 'OUT'
    ), 0) as saldo_kas
from public.petty_cash_accounts a
order by a.name;