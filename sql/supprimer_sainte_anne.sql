-- Suppression de la médiathèque Sainte-Anne (21/10/2026, demande de Mégane)
-- ============================================================
-- BliGO ne garde que Val-Fleuri, médiathèque de démonstration (pas une vraie
-- médiathèque). État des lieux fait avant (diag_sainte_anne.sql et
-- diag_sainte_anne_2.sql) :
--   - 34 livres, tous en double avec Val-Fleuri → supprimés, avec leurs
--     35 exemplaires et 4 commandes de test (suppression en cascade) ;
--   - 2 événements, 3 livres hors condition, 111 lignes du journal d'activité
--     → supprimés ;
--   - 1 compte (Nicolas) et son adhésion → déplacés à Val-Fleuri.
-- Un seul bloc : si une étape échoue, rien n'est modifié.

do $$
declare
  v_sa bigint;
  v_vf bigint;
begin
  select id into v_sa from public.communes where name = 'Sainte-Anne';
  select id into v_vf from public.communes where name = 'Val-Fleuri';
  if v_sa is null then raise exception 'Sainte-Anne introuvable (déjà supprimée ?)'; end if;
  if v_vf is null then raise exception 'Val-Fleuri introuvable : rien n''est modifié'; end if;

  -- 1. Comptes et adhésions → Val-Fleuri (une adhésion en double est retirée).
  update public.profiles set commune_id = v_vf where commune_id = v_sa;
  delete from public.memberships m
   where m.commune_id = v_sa
     and exists (select 1 from public.memberships m2 where m2.user_id = m.user_id and m2.commune_id = v_vf);
  update public.memberships set commune_id = v_vf where commune_id = v_sa;

  -- 2. Livres en double (exemplaires et commandes de test partent avec).
  delete from public.books where commune_id = v_sa;
  -- Par sécurité : un exemplaire d'un autre livre encore rattaché à Sainte-Anne
  -- revient à Val-Fleuri plutôt que d'être supprimé.
  update public.book_copies set owner_commune_id = v_vf where owner_commune_id = v_sa;
  update public.book_copies set current_commune_id = v_vf where current_commune_id = v_sa;

  -- 3. Agenda, livres hors condition, journal d'activité.
  delete from public.events where commune_id = v_sa;
  delete from public.free_books where commune_id = v_sa;
  delete from public.activity_events where commune_id = v_sa;

  -- 4. La médiathèque elle-même.
  delete from public.communes where id = v_sa;
end $$;

-- Vérification : il ne doit rester que Val-Fleuri, et Nicolas doit y être.
select c.name as mediatheque,
       (select count(*) from public.books b where b.commune_id = c.id) as livres,
       (select count(*) from public.profiles p where p.commune_id = c.id) as comptes,
       (select string_agg(u.email, ', ') from public.profiles p join auth.users u on u.id = p.id
         where p.commune_id = c.id and u.email = 'nicop421@gmail.com') as nicolas
  from public.communes c;
