-- BliGO : genre de l'usager dans la fiche usager du logiciel (18/11/2026, demande de Mégane).
-- Renseigné par l'agent ; vide = non renseigné.
alter table public.profiles add column if not exists genre text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_genre_valide') then
    alter table public.profiles
      add constraint profiles_genre_valide check (genre is null or genre in ('femme', 'homme', 'transgenre', 'non_precise'));
  end if;
end $$;

create or replace function public.set_usager_genre(p_user_id uuid, p_genre text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  update public.profiles set genre = nullif(p_genre, '') where id = p_user_id;
end;
$$;

grant execute on function public.set_usager_genre(uuid, text) to authenticated;
