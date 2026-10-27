// Vidéo 2 : Karim, chef de l'équipe « Unité 4 » (Camille, Léo, Hugo) — saisit et valide le temps de son équipe.
import { APP, helpers, record } from '../lib/helpers.mjs';

export const warmup = ['karim@demo.clockifai.fr'];
export const name = '2-karim-chef-equipe';
const ROLE = 'Chef d’équipe';
const C = (chapter) => `Karim · ${chapter}`;

export async function run(browser, failures) {
  const desktop = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.goto(APP);
    await h.wait(3500);
    await h.card('Vidéo 2 / 5 · Karim', 'Chef de l’équipe « Unité 4 » : Camille, Léo, Hugo', [
      'Pointer toute l’équipe en une seule saisie',
      'Saisir ou corriger le temps d’un collègue',
      'Valider les feuilles de temps et les absences de son équipe',
      'Suivre les heures de son équipe, et seulement elle',
    ], 6500);
    await h.hideCard();

    await h.scene('connexion', async () => {
      await h.login('karim@demo.clockifai.fr');
      await h.caption(C('Son menu'), 'Chef d’équipe : un périmètre, pas un super-pouvoir', 'Sophie, qui gère l’entreprise, l’a nommé chef du groupe « Unité 4 ». La rubrique « Équipe » gagne « Pointage d’équipe » et « Approbations ».', ROLE, 6000);
      await h.nav('Équipe');
      await h.hover(/^Pointage d'équipe$/).catch(() => {});
      await h.wait(1500);
    });

    await h.scene('pointage d’équipe', async () => {
      await h.nav("Pointage d'équipe");
      await h.caption(C('Pointage d’équipe'), 'En fin de journée, il déclare les heures de l’équipe', 'Une description, un projet et une tâche, des horaires par défaut.', ROLE, 3500);
      await h.typeInto('Description', 'Montage niveau 5');
      await h.click('Sans projet', 900);
      await h.typeInto('Rechercher un projet, une tâche, un client', 'unité');
      await h.pick(/^\d+ tâches/, 900);
      await h.pick(/^Montage$/, 1000);
      await h.caption(C('Pointage d’équipe'), 'Les présents sont déjà cochés', 'Une absence validée ou une journée déjà saisie se décoche d’office. Hugo n’est pas venu aujourd’hui : Karim le décoche.', ROLE, 4000);
      await h.pick(/Hugo Petit/, 1200);
      await h.caption(C('Pointage d’équipe'), 'Une exception ? Sur les horaires de la personne', '« Arrivée à… », « Départ à… » : la ligne affiche alors « Départ à 15:00 ».', ROLE, 3500);
      await h.click(/^Créer les entrées$/, 2000);
      await h.caption(C('Pointage d’équipe'), 'Une entrée par personne, même sans réseau', 'Chez Camille et Léo, ces heures apparaissent avec la mention « saisi par Karim Haddad ». Une erreur ? « Annuler » dans le bandeau.', ROLE, 5000);
    });

    await h.scene('saisie pour une collègue', async () => {
      await h.nav('Feuille de temps');
      await h.caption(C('Feuille de temps'), 'Corriger la feuille d’une collègue', 'Le sélecteur en haut permet d’afficher la feuille de chaque membre de son équipe.', ROLE, 3000);
      await h.click(/^Karim Haddad$/, 900);
      await h.pick(/^Camille Martin$/, 1800);
      await h.caption(C('Feuille de temps'), '« Vous saisissez le temps de Camille Martin »', 'Le bandeau rappelle pour qui on saisit. Camille garde la main sur ses heures.', ROLE, 5000);
      await h.click(/^Semaine précédente$/, 1800);
      await h.caption(C('Feuille de temps'), 'Sa semaine passée', 'Il voit ce qu’elle a déclaré, jour par jour et projet par projet.', ROLE, 4000);
    });

    await h.scene('approbations', async () => {
      await h.nav('Approbations');
      await h.caption(C('Approbations'), 'Semaine dernière : qui n’a pas soumis', 'Heures saisies et prévues au planning pour chacun, et « Relancer » : un bandeau et une notification chez la personne.', ROLE, 5000);
      await h.caption(C('Approbations'), 'Léo a soumis sa semaine', 'Karim ne voit que les feuilles de son équipe : celle de Nadia, soumise aussi, ne lui est pas présentée. Il ouvre celle de Léo…', ROLE, 4500);
      await h.click(/Léo Dubois/, 2500);
      await h.caption(C('Approbations'), '… puis il approuve', 'La semaine de Léo est verrouillée. En cas de souci, « Refuser » avec un commentaire la renvoie à Léo.', ROLE, 2500);
      await h.click(/^Approuver$/, 2500);
    });

    await h.scene('absences', async () => {
      await h.nav('Absences');
      await h.caption(C('Absences'), 'Les demandes de son équipe', 'Hugo demande une semaine de congés. La demande de Nadia, d’une autre équipe, ne lui est pas présentée.', ROLE, 5000);
      await h.click(/^Approuver$/, 2000);
      await h.caption(C('Absences'), 'Demande approuvée', 'Elle apparaît dans le planning d’Hugo et décompte ses congés.', ROLE, 3500);
    });

    await h.scene('rapports', async () => {
      await h.nav('Rapports');
      await h.caption(C('Rapports'), 'Les heures de son équipe', 'Il peut filtrer par personne : seulement Camille, Léo, Hugo et lui-même.', ROLE, 3000);
      await h.click(/^Tous les membres$/, 1500);
      await h.wait(1500);
      await page.keyboard.press('Escape');
      await h.wait(600);
      await h.click(/Grouper par projet/, 900);
      await h.pick(/^Grouper par utilisateur$/, 1800);
      await h.caption(C('Rapports'), 'Heures par personne sur la semaine', 'Nadia, de l’équipe Calorifuge, n’apparaît pas : elle est hors de son périmètre.', ROLE, 5000);
    });

    await h.scene('équipe', async () => {
      await h.nav('Équipe');
      await h.caption(C('Équipe'), 'Qui travaille sur quoi', 'Tout le monde figure dans l’annuaire, mais il ne voit les heures et les chronomètres que de son équipe : pas ceux de Nadia.', ROLE, 6000);
    });
  });

  const end = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.setContent('<html><body style="margin:0;background:#0f172a"></body></html>');
    await page.evaluate(() => window.__demo.ensure());
    await h.card('Karim, chef d’équipe', 'Ce qu’il peut faire, pour son équipe seulement', [
      'Pointer plusieurs personnes à la fois, saisir ou corriger leurs heures',
      'Approuver ou refuser leurs feuilles de temps et leurs absences',
      'Voir leurs heures dans les rapports, le planning et la page Équipe',
      'Pas de chronomètre pour un autre, pas de factures ni de réglages',
    ], 7000);
  });

  return [{ webm: desktop }, { webm: end }];
}
