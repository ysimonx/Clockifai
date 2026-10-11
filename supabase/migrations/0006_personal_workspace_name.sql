-- 0006 — Nom du workspace personnel créé à l'inscription : « Espace de <nom> » (exécuté en tant que postgres).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  ws_id uuid;
  dname text;
begin
  dname := coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, ''), '@', 1));
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, dname)
  on conflict (id) do nothing;

  insert into public.workspaces (name, created_by)
  values ('Espace de ' || coalesce(nullif(dname, ''), 'moi'), new.id)
  returning id into ws_id;

  update public.profiles set default_workspace_id = ws_id where id = new.id and default_workspace_id is null;
  return new;
end $$;
