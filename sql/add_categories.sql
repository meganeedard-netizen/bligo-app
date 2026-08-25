-- À exécuter dans Supabase (SQL Editor > New query > coller > Run)
-- Ajoute la catégorie et le résumé de chaque livre, pour l'aperçu au clic dans le catalogue.

alter table public.books add column if not exists category text;
alter table public.books add column if not exists summary text;

update public.books set category = 'Roman', summary = 'Fresque d''un quartier populaire de Martinique à travers plusieurs générations d''une famille créole, de la période coloniale à l''urbanisation moderne. Prix Goncourt 1992.' where id = 1;
update public.books set category = 'Roman', summary = 'La vie de Télumée, une femme guadeloupéenne confrontée à l''amour, aux épreuves et à la résilience à travers les générations. Un texte fondateur de la littérature caribéenne.' where id = 2;
update public.books set category = 'Roman épistolaire', summary = 'Une veuve sénégalaise écrit une longue lettre à sa meilleure amie, méditant sur le mariage, la polygamie et la condition des femmes dans l''Afrique post-coloniale.' where id = 3;
update public.books set category = 'Poésie', summary = 'Long poème fondateur du mouvement de la Négritude, méditation lyrique sur l''identité, la colonisation et l''héritage martiniquais et africain.' where id = 4;
update public.books set category = 'Roman', summary = 'Un conte initiatique et fantastique suivant Ti Jean dans une quête mêlant folklore caribéen, magie et recherche d''identité.' where id = 5;
update public.books set category = 'Roman', summary = 'Portrait satirique d''un prince africain déchu, confronté aux désillusions des jeunes nations africaines nouvellement indépendantes.' where id = 6;
update public.books set category = 'Roman', summary = 'Meursault, employé indifférent à Alger, commet un acte de violence absurde et affronte l''exigence de sens de la société. Un classique de la littérature existentialiste.' where id = 7;
update public.books set category = 'Roman historique', summary = 'Un village africain confronté à la disparition de ses jeunes hommes à l''aube de la traite négrière transatlantique. Prix Goncourt des lycéens 2013.' where id = 8;
update public.books set category = 'Thriller', summary = 'Un dîner qui tourne au cauchemar : secrets, manipulation et tension psychologique dans ce thriller à l''intrigue redoutable.' where id = 9;
update public.books set category = 'Thriller', summary = 'Un thriller psychologique haletant autour d''une professeure dont le passé cache de sombres secrets, jusqu''au twist final.' where id = 10;
update public.books set category = 'Roman feel-good', summary = 'Un roman chaleureux et plein de vie sur des destins ordinaires qui se croisent à des moments fragiles, entre résilience et lien humain.' where id = 11;
update public.books set category = 'Roman', summary = 'Une saga familiale tendre et bouleversante explorant les secrets et les liens entre plusieurs générations de femmes.' where id = 12;
update public.books set category = 'Thriller', summary = 'Les séances d''une psychothérapeute basculent dans une toile de manipulation et de danger, dans ce thriller psychologique addictif.' where id = 13;
update public.books set category = 'Thriller', summary = 'Un thriller sur l''identité et les vies qu''on aurait pu vivre, avec les retournements de situation caractéristiques de Guillaume Musso.' where id = 14;
update public.books set category = 'Thriller', summary = 'Une femme sans domicile devient gouvernante dans une famille aisée, et se retrouve prise dans un engrenage de mensonges et de danger.' where id = 15;
update public.books set category = 'Thriller', summary = 'Un thriller à suspense où le passé trouble d''une femme refait surface, l''obligeant à affronter des secrets qu''elle croyait enterrés.' where id = 16;
update public.books set category = 'Thriller', summary = 'La suite de « La femme de ménage » : la nouvelle vie de Millie se fissure quand d''anciens secrets et de nouvelles menaces se percutent.' where id = 17;
update public.books set category = 'Thriller', summary = 'La saga continue : Millie affronte un nouveau danger tandis que des vérités enfouies menacent la paix fragile qu''elle a construite.' where id = 18;
