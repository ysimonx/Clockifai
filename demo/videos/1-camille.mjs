// Vidéo 1 : Camille, membre d'une équipe — saisir et suivre son propre temps.
import { APP, frDay, helpers, offline, previous, record } from '../lib/helpers.mjs';

export const warmup = ['camille@demo.clockifai.fr'];
export const name = '1-camille-membre';
const ROLE = 'Membre';
const C = (chapter) => `Camille · ${chapter}`;

export async function run(browser, failures) {
  const desktop = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.goto(APP);
    await h.wait(3500);
    await h.card('Vidéo 1 / 5 · Camille', 'Membre de l’équipe « Unité 4 »', [
      'Sa journée proposée, une saisie en une ligne',
      'Saisir ses heures après coup, ou en direct',
      'Remplir et soumettre sa feuille de temps',
      'Absences, planning, rapports personnels',
      'Travailler sans réseau sur le chantier',
    ], 6000);
    await h.hideCard();

    await h.scene('connexion', async () => {
      await h.caption(C('Connexion'), 'Camille se connecte avec son compte', 'Email et mot de passe (ou lien reçu par email). Elle n’a besoin de rien installer sur un ordinateur : l’app existe aussi sur iPhone et Android.', ROLE, 4500);
      await h.login('camille@demo.clockifai.fr');
    });

    await h.scene('aujourd’hui', async () => {
      await h.caption(C('Aujourd’hui'), 'Sa journée, prête à confirmer', 'À l’ouverture, « Aujourd’hui » : ce qu’elle a saisi, les créneaux vides de sa journée habituelle, et des propositions tirées de ses habitudes et du planning, à confirmer d’un geste.', ROLE, 6500);
      await h.typeInto('Saisie express', '2h pose garde-corps unité 4 hier', 60);
      await h.caption(C('Saisie express'), 'Une ligne en clair', 'Durée, projet, jour : Clockifai montre ce qu’il a compris et range l’entrée dans un créneau vide. Entrée enregistre.', ROLE, 5500);
      await page.keyboard.press('Enter');
      await h.wait(1500);
      await h.caption(C('Saisie express'), 'Ajoutée, avec « Annuler »', 'Une erreur ? Le bandeau propose d’annuler pendant quelques secondes.', ROLE, 3500);
    });

    await h.scene('accueil', async () => {
      await h.nav('Suivi du temps');
      await h.caption(C('Semaine'), 'Ses heures, jour par jour', '« Semaine », vue « Liste » : la description, le projet et la tâche, les horaires et la durée. Total par jour et par semaine.', ROLE, 5000);
      await h.hover(/saisi par Karim Haddad/).catch(() => {});
      await h.caption(C('Semaine'), '« saisi par Karim Haddad »', 'Jeudi, son chef d’équipe a pointé toute l’équipe. Les heures sont bien à Camille : elle peut les corriger si besoin.', ROLE, 5500);
    });

    await h.scene('saisie après coup', async () => {
      await h.caption(C('Saisie après coup'), 'Déclarer des heures déjà faites', '« Ajouter du temps », en haut à droite.', ROLE, 2500);
      await h.click(/^Ajouter du temps$/, 1200);
      await h.typeInto('Description', 'Contrôle des ancrages');
      await h.click('Sans projet', 900);
      await h.typeInto('Rechercher un projet, une tâche, un client', 'unité');
      await h.caption(C('Saisie après coup'), 'Projet et tâche', 'Les tâches apparaissent sous chaque projet : ici « Montage » du projet « Échafaudage unité 4 ».', ROLE, 1500);
      await h.pick(/^\d+ tâches/, 900);
      await h.pick(/^Montage$/, 900);
      await h.click(/^Date/, 900);
      await h.click(frDay(previous(5)), 500);
      await h.click(/^OK$/, 800);
      await h.caption(C('Saisie après coup'), 'Une durée suffit', '« 1:30 », « 1,5 » ou « 90m » : l’heure de fin se calcule toute seule.', ROLE, 1200);
      await h.typeInto('Durée', '1:30', 150);
      await h.wait(1500);
      await h.click(/^Enregistrer$/, 1500);
      await h.caption(C('Saisie après coup'), 'Ajoutée au vendredi', 'Enregistrée immédiatement sur l’appareil, puis envoyée au serveur.', ROLE, 3500);
    });

    await h.scene('chronomètre et tâche à la volée', async () => {
      await h.caption(C('Chronomètre'), 'Ou en direct, avec le chronomètre', '« Démarrer » : elle décrit ce qu’elle fait et choisit le projet.', ROLE, 2500);
      await h.click(/^Démarrer$/, 1200);
      await h.typeInto('Sur quoi travaillez-vous ?', 'Rangement du dépôt');
      await h.click(/^Projet$/, 900);
      await h.typeInto('Rechercher un projet, une tâche, un client', 'Rangement dépôt');
      await h.caption(C('Chronomètre'), 'La tâche n’existe pas ? On la crée sur place', 'Il suffit de choisir le projet dans lequel la ranger.', ROLE, 3000);
      await h.pick(/^Interne/, 1200);
      await h.clickLast(/^Démarrer$/, 1500);
      await h.caption(C('Chronomètre'), 'Le chronomètre tourne', 'Une pastille en haut à droite. Il continue si l’app est fermée, et Camille le retrouve sur son téléphone.', ROLE, 4000);
      await h.click(/^Arrêter le chronomètre$/, 2000);
    });

    await h.scene('feuille de temps', async () => {
      await h.nav('Feuille de temps');
      await h.caption(C('Semaine'), 'La semaine en une grille', 'La feuille de temps : une ligne par projet, une colonne par jour ; on tape les heures directement dans les cases.', ROLE, 4000);
      await h.click(/^Ajouter une ligne$/, 900);
      await h.typeInto('Rechercher un projet, une tâche, un client', 'Arrêt');
      await h.pick(/^Arrêt de tranche 2026/, 1200);
      // Attendre la fermeture du sélecteur : son élément « Arrêt de tranche 2026 » est à la hauteur d'une autre ligne.
      for (let i = 0; i < 30 && (await h.findAll(/^Choisir un projet$/)).length; i++) await h.wait(200);
      const row = await h.find(/Arrêt de tranche 2026/, { which: 'first' });
      const cells = await h.inputsAt(row.y);
      if (!cells.length) throw new Error('cases de la ligne « Arrêt de tranche 2026 » introuvables');
      await h.clickXY(cells[0].x, cells[0].y, 300);
      await page.keyboard.type('2', { delay: 150 });
      await page.keyboard.press('Enter');
      await h.wait(1500);
      await h.click(/^Semaine précédente$/, 1200);
      await h.caption(C('Feuille de temps'), 'Semaine précédente : complète', 'Camille vérifie sa semaine passée puis la soumet à son chef d’équipe.', ROLE, 3000);
      await h.click(/^Soumettre pour approbation$/, 1000);
      await h.caption(C('Feuille de temps'), 'Avant de soumettre', 'Clockifai signale ce qui mérite un coup d’œil : jour vide, heures sous le planning, chronomètre oublié.', ROLE, 3500);
      await h.typeInto('Commentaire (facultatif)', 'Semaine sur l’unité 4');
      await h.clickLast(/^Soumettre( quand même)?$/, 2000);
      await h.caption(C('Feuille de temps'), 'En attente d’approbation', 'Karim, son chef d’équipe, la validera. Une fois approuvée, la semaine est verrouillée.', ROLE, 4500);
    });

    await h.scene('calendrier', async () => {
      await h.nav('Calendrier');
      await h.caption(C('Calendrier'), 'Ses journées en un coup d’œil', 'Les heures apparaissent en blocs ; un clic sur un créneau libre ouvre la saisie à cette heure-là.', ROLE, 5500);
    });

    await h.scene('planning', async () => {
      await h.nav('Planning');
      await h.caption(C('Planning'), 'Où elle est attendue', 'Son affectation sur l’unité 4 cette semaine, et son RTT de vendredi déjà validé.', ROLE, 5500);
    });

    await h.scene('absences', async () => {
      await h.nav('Absences');
      await h.caption(C('Absences'), 'Ses soldes de congés et de RTT', 'Calculés automatiquement à partir des demandes approuvées.', ROLE, 4000);
      await h.click(/^Demander une absence$/, 1500);
      await h.caption(C('Absences'), 'Faire une demande', 'Type d’absence, dates, demi-journée : le nombre de jours ouvrés se calcule seul. Son chef d’équipe reçoit la demande.', ROLE, 5000);
      await h.clickLast(/^Annuler$/, 800);
    });

    await h.scene('rapports', async () => {
      await h.nav('Rapports');
      await h.caption(C('Rapports'), 'Ses propres chiffres', 'Un membre ne voit que ses heures : total, temps facturable, répartition par projet.', ROLE, 3000);
      await h.click(/^Cette semaine$/, 900);
      await h.pick(/^Ce mois-ci$/, 2000);
      await h.caption(C('Rapports'), 'Sur le mois en cours', 'Exportable en CSV, même hors ligne.', ROLE, 3500);
    });

    await h.scene('hors ligne', async () => {
      await h.nav('Suivi du temps');
      await h.caption(C('Hors ligne'), 'Pas de réseau sur le chantier ?', 'On coupe le réseau du navigateur pour la démonstration…', ROLE, 2500);
      await offline(page, async () => {
        await h.wait(2500);
        await h.click(/^Ajouter du temps$/, 1000);
        await h.typeInto('Description', 'Montage niveau 5 (sans réseau)');
        await h.typeInto('Durée', '3:00', 150);
        await h.click(/^Enregistrer$/, 1500);
        await h.click(/^(Synchronisé|Synchronisation…|Hors ligne)( · .*)?$/, 1500);
        await h.caption(C('Hors ligne'), 'La saisie attend sur l’appareil', '« Hors ligne · 1 modification en attente », en bas du menu : rien n’est perdu.', ROLE, 4000);
        await h.clickLast(/^Fermer$/, 500);
      });
      await h.caption(C('Hors ligne'), 'Le réseau revient…', 'L’envoi se fait tout seul, sans rien faire.', ROLE, 9000);
      await h.click(/^(Synchronisé|Synchronisation…|Hors ligne)( · .*)?$/, 1500);
      await h.wait(3000);
      await h.clickLast(/^Fermer$/, 500);
    });
  });

  const phone = await record(browser, { phone: true }, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.goto(APP);
    await h.wait(3500);
    await h.scene('mobile', async () => {
      await h.login('camille@demo.clockifai.fr');
      await h.caption('Camille · Sur téléphone', 'La même app dans sa poche', 'iPhone ou Android, mêmes données. En bas : Aujourd’hui, Semaine, « + » pour ajouter du temps ou démarrer le compteur, Équipe.', ROLE, 5000, 92);
      await h.click(h.navRe('Semaine'), 2000);
      await h.caption('Camille · Sur téléphone', 'Sa feuille de temps', 'On fait glisser la grille pour voir toute la semaine.', ROLE, 4000, 92);
    });
  });

  const end = await record(browser, {}, async (page, clock) => {
    const h = helpers(page, failures, clock);
    await page.setContent('<html><body style="margin:0;background:#0f172a"></body></html>');
    await page.evaluate(() => window.__demo.ensure());
    await h.card('Camille, membre', 'Ce qu’elle peut faire', [
      'Saisir, corriger et supprimer ses propres heures',
      'Soumettre sa feuille de temps, demander des absences',
      'Voir son planning et ses propres rapports',
      'Elle ne voit pas les heures des autres',
    ], 6500);
  });

  return [{ webm: desktop }, { webm: phone, phone: true }, { webm: end }];
}
