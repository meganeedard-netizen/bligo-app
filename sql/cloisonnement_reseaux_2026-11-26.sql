-- Cloisonnement entre médiathèques (26/11/2026, accord de Mégane).
-- Avant : tout agent de n'importe quelle commune lisait les usagers, prêts,
-- réservations, dettes, dons… de TOUTES les médiathèques, et pouvait modifier
-- leurs livres, exemplaires et événements. Le logiciel filtrait à l'écran,
-- pas la base.
-- Maintenant : un agent ne voit et ne modifie que les données de son RÉSEAU
-- (communes de la même communauté : EPCI, BDP et ses bibliothèques). Le
-- travail en réseau (transferts, retour n'importe où, dépôts BDP) continue.
-- La super-administratrice (Mégane) garde l'accès complet.
-- Retour arrière : sql/retour_arriere_cloisonnement_2026-11-26.sql

-- Communes du réseau de l'agent connecté (sa commune seule si pas de réseau).
create or replace function public.agent_network_commune_ids()
returns bigint[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(c.id), '{}'::bigint[])
    from public.communes c
    join public.profiles p on p.id = auth.uid() and p.role in ('agent', 'super_admin')
    join public.communes moi on moi.id = p.commune_id
   where c.id = moi.id
      or (moi.community_id is not null and c.community_id = moi.community_id);
$$;

-- Vrai si l'agent connecté peut voir les données de cette commune.
create or replace function public.agent_sees_commune(p_commune_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin()
      or (p_commune_id is not null and p_commune_id = any (public.agent_network_commune_ids()));
$$;

-- Appelées dans les règles d'accès, donc aussi pour un visiteur sans compte
-- (elles répondent alors « rien » / « non »).
grant execute on function public.agent_network_commune_ids() to anon, authenticated;
grant execute on function public.agent_sees_commune(bigint) to anon, authenticated;

-- Nombre d'inscrits par événement, sans exposer qui est inscrit (l'agenda
-- lisait toute la table event_rsvps, lisible même sans compte).
create or replace function public.event_rsvp_counts(p_event_ids bigint[])
returns table (event_id bigint, n bigint)
language sql
stable
security definer
set search_path = public
as $$
  select r.event_id, count(*) from public.event_rsvps r
   where r.event_id = any (p_event_ids)
   group by r.event_id;
$$;
grant execute on function public.event_rsvp_counts(bigint[]) to anon, authenticated;

-- ---------- Usagers ----------
drop policy if exists "Un agent voit tous les profils" on public.profiles;
create policy "Un agent voit les usagers de son réseau" on public.profiles for select using (
  public.is_agent() and (
    public.agent_sees_commune(commune_id)
    or exists (select 1 from public.memberships m where m.user_id = profiles.id and public.agent_sees_commune(m.commune_id))
    or exists (select 1 from public.loans l where l.user_id = profiles.id and public.agent_sees_commune(l.borrowed_at_commune_id))
  )
);

-- ---------- Prêts ----------
drop policy if exists "Les agents gèrent les prêts" on public.loans;
drop policy if exists "Un usager voit ses propres prêts" on public.loans;
create policy "Un usager voit ses propres prêts" on public.loans for select using (auth.uid() = user_id);
create policy "Les agents gèrent les prêts de leur réseau" on public.loans for all using (
  public.is_super_admin()
  or public.agent_sees_commune(borrowed_at_commune_id)
  or public.agent_sees_commune(returned_at_commune_id)
  or exists (select 1 from public.book_copies c where c.id = loans.copy_id
             and (public.agent_sees_commune(c.owner_commune_id) or public.agent_sees_commune(c.current_commune_id)))
) with check (
  public.is_super_admin()
  or public.agent_sees_commune(borrowed_at_commune_id)
  or public.agent_sees_commune(returned_at_commune_id)
  or exists (select 1 from public.book_copies c where c.id = loans.copy_id
             and (public.agent_sees_commune(c.owner_commune_id) or public.agent_sees_commune(c.current_commune_id)))
);

-- ---------- Réservations ----------
drop policy if exists "Un agent voit toutes les réservations" on public.reservations;
drop policy if exists "Un agent met à jour toutes les réservations" on public.reservations;
create policy "Un agent voit les réservations de son réseau" on public.reservations for select using (
  public.is_super_admin() or public.is_agent() and (
    public.agent_sees_commune(pickup_commune_id)
    or exists (select 1 from public.books b where b.id = reservations.book_id and public.agent_sees_commune(b.commune_id))
  )
);
create policy "Un agent met à jour les réservations de son réseau" on public.reservations for update using (
  public.is_super_admin() or public.is_agent() and (
    public.agent_sees_commune(pickup_commune_id)
    or exists (select 1 from public.books b where b.id = reservations.book_id and public.agent_sees_commune(b.commune_id))
  )
);

-- ---------- Files d'attente ----------
drop policy if exists "Un usager voit ses files d'attente" on public.holds;
create policy "Un usager voit ses files d'attente" on public.holds for select using (
  auth.uid() = user_id
  or public.is_super_admin()
  or (public.is_agent() and (
    exists (select 1 from public.books b where b.id = holds.book_id and public.agent_sees_commune(b.commune_id))
    or exists (select 1 from public.reservations r where r.id = holds.reservation_id and public.agent_sees_commune(r.pickup_commune_id))
  ))
);

-- ---------- Dettes (documents perdus ou abîmés) ----------
drop policy if exists "Un usager voit ses dettes" on public.document_debts;
create policy "Un usager voit ses dettes" on public.document_debts for select using (
  auth.uid() = user_id or (public.is_agent() and public.agent_sees_commune(commune_id))
);

-- ---------- Dons ----------
drop policy if exists "Agent ou super-admin voit les dons" on public.donations;
create policy "Un agent voit les dons de son réseau" on public.donations for select using (
  public.is_super_admin() or public.is_agent() and (
    exists (select 1 from public.donation_sessions s where s.id = donations.session_id and public.agent_sees_commune(s.commune_id))
    or exists (select 1 from public.books b where b.id = donations.book_id and public.agent_sees_commune(b.commune_id))
  )
);

-- ---------- Événements et inscriptions ----------
drop policy if exists "Les inscriptions sont publiques en lecture" on public.event_rsvps;
create policy "Un usager voit ses inscriptions, un agent celles de son réseau" on public.event_rsvps for select using (
  auth.uid() = user_id
  or (public.is_agent() and exists (select 1 from public.events e where e.id = event_rsvps.event_id and public.agent_sees_commune(e.commune_id)))
);
drop policy if exists "Les agents voient les inscrits sans compte" on public.event_rsvp_guests;
create policy "Les agents voient les inscrits sans compte de leur réseau" on public.event_rsvp_guests for select using (
  public.is_agent() and exists (select 1 from public.event_rsvps r join public.events e on e.id = r.event_id
                                where r.id = event_rsvp_guests.rsvp_id and public.agent_sees_commune(e.commune_id))
);
drop policy if exists "La direction ajoute des événements" on public.events;
drop policy if exists "La direction modifie les événements" on public.events;
drop policy if exists "La direction supprime des événements" on public.events;
create policy "La direction ajoute des événements" on public.events for insert with check (public.is_direction() and public.agent_sees_commune(commune_id));
create policy "La direction modifie les événements" on public.events for update using (public.is_direction() and public.agent_sees_commune(commune_id)) with check (public.is_direction() and public.agent_sees_commune(commune_id));
create policy "La direction supprime des événements" on public.events for delete using (public.is_direction() and public.agent_sees_commune(commune_id));

-- ---------- Catalogue : livres et exemplaires (lecture publique inchangée) ----------
drop policy if exists "Les agents ajoutent des livres" on public.books;
drop policy if exists "La direction ajoute des livres" on public.books;
drop policy if exists "Les agents modifient les livres" on public.books;
drop policy if exists "La direction modifie les livres" on public.books;
drop policy if exists "La direction supprime des livres" on public.books;
create policy "Les agents ajoutent des livres" on public.books for insert with check (public.is_agent() and (commune_id is null or public.agent_sees_commune(commune_id)));
create policy "Les agents modifient les livres de leur réseau" on public.books for update using (public.is_agent() and (commune_id is null or public.agent_sees_commune(commune_id)));
create policy "La direction supprime des livres" on public.books for delete using (public.is_direction() and public.agent_sees_commune(commune_id));

drop policy if exists "Les agents gèrent les exemplaires" on public.book_copies;
create policy "Les agents gèrent les exemplaires de leur réseau" on public.book_copies for all using (
  public.is_agent() and (public.agent_sees_commune(owner_commune_id) or public.agent_sees_commune(current_commune_id))
) with check (
  public.is_agent() and (public.agent_sees_commune(owner_commune_id) or public.agent_sees_commune(current_commune_id))
);

-- ---------- Transferts, dépôts BDP ----------
drop policy if exists "Les agents voient et gèrent les transferts" on public.transfers;
create policy "Les agents gèrent les transferts de leur réseau" on public.transfers for all using (
  public.is_agent() and (public.agent_sees_commune(from_commune_id) or public.agent_sees_commune(to_commune_id))
) with check (
  public.is_agent() and (public.agent_sees_commune(from_commune_id) or public.agent_sees_commune(to_commune_id))
);
drop policy if exists "Les agents voient les dépôts" on public.depots;
create policy "Les agents voient les dépôts de leur réseau" on public.depots for select using (
  public.is_agent() and (public.agent_sees_commune(bdp_commune_id) or public.agent_sees_commune(library_commune_id))
);
drop policy if exists "Les agents voient les demandes de dépôt" on public.depot_requests;
create policy "Les agents voient les demandes de dépôt de leur réseau" on public.depot_requests for select using (
  public.is_agent() and (public.agent_sees_commune(bdp_commune_id) or public.agent_sees_commune(library_commune_id))
);

-- ---------- Fréquentation, récolement, journal ----------
drop policy if exists "Un agent ajoute des entrées visiteurs" on public.visitor_entries;
drop policy if exists "Un agent voit les entrées visiteurs" on public.visitor_entries;
drop policy if exists "Un agent corrige une entrée visiteur" on public.visitor_entries;
create policy "Un agent ajoute des entrées visiteurs" on public.visitor_entries for insert with check (public.is_agent() and public.agent_sees_commune(commune_id));
create policy "Un agent voit les entrées visiteurs" on public.visitor_entries for select using (public.is_agent() and public.agent_sees_commune(commune_id));
create policy "Un agent corrige une entrée visiteur" on public.visitor_entries for update using (public.is_agent() and public.agent_sees_commune(commune_id)) with check (public.is_agent() and public.agent_sees_commune(commune_id));

drop policy if exists "Les agents gèrent les scans de récolement" on public.inventory_scans;
create policy "Les agents gèrent les scans de récolement" on public.inventory_scans for all using (
  exists (select 1 from public.inventories i where i.id = inventory_scans.inventory_id
          and (public.is_super_admin() or (public.is_agent() and i.commune_id = public.agent_commune_id())))
) with check (
  exists (select 1 from public.inventories i where i.id = inventory_scans.inventory_id
          and (public.is_super_admin() or (public.is_agent() and i.commune_id = public.agent_commune_id())))
);

drop policy if exists "La direction consulte le journal d'activité" on public.activity_events;
create policy "La direction consulte le journal d'activité" on public.activity_events for select using (public.is_direction() and public.agent_sees_commune(commune_id));

drop policy if exists "Les agents voient les ouvertures" on public.digital_resource_opens;
create policy "Les agents voient les ouvertures" on public.digital_resource_opens for select using (
  public.is_agent() and exists (select 1 from public.digital_resources r where r.id = digital_resource_opens.resource_id and public.agent_sees_commune(r.commune_id))
);

-- Bibliothèque Libre (retirée) : plus aucun agent ne lit ces emprunts.
drop policy if exists "Un agent voit tous les emprunts hors condition" on public.free_book_loans;
drop policy if exists "Un agent met à jour les emprunts hors condition" on public.free_book_loans;
create policy "Un super-admin voit les emprunts hors condition" on public.free_book_loans for select using (public.is_super_admin());
create policy "Un super-admin met à jour les emprunts hors condition" on public.free_book_loans for update using (public.is_super_admin());
