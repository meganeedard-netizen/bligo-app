-- 16/10/2026
-- Tutoiement partout : les messages automatiques (notifications de l'appli et
-- e-mails) disaient encore « Votre », « vous », « Pensez »… Les mêmes
-- fonctions ont été redéfinies dans plusieurs fichiers au fil du temps : au
-- lieu de deviner la dernière version, on corrige directement les fonctions
-- en place dans la base, phrase par phrase. La logique ne change pas, seul le
-- texte change. Les anciennes notifications déjà reçues sont corrigées aussi.

drop table if exists pg_temp.tutoiement_phrases;
create temporary table tutoiement_phrases (ord int, avant text, apres text);
insert into tutoiement_phrases values
  (1,  'Votre inscription a été validée par la médiathèque ! Votre carte et votre QR code sont maintenant actifs dans votre profil.',
       'Ton inscription a été validée par la médiathèque ! Ta carte et ton QR code sont maintenant actifs dans ton profil.'),
  (2,  ' » que vous attendiez est revenu : il est mis de côté pour vous à la médiathèque.',
       ' » que tu attendais est revenu : il est mis de côté pour toi à la médiathèque.'),
  (3,  'Vous avez 48 heures pour venir le chercher', 'Tu as 48 heures pour venir le chercher'),
  (4,  'Félicitations ! Vous venez de débloquer', 'Félicitations ! Tu viens de débloquer'),
  (5,  'Grâce à vos dons, vous donnez', 'Grâce à tes dons, tu donnes'),
  (6,  'Votre adhésion à la médiathèque arrive à échéance', 'Ton adhésion à la médiathèque arrive à échéance'),
  (7,  'Votre adhésion expire le', 'Ton adhésion expire le'),
  (8,  'Votre adhésion a été renouvelée', 'Ton adhésion a été renouvelée'),
  (9,  'Pensez à la renouveler', 'Pense à la renouveler'),
  (10, 'Votre livre est arrivé', 'Ton livre est arrivé'),
  (11, 'Votre livre hors condition', 'Ton livre hors condition'),
  (12, 'Votre réservation', 'Ta réservation'),
  (13, 'Votre aventure BliGO', 'Ton aventure BliGO'),
  (14, 'Votre passion', 'Ta passion'),
  (15, 'Votre générosité', 'Ta générosité'),
  (16, 'Votre engagement', 'Ton engagement'),
  (17, 'est votre spécialité', 'est ta spécialité'),
  (18, 'arrête votre soif', 'arrête ta soif'),
  (19, 'commune vous dit', 'commune te dit'),
  (20, 'de votre commune', 'de ta commune'),
  (21, 'grâce à vous', 'grâce à toi'),
  (22, 'est à vous', 'est à toi'),
  (23, 'Vous avez débloqué', 'Tu as débloqué'),
  (24, 'vous avez débloqué', 'tu as débloqué'),
  (25, 'Vous obtenez', 'Tu obtiens'),
  (26, 'Vous décrochez', 'Tu décroches'),
  (27, 'vous êtes officiellement', 'tu es officiellement'),
  (28, 'Merci pour votre avis', 'Merci pour ton avis'),
  (29, 'Merci pour votre contribution', 'Merci pour ta contribution'),
  (30, 'Vous gagnez', 'Tu gagnes'),
  (31, 'vous gagnez', 'tu gagnes'),
  (32, 'Il vous reste', 'Il te reste'),
  (33, 'Votre médiathèque', 'Ta médiathèque');

-- 1. Fonctions en place (notifications, badges, défis, e-mails)
do $$
declare
  f record;
  ph record;
  def text;
  newdef text;
begin
  for f in
    select p.oid, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.prosrc ~* '\m(vous|votre|vos|pensez)\M'
  loop
    def := pg_get_functiondef(f.oid);
    newdef := def;
    for ph in select * from tutoiement_phrases order by ord loop
      newdef := replace(newdef, ph.avant, ph.apres);
    end loop;
    if newdef <> def then
      execute newdef;
      raise notice 'Passée au tutoiement : %', f.proname;
    end if;
  end loop;
end $$;

-- 2. Notifications déjà reçues par les usagers
do $$
declare
  ph record;
begin
  for ph in select * from tutoiement_phrases order by ord loop
    update public.notifications set message = replace(message, ph.avant, ph.apres)
     where position(ph.avant in message) > 0;
  end loop;
end $$;

-- Vérification : fonctions où il reste « vous / votre / vos / pensez ».
-- Normalement aucune ligne (ou seulement des titres de livres).
select p.proname as fonction,
       substring(p.prosrc from '(?i).{0,40}\m(vous|votre|vos|pensez)\M.{0,40}') as extrait
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind = 'f'
   and p.prosrc ~* '\m(vous|votre|vos|pensez)\M';
