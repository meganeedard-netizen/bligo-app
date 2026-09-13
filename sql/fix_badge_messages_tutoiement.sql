-- Les messages de notification des badges de fidélité étaient en vouvoiement
-- ("Vous avez débloqué...") — contraire à la règle BliGO du tutoiement partout.
-- Passage en tutoiement, sans toucher aux seuils ni à la logique de déblocage.

create or replace function public.check_and_award_badges(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_xp integer;
  v_plume_xp integer;
  v_current_tier integer;
  v_plume_unlocked boolean;
  v_coeur_unlocked boolean;
  v_donation_count integer;
  r record;
begin
  select loyalty_points, plume_locale_xp, badge_tier, plume_locale_unlocked, coeur_genereux_unlocked
    into v_xp, v_plume_xp, v_current_tier, v_plume_unlocked, v_coeur_unlocked
    from public.profiles where id = p_user_id;

  for r in
    select * from (values
      (1, 30, '📖 Félicitations ! Tu viens de débloquer le badge Premier Chapitre. Ton aventure BliGO commence aujourd''hui !'),
      (2, 100, '🔍 Bravo ! Badge Petit Curieux débloqué. Ta passion pour la lecture commence à porter ses fruits dans le quartier !'),
      (3, 250, '🎯 Bien joué ! Tu as débloqué le badge Dénicheur. Trouver les plus belles pépites de la commune, c''est ta spécialité !'),
      (4, 500, '📚 Super ! Badge Bouquineur débloqué. Déjà 10 livres remis en circulation grâce à toi. Merci pour la communauté !'),
      (5, 1000, '🤝 Impressionnant ! Tu obtiens le badge Passeur de Mots. Ta générosité fait voyager la culture de voisin en voisin !'),
      (6, 2000, '🚀 Quel rythme ! Félicitations, tu as débloqué le badge Dévoreur. Plus rien n''arrête ta soif de lecture !'),
      (7, 3500, '🌟 Chapeau bas ! Le badge Bibliophile est à toi. Un véritable pilier de la lecture partagée au cœur de ta commune !'),
      (8, 5000, '🏰 Incroyable ! Tu décroches le badge Gardien du Savoir. 100 livres partagés, un immense merci pour ce formidable impact local !'),
      (9, 7500, '👑 Légendaire ! Badge Maître des Pages débloqué. Ton engagement inspire toute la communauté BliGO !'),
      (10, 10000, '🏆 Sommet atteint ! Bravo, tu es officiellement une Légende BliGO. La culture de ta commune te dit un grand MERCI !')
    ) as t(tier, threshold, message)
    where tier > coalesce(v_current_tier, 0) and v_xp >= threshold
    order by tier asc
  loop
    insert into public.notifications (user_id, message) values (p_user_id, r.message);
    update public.profiles set badge_tier = r.tier where id = p_user_id;
  end loop;

  if coalesce(v_plume_xp, 0) >= 150 and not coalesce(v_plume_unlocked, false) then
    insert into public.notifications (user_id, message)
    values (p_user_id, '🌴 Bravo péyi ! Tu as débloqué le badge Plume Locale. Merci de faire rayonner les auteurs et la culture du territoire !');
    update public.profiles set plume_locale_unlocked = true where id = p_user_id;
  end if;

  select count(*) into v_donation_count from public.free_books where donated_by = p_user_id;
  if v_donation_count >= 5 and not coalesce(v_coeur_unlocked, false) then
    insert into public.notifications (user_id, message)
    values (p_user_id, '💛 Un grand Cœur ! Tu as débloqué le badge Cœur Généreux. Grâce à tes dons, tu donnes une seconde vie aux livres !');
    update public.profiles set coeur_genereux_unlocked = true where id = p_user_id;
  end if;
end;
$$;
