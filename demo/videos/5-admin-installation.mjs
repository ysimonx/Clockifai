// Vidéo 5 : l'administrateur de l'installation (hébergement) — Supabase Studio et paramétrage du serveur.
// Il n'existe pas de « super-admin » dans l'app : au-dessus des workspaces, c'est la personne qui héberge
// Clockifai qui administre, avec Supabase Studio et le fichier deploy/.env.
import fs from 'node:fs';
import path from 'node:path';
import { FAST, W, H, deadTime, helpers, out, overlay, repo } from '../lib/helpers.mjs';

export const name = '5-admin-installation';
const ROLE = 'Administrateur de l’installation';
const C = (chapter) => `Installation · ${chapter}`;
const STUDIO = process.env.STUDIO_URL || 'http://localhost:8000';

function dashboardCredentials() {
  const env = fs.readFileSync(path.join(repo, 'deploy', '.env'), 'utf8');
  const get = (k) => env.match(new RegExp(`^${k}=(.*)$`, 'm'))?.[1]?.trim();
  return { username: get('DASHBOARD_USERNAME'), password: get('DASHBOARD_PASSWORD') };
}

export async function run(browser, failures) {
  const ctx = await browser.newContext({
    viewport: { width: W, height: H },
    locale: 'fr-FR',
    httpCredentials: dashboardCredentials(),
    ...(FAST ? {} : { recordVideo: { dir: out, size: { width: W, height: H } } }),
  });
  await ctx.addInitScript(overlay);
  const clock = { start: Date.now(), cuts: [] };
  const page = await ctx.newPage();
  const h = helpers(page, failures, clock);
  const studio = async (route, pause = 3500) => { await page.goto(`${STUDIO}${route}`, { waitUntil: 'domcontentloaded' }); await h.wait(pause); };
  const clickText = async (text, pause = 1500) => {
    const loc = page.getByText(text, { exact: true }).first();
    await loc.waitFor({ timeout: 15000 });
    await h.clickLoc(loc, pause);
  };

  try {
    await page.setContent('<html><body style="margin:0;background:#0f172a"></body></html>');
    await page.evaluate(() => window.__demo.ensure());
    await h.card('Vidéo 5 / 5 · L’administrateur de l’installation', 'La personne qui héberge Clockifai (OVH, Scaleway ou serveur interne)', [
      'Il administre le serveur, pas le travail des équipes',
      'Comptes de toute l’installation, sécurité, sauvegardes, mises à jour',
      'Rôles et règles d’une entreprise : dans l’app, par son propriétaire (vidéo 4)',
    ], 7000);
    await h.card('Trois niveaux', 'Du serveur à la personne', [
      'Installation : un serveur, plusieurs entreprises (workspaces) possibles',
      'Workspace : propriétaire, administrateurs, managers, membres',
      'Équipe : un chef d’équipe pour un groupe de personnes',
    ], 7000);

    await h.scene('studio', async () => {
      await studio('/project/default/auth/users', 4000);
      await h.hideCard();
      await h.caption(C('Supabase Studio'), 'La console d’administration du serveur', 'Livrée avec Clockifai, protégée par un mot de passe et accessible sur une adresse séparée (studio.votre-domaine).', ROLE, 5500);
      await h.caption(C('Comptes'), 'Tous les comptes de l’installation', 'Quelle que soit leur entreprise : date de création, dernière connexion, méthode de connexion.', ROLE, 5000);
      await h.clickLoc(page.getByRole('button', { name: /Add user/ }).first(), 1500);
      await h.caption(C('Comptes'), 'Créer un compte ou envoyer une invitation', 'Utile pour le tout premier propriétaire d’une entreprise. Ensuite, les invitations se font dans l’app.', ROLE, 5000);
      await page.keyboard.press('Escape');
      await h.wait(800);
      await clickText('karim@demo.clockifai.fr', 2500);
      await h.caption(C('Comptes'), 'La fiche d’un compte', 'Envoyer un lien de connexion, réinitialiser le mot de passe, bloquer ou supprimer un compte.', ROLE, 6000);
      await page.keyboard.press('Escape');
      await h.wait(800);
    });

    await h.scene('données', async () => {
      await studio('/project/default/editor', 4000);
      await h.caption(C('Données'), 'Les tables de Clockifai', 'Entreprises, membres, projets, entrées de temps, absences, factures…', ROLE, 4000);
      await clickText('workspaces', 3000);
      await h.caption(C('Données'), 'Les entreprises hébergées', 'Ici une seule : « Échafaudages du Nord ». Un même serveur peut en accueillir plusieurs, totalement cloisonnées.', ROLE, 5500);
      await clickText('workspace_members', 3000);
      await h.caption(C('Données'), 'Les rôles de chacun', 'En dépannage (propriétaire parti, compte bloqué), l’administrateur peut corriger un rôle directement.', ROLE, 6000);
      await h.caption(C('Sécurité'), 'Chaque entreprise ne voit que ses données', 'Le cloisonnement est appliqué par la base elle-même (sécurité au niveau des lignes), pas seulement par l’app.', ROLE, 5500);
    });

    await h.scene('sql', async () => {
      await studio('/project/default/sql/new', 4500);
      await h.caption(C('Requêtes'), 'Statistiques et contrôles en SQL', 'Par exemple : nombre de personnes et d’heures par entreprise.', ROLE, 2500);
      const editor = page.locator('.monaco-editor').first();
      await h.clickLoc(editor, 600);
      // Sans espaces de tête : l'éditeur reprend l'indentation de la ligne précédente (sinon, escalier).
      await page.keyboard.insertText([
        'select w.name as entreprise,',
        'count(distinct m.user_id) as personnes,',
        'round(sum(t.duration_seconds) / 3600.0) as heures',
        'from workspaces w',
        'join workspace_members m on m.workspace_id = w.id',
        'left join time_entries t on t.workspace_id = w.id and t.user_id = m.user_id',
        'group by w.name;',
      ].join('\n'));
      await h.wait(1200);
      await h.clickLoc(page.getByRole('button', { name: /^Run/ }).first(), 3500);
      await h.caption(C('Requêtes'), 'Résultat immédiat', 'Exportable en CSV. Les requêtes sont enregistrées pour être rejouées.', ROLE, 6000);
    });

    await h.scene('paramétrage', async () => {
      await page.setContent('<html><body style="margin:0;background:#0f172a"></body></html>');
      await page.evaluate(() => window.__demo.ensure());
      await h.code('deploy/.env', 'le paramétrage de l’installation (un seul fichier)', [
        'SITE_URL=https://temps.mon-entreprise.fr     # adresse de l’application',
        'APP_DOMAIN / SUPABASE_DOMAIN / SYNC_DOMAIN   # noms de domaine, HTTPS automatique',
        'DISABLE_SIGNUP=true                          # inscriptions fermées : sur invitation seulement',
        'ENABLE_EMAIL_AUTOCONFIRM=false               # adresse email à confirmer',
        'SMTP_HOST=ssl0.ovh.net  SMTP_USER=…          # envoi des emails (invitations, liens)',
        'GOOGLE_ENABLED / AZURE_ENABLED               # connexion avec Google ou Microsoft',
        'JWT_EXPIRY=3600                              # durée d’une session (secondes)',
        'BACKUP_KEEP_DAYS=14  BACKUP_HOUR=03          # sauvegarde chaque nuit, gardée 14 jours',
        'JOBS_ENABLED=true                            # tâches automatiques (chronomètres oubliés…)',
      ], 12000);
      await h.code('Exploitation', 'quelques commandes, depuis le dossier Clockifai', [
        'make prod-up                 # démarrer ou mettre à jour (Docker, HTTPS)',
        'make migrate                 # appliquer les évolutions de la base',
        'make backup                  # sauvegarde immédiate',
        'make logs SERVICE=powersync  # journaux d’un service',
        'make psql                    # console de la base',
        '',
        '# Restauration : voir deploy/backup.sh (pg_restore)',
        '# Changer d’hébergeur : copier deploy/.env, restaurer la sauvegarde, make prod-up',
      ], 11000);
      await h.hideCode();
    });

    await h.card('Qui fait quoi ?', 'Récapitulatif des cinq vidéos', [
      'Administrateur de l’installation : serveur, comptes, sauvegardes, paramétrage',
      'Propriétaire / administrateur : équipe, rôles, groupes, règles, facturation',
      'Manager : voit toute l’entreprise, valide, planifie, facture',
      'Chef d’équipe : saisit et valide le temps de son équipe',
      'Membre : saisit et suit son propre temps',
    ], 9000);
  } finally {
    await ctx.close();
  }
  if (FAST) return [];
  const webm = await page.video().path();
  deadTime.set(webm, clock.cuts);
  return [{ webm }];
}
