// Accord au prénom (27/11/2026, demande de Mégane) : « Inscrite » ou
// « Inscrit » selon le prénom de l'usager, et l'écriture inclusive (« Inscrit·e »)
// quand on ne sait pas (prénom mixte comme Camille ou Dominique, ou inconnu).
// Rien n'est stocké : on déduit à l'affichage, à partir du premier prénom.

const FEMININS = new Set(`
adele adeline adrienne agathe agnes aicha alexandra alexia alice aline alicia alison amandine amelie amelia ana anais anastasia andrea angele angelique anissa anna annabelle anne annick annie anouk antoinette apolline ariane arielle armelle audrey aurelie aurore axelle beatrice belinda benedicte berenice bernadette blanche brigitte capucine carine carla carmen carole caroline cassandra catherine cecile celia celine chantal charlene charlotte chloe christelle christiane christine claire clara clarisse claudine clemence clementine colette coline coralie corinne cynthia daisy daniele danielle delphine denise diane dominika dorothee edith eleonore elise elisa elodie eloise elsa emeline emilie emma emmanuelle estelle esther eugenie eva eve evelyne fabienne fanny fatima fatou flavie flore florence florine francine francoise gabrielle genevieve georgette geraldine germaine ghislaine gisele grace helene heloise henriette hortense ines ingrid irene isabelle jacqueline jade jeanne jennifer jessica jocelyne joelle josephine josiane judith julia julie juliette justine karine katia kelly laetitia laura laure laurence lea leana leila lena leonie liliane lina linda line lisa lise lola lou louane louise louna luce lucie lucienne ludivine lydie madeleine maelle maeva magali manon marcelle margaux margot marguerite maria marianne marie marie-claire marie-france marie-josee marie-laure marie-noelle marie-paule marielle marine marion marjorie marlene marthe martine maryse mathilde maud maureen megane melanie melissa micheline mila mireille monique morgane muriel myriam nadege nadia nadine naomi natacha nathalie nelly nicole nina noemie oceane odette odile olga olivia ophelie patricia paule paulette pauline perrine rachel raymonde regine rebecca renee rose rosine roxane sabine sabrina salome samantha sandra sandrine sarah severine simone solange solene sonia sophie stephanie suzanne suzette sylvie tatiana therese tiphaine valentine valerie vanessa veronique victoire victoria violette virginie viviane yolande yvette yvonne zoe
`.trim().split(/\s+/));

const MASCULINS = new Set(`
aaron adam adrien alain alban albert alexandre alexis alfred alphonse ambroise andre anthony antoine antonin armand arnaud arthur augustin aurelien axel baptiste barthelemy basile bastien benjamin benoit bernard bertrand bruno cedric charles christian christophe clement corentin cyril cyrille damien daniel david denis didier dimitri dylan edouard elie eliott emile emmanuel enzo eric erwan etienne eugene fabien fabrice felix ferdinand florent florian francis franck francois frederic gabriel gael gaetan gaston gauthier georges gerard gerald gilbert gilles gregoire gregory guillaume gustave guy hadrien hector henri herve hugo hugues jacques james jean jean-baptiste jean-charles jean-claude jean-francois jean-jacques jean-louis jean-luc jean-marc jean-marie jean-michel jean-paul jean-pierre jeremie jeremy jerome joel johan jonathan jordan joseph josue jules julien kevin kylian laurent leo leon leonard lionel loic lorenzo louis luc lucas ludovic lukas marc marcel marius martin mathias mathieu matheo mathis matteo matthieu maurice max maxime maximilien medhi mehdi michel mickael nathan nicolas noah noe noel norbert octave olivier oscar pascal patrice patrick paul philippe pierre quentin raphael raymond regis remi renaud rene richard robert robin rodolphe roger roland romain romeo ruben samuel sebastien serge simon stephane steve sylvain theo theodore thibault thibaut thierry thomas timothee tom tony tristan ulysse valentin victor vincent william xavier yann yannick yanis yves yvan
`.trim().split(/\s+/));

function normaliser(prenom) {
  return String(prenom || '').trim().toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '');
}

// 'f', 'm' ou null (on ne sait pas). Prénom composé : on essaie le prénom
// entier (« Marie-Claire »), puis sa première partie (« Jean » de « Jean-Noël »).
export function genreDuPrenom(nomComplet) {
  const premier = normaliser(nomComplet).split(/\s+/)[0] || '';
  for (const essai of [premier, premier.split('-')[0]]) {
    if (FEMININS.has(essai)) return 'f';
    if (MASCULINS.has(essai)) return 'm';
  }
  return null;
}

// accord('f', 'Inscrit', 'Inscrite') → « Inscrite » ; genre inconnu → « Inscrit·e ».
export function accord(genre, masculin, feminin, inclusif) {
  if (genre === 'f') return feminin;
  if (genre === 'm') return masculin;
  return inclusif || `${masculin}·${feminin.slice(masculin.length) || 'e'}`;
}
