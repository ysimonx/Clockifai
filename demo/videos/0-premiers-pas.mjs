// Vidéo 0 : premiers pas, pour tout le monde — démarrer et arrêter son compteur, ajouter des heures après coup,
// sur ordinateur puis sur téléphone (plans/14-coller-aux-maquettes.md, lot 5).
import { APP, helpers, record } from '../lib/helpers.mjs';

export const warmup = ['leo@demo.clockifai.fr', 'hugo@demo.clockifai.fr'];
export const name = '0-premiers-pas';
const ROLE = 'Tout le monde';
const C = (chapter) => `Premiers pas · ${chapter}`;

export async function run(browser, failures) {
  const desktop = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.goto(APP);
    await h.wait(3500);
    await h.card('Premiers pas', 'Compter son temps avec Clockifai', [
      'Démarrer son compteur, l’arrêter',
      'Ajouter des heures déjà faites',
      'Sur téléphone : reprendre sa journée d’un geste',
    ], 5000);
    await h.hideCard();

    await h.scene('connexion', async () => {
      await h.caption(C('Connexion'), 'Léo se connecte', 'Son email et son mot de passe. L’app s’ouvre sur « Aujourd’hui » : sa journée.', ROLE, 3500);
      await h.login('leo@demo.clockifai.fr');
      await h.wait(1500);
    });

    await h.scene('démarrer', async () => {
      await h.hover(/^Démarrer$/).catch(() => {});
      await h.caption(C('Démarrer'), 'En haut à droite : « Démarrer »', 'Toujours au même endroit, sur chaque page.', ROLE, 3500);
      await h.click(/^Démarrer$/, 1200);
      await h.typeInto('Sur quoi travaillez-vous ?', 'Montage niveau 2');
      await h.click(/^Projet$/, 900);
      await h.typeInto('Rechercher un projet, une tâche, un client', 'unité');
      await h.pick(/^Échafaudage unité 4/, 1200);
      await h.caption(C('Démarrer'), 'Ce qu’il fait, et le projet', 'Plus court encore : reprendre une entrée récente, d’un clic.', ROLE, 3500);
      await h.clickLast(/^Démarrer$/, 1500);
      await h.caption(C('Démarrer'), 'Le compteur tourne', 'Le bouton devient une pastille : un point vert, ce qu’il fait, le temps qui défile. Il continue même l’app fermée.', ROLE, 5500);
    });

    await h.scene('arrêter', async () => {
      await h.hover(/^Arrêter le chronomètre$/).catch(() => {});
      await h.caption(C('Arrêter'), 'Pour l’arrêter : le carré noir', 'L’entrée est enregistrée, avec son heure de début et de fin.', ROLE, 3500);
      await h.click(/^Arrêter le chronomètre$/, 2000);
    });

    await h.scene('ajouter du temps', async () => {
      await h.hover(/^Ajouter du temps$/).catch(() => {});
      await h.caption(C('Ajouter du temps'), 'Oublié de démarrer ? Ajoutez vos heures après coup', '« Ajouter du temps », juste à côté.', ROLE, 3500);
      await h.click(/^Ajouter du temps$/, 1200);
      await h.typeInto('Description', 'Réception du matériel');
      await h.click('Sans projet', 900);
      await h.typeInto('Rechercher un projet, une tâche, un client', 'unité');
      await h.pick(/^Échafaudage unité 4/, 1200);
      await h.caption(C('Ajouter du temps'), 'Une durée suffit', '« 2:00 », « 2h » ou « 120m » : l’heure de fin se calcule toute seule.', ROLE, 1500);
      await h.typeInto('Durée', '2:00', 150);
      await h.wait(1200);
      await h.click(/^Enregistrer$/, 1500);
      await h.caption(C('Ajouter du temps'), 'C’est tout', 'Les deux entrées sont dans sa journée. Une erreur ? Le bandeau propose d’annuler.', ROLE, 4500);
    });
  });

  const phone = await record(browser, { phone: true }, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.goto(APP);
    await h.wait(3500);
    await h.scene('téléphone', async () => {
      await h.login('hugo@demo.clockifai.fr');
      await h.caption(C('Sur téléphone'), 'Hugo, sur le chantier', 'Même app, mêmes données. Sa journée est vide : Clockifai lui propose celle d’hier.', ROLE, 5000, 92);
      await h.click(/^Reprendre la journée/, 2000);
      await h.caption(C('Sur téléphone'), 'Sa journée, en un geste', 'Les mêmes heures qu’hier, aux mêmes horaires. Un détail à changer ? Il touche la ligne.', ROLE, 4500, 92);
      // Le « + » de la barre du bas, dernier « Ajouter » de l'écran.
      await h.pick(h.navRe('Ajouter'), 1500);
      await h.caption(C('Sur téléphone'), 'Le bouton « + »', 'Ajouter des heures, ou démarrer le compteur.', ROLE, 3000, 92);
      await h.pick(/^Démarrer le chronomètre$/, 1200);
      await h.typeInto('Sur quoi travaillez-vous ?', 'Démontage façade');
      await h.pick(/^Démarrer$/, 1500);
      await h.caption(C('Sur téléphone'), 'Le compteur tourne', 'En haut de l’écran, avec le carré pour l’arrêter. Il tourne même téléphone en poche.', ROLE, 4500, 92);
      await h.click(/^Arrêter le chronomètre$/, 1500);
    });
  });

  const end = await record(browser, {}, async (page) => {
    const h = helpers(page, failures);
    await page.setContent('<html><body style="margin:0;background:#0f172a"></body></html>');
    await page.evaluate(() => window.__demo.ensure());
    await h.card('Premiers pas', 'À retenir', [
      '« Démarrer » en haut à droite, le carré noir pour arrêter',
      '« Ajouter du temps » pour les heures déjà faites',
      'Sur téléphone : « Reprendre la journée », et le bouton « + »',
    ], 6000);
  });

  return [{ webm: desktop }, { webm: phone, phone: true }, { webm: end }];
}
