// Tournage des vidéos de démonstration de Clockifai.
//
//   make up && make app-build-web        # pile locale et build web à jour
//   cd demo && npm install
//   node record.mjs                      # les 5 vidéos (données réinitialisées avant chacune)
//   node record.mjs 2 3                  # seulement les vidéos 2 et 3
//
// Résultats : demo/out/<n>-<nom>.mp4, sans voix, avec incrustations explicatives, et
// demo/out/<n>-<nom>.chapters.json (début de chaque scène, lu par le guide utilisateur).
import { execSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { APP, FAST, concat, duration, encode, ensureServer, helpers, here, out } from './lib/helpers.mjs';

// macOS : un portable en veille ne fait tourner le tournage que pendant ses brefs réveils de maintenance
// (des scènes de plusieurs minutes). On réveille l'écran (-u), puis on empêche la veille jusqu'à la fin.
if (process.platform === 'darwin') {
  spawn('caffeinate', ['-u', '-t', '5'], { stdio: 'ignore' }).unref();
  spawn('caffeinate', ['-dis', '-w', String(process.pid)], { stdio: 'ignore' }).unref();
}

const videos = {
  1: () => import('./videos/1-camille.mjs'),
  2: () => import('./videos/2-chef-equipe.mjs'),
  3: () => import('./videos/3-manager.mjs'),
  4: () => import('./videos/4-gestion-workspace.mjs'),
  5: () => import('./videos/5-admin-installation.mjs'),
};
const wanted = process.argv.slice(2).filter((a) => videos[a]);
const ids = wanted.length ? wanted : Object.keys(videos);

fs.mkdirSync(out, { recursive: true });
const srv = await ensureServer();
const report = [];
let browser;
try {
  for (const id of ids) {
    // Navigateur neuf par vidéo : aucun état (worker de synchronisation, stockage) ne passe d'une vidéo à l'autre.
    await browser?.close();
    // Chromium complet (nouveau mode sans fenêtre) : rendu GPU, bien plus léger que le rendu logiciel.
    // DEMO_CHANNEL=chrome (Chrome installé) convient aux répétitions DEMO_FAST, pas au tournage : ses vidéos ont un
    // horodatage faux (plus courtes ou plus longues que le temps réel), donc des coupes et des chapitres décalés.
    browser = await chromium.launch({ channel: process.env.DEMO_CHANNEL || 'chromium' });
    const video = await videos[id]();
    console.log(`\n▶ vidéo ${video.name}`);
    if (video.prepare !== false) execSync(`sh "${path.join(here, 'prepare-demo.sh')}"`, { stdio: 'ignore' });
    // Chauffe non filmée : après la remise à zéro, le serveur de synchronisation re-réplique les données ;
    // on attend que la première synchronisation aboutisse pour ne pas filmer d'attente.
    for (const email of video.warmup ?? []) {
      const t0 = Date.now();
      const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'fr-FR' });
      const h = helpers(page, []);
      await page.goto(APP);
      await h.wait(2500);
      await h.login(email);
      await h.find(/^Suivi du temps(\s|$)/, { timeout: 600000 });
      await h.wait(3000);
      await page.close();
      console.log(`  chauffe ${email} : ${Math.round((Date.now() - t0) / 1000)} s`);
    }
    const failures = [];
    const parts = await video.run(browser, failures);
    if (FAST) { report.push({ video: video.name, failures }); console.log(`  répétition : ${failures.length} échec(s)`); continue; }
    const chapters = [];
    let offset = 0;
    const mp4s = parts.map((p, i) => {
      const target = path.join(out, `${video.name}.part${i}.mp4`);
      for (const c of encode(p.webm, target, { phone: p.phone })) {
        chapters.push({ scene: c.scene, start: Math.round((offset + c.start) * 10) / 10 });
      }
      offset += duration(target);
      fs.rmSync(p.webm, { force: true });
      return target;
    });
    const final = path.join(out, `${video.name}.mp4`);
    concat(mp4s, final);
    mp4s.forEach((f) => fs.rmSync(f, { force: true }));
    fs.writeFileSync(path.join(out, `${video.name}.chapters.json`), `${JSON.stringify(chapters, null, 2)}\n`);
    report.push({ video: final, failures });
    console.log(`  → ${final}${failures.length ? `  (${failures.length} scène(s) en échec)` : ''}`);
  }
} finally {
  await browser?.close();
  srv?.kill();
}
const failed = report.filter((r) => r.failures.length);
for (const r of failed) console.log(`\nÉchecs dans ${path.basename(r.video)} :\n- ${r.failures.join('\n- ')}`);
process.exitCode = failed.length ? 1 : 0;
