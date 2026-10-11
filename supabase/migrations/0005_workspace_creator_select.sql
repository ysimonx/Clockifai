-- 0005 — Le créateur d'un workspace peut le lire (exécuté en tant que postgres).
--
-- Le client envoie ses créations en upsert (INSERT … ON CONFLICT DO UPDATE, via PowerSync).
-- Postgres applique alors aussi la politique SELECT à la nouvelle ligne, évaluée AVANT
-- le trigger AFTER INSERT qui crée l'adhésion owner : sans cette règle, la création
-- d'un workspace depuis l'app est refusée (42501).
drop policy if exists workspaces_select on public.workspaces;
create policy workspaces_select on public.workspaces for select to authenticated
  using (public.is_member(id) or created_by = auth.uid());
