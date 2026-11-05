// Vidéo 6 : l'app telle que sur une vraie instance, à une adresse https, pour que l'écran Claude Code montre les
// commandes de production (marketplace servie par l'instance, plugin clockifai@clockifai) et non celles de la pile
// locale (clockifai-dev). Un build web à part, compilé avec SERVICES_URL = PUBLIC_URL, est servi sur 3101 ; le
// navigateur ne contacte jamais cette adresse : Playwright intercepte ses requêtes et les passe au Flask local.
import { execSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { APP, here, out, repo } from './helpers.mjs';

export const PUBLIC_URL = 'https://clockifai.example.fr';
export const PUBLIC_APP = 'http://localhost:3101';
export const SERVICES = 'http://localhost:5050';
const build = path.join(repo, 'app', 'build', 'web-demo');

/** Compile le build « adresse publique » s'il manque ou s'il est plus ancien que app/build/web (make app-build-web). */
function ensureBuild() {
  const js = path.join(build, 'main.dart.js');
  const ref = path.join(repo, 'app', 'build', 'web', 'main.dart.js');
  if (fs.existsSync(js) && (!fs.existsSync(ref) || fs.statSync(js).mtimeMs >= fs.statSync(ref).mtimeMs)) return;
  const config = JSON.parse(fs.readFileSync(path.join(repo, 'app', 'config', 'local.json'), 'utf8'));
  const defines = path.join(out, 'public-instance.json');
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(defines, JSON.stringify({ ...config, SERVICES_URL: PUBLIC_URL }));
  const t0 = Date.now();
  try {
    execSync(`fvm flutter build web --release --dart-define-from-file="${defines}" -o "${build}"`,
      { cwd: path.join(repo, 'app'), stdio: 'ignore' });
  } finally {
    fs.rmSync(defines, { force: true });
  }
  console.log(`  build web à l'adresse ${PUBLIC_URL} : ${Math.round((Date.now() - t0) / 1000)} s`);
}

/** Build à jour et servi sur PUBLIC_APP ; renvoie le serveur à arrêter. */
export async function startPublicApp() {
  ensureBuild();
  const srv = spawn(process.execPath, [path.join(here, 'serve.mjs'), new URL(PUBLIC_APP).port, build], { stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 800));
  return srv;
}

/** Contexte du navigateur : requêtes vers PUBLIC_URL passées au Flask local, presse-papiers autorisé. */
export async function routePublic(ctx) {
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: PUBLIC_APP });
  await ctx.route(`${PUBLIC_URL}/**`, async (route) => {
    const req = route.request();
    // Flask n'admet que les origines de la pile locale (CORS_ORIGINS) : on présente celle du build habituel.
    const response = await route.fetch({ url: req.url().replace(PUBLIC_URL, SERVICES), headers: { ...req.headers(), origin: APP } });
    await route.fulfill({ response, headers: { ...response.headers(), 'access-control-allow-origin': PUBLIC_APP } });
  });
}
