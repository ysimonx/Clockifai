-- 0008 — Tables techniques hors du schéma public (exécuté en tant que supabase_admin).
--
-- La publication PowerSync couvre tout le schéma public et PostgREST l'expose : les hash de PIN
-- kiosque et les compteurs de facture n'ont rien à y faire.
create schema if not exists clockifai_private;
revoke all on schema clockifai_private from public, anon, authenticated;
grant usage on schema clockifai_private to postgres, service_role;

alter table public.member_pins set schema clockifai_private;
alter table public.invoice_counters set schema clockifai_private;
alter table clockifai_private.member_pins owner to postgres;
alter table clockifai_private.invoice_counters owner to postgres;
revoke all on clockifai_private.member_pins, clockifai_private.invoice_counters from powersync_role, anon, authenticated;

create or replace function public.set_kiosk_pin(p_workspace_id uuid, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_member(p_workspace_id) then
    raise exception 'not a member of this workspace' using errcode = '42501';
  end if;
  if p_pin !~ '^[0-9]{4,8}$' then
    raise exception 'PIN must be 4 to 8 digits' using errcode = '22023';
  end if;
  insert into clockifai_private.member_pins (workspace_id, user_id, pin_hash)
  values (p_workspace_id, auth.uid(), crypt(p_pin, gen_salt('bf', 8)))
  on conflict (workspace_id, user_id) do update set pin_hash = excluded.pin_hash, updated_at = now();
end $$;
alter function public.set_kiosk_pin(uuid, text) owner to postgres;

create or replace function public.has_kiosk_pin(p_workspace_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from clockifai_private.member_pins where workspace_id = p_workspace_id and user_id = auth.uid())
$$;
alter function public.has_kiosk_pin(uuid) owner to postgres;

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
    insert into clockifai_private.invoice_counters (workspace_id, year, last_value) values (new.workspace_id, y, 1)
    on conflict (workspace_id, year) do update set last_value = invoice_counters.last_value + 1
    returning last_value into n;
    select invoice_prefix into prefix from public.workspaces where id = new.workspace_id;
    new.number := coalesce(nullif(prefix, ''), 'F') || '-' || y || '-' || lpad(n::text, 4, '0');
  end if;
  if new.due_date is null then
    new.due_date := new.issue_date + coalesce((select invoice_due_days from public.workspaces where id = new.workspace_id), 30);
  end if;
  select coalesce(sum(amount_cents), 0) into new.subtotal_cents
    from public.invoice_items where invoice_id = new.id and deleted_at is null;
  new.discount_cents := round(new.subtotal_cents * new.discount_percent / 100);
  new.tax_cents := round((new.subtotal_cents - new.discount_cents) * new.tax_percent / 100);
  new.total_cents := new.subtotal_cents - new.discount_cents + new.tax_cents;
  return new;
end $$;
alter function public.invoices_before_write() owner to postgres;
