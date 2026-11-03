-- Supabase PostgreSQL schema for Sistem Akuntansi Petty Cash KJA.
-- Core tables include users, petty_cash_accounts, petty_cash_requests,
-- petty_cash_transactions, expense_categories, cash_counts, monthly_closings,
-- chart_of_accounts, journal_entries, and journal_details.

create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role text not null check (role in ('ADMIN', 'MANAGER')),
  created_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select role from public.users where id = auth.uid()
$$;

revoke all on function public.current_app_role() from public, anon;
grant execute on function public.current_app_role() to authenticated;

create table if not exists public.petty_cash_accounts (
  id uuid primary key default gen_random_uuid(),
  account_code text not null unique,
  name text not null,
  initial_balance numeric(14, 2) not null default 0 check (initial_balance >= 0),
  is_active boolean not null default true,
  created_by uuid not null references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- [FITUR BARU] Tahap 1: Chart of Accounts standar KJA.
create table if not exists public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  type text not null check (type in ('ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.chart_of_accounts (code, name, type)
values
  ('1-1001', 'Kas Kecil', 'ASSET'),
  ('1-1002', 'Kas Bank', 'ASSET'),
  ('5-1001', 'Beban Perlengkapan', 'EXPENSE'),
  ('5-1002', 'Beban Transportasi', 'EXPENSE'),
  ('5-1003', 'Beban Operasional Lainnya', 'EXPENSE'),
  ('5-1004', 'Selisih Kas Kecil', 'EXPENSE')
on conflict (code) do nothing;

-- [FITUR BARU] Tahap 1: batas saldo minimum akun kas.
-- Addition is safe for populated databases: existing rows receive DEFAULT 0,
-- and no account, request, or transaction data is changed.
alter table public.petty_cash_accounts
  add column if not exists min_balance numeric(14, 2)
    not null default 0
    check (min_balance >= 0);

-- Verify before applying this block in the Supabase SQL Editor, then run the
-- block again after the schema is applied to confirm idempotency.
-- Query sebelum: bandingkan hasil saldo_kas untuk setiap akun.
/*
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
*/

-- Query sesudah: hasil account_id, nama_akun, dan saldo_kas harus identik
-- dengan hasil sebelum perubahan (kolom min_balance tidak mengubah saldo).
-- Lakukan query ini setelah mengeksekusi bagian "Tahap 1" di schema.sql.
/*
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
*/

create table if not exists public.petty_cash_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.users (id),
  account_id uuid not null references public.petty_cash_accounts (id),
  purpose text not null,
  requested_amount numeric(14, 2) not null check (requested_amount > 0),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references public.users (id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'pending' and reviewed_by is null and reviewed_at is null)
    or (status in ('approved', 'rejected') and reviewed_by is not null and reviewed_at is not null)
  )
);

create table if not exists public.petty_cash_transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.petty_cash_accounts (id),
  request_id uuid references public.petty_cash_requests (id),
  created_by uuid not null references public.users (id),
  transaction_type text not null default 'OUT',
  transaction_date date not null default current_date,
  description text not null,
  amount numeric(14, 2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint petty_cash_transactions_out_only check (transaction_type = 'OUT')
);

-- [FITUR BARU] Tahap 2: kategori pengeluaran.
-- Existing transactions remain category_id NULL and display "Tanpa kategori".
create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  coa_code text,
  coa_id uuid references public.chart_of_accounts (id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.expense_categories
  add column if not exists coa_id uuid references public.chart_of_accounts (id);

alter table public.petty_cash_transactions
  add column if not exists category_id uuid
    references public.expense_categories(id);

alter table public.petty_cash_transactions
  add column if not exists coa_id uuid
    references public.chart_of_accounts (id);

insert into public.expense_categories (name, coa_code, coa_id, is_active)
values
  ('ATK', 'ATK', (select id from public.chart_of_accounts where code = '5-1001'), true),
  ('Transportasi', 'TRANSPORTASI', (select id from public.chart_of_accounts where code = '5-1002'), true),
  ('Konsumsi', 'KONSUMSI', (select id from public.chart_of_accounts where code = '5-1003'), true),
  ('Listrik & Air', 'LISTRIK_AIR', (select id from public.chart_of_accounts where code = '5-1003'), true),
  ('Kebersihan', 'KEBERSIHAN', (select id from public.chart_of_accounts where code = '5-1003'), true),
  ('Lain-lain', 'LAIN', (select id from public.chart_of_accounts where code = '5-1003'), true)
on conflict (name) do nothing;

update public.expense_categories as category
set coa_id = coa.id
from (values
  ('ATK', '5-1001'),
  ('Transportasi', '5-1002'),
  ('Konsumsi', '5-1003'),
  ('Listrik & Air', '5-1003'),
  ('Kebersihan', '5-1003'),
  ('Lain-lain', '5-1003')
) as mapping(category_name, coa_code)
join public.chart_of_accounts as coa on coa.code = mapping.coa_code
where category.name = mapping.category_name
  and category.coa_id is null;

alter table public.chart_of_accounts enable row level security;
drop policy if exists chart_of_accounts_read_authenticated on public.chart_of_accounts;
drop policy if exists chart_of_accounts_insert_admin on public.chart_of_accounts;
drop policy if exists chart_of_accounts_update_admin on public.chart_of_accounts;
create policy chart_of_accounts_read_authenticated
  on public.chart_of_accounts for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
create policy chart_of_accounts_insert_admin
  on public.chart_of_accounts for insert to authenticated
  with check (public.current_app_role() = 'ADMIN');
create policy chart_of_accounts_update_admin
  on public.chart_of_accounts for update to authenticated
  using (public.current_app_role() = 'ADMIN')
  with check (public.current_app_role() = 'ADMIN');
grant select, insert, update on public.chart_of_accounts to authenticated;

alter table public.expense_categories enable row level security;

drop policy if exists expense_categories_read_authenticated on public.expense_categories;
drop policy if exists expense_categories_insert_admin on public.expense_categories;
drop policy if exists expense_categories_update_admin on public.expense_categories;

create policy expense_categories_read_authenticated
  on public.expense_categories for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
create policy expense_categories_insert_admin
  on public.expense_categories for insert to authenticated
  with check (public.current_app_role() = 'ADMIN');
create policy expense_categories_update_admin
  on public.expense_categories for update to authenticated
  using (public.current_app_role() = 'ADMIN')
  with check (public.current_app_role() = 'ADMIN');

grant select, insert, update on public.expense_categories to authenticated;

-- Existing databases receive a nullable column so existing requests are kept.
-- RLS requires an account on every new request; legacy requests can be edited
-- to assign their account before approval.
alter table public.petty_cash_requests
  add column if not exists account_id uuid references public.petty_cash_accounts (id);

update public.petty_cash_requests
set account_id = (select id from public.petty_cash_accounts limit 1)
where account_id is null
  and (select count(*) from public.petty_cash_accounts) = 1;

-- Keep historical IN rows intact, but reject new or modified IN transactions.
alter table public.petty_cash_transactions
  drop constraint if exists petty_cash_transactions_check;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.petty_cash_transactions'::regclass
      and conname = 'petty_cash_transactions_out_only'
  ) then
    alter table public.petty_cash_transactions
      add constraint petty_cash_transactions_out_only
      check (transaction_type = 'OUT') not valid;
  end if;
end;
$$;

create index if not exists petty_cash_requests_status_created_idx
  on public.petty_cash_requests (status, created_at desc);
create index if not exists petty_cash_requests_requester_idx
  on public.petty_cash_requests (requester_id, created_at desc);
create index if not exists petty_cash_transactions_account_date_idx
  on public.petty_cash_transactions (account_id, transaction_date desc);
create index if not exists petty_cash_transactions_request_idx
  on public.petty_cash_transactions (request_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists petty_cash_accounts_set_updated_at on public.petty_cash_accounts;
create trigger petty_cash_accounts_set_updated_at
before update on public.petty_cash_accounts
for each row execute function public.set_updated_at();

drop trigger if exists petty_cash_requests_set_updated_at on public.petty_cash_requests;
create trigger petty_cash_requests_set_updated_at
before update on public.petty_cash_requests
for each row execute function public.set_updated_at();

drop trigger if exists petty_cash_transactions_set_updated_at on public.petty_cash_transactions;
create trigger petty_cash_transactions_set_updated_at
before update on public.petty_cash_transactions
for each row execute function public.set_updated_at();

create or replace function public.protect_petty_cash_opening_balance()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' and new.initial_balance <> 0 then
    raise exception 'Saldo awal akun baru harus Rp0; gunakan pengajuan untuk pengisian kas';
  end if;

  if tg_op = 'UPDATE' and new.initial_balance is distinct from old.initial_balance then
    raise exception 'Saldo awal tidak dapat diubah; gunakan pengajuan untuk pengisian kas';
  end if;

  return new;
end;
$$;

drop trigger if exists petty_cash_accounts_protect_opening_balance on public.petty_cash_accounts;
create trigger petty_cash_accounts_protect_opening_balance
before insert or update on public.petty_cash_accounts
for each row execute function public.protect_petty_cash_opening_balance();

-- current_app_role() is defined before policies that reference it.

-- Approval is a single atomic operation; managers cannot edit request amounts
-- or assign themselves through a general-purpose table update.
create or replace function public.review_petty_cash_request(
  p_request_id uuid,
  p_decision text,
  p_rejection_reason text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null or public.current_app_role() <> 'MANAGER' then
    raise exception 'Akses hanya untuk MANAGER' using errcode = '42501';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'Keputusan tidak valid' using errcode = '22023';
  end if;

  if p_decision = 'rejected' and nullif(btrim(p_rejection_reason), '') is null then
    raise exception 'Alasan penolakan wajib diisi' using errcode = '22023';
  end if;

  update public.petty_cash_requests
  set status = p_decision,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      rejection_reason = case when p_decision = 'rejected' then btrim(p_rejection_reason) else null end
  where id = p_request_id
    and status = 'pending'
    and (p_decision = 'rejected' or account_id is not null);

  if not found then
    raise exception 'Pengajuan tidak ditemukan atau sudah diproses' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.review_petty_cash_request(uuid, text, text) from public, anon;
grant execute on function public.review_petty_cash_request(uuid, text, text) to authenticated;

-- Transactions are expense-only. Cash inflows are approved requests.
create or replace function public.validate_petty_cash_transaction()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.transaction_type is distinct from 'OUT' then
    raise exception 'Transaksi petty cash hanya boleh berupa kas keluar';
  end if;
  return new;
end;
$$;

drop trigger if exists petty_cash_transactions_validate_request on public.petty_cash_transactions;
create trigger petty_cash_transactions_validate_request
before insert or update on public.petty_cash_transactions
for each row execute function public.validate_petty_cash_transaction();

-- Stage 3: prevent an OUT transaction from driving cash below zero.
-- The account row is locked before the balance is calculated, preventing
-- concurrent transactions from both passing the same balance check.
create or replace function public.validate_petty_cash_balance()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_account_id uuid;
  current_balance numeric(14, 2);
begin
  select id
  into target_account_id
  from public.petty_cash_accounts
  where id = new.account_id
  for update;

  if tg_op = 'UPDATE' and old.account_id is distinct from new.account_id then
    select id
    from public.petty_cash_accounts
    where id = old.account_id
    for update;
  end if;

  select
    coalesce(a.initial_balance, 0)
      + coalesce((
        select sum(r.requested_amount)
        from public.petty_cash_requests r
        where r.account_id = a.id
          and r.status = 'approved'
      ), 0)
      - coalesce((
        select sum(t.amount)
        from public.petty_cash_transactions t
        where t.account_id = a.id
          and t.id is distinct from new.id
          and t.transaction_type = 'OUT'
      ), 0)
  into current_balance
  from public.petty_cash_accounts a
  where a.id = target_account_id;

  if current_balance - new.amount < 0 then
    raise exception
      'Saldo akun tidak mencukupi. Saldo saat ini Rp %',
      current_balance
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists petty_cash_transactions_validate_balance on public.petty_cash_transactions;
create trigger petty_cash_transactions_validate_balance
before insert or update on public.petty_cash_transactions
for each row execute function public.validate_petty_cash_balance();

-- [FITUR BARU] Tahap 4: koreksi transaksi (void/reversal).
-- Mekanisme yang dipilih: VOID (bukan reversal).
--
-- Alasan pemilihan void:
--   1. Rumus saldo saat ini: initial_balance + sum(approved_requests) - sum(OUT_posted).
--      Membatalkan transaksi OUT = mengecualikannya dari pengurangan sehingga
--      saldo selalu naik (atau tetap). Tidak pernah menyebabkan saldo minus.
--   2. Tidak menciptakan baris transaksi tambahan, menjaga jejak audit tetap
--      utuh dan tidak menambah kompleksitas rekonstruksi saldo.
--   3. Reversal (baris IN + ve) cocok bila sistem punya sisi DEBIT/KREDIT,
--      tetapi sistem ini hanya punya kas keluar (OUT), jadi void lebih bersih.
-- Kolom reversal_of disertakan (nullable, selalu NULL untuk void) untuk
-- kemungkinan penambahan mekanisme reversal di masa depan.
alter table public.petty_cash_transactions
  add column if not exists status text not null default 'posted'
    check (status in ('posted', 'void')),
  add column if not exists void_reason text,
  add column if not exists voided_by uuid references public.users (id),
  add column if not exists voided_at timestamptz,
  add column if not exists reversal_of uuid references public.petty_cash_transactions (id);

-- Semua transaksi existing otomatis dapat status 'posted' (DEFAULT),
-- sehingga perubahan ini tidak mengubah saldo akun yang ada.
-- Query verifikasi saldo sebelum dan sesudah harus identik:
--   SELECT a.id, a.name,
--     coalesce(a.initial_balance,0)
--     + coalesce((SELECT sum(r.requested_amount) FROM petty_cash_requests r
--                 WHERE r.account_id=a.id AND r.status='approved'),0)
--     - coalesce((SELECT sum(t.amount) FROM petty_cash_transactions t
--                 WHERE t.account_id=a.id AND t.transaction_type='OUT'
--                   AND t.status='posted'),0) AS saldo_kas
--   FROM petty_cash_accounts a ORDER BY a.name;

-- Perbarui trigger saldo agar mengecualikan transaksi void dari perhitungan.
-- Perilaku data existing tidak berubah karena semua transaksi existing = posted.
create or replace function public.validate_petty_cash_balance()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_account_id uuid;
  current_balance numeric(14, 2);
begin
  select id
  into target_account_id
  from public.petty_cash_accounts
  where id = new.account_id
  for update;

  if tg_op = 'UPDATE' and old.account_id is distinct from new.account_id then
    select id
    from public.petty_cash_accounts
    where id = old.account_id
    for update;
  end if;

  select
    coalesce(a.initial_balance, 0)
      + coalesce((
        select sum(r.requested_amount)
        from public.petty_cash_requests r
        where r.account_id = a.id
          and r.status = 'approved'
      ), 0)
      - coalesce((
        select sum(t.amount)
        from public.petty_cash_transactions t
        where t.account_id = a.id
          and t.id is distinct from new.id
          and t.transaction_type = 'OUT'
          and t.status = 'posted'
      ), 0)
  into current_balance
  from public.petty_cash_accounts a
  where a.id = target_account_id;

  if current_balance - new.amount < 0 then
    raise exception
      'Saldo akun tidak mencukupi. Saldo saat ini Rp %',
      current_balance
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists petty_cash_transactions_validate_balance on public.petty_cash_transactions;
create trigger petty_cash_transactions_validate_balance
before insert or update on public.petty_cash_transactions
for each row execute function public.validate_petty_cash_balance();

-- Prosedur void transaksi: hanya ADMIN, alasan wajib >= 5 karakter,
-- tidak bisa void ulang, dan tidak pernah membuat saldo minus.
-- Pengecekan periode tertutup (Tahap 6) akan ditambahkan pada trigger/fungsi ini nanti.
create or replace function public.void_petty_cash_transaction(
  p_transaction_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if public.current_app_role() <> 'ADMIN' then
    raise exception 'Akses ditolak. Hanya admin yang dapat membatalkan transaksi.' using errcode = '42501';
  end if;

  if nullif(btrim(p_reason), '') is null or length(btrim(p_reason)) < 5 then
    raise exception 'Alasan pembatalan wajib diisi minimal 5 karakter.' using errcode = '22023';
  end if;

  update public.petty_cash_transactions
  set status = 'void',
      void_reason = btrim(p_reason),
      voided_by = auth.uid(),
      voided_at = now()
  where id = p_transaction_id
    and status = 'posted';

  if not found then
    raise exception 'Transaksi tidak ditemukan atau sudah dibatalkan.' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.void_petty_cash_transaction(uuid, text) from public, anon;
grant execute on function public.void_petty_cash_transaction(uuid, text) to authenticated;

-- [FITUR BARU] Tahap 5: kas opname (pencatatan stok kas fisik).
-- Hanya MENCATAT: tidak mengubah saldo, tidak membuat transaksi otomatis.
-- Riwayat tidak bisa diubah atau dihapus (hanya SELECT + INSERT, tidak ada UPDATE/DELETE).
create table if not exists public.cash_counts (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.petty_cash_accounts (id),
  counted_at timestamptz not null default now(),
  system_balance numeric(14, 2) not null,
  physical_amount numeric(14, 2) not null check (physical_amount >= 0),
  difference numeric(14, 2) not null,
  notes text,
  created_by uuid not null references public.users (id),
  created_at timestamptz not null default now()
);

create index if not exists cash_counts_account_idx
  on public.cash_counts (account_id);
create index if not exists cash_counts_counted_at_idx
  on public.cash_counts (counted_at desc);

alter table public.cash_counts enable row level security;

drop policy if exists cash_counts_read_authenticated on public.cash_counts;
drop policy if exists cash_counts_insert_admin on public.cash_counts;

create policy cash_counts_read_authenticated
  on public.cash_counts for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
create policy cash_counts_insert_admin
  on public.cash_counts for insert to authenticated
  with check (public.current_app_role() = 'ADMIN' and created_by = auth.uid());

-- Hanya SELECT dan INSERT; riwayat kas opname tidak dapat diubah atau dihapus.
grant select, insert on public.cash_counts to authenticated;

-- [FITUR BARU] Tahap 6: tutup buku bulanan.
-- Rekam rekaman tutup buku per akun kas per bulan. Sekali disimpan — tidak ada UPDATE/DELETE.
create table if not exists public.monthly_closings (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.petty_cash_accounts (id),
  closing_month date not null,
  starting_balance numeric(14, 2) not null,
  total_inflows numeric(14, 2) not null default 0,
  total_outflows numeric(14, 2) not null default 0,
  adjustment numeric(14, 2) not null default 0,
  ending_balance numeric(14, 2) not null,
  closed_by uuid not null references public.users (id),
  closed_at timestamptz not null default now(),
  notes text
);

create unique index if not exists monthly_closings_account_month_idx
  on public.monthly_closings (account_id, closing_month);
create index if not exists monthly_closings_closed_at_idx
  on public.monthly_closings (closed_at desc);

drop policy if exists monthly_closings_read_authenticated on public.monthly_closings;
drop policy if exists monthly_closings_insert_admin on public.monthly_closings;

create policy monthly_closings_read_authenticated
  on public.monthly_closings for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
create policy monthly_closings_insert_admin
  on public.monthly_closings for insert to authenticated
  with check (public.current_app_role() = 'ADMIN' and closed_by = auth.uid());

-- Hanya SELECT dan INSERT; rekaman tutup buku tidak dapat diubah atau dihapus.
grant select, insert on public.monthly_closings to authenticated;

alter table public.users enable row level security;
alter table public.petty_cash_accounts enable row level security;
alter table public.petty_cash_requests enable row level security;
alter table public.petty_cash_transactions enable row level security;
alter table public.monthly_closings enable row level security;

-- Profiles are readable to authenticated users for names and role-based UI;
-- there are deliberately no client-side profile mutation policies.
drop policy if exists users_read_authenticated on public.users;
drop policy if exists accounts_read_authenticated on public.petty_cash_accounts;
drop policy if exists accounts_insert_admin on public.petty_cash_accounts;
drop policy if exists accounts_update_admin on public.petty_cash_accounts;
drop policy if exists accounts_delete_admin on public.petty_cash_accounts;
drop policy if exists requests_read_authenticated on public.petty_cash_requests;
drop policy if exists requests_insert_admin on public.petty_cash_requests;
drop policy if exists requests_update_own_pending_admin on public.petty_cash_requests;
drop policy if exists requests_delete_own_pending_admin on public.petty_cash_requests;
drop policy if exists transactions_read_authenticated on public.petty_cash_transactions;
drop policy if exists transactions_insert_admin on public.petty_cash_transactions;
drop policy if exists transactions_update_admin on public.petty_cash_transactions;
drop policy if exists transactions_delete_admin on public.petty_cash_transactions;

create policy users_read_authenticated
  on public.users for select to authenticated using (true);

create policy accounts_read_authenticated
  on public.petty_cash_accounts for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
create policy accounts_insert_admin
  on public.petty_cash_accounts for insert to authenticated
  with check (public.current_app_role() = 'ADMIN' and created_by = auth.uid());
create policy accounts_update_admin
  on public.petty_cash_accounts for update to authenticated
  using (public.current_app_role() = 'ADMIN')
  with check (public.current_app_role() = 'ADMIN');
create policy accounts_delete_admin
  on public.petty_cash_accounts for delete to authenticated
  using (public.current_app_role() = 'ADMIN');

create policy requests_read_authenticated
  on public.petty_cash_requests for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
create policy requests_insert_admin
  on public.petty_cash_requests for insert to authenticated
  with check (
    public.current_app_role() = 'ADMIN'
    and requester_id = auth.uid()
    and account_id is not null
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  );
create policy requests_update_own_pending_admin
  on public.petty_cash_requests for update to authenticated
  using (
    public.current_app_role() = 'ADMIN'
    and requester_id = auth.uid()
    and status = 'pending'
  )
  with check (
    public.current_app_role() = 'ADMIN'
    and requester_id = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  );
create policy requests_delete_own_pending_admin
  on public.petty_cash_requests for delete to authenticated
  using (
    public.current_app_role() = 'ADMIN'
    and requester_id = auth.uid()
    and status = 'pending'
  );

create policy transactions_read_authenticated
  on public.petty_cash_transactions for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
create policy transactions_insert_admin
  on public.petty_cash_transactions for insert to authenticated
  with check (public.current_app_role() = 'ADMIN' and created_by = auth.uid());
create policy transactions_update_admin
  on public.petty_cash_transactions for update to authenticated
  using (public.current_app_role() = 'ADMIN')
  with check (public.current_app_role() = 'ADMIN' and created_by = auth.uid());
create policy transactions_delete_admin
  on public.petty_cash_transactions for delete to authenticated
  using (public.current_app_role() = 'ADMIN');

grant usage on schema public to authenticated;
grant select on public.users to authenticated;
grant select, insert, update, delete on public.petty_cash_accounts to authenticated;
grant select, insert, update, delete on public.petty_cash_requests to authenticated;
grant select, insert, update, delete on public.petty_cash_transactions to authenticated;

-- [FITUR BARU] Tahap 7: views untuk laporan dan ekspor.
-- Views menggunakan security_invoker (default) sehingga RLS pada tabel dasar
-- tetap diterapkan. Cukup concession SELECT kepada authenticated.

-- View: transaksi dengan nama akun, kategori, dan pencreator —
-- menyederhanakan query join untuk filter laporan sisi-klien.
create or replace view public.transaction_details as
select
  t.id,
  t.account_id,
  a.account_code,
  a.name               as account_name,
  t.category_id,
  c.name               as category_name,
  t.created_by,
  u.full_name          as creator_name,
  t.transaction_type,
  t.transaction_date,
  t.description,
  t.amount,
  t.status,
  t.created_at,
  t.request_id
from public.petty_cash_transactions t
left join public.petty_cash_accounts    a on t.account_id  = a.id
left join public.expense_categories     c on t.category_id = c.id
left join public.users                  u on t.created_by  = u.id
where t.transaction_type = 'OUT';

-- View: rekap per kategori pengeluaran (hanya transaksi non-void).
create or replace view public.category_summary as
select
  c.id               as category_id,
  c.name             as category_name,
  count(t.id)        as transaction_count,
  sum(t.amount)      as total_amount,
  avg(t.amount)      as avg_amount,
  max(t.amount)      as max_amount,
  min(t.amount)      as min_amount
from public.petty_cash_transactions t
left join public.expense_categories c on t.category_id = c.id
where t.transaction_type = 'OUT' and t.status <> 'void'
group by c.id, c.name
order by sum(t.amount) desc;

-- View: rekap per akun kas (total masuk dari request approved, total keluar dari transaksi non-void).
create or replace view public.account_transaction_summary as
select
  a.id               as account_id,
  a.account_code,
  a.name             as account_name,
  count(t.id)        as transaction_count,
  sum(t.amount)      as total_outflow,
  count(r.id)        as approved_request_count,
  sum(r.requested_amount) as total_inflow
from public.petty_cash_accounts a
left join public.petty_cash_transactions t
  on a.id = t.account_id
  and t.transaction_type = 'OUT'
  and t.status <> 'void'
left join public.petty_cash_requests r
  on a.id = r.account_id
  and r.status = 'approved'
group by a.id, a.account_code, a.name
order by a.name;

grant select on public.transaction_details to authenticated;
grant select on public.category_summary to authenticated;
grant select on public.account_transaction_summary to authenticated;

-- Provision users through Supabase Auth, then add their matching profile:
-- insert into public.users (id, full_name, role)
-- values ('AUTH_USER_UUID', 'Nama Pengguna', 'ADMIN');
-- Never expose a service_role key in frontend code.

-- [FITUR BARU] Tahap 1: Manager hanya dapat mengubah batas saldo minimum akun.
drop policy if exists accounts_update_manager_min_balance on public.petty_cash_accounts;
create policy accounts_update_manager_min_balance
  on public.petty_cash_accounts for update to authenticated
  using (public.current_app_role() = 'MANAGER')
  with check (public.current_app_role() = 'MANAGER');

create or replace function public.protect_petty_cash_manager_account_update()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if public.current_app_role() = 'MANAGER' and (
    new.id is distinct from old.id
    or new.account_code is distinct from old.account_code
    or new.name is distinct from old.name
    or new.initial_balance is distinct from old.initial_balance
    or new.is_active is distinct from old.is_active
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'Manager hanya dapat mengubah batas saldo minimum akun'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists petty_cash_accounts_protect_manager_update on public.petty_cash_accounts;
create trigger petty_cash_accounts_protect_manager_update
before update on public.petty_cash_accounts
for each row execute function public.protect_petty_cash_manager_account_update();

-- Verifikasi saldo setelah Tahap 1; hasil harus identik sebelum dan sesudah
-- perubahan karena min_balance tidak masuk ke dalam perhitungan saldo.
-- Jalankan di Supabase SQL Editor; query ini hanya membaca data.
-- select
--   a.id as account_id,
--   a.name as nama_akun,
--   coalesce(a.initial_balance, 0)
--     + coalesce((
--       select sum(r.requested_amount)
--       from public.petty_cash_requests r
--       where r.account_id = a.id and r.status = 'approved'
--     ), 0)
--     - coalesce((
--       select sum(t.amount)
--       from public.petty_cash_transactions t
--       where t.account_id = a.id
--         and t.transaction_type = 'OUT'
--         and t.status = 'posted'
--     ), 0) as saldo_kas
-- from public.petty_cash_accounts a
-- order by a.name;

-- [FITUR BARU] Tahap 1: CoA dan auto-journaling append-only.
create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  source_type text not null,
  source_id uuid not null,
  source_sequence bigint not null default 0,
  entry_date date not null,
  description text not null,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  unique (source_type, source_id, source_sequence)
);

create table if not exists public.journal_details (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references public.journal_entries (id),
  line_number integer not null check (line_number > 0),
  coa_id uuid not null references public.chart_of_accounts (id),
  debit numeric(14, 2) not null default 0 check (debit >= 0),
  credit numeric(14, 2) not null default 0 check (credit >= 0),
  created_at timestamptz not null default now(),
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0)),
  unique (journal_entry_id, line_number)
);

create index if not exists journal_details_coa_idx
  on public.journal_details (coa_id, journal_entry_id);
create index if not exists journal_entries_date_idx
  on public.journal_entries (entry_date desc);

alter table public.journal_entries enable row level security;
alter table public.journal_details enable row level security;
drop policy if exists journal_entries_read_authenticated on public.journal_entries;
drop policy if exists journal_details_read_authenticated on public.journal_details;
create policy journal_entries_read_authenticated
  on public.journal_entries for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
create policy journal_details_read_authenticated
  on public.journal_details for select to authenticated
  using (public.current_app_role() in ('ADMIN', 'MANAGER'));
revoke all on public.journal_entries, public.journal_details from public, anon, authenticated;
grant select on public.journal_entries, public.journal_details to authenticated;

create or replace function public.append_cash_journal(
  p_source_type text,
  p_source_id uuid,
  p_source_sequence bigint,
  p_entry_date date,
  p_description text,
  p_created_by uuid,
  p_debit_coa uuid,
  p_credit_coa uuid,
  p_amount numeric
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  entry_id uuid;
begin
  if p_amount <= 0 or p_debit_coa is null or p_credit_coa is null then
    raise exception 'Jurnal tidak valid: akun debit, kredit, dan nominal wajib tersedia';
  end if;

  insert into public.journal_entries (
    source_type, source_id, source_sequence, entry_date, description, created_by
  ) values (
    p_source_type, p_source_id, p_source_sequence, p_entry_date, p_description, p_created_by
  )
  on conflict (source_type, source_id, source_sequence) do nothing;

  select id into entry_id
  from public.journal_entries
  where source_type = p_source_type
    and source_id = p_source_id
    and source_sequence = p_source_sequence;

  insert into public.journal_details (journal_entry_id, line_number, coa_id, debit, credit)
  values (entry_id, 1, p_debit_coa, p_amount, 0)
  on conflict (journal_entry_id, line_number) do nothing;
  insert into public.journal_details (journal_entry_id, line_number, coa_id, debit, credit)
  values (entry_id, 2, p_credit_coa, 0, p_amount)
  on conflict (journal_entry_id, line_number) do nothing;

  return entry_id;
end;
$$;

revoke all on function public.append_cash_journal(text, uuid, bigint, date, text, uuid, uuid, uuid, numeric)
  from public, anon, authenticated;

create or replace function public.assign_petty_cash_transaction_coa()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.transaction_type is distinct from 'OUT' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.category_id is null then
      raise exception 'Pilih kategori pengeluaran sebelum mencatat transaksi';
    end if;
  elsif new.category_id is distinct from old.category_id then
    if new.category_id is null then
      raise exception 'Pilih kategori pengeluaran sebelum mencatat transaksi';
    end if;
  else
    return new;
  end if;

  select category.coa_id
  into new.coa_id
  from public.expense_categories as category
  join public.chart_of_accounts as coa on coa.id = category.coa_id
  where category.id = new.category_id
    and category.is_active
    and coa.is_active
    and coa.type = 'EXPENSE';

  if new.coa_id is null then
    raise exception 'Kategori tidak aktif atau akun CoA belum dipetakan atau tidak aktif';
  end if;

  return new;
end;
$$;

drop trigger if exists petty_cash_transactions_assign_coa on public.petty_cash_transactions;
create trigger petty_cash_transactions_assign_coa
before insert or update on public.petty_cash_transactions
for each row execute function public.assign_petty_cash_transaction_coa();

create or replace function public.journal_approved_petty_cash_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  petty_cash_coa uuid;
  bank_coa uuid;
begin
  if new.status <> 'approved' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if old.status = 'approved' then
      return new;
    end if;
  end if;

  select id into petty_cash_coa from public.chart_of_accounts where code = '1-1001';
  select id into bank_coa from public.chart_of_accounts where code = '1-1002';
  if petty_cash_coa is null or bank_coa is null then
    raise exception 'CoA Kas Kecil atau Kas Bank belum tersedia';
  end if;

  perform public.append_cash_journal(
    'REQUEST_APPROVED', new.id, 0,
    coalesce(new.reviewed_at::date, new.created_at::date),
    'Pengisian kas kecil: ' || new.purpose,
    coalesce(new.reviewed_by, new.requester_id),
    petty_cash_coa, bank_coa, new.requested_amount
  );
  return new;
end;
$$;

drop trigger if exists petty_cash_requests_journal_approved on public.petty_cash_requests;
create trigger petty_cash_requests_journal_approved
after insert or update on public.petty_cash_requests
for each row execute function public.journal_approved_petty_cash_request();

create or replace function public.journal_petty_cash_transaction()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  petty_cash_coa uuid;
  expense_coa uuid;
  old_expense_coa uuid;
  event_sequence bigint;
begin
  if new.transaction_type is distinct from 'OUT' then
    return new;
  end if;

  select id into petty_cash_coa from public.chart_of_accounts where code = '1-1001';
  if petty_cash_coa is null then
    raise exception 'CoA Kas Kecil belum tersedia';
  end if;

  select id into expense_coa from public.chart_of_accounts where code = '5-1003';
  expense_coa := coalesce(new.coa_id, expense_coa);
  if tg_op = 'INSERT' then
    if new.status = 'posted' then
      perform public.append_cash_journal(
        'PETTY_CASH_OUT', new.id, 0, new.transaction_date,
        'Pengeluaran kas kecil: ' || new.description, new.created_by,
        expense_coa, petty_cash_coa, new.amount
      );
    end if;
    return new;
  end if;

  select category.coa_id
  into old_expense_coa
  from public.expense_categories as category
  where category.id = old.category_id;
  select id into expense_coa from public.chart_of_accounts where code = '5-1003';
  old_expense_coa := coalesce(old.coa_id, old_expense_coa, expense_coa);
  expense_coa := coalesce(new.coa_id, expense_coa);
  select coalesce(max(journal.source_sequence), 0) + 1
  into event_sequence
  from public.journal_entries as journal
  where journal.source_id = new.id
    and journal.source_type like 'PETTY_CASH_%';

  if old.status = 'posted' and new.status = 'void' then
    perform public.append_cash_journal(
      'PETTY_CASH_OUT', old.id, 0, old.transaction_date,
      'Pengeluaran kas kecil: ' || old.description, old.created_by,
      old_expense_coa, petty_cash_coa, old.amount
    );
    perform public.append_cash_journal(
      'PETTY_CASH_VOID', new.id, event_sequence,
      coalesce(new.voided_at::date, current_date),
      'Pembatalan transaksi kas kecil: ' || old.description,
      coalesce(new.voided_by, new.created_by),
      petty_cash_coa, old_expense_coa, old.amount
    );
  elsif old.status = 'posted' and new.status = 'posted' and (
    old.account_id is distinct from new.account_id
    or old.category_id is distinct from new.category_id
    or old.coa_id is distinct from new.coa_id
    or old.transaction_date is distinct from new.transaction_date
    or old.description is distinct from new.description
    or old.amount is distinct from new.amount
  ) then
    perform public.append_cash_journal(
      'PETTY_CASH_OUT', old.id, 0, old.transaction_date,
      'Pengeluaran kas kecil: ' || old.description, old.created_by,
      old_expense_coa, petty_cash_coa, old.amount
    );
    perform public.append_cash_journal(
      'PETTY_CASH_EDIT_REVERSAL', new.id, event_sequence,
      coalesce(new.updated_at::date, current_date),
      'Pembalikan perubahan transaksi: ' || old.description, new.created_by,
      petty_cash_coa, old_expense_coa, old.amount
    );
    perform public.append_cash_journal(
      'PETTY_CASH_EDIT_POSTING', new.id, event_sequence,
      new.transaction_date, 'Perubahan transaksi kas kecil: ' || new.description,
      new.created_by, expense_coa, petty_cash_coa, new.amount
    );
  elsif old.status = 'void' and new.status = 'posted' then
    perform public.append_cash_journal(
      'PETTY_CASH_REPOST', new.id, event_sequence, new.transaction_date,
      'Pencatatan kembali transaksi kas kecil: ' || new.description,
      new.created_by, expense_coa, petty_cash_coa, new.amount
    );
  end if;

  return new;
end;
$$;

drop trigger if exists petty_cash_transactions_journal on public.petty_cash_transactions;
create trigger petty_cash_transactions_journal
after insert or update on public.petty_cash_transactions
for each row execute function public.journal_petty_cash_transaction();

-- Verifikasi Tahap 1: jalankan query ini sebelum dan sesudah schema diterapkan.
-- Simpan hasil per account_id; saldo_kas harus identik karena penambahan CoA
-- dan jurnal tidak mengubah saldo kas sumber.
-- select
--   a.id as account_id,
--   a.name as nama_akun,
--   coalesce(a.initial_balance, 0)
--     + coalesce((
--       select sum(r.requested_amount)
--       from public.petty_cash_requests r
--       where r.account_id = a.id and r.status = 'approved'
--     ), 0)
--     - coalesce((
--       select sum(t.amount)
--       from public.petty_cash_transactions t
--       where t.account_id = a.id
--         and t.transaction_type = 'OUT'
--         and t.status = 'posted'
--     ), 0) as saldo_kas
-- from public.petty_cash_accounts a
-- order by a.name;