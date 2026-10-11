-- 0002 — Trigger sur auth.users (exécuté en tant que supabase_admin : la table appartient à l'auth).
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Le propriétaire de la fonction doit pouvoir écrire dans les tables public : c'est postgres (0001).
alter function public.handle_new_user() owner to postgres;
grant execute on function public.handle_new_user() to supabase_auth_admin;
