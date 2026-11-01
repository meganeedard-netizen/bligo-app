-- BliGO - vérification de l'adresse e-mail « plus tard » (01/11/2026)
--
-- Avant : impossible d'entrer dans l'appli sans le code reçu par e-mail.
-- Maintenant : le compte s'ouvre tout de suite (Supabase « Confirm email »
-- désactivé), l'usager vérifie son adresse quand il veut (Profil > Vérifier
-- mon compte). Tant que ce n'est pas fait, il ne peut ni commander de
-- document ni s'inscrire à un événement.

alter table public.profiles add column if not exists email_verifie boolean not null default false;

-- Comptes existants : leur adresse a déjà été vérifiée par l'ancien parcours.
update public.profiles p set email_verifie = true
from auth.users u
where u.id = p.id and u.email_confirmed_at is not null and not p.email_verifie;

-- Appelée juste après la saisie du code (verifyOtp type 'email') : la session
-- vient alors d'un code reçu par e-mail (amr « otp »), preuve que l'usager
-- lit bien cette boîte. La colonne est protégée (protect_profile_columns),
-- l'usager ne peut pas la changer lui-même autrement.
create or replace function public.confirmer_mon_email()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Non connecté';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr', '[]'::jsonb)) a
    where a->>'method' in ('otp', 'magiclink', 'recovery')
  ) then
    raise exception 'Code de vérification manquant';
  end if;
  update public.profiles set email_verifie = true where id = auth.uid();
  return true;
end;
$$;

grant execute on function public.confirmer_mon_email() to authenticated;

-- Commandes et inscriptions aux événements : adresse vérifiée obligatoire.
-- Les agents (comptoir, back-office) ne sont pas concernés.
-- Pas « security definer » : current_user doit rester celui de l'appelant.
create or replace function public.require_email_verifie()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_agent() then
    return new;
  end if;
  if not coalesce((select email_verifie from public.profiles where id = new.user_id), false) then
    raise exception 'Vérifie ton adresse e-mail pour continuer (Profil > Vérifier mon compte).';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_a_require_email_verifie on public.reservations;
create trigger trg_a_require_email_verifie before insert on public.reservations
  for each row execute function public.require_email_verifie();

drop trigger if exists trg_a_require_email_verifie on public.event_rsvps;
create trigger trg_a_require_email_verifie before insert on public.event_rsvps
  for each row execute function public.require_email_verifie();
