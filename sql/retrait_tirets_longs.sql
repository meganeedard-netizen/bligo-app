-- Plus aucun grand tiret dans les messages envoyés par la base (23/10/2026) :
-- notifications de défis réussis, messages d'erreur de réservation, etc.
-- Les fonctions concernées sont réécrites à l'identique, avec « - » à la place
-- de « — » entouré d'espaces (les tirets collés, ex. dans une expression
-- régulière, ne sont pas touchés).

do $$
declare
  f record;
  def text;
begin
  for f in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.prosrc like '% — %'
  loop
    def := pg_get_functiondef(f.oid);
    execute replace(def, ' — ', ' - ');
  end loop;
end $$;

-- Notifications déjà reçues par les usagers.
update public.notifications set message = replace(message, ' — ', ' - ') where message like '% — %';

-- Vérification : doit renvoyer 0 et 0.
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosrc like '% — %') as fonctions_restantes,
  (select count(*) from public.notifications where message like '% — %') as notifications_restantes;
