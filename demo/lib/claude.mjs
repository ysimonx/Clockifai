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

/** Session terminée : début, prompt, tâche nommée par Claude, outils toutes les 2 min 30, commits, fin du tour. */
export function pastSession({ repo, start, minutes, task, commits = [] }) {
  const s = claudeSession(repo);
  const at = (sec) => new Date(start.getTime() + sec * 1000);
  const end = minutes * 60;
  const events = [s.ev('session_start', at(0), { payload: { source: 'startup' } }), s.ev('prompt', at(5)),
    s.ev('session_task', at(30), { payload: { task_name: task } })];
  for (let sec = 60; sec < end - 60; sec += 150) events.push(s.ev('agent_tool', at(sec), { duration_ms: 20000 }));
  if (end > 20 * 60) events.push(s.ev('prompt', at(Math.round(end / 2))));
  commits.forEach((subject, i) => {
    const t = at(end - 90 + i * 10);
    events.push(s.ev('commit', t, { sha: randomBytes(20).toString('hex'), subject, authored_at: t.toISOString() }));
  });
  events.push(s.ev('agent_stop', at(end)));
  return events;
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
