-- Supabase PostgreSQL schema for Sistem Akuntansi Petty Cash KJA.
-- The only application tables are users, petty_cash_accounts,
-- petty_cash_requests, and petty_cash_transactions.

create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role text not null check (role in ('ADMIN', 'MANAGER')),
  created_at timestamptz not null default now()
);

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

-- Query sesudah: hasil account_id, nama_akun, dan saldo_kas harus identik
-- dengan hasil sebelum perubahan (kolom min_balance tidak mengubah saldo).
-- Lakukan query ini setelah mengeksekusi bagian "Tahap 1" di schema.sql.
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
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.petty_cash_transactions
  add column if not exists category_id uuid
    references public.expense_categories(id);

insert into public.expense_categories (name, coa_code, is_active)
values
  ('ATK', 'ATK', true),
  ('Transportasi', 'TRANSPORTASI', true),
  ('Konsumsi', 'KONSUMSI', true),
  ('Listrik & Air', 'LISTRIK_AIR', true),
  ('Kebersihan', 'KEBERSIHAN', true),
  ('Lain-lain', 'LAIN', true)
on conflict (name) do nothing;

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

-- SECURITY DEFINER avoids recursive users-table RLS checks in policies.
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
drop policy if not exists monthly_closings_insert_admin on public.monthly_closings;

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

-- Provision users through Supabase Auth, then add their matching profile:
-- insert into public.users (id, full_name, role)
-- values ('AUTH_USER_UUID', 'Nama Pengguna', 'ADMIN');
-- Never expose a service_role key in frontend code.