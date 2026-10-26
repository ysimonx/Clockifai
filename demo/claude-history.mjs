// Vidéo 6 (appelé par prepare-demo.sh) : Alex connecte son Mac mini à Claude Code, puis les sessions de Claude des
// derniers jours ouvrés passent par le vrai chemin (jeton personnel, POST /api/activity/events, chronomètre de
// l'agent), comme si le plugin les avait envoyées au fil de la semaine.
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { PASSWORD, repo } from './lib/helpers.mjs';
import { pastSession, postEvents } from './lib/claude.mjs';
import { SERVICES } from './lib/public-instance.mjs';

const SUPABASE = process.env.SUPABASE_URL || 'http://localhost:8000';
const ANON = fs.readFileSync(path.join(repo, 'deploy', '.env'), 'utf8').match(/^ANON_KEY=(.*)$/m)[1].trim();
const psql = (sql) => execSync('docker exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=1 -qAt', { input: sql }).toString().trim();

const login = await (await fetch(`${SUPABASE}/auth/v1/token?grant_type=password`, {
  method: 'POST',
  headers: { apikey: ANON, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: 'alex@demo.clockifai.fr', password: PASSWORD }),
})).json();
const workspaceId = psql(`select default_workspace_id from public.profiles where id = '${login.user.id}'`);
const res = await fetch(`${SERVICES}/api/tokens`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${login.access_token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ workspace_id: workspaceId, name: 'Mac mini' }),
});
if (res.status !== 201) throw new Error(`jeton : ${res.status} ${await res.text()}`);
const { token } = await res.json();

// Les événements de plus de 7 jours sont refusés : jours ouvrés des 6 derniers jours, du plus ancien au plus récent.
const days = [];
for (let i = 1; i <= 6 && days.length < 5; i++) {
  const d = new Date();
  d.setDate(d.getDate() - i);
  if (d.getDay() % 6 !== 0) days.unshift(d);
}
const plan = [
  [['site-boulangerie', '10:05', 50, 'Page Contact', ['Ajoute la page Contact']],
    ['appli-rdv', '15:20', 40, 'Formulaire de réservation', ['Formulaire de réservation : choix du créneau']]],
  [['site-boulangerie', '09:40', 35, 'Menu mobile', ['Corrige le menu sur mobile']],
    ['appli-rdv', '14:00', 55, 'Formulaire de réservation', ['Vérifie les champs du formulaire']]],
  [['appli-rdv', '10:30', 70, 'Rappels par SMS', ['Envoie un rappel la veille du rendez-vous', 'Ajoute le modèle de SMS']],
    ['site-boulangerie', '16:00', 20, 'Page Contact', ["Ajoute le plan d'accès"]]],
  [['site-boulangerie', '11:00', 30, 'Optimisation des images', ['Compresse les photos de la vitrine']],
    ['appli-rdv', '15:00', 45, 'Tests du paiement', ["Teste le paiement de l'acompte"]]],
  [['appli-rdv', '09:50', 30, 'Rappels par SMS', ['Raccourcit le texte du rappel']],
    ['site-boulangerie', '14:30', 25, "Horaires d'ouverture", ['Met à jour les horaires']]],
].slice(-days.length);

let last;
for (const [i, sessions] of plan.entries()) {
  for (const [repoName, time, minutes, task, commits] of sessions) {
    const start = new Date(days[i]);
    const [h, m] = time.split(':').map(Number);
    start.setHours(h, m, 0, 0);
    await postEvents(token, pastSession({ repo: repoName, start, minutes, task, commits }));
    last = new Date(start.getTime() + minutes * 60000);
  }
}
// Dernier événement du Mac mini : la fin de la dernière session, pas l'heure de cette préparation.
psql(`update clockifai_private.api_tokens set last_used_at = '${last.toISOString()}' where workspace_id = '${workspaceId}' and name = 'Mac mini'`);
console.log(`[demo] Claude Code : ${plan.flat().length} sessions sur ${days.length} jours`);
