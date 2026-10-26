// Vidéo 6 : Alex, développeur indépendant, et son agent « Claude · Alex Girard » — le temps de Claude Code.
// L'app est celle d'une vraie instance (https://clockifai.example.fr, lib/public-instance.mjs) ; l'historique de
// Claude vient de demo/claude-history.mjs, et la session en direct est envoyée pendant le tournage avec le jeton
// que la scène « connexion » vient de créer, comme le ferait le plugin.
import { helpers, record } from '../lib/helpers.mjs';
import { claudeSession, postEvents, usagePayload } from '../lib/claude.mjs';
import { PUBLIC_APP, PUBLIC_URL, routePublic, startPublicApp } from '../lib/public-instance.mjs';

export const warmup = ['alex@demo.clockifai.fr'];
export const name = '6-alex-claude-code';
const ROLE = 'Développeur';
const C = (chapter) => `Alex · ${chapter}`;
const frDate = (d) => new Intl.DateTimeFormat('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(d);
const today = frDate(new Date());
// L'historique de Claude couvre les 6 derniers jours (demo/claude-history.mjs), à cheval sur deux semaines selon le jour.
const weekAgo = frDate(new Date(Date.now() - 6 * 86400000));

export async function run(browser, failures) {
  const srv = await startPublicApp();
  let token;
  let heartbeat;
  try {
    const desktop = await record(browser, { onContext: routePublic }, async (page, clock) => {
      const h = helpers(page, failures, clock);
      await page.goto(PUBLIC_APP);
      await h.wait(3500);
      await h.card('Vidéo 6 / 6 · Claude Code', 'Alex, développeur indépendant, et son agent « Claude · Alex Girard »', [
        'Connecter son ordinateur, une fois par poste',
        'Chaque session de Claude Code devient du temps, tout seul',
        'Claude nomme la tâche de son travail',
        'Contrôler et corriger le temps de son agent, et ce qu’il coûte',
        'Facturer ses heures et celles de Claude',
      ], 7000);
      await h.hideCard();

      await h.scene('connexion', async () => {
        await h.login('alex@demo.clockifai.fr');
        await h.nav('Paramètres');
        await h.reveal(/^Claude Code/, 420);
        await h.click(/^Claude Code/, 1500);
        await h.caption(C('Claude Code'), 'Paramètres › Intégrations › Claude Code',
          'Le temps de chaque session devient celui de son agent « Claude · Alex Girard », membre de l’équipe. Son Mac mini est déjà connecté.', ROLE, 6000);
        await h.clickLast(/^Connecter un poste$/, 1200);
        await h.typeInto('Nom du poste', 'MacBook Air');
        await h.clickLast(/^Enregistrer$/, 2000);
        await h.reveal(/Dans un terminal \(le panneau/, 330, { x: 720 });
        await h.caption(C('Claude Code'), 'Les commandes à lancer dans un terminal',
          'Installer le plugin Clockifai depuis l’instance, puis lui donner le jeton de ce poste. Le jeton ne s’affiche qu’une fois.', ROLE, 6500);
        await h.reveal(/^Copier le jeton$/, 520, { x: 720 });
        await h.click(/^Copier le jeton$/, 1200);
        token = JSON.parse(await page.evaluate(() => navigator.clipboard.readText())).token;
        if (!token?.startsWith('clk_')) throw new Error('jeton absent du presse-papiers');
        await h.caption(C('Claude Code'), 'Copier le jeton',
          'Il part dans le presse-papiers, que la commande 3 lit dans le terminal : il n’apparaît ni à l’écran ni dans l’historique.', ROLE, 5000);
        await h.clickLast(/^Fermer$/, 1000);
      });

      await h.scene('installation', async () => {
        await h.code('Terminal', 'sur le MacBook Air, une seule fois', [
          'claude --version                     # Claude Code est bien installé',
          `claude plugin marketplace add ${PUBLIC_URL}/api/claude/marketplace.json`,
          'claude plugin install clockifai@clockifai',
          'pbpaste | claude plugin configure clockifai@clockifai --values-stdin',
          '                                     # Entrée après « Copier le jeton »',
        ], 11000);
        await h.hideCode();
      });

      await h.scene('session', async () => {
        await h.code('Terminal', 'une nouvelle conversation, dans le dépôt du site de la boulangerie', [
          'cd ~/code/site-boulangerie',
          'claude',
          '> Ajoute un formulaire de commande de gâteaux sur la page Contact',
          '',
          '# Claude nomme la tâche de ce travail : « Commande de gâteaux »',
        ], 7000);
        // Ce qu'envoie le plugin : début de session, prompt, tâche nommée par Claude, ses outils et son usage IA.
        const live = claudeSession('site-boulangerie');
        const t0 = new Date(Date.now() - 60000);
        const at = (s) => new Date(t0.getTime() + s * 1000);
        await postEvents(token, [
          live.ev('session_start', at(0), { payload: { source: 'startup' } }), live.ev('prompt', at(5)),
          live.ev('session_task', at(30), { payload: { task_name: 'Commande de gâteaux' } }),
          live.ev('agent_tool', at(55), { duration_ms: 15000 }),
          live.ev('agent_usage', at(56), { payload: usagePayload(0.5) }),
        ]);
        heartbeat = setInterval(() => postEvents(token, [live.ev('agent_tool', new Date(), { duration_ms: 15000 }),
          live.ev('agent_usage', new Date(), { payload: usagePayload(0.1) })]).catch(() => {}), 30000);
        await h.hideCode();
        await h.nav('Suivi du temps', 1000);
        await h.find(/Commande de gâteaux/, { timeout: 30000 });
        await h.caption(C('Suivi du temps'), 'Claude travaille',
          'La session en cours, rangée dans le projet du dépôt et la tâche nommée par Claude. Rien à démarrer ni à arrêter : après 10 minutes sans activité, l’entrée s’arrête à la dernière action.', ROLE, 8000);
      });

      await h.scene('tâches', async () => {
        await h.nav('Paramètres');
        await h.reveal(/^Claude Code/, 420);
        await h.click(/^Claude Code/, 1500);
        await h.click(/^Une tâche par sujet/, 1200);
        await h.caption(C('Tâches de Claude'), 'Comment ranger le temps de Claude',
          'Par sujet : un même nom retombe sur la même tâche, d’une session à l’autre (« Page Contact »). Par session : chaque conversation a la sienne. Ou le projet seulement.', ROLE, 8000);
        await h.page.keyboard.press('Escape');
        await h.wait(800);
        await h.reveal(/^Postes connectés$/, 420, { x: 720 });
        await h.caption(C('Claude Code'), 'Postes connectés', 'Le dernier événement reçu de chaque ordinateur. Révoquer déconnecte un poste ; Reconnecter lui redonne un jeton.', ROLE, 5000);
        await h.reveal(/^Voir sa fiche dans l'équipe$/, 300, { x: 720 });
        await h.click(/^Voir sa fiche dans l'équipe$/, 2500);
        await h.caption(C('Équipe'), 'Un membre de l’équipe, piloté par Alex',
          'L’agent a sa fiche : ses sessions en cours, son total de la semaine et son coût IA estimé. Un administrateur peut le désactiver ou le retirer.', ROLE, 7000);
      });

      await h.scene('contrôle', async () => {
        await h.nav('Rapports');
        await h.click(/^Cette semaine$/, 900);
        await h.pick(/^Période personnalisée$/, 1500);
        await h.click(/Passer à la saisie/, 1000);
        // Champs vides (étiquette « Date de début jj/mm/aaaa ») : le premier a déjà le focus.
        await h.page.keyboard.type(weekAgo, { delay: 45 });
        await h.click(/^Date de fin/, 300);
        await h.page.keyboard.type(today, { delay: 45 });
        await h.wait(400);
        await h.clickLast(/^OK$/, 1800);
        await h.click(/^Humains et agents$/, 900);
        await h.pick(/^Agents$/, 1800);
        await h.hover(/^Coût IA estimé/);
        await h.caption(C('Rapports'), 'Le temps de Claude, à part, et ce qu’il coûte',
          'Le filtre « Humains et agents » sépare les heures d’Alex de celles de son agent. « Coût IA estimé » : ses tokens au tarif de l’API d’Anthropic, en dollars (avec un abonnement Claude, un ordre de grandeur).', ROLE, 8000);
        await h.click(/^Agents$/, 900);
        await h.pick(/^Humains et agents$/, 1500);
        await h.click(/^Détaillé$/, 1500);
        await h.reveal(/^Détaillé$/, 230);
        await h.caption(C('Rapports'), 'Jour par jour',
          'Les heures d’Alex et celles de Claude ; chaque session dans sa tâche, décrite par les messages de ses commits, avec ses tokens et son coût.', ROLE, 7000);
        await h.reveal(/Compresse les photos de la vitrine/, 420);
        await h.click(/Compresse les photos de la vitrine/, 2000);
        await h.caption(C('Rapports'), 'Corriger le temps de son agent',
          'Projet, tâche, description, horaires, ou supprimer l’entrée. Pas d’ajout à la main : seul Claude Code enregistre ce temps, et une correction n’est jamais écrasée.', ROLE, 7000);
        await h.hover(/^Usage IA/);
        await h.caption(C('Rapports'), 'Usage IA de la session',
          'Par modèle et par effort : appels, tokens en entrée et en sortie, écrits et lus en cache. Le plugin ne lit que ces totaux dans la transcription, jamais vos messages.', ROLE, 7500);
        await h.clickLast(/^Annuler$/, 1000);
      });

      await h.scene('facturation', async () => {
        await h.nav('Factures');
        await h.click(/^Nouvelle facture$/, 1500);
        await h.click(/→/, 1500);
        await h.click(/Passer à la saisie/, 1000);
        await h.typeInto('Date de début', `01/${today.slice(3)}`);
        await h.typeInto('Date de fin', today);
        await h.clickLast(/^OK$/, 1200);
        await h.caption(C('Factures'), 'Facturer le mois à la boulangerie', '« Détailler par tâche » est coché : une ligne par tâche, qu’elle soit d’Alex ou de Claude.', ROLE, 4000);
        await h.clickLast(/^Générer$/, 3500);
        await h.caption(C('Factures'), 'Les heures d’Alex et celles de Claude, au taux du projet',
          'Le temps de l’agent se facture comme celui d’un humain ; un réglage de l’entreprise (ou du projet) peut le rendre non facturable.', ROLE, 7000);
        await h.clickLast(/^Fermer$/, 1200);
      });
    });

    const end = await record(browser, {}, async (page, clock) => {
      const h = helpers(page, failures, clock);
      await page.setContent('<html><body style="margin:0;background:#0f172a"></body></html>');
      await page.evaluate(() => window.__demo.ensure());
      await h.card('Alex et son agent Claude', 'Ce qu’il faut retenir', [
        'Un jeton par ordinateur : Paramètres › Intégrations › Claude Code',
        'Chaque session de Claude Code devient du temps de son agent',
        'Claude nomme ses tâches ; le dépôt donne le projet',
        'Rien de vos messages ni de votre code ne part vers Clockifai',
        'Le temps de l’agent se contrôle, se corrige et se facture',
        'Son usage de l’IA : tokens et coût estimé de chaque entrée',
      ], 9000);
    });

    return [{ webm: desktop }, { webm: end }];
  } finally {
    clearInterval(heartbeat);
    srv.kill();
  }
}
