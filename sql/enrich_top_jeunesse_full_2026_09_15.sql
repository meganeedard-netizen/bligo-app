-- BliGO — Fiche complète pour le Top Jeunesse (15/09/2026)
-- Résumé, format, éditeur, date de publication, nombre de pages, langue,
-- récupérés via Google Books (Open Library en appoint pour le format).
-- Chaque résumé vérifié un par un : 3 retirés (fiche produit/pédagogique
-- plutôt qu'un vrai résumé, ou mauvaise langue).
--
-- Prérequis : sql/add_curated_lists_full_record.sql
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

-- Harry Potter à l'école des sorciers
update public.top_jeunesse_books set publisher = 'Gallimard-Jeunesse', published_date = '2008-10-02', page_count = '324', language = 'fr' where rank = 1;

-- Mortelle Adèle
update public.top_jeunesse_books set summary = 'L''héroïne N°1 de la bande dessinée jeunesse revient dans un 23e tome de gags toujours aussi attendu du public ! Plus de 70 gags pleins d''énergie et de réflexions sur le quotidien, comme Antoine Dole alias Mr Tan en a le secret, et toujours illustrée par la talentueuse Diane Le Feyer ! © Mr Tan et Diane Le Feyer d''après l''œuvre créée par Mr Tan et Miss Prickly © Mr Tan & Co', publisher = 'Mr Tan Company', published_date = '2026-05-28', page_count = '80', language = 'fr' where rank = 2;

-- Gardiens des Cités Perdues
update public.top_jeunesse_books set summary = 'Vous rêvez de visiter l''ATlantide ou la mythique cité de Shangri-La ? Suivez le guide ! Sophie ne sait plus quelle stratégie adopter. Ses amis eux-mêmes semblent avoir perdu la foi : leur retentissante victoire en Atlantide aurait dû marquer un tournant décisif dans le combat contre les Invisibles, et pourtant la lutte paraît au point mort. Toujours prêtes à déstabiliser le monde des elfes, Vespéra et Lady Gisela ont disparu dans la nature. Quant à Fintan, prisonnier du Conseil, il refuse obstinément de révéler quoi que ce soit de leurs sombres plans. Pour couronner le tout, les jeunes recrues du Cygne Noir reçoivent un véritable coup de massue à l''énoncé du verdict du procès d''Alvar, toujours amnésique. Mais quand Sophie et Fitz, victimes d''une nouvelle attaque, échappent de justesse à la mort, ils n''ont plus guère le choix. S''ils veulent garder une chance de l''emporter face à ces ennemis sans pitié, il leur faut dès à présent changer radicalement de tactique pour adopter celle de leurs adversaires – quitte à trahir leur nature et leurs plus intimes convictions... Dans ce septième tome de Gardiens des Cités perdues, Shannon Messenger fait sortir de l''ombre, avec un délice évident, les secrets les plus inquiétants du monde des elfes... Sophie Foster n''a pas fini de vous réserver des surprises !', publisher = 'Lumen', published_date = '2018-11-15', page_count = '620', language = 'fr' where rank = 3;

-- Le Journal d'un dégonflé
update public.top_jeunesse_books set summary = 'Grâce à un héritage inattendu, les Heffley vont pouvoir faire de grands travaux dans leur maison. Mais dès le premier coup de marteau, les problèmes commencent. Bois pourri, moisissures, bestioles envahissantes et pire encore... Manifestement, la demeure de Greg est en très mauvais état ! Les Heffley réussiront-ils à sauver leur maison, ou devront-ils plier bagages ?', publisher = 'Média Diffusion', published_date = '2019-11-07T00:00:00+01:00', page_count = '226', language = 'fr' where rank = 4;

-- Le Petit Prince
update public.top_jeunesse_books set publisher = 'Numitor Comun Publishing', published_date = '1943', language = 'fr' where rank = 5;

-- Chair de poule
update public.top_jeunesse_books set summary = 'Axel découvre que le camp d''été où il a été envoyé cache de terribles secrets. Des enfants disparaissent, d''horribles créatures hantent les lieux la nuit, et les moniteurs proposent de dangereuses activités. Axel décide de mener son enquête, mais personne semble vouloir répondre à ses questions... Une collection toujours aussi captivante Avec la sortie de l''adaptation sur Disney+ en octobre 2023, l''intérêt des fans d''épouvante est renouvelé pour cette collection incontournable. Depuis 1995, la série Chair de Poule a conquis plus de 12 millions de lecteurs en France. Ce tome est une nouvelle édition dotée d''une couverture revisitée, s''inspirant de l''esthétique des jeux vidéo pour attirer un nouveau public. Avec déjà 39 000 exemplaires vendus, cette aventure angoissante promet des frissons à tous ses lecteurs . Une lecture qui vous tient en haleine. Les lecteurs apprécient l''intensité et l''atmosphère mystérieuse du camp : "J''ai adoré ce tome. On est plongé dans une ambiance angoissante dès les premières pages. Les disparitions et les créatures sont vraiment bien décrits, on a envie de savoir la vérité" . Un autre lecteur a souligné que La colo de la peur "vous tient en haleine jusqu''à la dernière page" .', publisher = 'Bayard Jeunesse', published_date = '2024-04-03', page_count = '96', language = 'fr' where rank = 6;

-- Hunger Games
update public.top_jeunesse_books set summary = 'Une magnifique édition du tome 1 illustrée en noir et blanc ! Dans chaque district de Panem, une société reconstruite sur les ruines des États-Unis, deux adolescents sont choisis pour participer aux Hunger Games. La règle est simple : tuer ou se faire tuer. Celui qui remporte l''épreuve, le dernier survivant, assure la prospérité à son district pendant un an. Katniss et Peeta sont les " élus " du district numéro douze. Les voilà catapultés dans un décor violent, semé de pièges, où la nourriture est rationnée et, en plus, ils doivent remporter les votes de ceux qui les observent derrière leur télé... Alors que les candidats tombent comme des mouches, que les alliances se font et se défont, Peeta déclare sa flamme pour Katniss à l''antenne. La jeune fille avoue elle-aussi son amour. Calcul ? Idylle qui se conclura par la mort d''un des amants ? Un suicide ? Tout est possible, et surtout, tout est faussé au sein des Hunger Games...', publisher = 'lePetitLitteraire.fr', published_date = '2016-01-21', page_count = '49', language = 'fr' where rank = 7;

-- La Passe-miroir
update public.top_jeunesse_books set summary = 'Le premier volume de la saga fantastique devenue culte, maintenant en bande dessinée. Lorsque sa famille la fiance à Thorn, du puissant clan des Dragons, Ophélie doit tout quitter pour le suivre jusqu''à la Citacielle. À la cour du seigneur Farouk, les apparences sont trompeuses et les intrigues parfois mortelles...', publisher = 'Éditions Gallimard BD', published_date = '2026-01-28T00:00:00+01:00', page_count = '289', language = 'fr' where rank = 8;

-- Percy Jackson
update public.top_jeunesse_books set summary = 'Je n''ai jamais voulu être un demi-dieu. Une vie de demi-dieu, c''est dangereux, c''est angoissant. Le plus souvent, ça se termine par une mort abominable et douloureuse. Il se peut que vous soyez des nôtres. Or, dès l''instant où vous le saurez, il ne leur faudra pas longtemps pour le percevoir, eux aussi, et se lancer à vos trousses. Je vous aurai prévenus.', publisher = 'Livre de Poche Jeunesse (Le)', published_date = '2016-10-12', language = 'fr', format = 'Broché' where rank = 9;

-- Les Carnets de Cerise
update public.top_jeunesse_books set summary = 'Une série d''enquêtes fraîches et sucrées entre bande dessinée et carnet intime!', publisher = 'Soleil', published_date = '2014-11-13', page_count = '90', language = 'fr' where rank = 10;

-- Ewilan
update public.top_jeunesse_books set summary = 'En Gwendalavir, Ewilan et Salim partent avec leurs compagnons aux abords des Frontières de Glace pour libérer les Sentinelles garantes de la paix. Ils repoussent en chemin les attaques de guerriers cochons, d''ogres et de mercenaires du Chaos, résolus avec les Ts''liches à tuer Ewilan, mais se découvrent un peuple allié : les Faëls. Salim se lie d''amitié avec une marchombre aux pouvoirs fascinants, tandis qu''Ewilan assoit son autorité et affermit son Don. Mais pour prétendre délivrer les Sentinelles, elle devra d''abord percer le secret du Dragon. Pour en savoir plus : www.ewilan.com', publisher = 'Rageot Editeur', published_date = '2006-05-17', page_count = '195', language = 'fr' where rank = 11;

-- Charlie et la Chocolaterie
update public.top_jeunesse_books set summary = '"Moi, Willy Wonka, j''ai décidé de permettre à cinq enfants de visiter ma chocolaterie cette année. Ces cinq chanceux seront initiés à tous mes secrets, à toute ma magie."-- Quatrième de couverture.', published_date = '2016-06-16', language = 'fr' where rank = 12;

-- Twilight
update public.top_jeunesse_books set summary = 'Bella, dix-sept ans, décide de quitter l’Arizona ensoleillé où elle vivait avec sa mère, pour s’installer chez son père. Elle croit renoncer à tout ce qu’elle aime, certaine qu’elle ne s’habituera jamais ni à la pluie, ni à la petite ville de Forks, où l’anonymat est interdit. Mais elle rencontre Edwards, lycéen de son âge, d’une beauté inquiétante. Quels mystères et quels dangers cache cet être insaisissable, aux humeurs si changeantes ? A la fois attirant et hors d’atteinte, Edward Cullen n’est pas humain. Il est plus que ça. Bella en est certaine.', publisher = 'Hachette', published_date = '2011-01-12', page_count = '570', language = 'fr' where rank = 13;

-- Tobie Lolness
update public.top_jeunesse_books set summary = 'Couronné de nombreux prix (prix TAM-TAM, prix SAINT-EXUPÉRY, prix SORCIÈRES, prix LIRE AU COLLÈGE, etc), ce premier roman a été traduit dans plus de vingt-six langues. Titre recommandé par le ministère de l''Éducation nationale en classe de CM1, CM2, 6e,5e et 4e. Fiche pédagogique téléchargeable gratuitement sur le site www.cercle-enseignement.com.', publisher = 'Gallimard Jeunesse', published_date = '2014-03-06T00:00:00+01:00', page_count = '283', language = 'fr' where rank = 14;

-- Les Enfants de la Résistance
update public.top_jeunesse_books set summary = 'Les enfants de la Résistance ont maintes fois manqué mourir pour leurs idées. Cette fois, ils devront risquer leur vie pour la libre circulation de l''information. Ou plutôt la circulation de l''information libre ! En cet été 1943, la nouvelle mission du Lynx est de livrer un stock de papier qui servira à imprimer les journaux de la Résistance... à 250 km de chez eux. Pour cela, ils vont devoir monter tout un réseau. Ce qui implique de prendre le plus grand des risques : faire confiance...', publisher = 'Le Lombard', published_date = '2022-09-16T00:00:00+02:00', page_count = '59', language = 'fr' where rank = 15;

-- Nos étoiles contraires
update public.top_jeunesse_books set summary = 'Entre rire et larmes, le destin bouleversant de deux amoureux de la vie. Hazel, 16 ans, est atteinte d''un cancer. Son dernier traitement semble avoir arrêté l''évolution de la maladie, mais elle se sait condamnée. Bien qu''elle s''y ennuie passablement, elle intègre un groupe de soutien, fréquenté par d''autres jeunes malades. C''est là qu''elle rencontre Augustus, un garçon en rémission, qui partage son humour et son goût de la littérature. Entre les deux adolescents, l''attirance est immédiate. Et malgré les réticences d''Hazel, qui a peur de s''impliquer dans une relation dont le temps est compté, leur histoire d''amour commence... les entraînant vite dans un projet un peu fou, ambitieux, drôle et surtout plein de vie. . Élu " Meilleur roman 2012 " par le Time Magazine ! Prix de L''Échappée Lecture 2014 de la Nièvre Prix du Jury littéraire Giennois 2014 Prix Plaisirs de lire 2014, département de l''Yonne Prix des Embouquineurs 2014 Prix Farniente 2015 (Belgique) Prix Les goûts et les couleurs 2015 CANOPE - Académie de Rennes Prix des Incorruptibles 2015', publisher = 'Nathan', published_date = '2013-02-14', page_count = '287', language = 'fr' where rank = 16;

-- Divergente
update public.top_jeunesse_books set summary = 'Différente. Déterminée. Dangereuse. Tris vit dans un monde post-apocalyptique où la société est divisée en cinq factions. À 16 ans elle doit choisir sa nouvelle appartenance pour le reste de sa vie. Cas rarissime, son test d''aptitudes n''est pas concluant. Elle est divergente. Ce secret peut la sauver... ou la tuer.', publisher = 'Nathan', published_date = '2012-10-31', page_count = '433', language = 'fr' where rank = 17;

-- Les Chroniques de Narnia
update public.top_jeunesse_books set publisher = 'Gallimard Jeunesse', published_date = '2013-10-10T00:00:00+02:00', page_count = '147', language = 'fr' where rank = 18;

-- Le Lion
update public.top_jeunesse_books set publisher = 'Gallimard Jeunesse', published_date = '2015-09-10T00:00:00+02:00', page_count = '235', language = 'fr' where rank = 19;

-- À contre-sens
update public.top_jeunesse_books set summary = 'Malgré ses promesses, Nick est retombé dans son vice : les courses de voitures illégales. Il a beau aimer Noah plus que tout, la soif de danger et de vitesse finit toujours par le rattraper. Même si, grâce à Noah, Nick échappe de justesse à la police, son délit n’est pas sans conséquences : alors qu’elle couvrait leur fuite, leur amie Jenna est arrêtée. Au même moment, Nick reçoit une proposition d’embauche dans un prestigieux cabinet d’avocats, qui pourrait régler nombre de soucis. Mais qui va surtout l’envoyer loin de Noah. Alors que, pour lutter contre ses démons intérieurs, Noah a plus que jamais besoin du soutien de Nick, cette promotion inattendue va-t-elle signer la fin de leur histoire d’amour ?', publisher = 'Hachette Romans', published_date = '2019-06-26', page_count = '255', language = 'fr' where rank = 20;

