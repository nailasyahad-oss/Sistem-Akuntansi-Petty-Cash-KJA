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

alter table public.users enable row level security;
alter table public.petty_cash_accounts enable row level security;
alter table public.petty_cash_requests enable row level security;
alter table public.petty_cash_transactions enable row level security;

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