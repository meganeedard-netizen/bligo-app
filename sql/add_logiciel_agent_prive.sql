-- Téléchargement du logiciel agent réservé aux équipes (19/10/2026)
-- ============================================================
-- La page de téléchargement de bligo.fr demande le compte BliGO de l'agent.
-- Les fichiers (.exe Windows, .dmg Mac) sont rangés dans un espace PRIVÉ :
-- seul un compte agent, direction ou super admin connecté obtient un lien de
-- téléchargement, valable 10 minutes. Un usager ou un inconnu n'obtient rien,
-- même avec l'adresse exacte d'un fichier.
--
-- Après ce SQL : Dashboard › Storage › logiciel-agent › Upload, déposer
-- BliGO-Agent-Windows.exe et BliGO-Agent-Mac.dmg (noms exacts).

insert into storage.buckets (id, name, public, file_size_limit)
values ('logiciel-agent', 'logiciel-agent', false, 104857600)
on conflict (id) do update set public = false;

drop policy if exists "Les agents téléchargent le logiciel" on storage.objects;
create policy "Les agents téléchargent le logiciel"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'logiciel-agent' and (public.is_agent() or public.is_super_admin()));

-- Vérification : doit renvoyer logiciel-agent | false
select id, public from storage.buckets where id = 'logiciel-agent';
