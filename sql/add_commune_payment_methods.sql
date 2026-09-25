-- Moyens de paiement acceptés par médiathèque, affichés à l'usager en
-- préinscription (montant de l'abonnement + comment le régler au retrait de
-- sa première commande). Les deux à true par défaut (carte + espèces),
-- ajustable par la direction dans "Tarifs médiathèque".

alter table public.communes
  add column if not exists accepts_card boolean not null default true,
  add column if not exists accepts_cash boolean not null default true;

comment on column public.communes.accepts_card is 'Carte bancaire acceptée pour régler l''abonnement.';
comment on column public.communes.accepts_cash is 'Espèces acceptées pour régler l''abonnement.';

create or replace function public.update_commune_tariffs(
  p_commune_id bigint, p_mineur_cents integer, p_majeur_cents integer, p_gratuit_cents integer,
  p_accepts_card boolean, p_accepts_cash boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;

  update public.communes
    set tariff_mineur_cents = p_mineur_cents,
        tariff_majeur_cents = p_majeur_cents,
        tariff_gratuit_cents = p_gratuit_cents,
        accepts_card = p_accepts_card,
        accepts_cash = p_accepts_cash,
        tariff_updated_at = now(),
        tariff_updated_by = auth.uid()
    where id = p_commune_id;
end;
$$;
