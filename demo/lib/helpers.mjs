// Outils communs du tournage : pilotage de l'app Flutter web, incrustations, encodage.
import { execSync, spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ffmpegPath from 'ffmpeg-static';

export const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const repo = path.resolve(here, '..');
export const out = path.join(here, 'out');
// Port dédié : le 3000 sert souvent au `flutter run` de développement.
export const APP = process.env.APP_URL || 'http://localhost:3100';
export const PASSWORD = 'Demo-2026-clockifai';
export const KIOSK_TOKEN = 'kio_demo_tablette_base_vie_2026';
export const W = 1440;
export const H = 900;
export const overlay = fs.readFileSync(path.join(here, 'lib', 'overlay.js'), 'utf8');
/** DEMO_FAST=1 : répétition sans vidéo, bandeaux 10× plus courts (mise au point des scénarios). */
export const FAST = process.env.DEMO_FAST === '1';

/** Sert app/build/web (build de production) sur le port 3100 si rien n'y répond déjà. */
export async function ensureServer() {
  try {
    if ((await fetch(APP)).ok) return null;
  } catch { /* démarrage ci-dessous */ }
  const srv = spawn(process.execPath, [path.join(here, 'serve.mjs'), '3100'], { stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 800));
  return srv;
}

/**
 * Horloge de chaque fichier vidéo ({ start, cuts, scenes }) :
 * - cuts : temps morts à couper au montage ; quand une action attend l'app (synchronisation,
 *   machine chargée) bien au-delà du prévu, l'intervalle est noté et retiré de la vidéo ;
 * - scenes : début de chaque scène, d'où les chapitres que le guide utilisateur relie à ses sections.
 */
export const timeline = new Map();
const SLACK = 1.5; // secondes d'attente tolérées à l'image

/**
 * Coupe le réseau du navigateur le temps de [fn] (comme un téléphone sans réseau), et le rétablit quoi qu'il arrive.
 * NB : un `docker pause` du serveur ne convient pas, les connexions restent pendantes et figent la page.
 */
export async function offline(page, fn) {
  await page.context().setOffline(true);
  try {
    await fn();
  } finally {
    await page.context().setOffline(false);
  }
}

export function ffmpeg(args) {
  execSync(`"${ffmpegPath}" -y -loglevel error ${args}`, { stdio: 'inherit' });
}

/** Intervalles [début, fin] fusionnés, d'au moins 0,5 s. */
function mergeCuts(cuts) {
  const sorted = cuts.filter(([a, b]) => b - a >= 0.5).sort((x, y) => x[0] - y[0]);
  const merged = [];
  for (const [a, b] of sorted) {
    const last = merged[merged.length - 1];
    if (last && a <= last[1]) last[1] = Math.max(last[1], b);
    else merged.push([a, b]);
  }
  return merged;
}

/**
 * Repères de début de scène (__demo.mark, overlay.js) : intervalles [début, fin] où le coin bas-droit du webm est
 * magenta (Cb et Cr élevés, ce que ni l'app ni les incrustations n'affichent à cet endroit).
 */
function sceneMarks(webm, { width, height }) {
  const { stderr } = spawnSync(ffmpegPath, ['-i', webm, '-vf', `crop=6:6:${width - 11}:${height - 11},signalstats,metadata=print`, '-f', 'null', '-'],
    { encoding: 'utf8', maxBuffer: 1 << 28 });
  const marks = [];
  let t = 0;
  let u = 0;
  for (const line of stderr.split('\n')) {
    const pts = line.match(/pts_time:([\d.]+)/);
    if (pts) t = Number(pts[1]);
    const cb = line.match(/signalstats\.UAVG=([\d.]+)/);
    if (cb) u = Number(cb[1]);
    const cr = line.match(/signalstats\.VAVG=([\d.]+)/);
    if (cr && u > 180 && Number(cr[1]) > 180) {
      const last = marks[marks.length - 1];
      if (last && t - last[1] < 0.3) last[1] = t;
      else marks.push([t, t]);
    }
  }
  return marks;
}

/**
 * webm Playwright → mp4 H.264 1440×900 (téléphone centré sur fond sombre), temps morts retirés, repères de scène
 * effacés. Renvoie les chapitres de cette partie, [{ scene, start }], recalés sur la vidéo coupée.
 */
export function encode(webm, target, { phone = false } = {}) {
  const { start = 0, end = start, cuts: raw = [], scenes = [] } = timeline.get(webm) ?? {};
  const info = probe(webm);
  // Horloge et vidéo ne coïncident pas : la vidéo commence avec sa première image (1 à 2 s après l'horloge) et
  // s'étire quand l'app anime l'écran (Playwright écrit chaque image reçue au moins une fois à 25 i/s). Les
  // chapitres viennent donc des repères filmés ; l'horloge, recalée sur la fin de la vidéo, ne sert qu'en secours.
  const lead = Math.max(0, (end - start) / 1000 - info.duration);
  const cuts = mergeCuts(raw.map(([a, b]) => [a - lead, b - lead]));
  const marks = sceneMarks(webm, info);
  const starts = marks.length === scenes.length
    ? marks.map(([a]) => a)
    : (console.log(`  ${marks.length} repère(s) pour ${scenes.length} scène(s) : chapitres d'après l'horloge, approximatifs`),
      scenes.map(([, t]) => t - lead));
  const select = cuts.length
    ? `select='not(${cuts.map(([a, b]) => `between(t,${a.toFixed(2)},${b.toFixed(2)})`).join('+')})',setpts=N/30/TB,`
    : '';
  if (cuts.length) console.log(`  coupe ${cuts.length} temps mort(s), ${Math.round(cuts.reduce((s, [a, b]) => s + b - a, 0))} s au total`);
  const unmark = marks.length
    ? `delogo=x=${info.width - 16}:y=${info.height - 16}:w=15:h=15:enable='${marks.map(([a, b]) => `between(t,${(a - 0.1).toFixed(2)},${(b + 0.1).toFixed(2)})`).join('+')}',`
    : '';
  const vf = phone ? `scale=-2:${H - 40},pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=0x0f172a` : `scale=${W}:${H}`;
  ffmpeg(`-i "${webm}" -vf "fps=30,${unmark}${select}${vf},format=yuv420p" -c:v libx264 -preset medium -crf 21 -an -movflags +faststart "${target}"`);
  const removedBefore = (t) => cuts.reduce((s, [a, b]) => s + Math.max(0, Math.min(b, t) - a), 0);
  return scenes.map(([scene], i) => ({ scene, start: Math.max(0, starts[i] - removedBefore(starts[i])) }));
}

/** Durée (secondes) et dimensions d'un fichier vidéo, lues dans l'en-tête par ffmpeg. */
export function probe(file) {
  const { stderr } = spawnSync(ffmpegPath, ['-i', file], { encoding: 'utf8' });
  const d = stderr.match(/Duration: (\d+):(\d+):([\d.]+)/);
  const s = stderr.match(/Video: .*?, (\d{2,5})x(\d{2,5})/);
  return {
    duration: d ? Number(d[1]) * 3600 + Number(d[2]) * 60 + Number(d[3]) : 0,
    width: s ? Number(s[1]) : W,
    height: s ? Number(s[2]) : H,
  };
}

export const duration = (file) => probe(file).duration;

export function concat(parts, target) {
  const list = `${target}.txt`;
  fs.writeFileSync(list, parts.map((p) => `file '${p}'`).join('\n'));
  ffmpeg(`-f concat -safe 0 -i "${list}" -c copy -movflags +faststart "${target}"`);
  fs.rmSync(list);
}

/** Jour au format des boutons du sélecteur de date Flutter : « 9, vendredi 9 octobre 2026 ». */
export const frDay = (d) =>
  `${d.getDate()}, ${d.toLocaleDateString('fr-FR', { weekday: 'long' })} ${d.getDate()} ${d.toLocaleDateString('fr-FR', { month: 'long' })} ${d.getFullYear()}`;
export const previous = (weekday) => { const d = new Date(); do { d.setDate(d.getDate() - 1); } while (d.getDay() !== weekday); return d; };

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export function helpers(page, failures, clock = null) {
  const wait = (ms) => page.waitForTimeout(ms);
  /** Exécute [fn] ; si l'attente dépasse [expectedMs] + marge, l'excédent est marqué comme temps mort. */
  const timed = async (what, expectedMs, fn) => {
    const t0 = Date.now();
    try {
      return await fn();
    } finally {
      const extra = (Date.now() - t0 - expectedMs) / 1000;
      if (extra > SLACK) {
        console.log(`    attente : ${what} +${Math.round(extra)} s`);
        if (clock) clock.cuts.push([(t0 - clock.start) / 1000 + expectedMs / 1000 + 0.5, (Date.now() - clock.start) / 1000 - 0.3]);
      }
    }
  };
  const semantics = async () => {
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await wait(300);
  };
  /** Bandeau explicatif : chapitre, titre, texte, rôle affiché en pastille. */
  const caption = async (chapter, title, text, role, ms = 4500, bottom) => {
    await timed('bandeau', 300, () => page.evaluate(([c, t, x, r, b]) => window.__demo.caption(c, t, x, r, b), [chapter, title, text ?? null, role ?? null, bottom ?? null]));
    await wait(FAST ? Math.min(ms, 400) : ms);
  };
  const hide = () => page.evaluate(() => window.__demo.hide());
  const card = async (title, subtitle, bullets, ms) => {
    await page.evaluate(([t, s, b]) => window.__demo.card(t, s, b), [title, subtitle, bullets]);
    await wait(FAST ? 300 : ms);
  };
  const hideCard = async () => { await page.evaluate(() => window.__demo.hideCard()); await wait(700); };
  const code = async (title, subtitle, lines, ms) => {
    await page.evaluate(([t, s, l]) => window.__demo.code(t, s, l), [title, subtitle, lines]);
    await wait(FAST ? 300 : ms);
  };
  const hideCode = async () => { await page.evaluate(() => window.__demo.hideCode()); await wait(700); };
  const moveTo = async (x, y) => { await page.mouse.move(x, y, { steps: 18 }); await wait(120); };
  const clickXY = async (x, y, pause = 500) => {
    await moveTo(x, y);
    await timed('clic', 300, () => page.mouse.click(x, y));
    await wait(pause);
  };
  const box = async (loc) => timed('localisation', 600, async () => {
    await loc.waitFor({ state: 'attached', timeout: 12000 });
    const b = await loc.boundingBox({ timeout: 12000 });
    if (!b) throw new Error('élément sans position');
    return b;
  });
  const clickLoc = async (loc, pause = 600) => { const b = await box(loc); await clickXY(b.x + b.width / 2, b.y + b.height / 2, pause); };
  const hover = async (target) => {
    if (target instanceof RegExp || typeof target === 'string') { const p = await find(target); return moveTo(p.x, p.y); }
    const b = await box(target); await moveTo(b.x + b.width / 2, b.y + b.height / 2);
  };
  const node = (text) => page.locator('flt-semantics').filter({ hasText: text });
  const button = (text) => page.locator('flt-semantics[role="button"]').filter({ hasText: text });
  const field = (label) => page.locator(`input[aria-label="${label}"], textarea[aria-label="${label}"]`).first();
  /**
   * Cherche dans l'arbre d'accessibilité Flutter un nœud dont l'étiquette ou le texte correspond à [re],
   * quel que soit son rôle (bouton, onglet, option de menu, tuile…). Renvoie le centre du nœud retenu.
   * which : 'first' | 'last' (le plus « au-dessus », ex. dans une boîte de dialogue) | 'top' (le plus haut à l'écran).
   */
  const find = (re, opts = {}) => timed(`recherche ${re}`, 600, () => findRaw(re, opts));
  const findRaw = async (re, { which = 'first', role, timeout = 12000 } = {}) => {
    const src = re instanceof RegExp ? re.source : String(re).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const flags = re instanceof RegExp ? re.flags : '';
    const t0 = Date.now();
    for (;;) {
      await semantics();
      const hit = await page.evaluate(([s, f, w, r]) => {
        const rx = new RegExp(s, f);
        const nodes = [...document.querySelectorAll('flt-semantics, input, textarea')].filter((n) => {
          if (r && n.getAttribute('role') !== r) return false;
          const label = n.getAttribute('aria-label');
          // Étiquette, sinon texte propre du nœud : ses textes et sous-éléments simples, sans les nœuds
          // d'accessibilité enfants (on vise l'élément le plus précis).
          const own = label || [...n.childNodes].map((c) => (c.nodeType === 3 ? c.textContent
            : c.nodeType === 1 && c.tagName !== 'FLT-SEMANTICS' && !c.querySelector('flt-semantics') ? c.textContent : '')).join('');
          if (!own || !rx.test(own.trim())) return false;
          const b = n.getBoundingClientRect();
          return b.width > 0 && b.height > 0 && b.bottom > 0 && b.top < innerHeight;
        }).map((n) => { const b = n.getBoundingClientRect(); return { x: b.x + b.width / 2, y: b.y + b.height / 2, area: b.width * b.height }; });
        if (!nodes.length) return null;
        if (w === 'last') return nodes[nodes.length - 1];
        if (w === 'top') return nodes.sort((a, b) => a.y - b.y)[0];
        return nodes[0];
      }, [src, flags, which, role ?? null]);
      if (hit) {
        const dt = Date.now() - t0;
        if (dt > 5000) console.log(`    lent : ${re} trouvé en ${Math.round(dt / 1000)} s`);
        return hit;
      }
      if (Date.now() - t0 > timeout) throw new Error(`introuvable : ${re} (${Math.round((Date.now() - t0) / 1000)} s)`);
      await wait(250);
    }
  };
  const clickFound = async (re, opts = {}, pause = 600) => { const p = await find(re, opts); await clickXY(p.x, p.y, pause); };
  /** Toutes les positions des nœuds dont l'étiquette ou le texte correspond (visibles à l'écran). */
  const findAll = async (re) => {
    await semantics();
    return page.evaluate(([s, f]) => {
      const rx = new RegExp(s, f);
      return [...document.querySelectorAll('flt-semantics, input, textarea')].filter((n) => {
        const own = n.getAttribute('aria-label') || [...n.childNodes].map((c) => (c.nodeType === 3 ? c.textContent
          : c.nodeType === 1 && c.tagName !== 'FLT-SEMANTICS' && !c.querySelector('flt-semantics') ? c.textContent : '')).join('');
        if (!own || !rx.test(own.trim())) return false;
        const b = n.getBoundingClientRect();
        return b.width > 0 && b.height > 0 && b.bottom > 0 && b.top < innerHeight;
      }).map((n) => { const b = n.getBoundingClientRect(); return { x: b.x + b.width / 2, y: b.y + b.height / 2, top: b.top, bottom: b.bottom }; });
    }, [re.source, re.flags]);
  };
  const click = async (text, pause) => clickFound(text, { which: 'first' }, pause);
  const clickLast = async (text, pause) => clickFound(text, { which: 'last' }, pause);
  /** Élément quelconque (tuile de liste, option de menu…) : la dernière occurrence est la plus « au-dessus ». */
  const pick = async (text, pause) => clickFound(text, { which: 'last' }, pause);
  const menuItem = async (label, pause) => clickFound(new RegExp(`^${esc(label)}$`), { which: 'last', role: 'menuitem' }, pause);
  const typeInto = async (label, text, delay = 45) => {
    await clickFound(new RegExp(`^${esc(label)}$`), { which: 'last' }, 250);
    await page.keyboard.press('ControlOrMeta+a');
    await timed(`frappe « ${label} »`, text.length * delay + 400, () => page.keyboard.type(text, { delay }));
    await wait(300);
  };
  /** Les entrées de menu ont un libellé d'accessibilité supplémentaire (« Onglet 2 sur 13 ») : on compare le début. */
  const navRe = (label) => new RegExp(`^${esc(label)}(\\s|$)`);
  // Pages regroupées dans une rubrique du menu (plans/14-coller-aux-maquettes.md) : la rubrique, puis son onglet.
  const SECTIONS = {
    'Suivi du temps': ['Semaine', 'Liste'],
    'Feuille de temps': ['Semaine', 'Grille'],
    Calendrier: ['Semaine', 'Calendrier'],
    Planning: ['Équipe', 'Planning'],
    Absences: ['Équipe', 'Absences'],
    Approbations: ['Équipe', 'Approbations'],
    "Pointage d'équipe": ['Équipe', "Pointage d'équipe"],
    Projets: ['Projets et clients', 'Projets'],
    Clients: ['Projets et clients', 'Clients'],
    Tags: ['Projets et clients', 'Tags'],
  };
  const nav = async (label, pause = 1800) => {
    const [section, tab] = SECTIONS[label] ?? [label];
    if (!tab) return clickFound(navRe(section), { which: 'first' }, pause);
    await clickFound(navRe(section), { which: 'first' }, 1200);
    await clickFound(new RegExp(`^${esc(tab)}$`), { which: 'top' }, pause);
  };
  /** Cases de la feuille de temps (champs étroits, étiquetés « – » ou sans étiquette) alignées sur la hauteur [y], de gauche à droite. */
  const inputsAt = (y) => page.evaluate((yy) => [...document.querySelectorAll('input')]
    .map((n) => n.getBoundingClientRect())
    .filter((b) => b.width > 0 && b.width < 150 && Math.abs(b.y + b.height / 2 - yy) < 18)
    .sort((a, b) => a.x - b.x)
    .map((b) => ({ x: b.x + b.width / 2, y: b.y + b.height / 2 })), y);
  /** Clique l'élément le plus haut à l'écran parmi plusieurs homonymes (ex. menu « ⋯ » de la barre de saisie). */
  const clickTop = async (re, pause = 700) => clickFound(re, { which: 'top' }, pause);
  /** Clique le bouton [buttonRe] situé dans le même bloc que le texte [rowRe] (ex. menu « ⋯ » de la carte d'un membre). */
  const clickNear = async (rowRe, buttonRe, pause = 800) => {
    const row = await find(rowRe);
    const cands = await findAll(buttonRe);
    const best = cands.sort((a, b) => Math.abs(a.y - row.y) - Math.abs(b.y - row.y))[0];
    if (!best || Math.abs(best.y - row.y) > 80) throw new Error(`pas de « ${buttonRe} » près de ${rowRe}`);
    await clickXY(best.x, best.y, pause);
  };
  const scroll = async (x, y, steps, dy = 260, pause = 450) => {
    await moveTo(x, y);
    for (let i = 0; i < steps; i++) { await page.mouse.wheel(0, dy); await wait(pause); }
  };
  /**
   * Fait défiler à la molette jusqu'à amener [re] à la hauteur [y] de l'écran (ou jusqu'en bas de la page).
   * Plus sûr qu'un nombre de crans fixe : le bandeau s'affiche quand le réglage dont il parle est visible.
   */
  const reveal = async (re, y = 300, { x = 830, step = 220, pause = 380 } = {}) => {
    await moveTo(x, 500);
    let last;
    for (let i = 0; i < 30; i++) {
      const hit = (await findAll(re))[0];
      if (hit && (Math.abs(hit.y - y) < 40 || hit.y === last)) return;
      last = hit?.y;
      await page.mouse.wheel(0, hit ? Math.max(-step, Math.min(step, hit.y - y)) : step);
      await wait(pause);
    }
    throw new Error(`introuvable en faisant défiler : ${re}`);
  };
  /** Une scène : en cas d'échec, on note, on ferme les boîtes de dialogue et on continue le tournage. */
  const scene = async (name, fn) => {
    const t0 = Date.now();
    clock?.scenes.push([name, (t0 - clock.start) / 1000]);
    // Repère filmé (chapitres du guide) : le laisser peindre avant que la scène ne change de page.
    await page.evaluate(() => window.__demo?.mark()).catch(() => {});
    if (!FAST) await wait(200);
    console.log(`  · ${new Date().toLocaleTimeString('fr-FR')} scène « ${name} »`);
    try { await semantics(); await fn(); console.log(`    ok (${Math.round((Date.now() - t0) / 1000)} s)`); }
    catch (e) {
      failures.push(`${name} : ${e.message.split('\n')[0]}`);
      console.error(`✗ ${name} : ${e.message.split('\n')[0]}`);
      // Capture et dernière cible recherchée, pour diagnostiquer sans rejouer.
      const shot = path.join(out, `echec-${name.replace(/[^a-z0-9]+/gi, '-')}.png`);
      await page.screenshot({ path: shot }).catch(() => {});
      console.error(`    capture : ${shot} · cible : ${e.message.match(/waiting for (.*)/)?.[1] ?? '?'}`);
      await page.keyboard.press('Escape').catch(() => {});
    }
    await hide().catch(() => {});
    await wait(400);
  };
  const login = async (email) => {
    await semantics();
    await typeInto('Email', email);
    await typeInto('Mot de passe', PASSWORD);
    await clickLast(/^Connexion$/, 6500);
    await semantics();
  };
  const signOut = async () => {
    await nav('Paramètres');
    await scroll(830, 500, 14, 500, 120); // le bouton est en bas de la page
    await click(/^Se déconnecter/, 800);
    await clickLast(/^Se déconnecter$/, 3000);
  };
  return {
    page, wait, semantics, caption, hide, card, hideCard, code, hideCode, moveTo, clickXY, clickLoc, hover, node, button, field,
    click, clickLast, clickFound, find, findAll, inputsAt, pick, menuItem, typeInto, navRe, nav, clickTop, clickNear, scroll, reveal, scene, login, signOut,
  };
}

/** Ouvre un contexte enregistré, exécute [fn], renvoie le chemin du webm. */
/** [onContext] : réglages du contexte avant la première page (interception de requêtes, permissions). */
export async function record(browser, { phone = false, onContext } = {}, fn) {
  const viewport = phone ? { width: 390, height: 844 } : { width: W, height: H };
  const ctx = await browser.newContext({
    viewport,
    deviceScaleFactor: phone ? 2 : 1,
    isMobile: phone,
    locale: 'fr-FR',
    timezoneId: 'Europe/Paris',
    // La vidéo est capturée en pixels CSS : une taille plus grande que le viewport laisse la page dans un coin.
    ...(FAST ? {} : { recordVideo: { dir: out, size: viewport } }),
  });
  await ctx.addInitScript(overlay);
  await onContext?.(ctx);
  const clock = { start: Date.now(), cuts: [], scenes: [] };
  const page = await ctx.newPage();
  try {
    await fn(page, clock);
  } finally {
    clock.end = Date.now();
    await ctx.close();
  }
  if (FAST) return null;
  const file = await page.video().path();
  timeline.set(file, clock);
  return file;
}
