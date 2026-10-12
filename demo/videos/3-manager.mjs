// Vidéo 3 : Julien, conducteur de travaux, rôle « Manager » — pilote toute l'entreprise sans en régler les paramètres.
import { APP, helpers, record } from '../lib/helpers.mjs';

export const warmup = ['julien@demo.clockifai.fr'];
export const name = '3-julien-manager';
const ROLE = 'Manager';
const C = (chapter) => `Julien · ${chapter}`;

/** Lundi prochain (dans les deux semaines affichées par le planning). */
const nextMonday = () => { const d = new Date(); d.setDate(d.getDate() + ((8 - d.getDay()) % 7 || 7)); return d; };

export async function run(browser, failures) {
  const desktop = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.goto(APP);
    await h.wait(3500);
    await h.card('Vidéo 3 / 5 · Julien', 'Conducteur de travaux, rôle « Manager »', [
      'Voir le temps de toute l’entreprise, toutes équipes confondues',
      'Valider les feuilles de temps et les absences de chacun',
      'Planifier les affectations sur les chantiers',
      'Exporter pour la paie, suivre les budgets, facturer',
      'Sans toucher aux règles ni aux rôles de l’entreprise',
    ], 7000);
    await h.hideCard();

    await h.scene('connexion', async () => {
      await h.login('julien@demo.clockifai.fr');
      await h.caption(C('Son menu'), 'Manager : toute l’entreprise, sans les réglages', 'Sophie, la propriétaire, lui a donné ce rôle. Il a les écrans d’équipe et les factures, pas la gestion des rôles ni des règles.', ROLE, 6000);
    });

    await h.scene('équipe', async () => {
      await h.nav('Équipe');
      await h.caption(C('Équipe'), 'Les heures de tout le monde', 'Toutes les équipes, Nadia comprise, avec les taux horaires. Mais ni invitation ni changement de rôle : c’est l’affaire de Sophie.', ROLE, 6000);
    });

    await h.scene('approbations', async () => {
      await h.nav('Approbations');
      await h.caption(C('Approbations'), 'Toutes les feuilles soumises', 'Léo (équipe Unité 4) et Nadia (équipe Calorifuge). Karim, chef d’équipe, ne voyait que celle de Léo.', ROLE, 4500);
      await h.click(/Nadia Rahmani/, 2000);
      await h.caption(C('Approbations'), 'La semaine de Nadia, entrée par entrée', 'Calorifuge le matin, préparation de l’arrêt de tranche l’après-midi.', ROLE, 3500);
      await h.clickNear(/Nadia Rahmani/, /^Approuver$/, 2500);
      await h.caption(C('Approbations'), 'Approuvée : la semaine est verrouillée', 'Plus personne ne la modifie, sauf un administrateur.', ROLE, 3500);
    });

    await h.scene('absences', async () => {
      await h.nav('Absences');
      await h.caption(C('Absences'), 'Les demandes de toute l’entreprise', 'Hugo (équipe de Karim) et Nadia. Un chef d’équipe valide son équipe ; le manager, tout le monde.', ROLE, 5000);
      await h.clickNear(/Nadia Rahmani/, /^Approuver$/, 2000);
      await h.caption(C('Absences'), 'Congés de Nadia approuvés', 'Ils s’affichent dans le planning et sont décomptés de son solde.', ROLE, 3500);
    });

    await h.scene('planning', async () => {
      await h.nav('Planning');
      await h.caption(C('Planning'), 'Qui est où, sur deux semaines', 'En rouge, la surcharge : Karim est prévu 8 h par jour pour 7 h de capacité.', ROLE, 4500);
      // Un clic dans une case libre crée une affectation pour cette personne et ce jour : Hugo, lundi prochain.
      const day = nextMonday().getDate();
      const col = await h.find(new RegExp(`(^|\\D)${day}$`), { which: 'top' });
      const row = await h.find(/Hugo Petit/);
      await h.clickXY(col.x, row.y, 1500);
      await h.caption(C('Planning'), 'Affecter Hugo à l’arrêt de tranche', 'Un clic dans la case du jour : la personne et la date sont déjà remplies.', ROLE, 2500);
      await h.pick(/^Sans projet$/, 900);
      await h.typeInto('Rechercher un projet, une tâche, un client', 'Arrêt');
      await h.pick(/^Arrêt de tranche 2026/, 1000);
      await h.typeInto('Commentaire (facultatif)', 'Préparation des échafaudages');
      await h.clickLast(/^Enregistrer$/, 2500);
      await h.caption(C('Planning'), 'Hugo est prévu lundi sur l’arrêt de tranche', 'Il le voit dans son propre planning. Une affectation peut aussi couvrir plusieurs jours.', ROLE, 5000);
    });

    await h.scene('rapports', async () => {
      await h.nav('Rapports');
      await h.click(/^Cette semaine$/, 900);
      await h.pick(/^Ce mois-ci$/, 1500);
      await h.click(/Grouper par projet/, 900);
      await h.pick(/^Grouper par utilisateur$/, 1800);
      await h.caption(C('Rapports'), 'Les heures de chacun sur le mois', 'Toute l’entreprise, Nadia et Julien compris, avec les montants au taux de chaque personne ou projet.', ROLE, 5000);
      await h.click(/^Exporter$/, 900);
      await h.menuItem('Excel (.xlsx)', 1500);
      await h.find(/^Export téléchargé/, { timeout: 20000 });
      await h.caption(C('Export'), 'Un fichier Excel pour la paie', 'Une ligne par entrée : personne, client, projet, tâche, horaires, durée. Existe aussi en CSV et en PDF.', ROLE, 5000);
    });

    await h.scene('projets', async () => {
      await h.nav('Projets');
      await h.caption(C('Projets'), 'Les budgets des chantiers', 'Heures passées comparées au budget de chaque projet. Le manager crée aussi projets, tâches et clients.', ROLE, 5500);
    });

    await h.scene('paramètres', async () => {
      await h.nav('Paramètres');
      await h.reveal(/^Seuls les administrateurs peuvent modifier ces réglages/, 220);
      await h.caption(C('Paramètres'), 'Les règles, en lecture seule', 'Il les voit sans pouvoir les changer : règles, rôles, groupes et tablettes restent l’affaire de Sophie, la propriétaire.', ROLE, 6500);
    });
  });

  const end = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.setContent('<html><body style="margin:0;background:#0f172a"></body></html>');
    await page.evaluate(() => window.__demo.ensure());
    await h.card('Julien, manager', 'Ce qu’il peut faire, pour toute l’entreprise', [
      'Voir le temps de chacun ; le saisir si la règle de l’entreprise le permet',
      'Approuver ou refuser les feuilles de temps et les absences',
      'Planifier, suivre les budgets, exporter, facturer',
      'Créer projets, tâches, clients et tags',
      'Pas de rôles, de groupes, de règles ni de tablettes kiosque',
    ], 7000);
  });

  return [{ webm: desktop }, { webm: end }];
}
