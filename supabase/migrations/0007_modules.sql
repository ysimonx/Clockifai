-- 0007 — Modules : approbation des feuilles de temps, absences, planning, kiosque, facturation.
-- (exécuté en tant que postgres)
--
-- Toutes les règles métier sont appliquées côté serveur (RLS + triggers) : l'app offline-first
-- peut écrire localement, le serveur arbitre à la synchronisation.

-- ===========================================================================
-- 0. Compléments sur les tables existantes
-- ===========================================================================
alter table public.workspaces add column if not exists company_name text;
alter table public.workspaces add column if not exists company_details text;      -- adresse, SIRET, TVA… (multiligne)
alter table public.workspaces add column if not exists invoice_prefix text not null default 'F';
alter table public.workspaces add column if not exists default_tax_percent numeric(5,2) not null default 20;
alter table public.workspaces add column if not exists invoice_due_days smallint not null default 30;

alter table public.workspace_members add column if not exists capacity_hours_per_day numeric(4,2) not null default 7;
-- Le hash du PIN kiosque ne doit jamais être lisible par les membres : il part dans member_pins.
alter table public.workspace_members drop column if exists kiosk_pin_hash;

alter table public.clients add column if not exists address text;
alter table public.clients add column if not exists email text;

-- Date locale d'un instant pour un utilisateur (fuseau du profil, Europe/Paris par défaut).
create or replace function public.user_local_date(ts timestamptz, uid uuid)
returns date language sql stable security definer set search_path = public as $$
  select (ts at time zone coalesce((select timezone from public.profiles where id = uid), 'Europe/Paris'))::date
$$;

-- Les triggers internes posent ce drapeau pour modifier des entrées sans repasser par la garde.
create or replace function public.guard_bypassed()
returns boolean language sql stable as $$
  select coalesce(current_setting('clockifai.bypass_guard', true), '') = 'on'
$$;

-- ===========================================================================
-- 1. Kiosque : PINs (jamais exposés) et appareils
-- ===========================================================================
create table if not exists public.member_pins (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  pin_hash text not null,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
alter table public.member_pins enable row level security;  -- aucune politique : inaccessible via l'API
revoke all on public.member_pins from anon, authenticated;

create or replace function public.set_kiosk_pin(p_workspace_id uuid, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_member(p_workspace_id) then
    raise exception 'not a member of this workspace' using errcode = '42501';
  end if;
  if p_pin !~ '^[0-9]{4,8}$' then
    raise exception 'PIN must be 4 to 8 digits' using errcode = '22023';
  end if;
  insert into public.member_pins (workspace_id, user_id, pin_hash)
  values (p_workspace_id, auth.uid(), crypt(p_pin, gen_salt('bf', 8)))
  on conflict (workspace_id, user_id) do update set pin_hash = excluded.pin_hash, updated_at = now();
end $$;
revoke all on function public.set_kiosk_pin(uuid, text) from public;
grant execute on function public.set_kiosk_pin(uuid, text) to authenticated;

create or replace function public.has_kiosk_pin(p_workspace_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.member_pins where workspace_id = p_workspace_id and user_id = auth.uid())
$$;
grant execute on function public.has_kiosk_pin(uuid) to authenticated;

create table if not exists public.kiosk_devices (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  token_hash text not null unique,
  created_by uuid references auth.users(id) on delete set null,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger kiosk_devices_updated_at before update on public.kiosk_devices
  for each row execute function public.set_updated_at();
alter table public.kiosk_devices enable row level security;
create policy kiosk_devices_admin on public.kiosk_devices for all to authenticated
  using (public.is_admin(workspace_id)) with check (public.is_admin(workspace_id));

-- ===========================================================================
-- 2. Approbation des feuilles de temps
-- ===========================================================================
create table if not exists public.timesheet_submissions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  status text not null default 'submitted' check (status in ('submitted', 'approved', 'rejected', 'withdrawn')),
  total_seconds integer,
  note text,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (period_end >= period_start),
  unique (workspace_id, user_id, period_start)
);
create index if not exists submissions_ws_status_idx on public.timesheet_submissions(workspace_id, status);
create trigger timesheet_submissions_updated_at before update on public.timesheet_submissions
  for each row execute function public.set_updated_at();

alter table public.timesheet_submissions enable row level security;
create policy submissions_select on public.timesheet_submissions for select to authenticated
  using (user_id = auth.uid() or public.is_manager(workspace_id));
create policy submissions_insert on public.timesheet_submissions for insert to authenticated
  with check (user_id = auth.uid() and public.is_member(workspace_id));
create policy submissions_update on public.timesheet_submissions for update to authenticated
  using (user_id = auth.uid() or public.is_manager(workspace_id))
  with check (user_id = auth.uid() or public.is_manager(workspace_id));

create or replace function public.timesheet_submissions_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  manager boolean;
begin
  if auth.uid() is null then
    return new;
  end if;
  manager := public.is_manager(new.workspace_id);
  if tg_op = 'INSERT' then
    if new.status not in ('submitted') and not manager then
      raise exception 'invalid_status: a submission starts as submitted' using errcode = '42501';
    end if;
  else
    if new.user_id <> old.user_id or new.workspace_id <> old.workspace_id
       or new.period_start <> old.period_start or new.period_end <> old.period_end then
      raise exception 'immutable: period and owner cannot change' using errcode = '42501';
    end if;
    if not manager then
      if old.status = 'approved' then
        raise exception 'approved: an approved timesheet can only be reopened by a manager' using errcode = '42501';
      end if;
      if new.status not in ('submitted', 'withdrawn') then
        raise exception 'insufficient_privilege: only managers approve or reject' using errcode = '42501';
      end if;
    end if;
  end if;
  if new.status in ('approved', 'rejected') and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;
  return new;
end $$;
create trigger timesheet_submissions_guard before insert or update on public.timesheet_submissions
  for each row execute function public.timesheet_submissions_guard();

-- Approuver verrouille les entrées de la période ; rouvrir les déverrouille.
create or replace function public.timesheet_submissions_apply()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  should_lock boolean := new.status = 'approved' and new.deleted_at is null;
  was_locked boolean := tg_op = 'UPDATE' and old.status = 'approved' and old.deleted_at is null;
begin
  if should_lock = was_locked then
    return new;
  end if;
  perform set_config('clockifai.bypass_guard', 'on', true);
  update public.time_entries te
     set locked = should_lock
   where te.workspace_id = new.workspace_id
     and te.user_id = new.user_id
     and te.deleted_at is null
     and public.user_local_date(te.start_at, te.user_id) between new.period_start and new.period_end;
  perform set_config('clockifai.bypass_guard', '', true);
  return new;
end $$;
create trigger timesheet_submissions_apply after insert or update on public.timesheet_submissions
  for each row execute function public.timesheet_submissions_apply();

-- ===========================================================================
-- 3. Absences
-- ===========================================================================
create table if not exists public.time_off_policies (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  color text not null default '#10B981',
  unit text not null default 'days' check (unit in ('days', 'hours')),
  annual_allowance numeric(7,2),              -- null = illimité
  paid boolean not null default true,
  requires_approval boolean not null default true,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger time_off_policies_updated_at before update on public.time_off_policies
  for each row execute function public.set_updated_at();

create table if not exists public.time_off_allowances (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_id uuid not null references public.time_off_policies(id) on delete cascade,
  year integer not null,
  allowance numeric(7,2) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (workspace_id, user_id, policy_id, year)
);
create trigger time_off_allowances_updated_at before update on public.time_off_allowances
  for each row execute function public.set_updated_at();

create table if not exists public.time_off_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_id uuid not null references public.time_off_policies(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  amount numeric(7,2) not null check (amount > 0),   -- jours ou heures selon la politique
  half_day boolean not null default false,
  note text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (end_date >= start_date)
);
create index if not exists time_off_requests_ws_idx on public.time_off_requests(workspace_id, status);
create trigger time_off_requests_updated_at before update on public.time_off_requests
  for each row execute function public.set_updated_at();

create table if not exists public.holidays (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger holidays_updated_at before update on public.holidays
  for each row execute function public.set_updated_at();

alter table public.time_off_policies enable row level security;
create policy policies_select on public.time_off_policies for select to authenticated using (public.is_member(workspace_id));
create policy policies_write on public.time_off_policies for all to authenticated
  using (public.is_admin(workspace_id)) with check (public.is_admin(workspace_id));

alter table public.holidays enable row level security;
create policy holidays_select on public.holidays for select to authenticated using (public.is_member(workspace_id));
create policy holidays_write on public.holidays for all to authenticated
  using (public.is_admin(workspace_id)) with check (public.is_admin(workspace_id));

alter table public.time_off_allowances enable row level security;
create policy allowances_select on public.time_off_allowances for select to authenticated
  using (user_id = auth.uid() or public.is_manager(workspace_id));
create policy allowances_write on public.time_off_allowances for all to authenticated
  using (public.is_admin(workspace_id)) with check (public.is_admin(workspace_id));

alter table public.time_off_requests enable row level security;
create policy requests_select on public.time_off_requests for select to authenticated
  using (user_id = auth.uid() or public.is_manager(workspace_id));
create policy requests_insert on public.time_off_requests for insert to authenticated
  with check ((user_id = auth.uid() and public.is_member(workspace_id)) or public.is_manager(workspace_id));
create policy requests_update on public.time_off_requests for update to authenticated
  using (user_id = auth.uid() or public.is_manager(workspace_id))
  with check (user_id = auth.uid() or public.is_manager(workspace_id));

create or replace function public.time_off_requests_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  manager boolean;
  needs_approval boolean;
begin
  if auth.uid() is null then
    return new;
  end if;
  manager := public.is_manager(new.workspace_id);
  select requires_approval into needs_approval from public.time_off_policies where id = new.policy_id;
  if tg_op = 'INSERT' then
    if not manager and new.status <> 'pending' then
      raise exception 'invalid_status: a request starts as pending' using errcode = '42501';
    end if;
    if not coalesce(needs_approval, true) and new.status = 'pending' then
      new.status := 'approved';   -- politique sans approbation
    end if;
  else
    if new.user_id <> old.user_id or new.workspace_id <> old.workspace_id then
      raise exception 'immutable: owner cannot change' using errcode = '42501';
    end if;
    if not manager then
      -- Le demandeur peut modifier une demande en attente, ou annuler.
      if new.status = 'cancelled' then
        null;
      elsif old.status <> 'pending' or new.status <> 'pending' then
        raise exception 'insufficient_privilege: only managers approve or reject' using errcode = '42501';
      end if;
    end if;
  end if;
  if new.status in ('approved', 'rejected') and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;
  return new;
end $$;
create trigger time_off_requests_guard before insert or update on public.time_off_requests
  for each row execute function public.time_off_requests_guard();

-- ===========================================================================
-- 4. Planning
-- ===========================================================================
create table if not exists public.schedule_assignments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid references public.projects(id) on delete set null,
  start_date date not null,
  end_date date not null,
  hours_per_day numeric(4,2) not null default 7 check (hours_per_day > 0 and hours_per_day <= 24),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (end_date >= start_date)
);
create index if not exists schedule_ws_dates_idx on public.schedule_assignments(workspace_id, start_date);
create trigger schedule_assignments_updated_at before update on public.schedule_assignments
  for each row execute function public.set_updated_at();
alter table public.schedule_assignments enable row level security;
create policy schedule_select on public.schedule_assignments for select to authenticated
  using (user_id = auth.uid() or public.is_manager(workspace_id));
create policy schedule_write on public.schedule_assignments for all to authenticated
  using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));

-- ===========================================================================
-- 5. Facturation
-- ===========================================================================
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  number text,                                  -- attribué par le serveur (unicité garantie)
  status text not null default 'draft' check (status in ('draft', 'sent', 'paid', 'void')),
  issue_date date not null default current_date,
  due_date date,
  currency text not null default 'EUR',
  tax_percent numeric(5,2) not null default 0,
  discount_percent numeric(5,2) not null default 0,
  note text,
  period_start date,
  period_end date,
  subtotal_cents bigint not null default 0,
  discount_cents bigint not null default 0,
  tax_cents bigint not null default 0,
  total_cents bigint not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (workspace_id, number)
);
create trigger invoices_updated_at before update on public.invoices
  for each row execute function public.set_updated_at();

create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  position integer not null default 0,
  description text not null default '',
  quantity numeric(12,2) not null default 1,
  unit_price_cents bigint not null default 0,
  amount_cents bigint not null default 0,      -- calculé par le serveur
  project_id uuid references public.projects(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists invoice_items_invoice_idx on public.invoice_items(invoice_id);

-- Entrées de temps facturées (lien n-n, géré par les managers sans toucher aux droits sur time_entries).
create table if not exists public.invoice_entries (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  time_entry_id uuid not null references public.time_entries(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (invoice_id, time_entry_id)
);
create index if not exists invoice_entries_entry_idx on public.invoice_entries(time_entry_id);

create table if not exists public.invoice_counters (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  year integer not null,
  last_value integer not null default 0,
  primary key (workspace_id, year)
);
revoke all on public.invoice_counters from anon, authenticated;

-- Numérotation continue par workspace et par année : F-2026-0001…
create or replace function public.invoices_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  n integer;
  prefix text;
  y integer;
begin
  new.updated_at := now();
  if tg_op = 'INSERT' and (new.number is null or new.number = '') then
    y := extract(year from new.issue_date)::integer;
    insert into public.invoice_counters (workspace_id, year, last_value) values (new.workspace_id, y, 1)
    on conflict (workspace_id, year) do update set last_value = invoice_counters.last_value + 1
    returning last_value into n;
    select invoice_prefix into prefix from public.workspaces where id = new.workspace_id;
    new.number := coalesce(nullif(prefix, ''), 'F') || '-' || y || '-' || lpad(n::text, 4, '0');
  end if;
  if new.due_date is null then
    new.due_date := new.issue_date + coalesce((select invoice_due_days from public.workspaces where id = new.workspace_id), 30);
  end if;
  -- Totaux recalculés à partir des lignes.
  select coalesce(sum(amount_cents), 0) into new.subtotal_cents
    from public.invoice_items where invoice_id = new.id and deleted_at is null;
  new.discount_cents := round(new.subtotal_cents * new.discount_percent / 100);
  new.tax_cents := round((new.subtotal_cents - new.discount_cents) * new.tax_percent / 100);
  new.total_cents := new.subtotal_cents - new.discount_cents + new.tax_cents;
  return new;
end $$;
drop trigger if exists invoices_updated_at on public.invoices;
create trigger invoices_before_write before insert or update on public.invoices
  for each row execute function public.invoices_before_write();

create or replace function public.invoice_items_before_write()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.amount_cents := round(new.quantity * new.unit_price_cents);
  return new;
end $$;
create trigger invoice_items_before_write before insert or update on public.invoice_items
  for each row execute function public.invoice_items_before_write();

-- Toute modification de ligne relance le calcul des totaux de la facture.
create or replace function public.invoice_items_after_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.invoices set updated_at = now() where id = coalesce(new.invoice_id, old.invoice_id);
  return null;
end $$;
create trigger invoice_items_after_write after insert or update or delete on public.invoice_items
  for each row execute function public.invoice_items_after_write();

create trigger invoice_entries_updated_at before update on public.invoice_entries
  for each row execute function public.set_updated_at();

alter table public.invoices enable row level security;
create policy invoices_manager on public.invoices for all to authenticated
  using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));
alter table public.invoice_items enable row level security;
create policy invoice_items_manager on public.invoice_items for all to authenticated
  using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));
alter table public.invoice_entries enable row level security;
create policy invoice_entries_manager on public.invoice_entries for all to authenticated
  using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));

-- ===========================================================================
-- 6. Garde des entrées de temps (remplace celle de 0003)
--    + fuseau horaire de l'utilisateur, période approuvée, entrée facturée, contournement interne.
-- ===========================================================================
create or replace function public.time_entries_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lock_date date;
  wid uuid;
  uid uuid;
  result public.time_entries;
begin
  if tg_op = 'DELETE' then
    result := old; wid := old.workspace_id; uid := old.user_id;
  else
    result := new; wid := new.workspace_id; uid := new.user_id;
  end if;

  if auth.uid() is null or public.guard_bypassed() or public.is_admin(wid) then
    return result;
  end if;

  if tg_op in ('UPDATE', 'DELETE') and old.locked then
    raise exception 'locked_entry: this time entry is locked' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.locked is distinct from old.locked then
    raise exception 'insufficient_privilege: only admins can lock entries' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and new.locked then
    raise exception 'insufficient_privilege: only admins can lock entries' using errcode = '42501';
  end if;

  select lock_entries_before into lock_date from public.workspaces where id = wid;
  if lock_date is not null then
    if tg_op in ('UPDATE', 'DELETE') and public.user_local_date(old.start_at, old.user_id) < lock_date then
      raise exception 'locked_period: entries before % are locked', lock_date using errcode = '42501';
    end if;
    if tg_op in ('INSERT', 'UPDATE') and public.user_local_date(new.start_at, new.user_id) < lock_date then
      raise exception 'locked_period: entries before % are locked', lock_date using errcode = '42501';
    end if;
  end if;

  -- Pas d'ajout ni de déplacement d'entrée dans une période déjà approuvée.
  if tg_op in ('INSERT', 'UPDATE') and exists (
    select 1 from public.timesheet_submissions s
     where s.workspace_id = wid and s.user_id = uid and s.status = 'approved' and s.deleted_at is null
       and public.user_local_date(new.start_at, uid) between s.period_start and s.period_end) then
    raise exception 'approved_period: this period has been approved' using errcode = '42501';
  end if;

  -- Une entrée facturée (facture non annulée) n'est plus modifiable par son auteur.
  if tg_op in ('UPDATE', 'DELETE') and exists (
    select 1 from public.invoice_entries ie join public.invoices i on i.id = ie.invoice_id
     where ie.time_entry_id = old.id and i.status <> 'void' and i.deleted_at is null) then
    raise exception 'invoiced_entry: this entry has been invoiced' using errcode = '42501';
  end if;

  return result;
end $$;

-- ===========================================================================
-- 7. Droits de lecture pour la réplication PowerSync (tables créées dans cette migration)
-- ===========================================================================
grant select on all tables in schema public to powersync_role;
grant all on all tables in schema public to authenticated, service_role;
revoke all on public.member_pins, public.invoice_counters from authenticated;
