-- Connexion d'un poste par lien (plans/21-installation-simple-du-plugin.md). Schéma privé : migration admin.
-- Seulement des empreintes SHA-256 : `code` (dans l'adresse du lien) et `poll` (gardé par le hook). Le jeton clk_…
-- n'existe qu'au moment où le hook le retire, une fois le lien validé (workspace_id, user_id, name, approved_at).
create table if not exists clockifai_private.device_links (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  poll_hash text not null unique,
  machine text not null default '',
  workspace_id uuid references public.workspaces(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  name text,
  approved_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists device_links_expires_idx on clockifai_private.device_links(expires_at);

alter table clockifai_private.device_links owner to postgres;
revoke all on clockifai_private.device_links from public, anon, authenticated, powersync_role;
