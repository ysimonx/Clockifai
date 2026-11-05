// Sessions de Claude Code simulées pour la vidéo 6 : les événements qu'enverrait le plugin (hook) d'Alex, postés
// sur POST /api/activity/events avec son jeton. Le serveur en tire les entrées de l'agent (chronomètre, tâches
// nommées, description par les commits), exactement comme en vrai.
import { randomBytes, randomUUID } from 'node:crypto';
import { SERVICES } from './public-instance.mjs';

export const repoKey = (name) => `github.com/studio-alex/${name}`;

/** Une session : identifiant, dépôt, et `ev(kind, à, champs)` pour en fabriquer les événements. */
export function claudeSession(repo) {
  const base = { session_id: randomUUID(), remote_key: repoKey(repo), git_branch: 'main', cwd: `/Users/alex/code/${repo}` };
  const ev = (kind, at, extra = {}) => ({ ...base, id: randomUUID(), kind, occurred_at: at.toISOString(), ...extra });
  return { ...base, ev };
}

/** Usage IA de 5 minutes de travail (plan 10, D17), comme le plugin le lit dans la transcription : Opus 5.5 en effort
 *  xhigh, environ 0,75 $ au tarif de l'API, un peu plus ou un peu moins selon [k]. */
export const usagePayload = (k = 1, model = 'claude-opus-5-5', effort = 'xhigh') => ({
  model, effort, speed: 'standard', requests: Math.round(12 * k), input_tokens: Math.round(20 * k),
  output_tokens: Math.round(6000 * k), cache_write_5m_tokens: 0, cache_write_1h_tokens: Math.round(40000 * k),
  cache_read_tokens: Math.round(1_500_000 * k),
});

/** Session terminée : début, prompt, tâche nommée par Claude, outils toutes les 2 min 30, usage IA par tranche de
 *  5 minutes (et un sous-agent Haiku), commits, fin du tour. */
export function pastSession({ repo, start, minutes, task, commits = [] }) {
  const s = claudeSession(repo);
  const at = (sec) => new Date(start.getTime() + sec * 1000);
  const end = minutes * 60;
  const events = [s.ev('session_start', at(0), { payload: { source: 'startup' } }), s.ev('prompt', at(5)),
    s.ev('session_task', at(30), { payload: { task_name: task } })];
  for (let sec = 60; sec < end - 60; sec += 150) events.push(s.ev('agent_tool', at(sec), { duration_ms: 20000 }));
  for (let sec = 300, i = 0; sec <= end; sec += 300, i++) {
    events.push(s.ev('agent_usage', at(sec - 10), { payload: usagePayload([1, 0.7, 1.3, 0.9][i % 4]) }));
  }
  events.push(s.ev('agent_usage', at(Math.round(end / 3)), { payload: usagePayload(0.6, 'claude-haiku-5-5', 'medium') }));
  if (end > 20 * 60) events.push(s.ev('prompt', at(Math.round(end / 2))));
  commits.forEach((subject, i) => {
    const t = at(end - 90 + i * 10);
    events.push(s.ev('commit', t, { sha: randomBytes(20).toString('hex'), subject, authored_at: t.toISOString() }));
  });
  events.push(s.ev('agent_stop', at(end)));
  return events;
}

/** Ce que fait le hook d'un poste sans jeton : demander un lien, puis le retirer une fois le lien validé. */
export async function requestLink(machine) {
  const res = await fetch(`${SERVICES}/api/claude/link`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ machine }),
  });
  if (res.status !== 201) throw new Error(`lien refusé : ${res.status}`);
  return res.json();
}

export async function fetchToken(poll) {
  const res = await fetch(`${SERVICES}/api/claude/link/poll`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ poll }),
  });
  const body = await res.json();
  if (!body.token?.startsWith('clk_')) throw new Error(`pas de jeton : ${res.status} ${JSON.stringify(body)}`);
  return body.token;
}

export async function postEvents(token, events) {
  const res = await fetch(`${SERVICES}/api/activity/events`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ events }),
  });
  const body = await res.json();
  if (res.status !== 202 || body.rejected?.length) throw new Error(`événements refusés : ${res.status} ${JSON.stringify(body)}`);
  return body;
}
