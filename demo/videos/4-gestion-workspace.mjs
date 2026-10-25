// Vidéo 4 : Sophie, propriétaire du workspace « Échafaudages du Nord » — organise l'équipe et fixe les règles.
import { APP, KIOSK_TOKEN, helpers, record } from '../lib/helpers.mjs';

export const warmup = ['sophie@demo.clockifai.fr'];
export const name = '4-sophie-gestion-workspace';
const ROLE = 'Propriétaire';
const C = (chapter) => `Sophie · ${chapter}`;

export async function run(browser, failures) {
  const desktop = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.goto(APP);
    await h.wait(3500);
    await h.card('Vidéo 4 / 5 · Sophie', 'Gérante, propriétaire du workspace « Échafaudages du Nord »', [
      'Inviter les personnes et leur donner un rôle',
      'Créer des groupes et nommer les chefs d’équipe',
      'Fixer les règles : saisie pour autrui, verrouillage, arrondi…',
      'Projets, absences, planning, rapports et facturation',
      'Installer une tablette de pointage (kiosque)',
    ], 7000);
    await h.hideCard();

    await h.scene('connexion', async () => {
      await h.login('sophie@demo.clockifai.fr');
      await h.caption(C('Son menu'), 'Le menu complet', 'Propriétaire : tous les écrans, dont Factures, et tous les réglages de l’entreprise.', ROLE, 4500);
    });

    await h.scene('rôles', async () => {
      await h.nav('Équipe');
      await h.caption(C('Équipe'), 'Les quatre rôles', 'Propriétaire et Administrateur : tout gérer. Manager (Julien) : voit toute l’entreprise, valide et facture. Membre : son propre temps.', ROLE, 6000);
      // Par son email : « Karim Haddad » figure aussi sur les cartes de son équipe (« Chef d'équipe : … »).
      await h.clickNear(/karim@demo\.clockifai\.fr/, /^Afficher le menu$/, 1200);
      await h.caption(C('Équipe'), 'Changer le rôle, les taux, ou nommer chef d’équipe', 'Karim reste « Membre » : il devient chef d’équipe d’un groupe, sans voir toute l’entreprise.', ROLE, 4000);
      await h.menuItem("Chef d'équipe de…", 1500);
      await h.caption(C('Équipe'), 'Karim encadre le groupe « Équipe Unité 4 »', 'Il voit, saisit et valide le temps de Camille, Léo et Hugo. On peut aussi lui confier des personnes une à une.', ROLE, 6000);
      await h.clickLast(/^Annuler$/, 800);
    });

    await h.scene('groupes', async () => {
      await h.pick(/^Groupes/, 1500);
      await h.caption(C('Groupes'), 'Équipes, chantiers, entreprises sous-traitantes', 'Les groupes servent à confier des personnes à un chef d’équipe et à filtrer les rapports.', ROLE, 3500);
      await h.click(/^Nouveau groupe$/, 900);
      await h.typeInto('Nom du groupe', 'Arrêt de tranche');
      await h.clickLast(/^Enregistrer$/, 1500);
      await h.caption(C('Groupes'), 'On choisit les membres du groupe', null, ROLE, 1500);
      await h.pick(/Nadia Rahmani/, 600);
      await h.pick(/Hugo Petit/, 600);
      await h.wait(1000);
      await h.clickLast(/^(Appliquer|Enregistrer)$/, 1500);
      await h.caption(C('Groupes'), 'Groupe créé', 'Une personne peut appartenir à plusieurs groupes.', ROLE, 3000);
    });

    await h.scene('invitation', async () => {
      await h.pick(/^Membres$/, 1200);
      await h.click(/^Inviter$/, 1000);
      await h.typeInto('Email', 'paul@demo.clockifai.fr');
      await h.caption(C('Inviter'), 'Inviter une nouvelle personne', 'Avec un rôle dès l’arrivée. Sans serveur d’email, le lien d’invitation s’affiche pour être envoyé par SMS.', ROLE, 2000);
      await h.clickLast(/^Inviter$/, 3000);
      await h.wait(2000);
      await h.clickLast(/^Fermer$/, 800);
    });

    await h.scene('règles', async () => {
      await h.nav('Paramètres');
      await h.reveal(/Arrondi des durées/, 230);
      await h.caption(C('Règles'), 'Les règles de l’entreprise', 'Projet ou description obligatoires, arrondi des durées, arrêt automatique des chronomètres oubliés.', ROLE, 5000);
      await h.reveal(/Saisie du temps pour autrui/, 330);
      await h.caption(C('Règles'), 'Qui peut saisir le temps des autres', '« Administrateurs et chefs d’équipe » : c’est ce réglage qui permet à Karim de pointer son équipe. Et qui peut créer des tâches.', ROLE, 6000);
      await h.reveal(/Verrouiller les entrées antérieures au/, 360);
      await h.caption(C('Règles'), 'Verrouiller les périodes passées', 'Après la paie, plus personne ne modifie le mois écoulé, sauf un administrateur.', ROLE, 4500);
      await h.reveal(/^Facturation$/, 200);
      await h.caption(C('Facturation'), 'Coordonnées affichées sur les factures', 'Raison sociale, adresse, SIRET, TVA, préfixe des numéros et délai de paiement.', ROLE, 4500);
      await h.reveal(/^Appareils kiosque/, 560);
      await h.click(/^Appareils kiosque/, 1500);
      await h.caption(C('Kiosque'), 'Les tablettes de pointage', 'Chaque tablette reçoit un jeton ; on peut la révoquer à tout moment (perte, vol).', ROLE, 4500);
      await h.clickLast(/^Fermer$/, 800);
    });

    await h.scene('projets', async () => {
      await h.nav('Projets');
      await h.caption(C('Projets'), 'Projets, clients, tâches, budgets', 'La jauge compare les heures passées au budget du projet.', ROLE, 4000);
      await h.click(/^Nouveau projet$/, 1200);
      await h.typeInto('Nom', 'Démontage hangar B');
      await h.typeInto('Taux horaire', '48');
      await h.typeInto('Budget', '60');
      await h.caption(C('Projets'), 'Taux horaire et budget', 'Le taux sert aux montants des rapports et des factures ; un taux par personne existe aussi.', ROLE, 3000);
      await h.clickLast(/^Enregistrer$/, 2000);
    });

    await h.scene('absences', async () => {
      await h.nav('Absences');
      await h.caption(C('Absences'), 'Types d’absence et droits annuels', 'Congés payés, RTT… Pour chaque type : le droit annuel et qui valide (managers, ou aussi les chefs d’équipe).', ROLE, 5000);
      await h.clickNear(/Nadia Rahmani/, /^Approuver$/, 2000);
      await h.caption(C('Absences'), 'Sophie valide la demande de Nadia', 'Nadia n’a pas de chef d’équipe : c’est la direction qui valide.', ROLE, 3500);
      await h.scroll(830, 500, 5, 300, 400);
      await h.caption(C('Absences'), 'Jours fériés', 'Ils sont exclus du décompte des jours d’absence et grisés dans le planning.', ROLE, 4000);
    });

    await h.scene('planning', async () => {
      await h.nav('Planning');
      await h.caption(C('Planning'), 'Toute l’entreprise sur deux semaines', 'En rouge, la surcharge : Karim est prévu 8 h par jour pour 7 h de capacité.', ROLE, 6000);
    });

    await h.scene('rapports', async () => {
      await h.nav('Rapports');
      await h.click(/^Cette semaine$/, 900);
      await h.pick(/^Ce mois-ci$/, 1500);
      await h.click(/Grouper par projet/, 900);
      await h.pick(/^Grouper par client$/, 1800);
      await h.caption(C('Rapports'), 'Heures et montants par client', 'Toute l’entreprise. Exports CSV, Excel et PDF.', ROLE, 5500);
    });

    await h.scene('factures', async () => {
      await h.nav('Factures');
      await h.caption(C('Facturation'), 'Facturer le temps passé', 'Une facture se génère à partir des heures facturables non facturées d’un client.', ROLE, 3000);
      await h.click(/^Nouvelle facture$/, 1500);
      await h.click(/Centrale Sud \(démo\)/, 1000);
      await h.pick(/Raffinerie Nord \(démo\)/, 1200);
      await h.caption(C('Facturation'), 'Détailler par tâche', 'Coché par défaut : une ligne par tâche (« Projet — Tâche ») plutôt qu’une seule par projet.', ROLE, 3500);
      await h.clickLast(/^Générer$/, 3500);
      await h.caption(C('Facturation'), 'Une ligne par projet et par tâche, au bon taux', 'Numérotation continue attribuée par le serveur, TVA, remise, PDF. Les heures facturées ne peuvent plus être modifiées.', ROLE, 6000);
      await h.clickLast(/^Fermer$/, 1200);
    });

    await h.scene('kiosque', async () => {
      await h.signOut();
      await h.click(/Mode kiosque/, 2500);
      await h.caption(C('Kiosque'), 'Installer la tablette de la base vie', 'On colle le jeton de l’appareil, une seule fois.', 'Tablette', 2000);
      await h.typeInto("Jeton d'appareil", KIOSK_TOKEN, 25);
      await h.click(/^Enregistrer$/, 3500);
      await h.caption(C('Kiosque'), 'Chacun pointe avec son code PIN', 'Pour les équipes sans smartphone : on touche son nom, on tape son code.', 'Tablette', 3000);
      await h.pick(/Camille Martin/, 1200);
      for (const d of ['1', '2', '3', '4']) await h.click(new RegExp(`^${d}$`), 350);
      // Touche « valider » : à droite du 0, au même pas que les autres touches (icône sans texte).
      const one = await h.find(/^1$/), two = await h.find(/^2$/), zero = await h.find(/^0$/);
      await h.clickXY(zero.x + (two.x - one.x), zero.y, 2500);
      await h.caption(C('Kiosque'), 'Arrivée de Camille enregistrée', 'Le temps apparaît dans sa feuille de temps, comme une saisie normale.', 'Tablette', 4500);
    });
  });

  const end = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.setContent('<html><body style="margin:0;background:#0f172a"></body></html>');
    await page.evaluate(() => window.__demo.ensure());
    await h.card('Sophie, propriétaire', 'Ce qu’elle peut faire', [
      'Inviter, attribuer les rôles et les taux, désactiver un compte',
      'Créer les groupes et nommer les chefs d’équipe',
      'Régler les permissions, le verrouillage, l’arrondi, les absences',
      'Voir et facturer le temps de toute l’entreprise',
      'Installer et révoquer les tablettes kiosque',
    ], 7000);
  });

  return [{ webm: desktop }, { webm: end }];
}
