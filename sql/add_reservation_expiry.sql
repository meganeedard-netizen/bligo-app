-- Ajoute l'expiration automatique à 48h des réservations non récupérées.

-- Autorise le nouveau statut "expiree"
alter table public.reservations drop constraint if exists reservations_status_check;
alter table public.reservations add constraint reservations_status_check
  check (status in ('preparation', 'pret', 'recupere', 'expiree'));

-- Fonction : remet le livre en rayon et marque la réservation comme expirée
create or replace function public.expire_old_reservations()
returns void
language plpgsql
security definer
as $$
declare
  cutoff timestamptz := now() - interval '48 hours';
begin
  update public.books
  set available = true
  where id in (
    select book_id from public.reservations
    where status in ('preparation', 'pret') and created_at < cutoff
  );

  update public.reservations
  set status = 'expiree'
  where status in ('preparation', 'pret') and created_at < cutoff;
end;
$$;

-- Planifie la vérification toutes les 15 minutes
create extension if not exists pg_cron with schema extensions;

select cron.unschedule('expire-reservations')
where exists (select 1 from cron.job where jobname = 'expire-reservations');

select cron.schedule('expire-reservations', '*/15 * * * *', $$select public.expire_old_reservations();$$);
