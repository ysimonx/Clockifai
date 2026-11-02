// Icônes de l'app (web, iOS, macOS, Android), celles de « Clockifai Dev » (builds Debug) et le logo affiché dans
// l'app (AppLogo) : un chronomètre dessiné ici en SVG, rendu à chaque taille par le Chromium de Playwright installé
// dans demo/ (`cd demo && npm install`). `make app-icons` ; `--preview <fichier.png>` rend seulement une planche.
import { createRequire } from 'node:module';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = createRequire(join(app, '../demo/package.json'))('playwright');

// Encre et bleu des liens du thème (lib/core/theme.dart), ambre des alertes pour l'étincelle, sur une grille de 1024.
const ink = ['#2A3140', '#0F1217'];
const accent = ['#9DB2FF', '#4C6BF5'];
const spark = ['#FFE7A3', '#FFB547'];
const paper = '#FFFFFF';

const gradient = (id, [from, to], diagonal) =>
  `<linearGradient id="${id}" x1="0" y1="0" x2="${diagonal ? 1 : 0}" y2="1"><stop offset="0" stop-color="${from}"/><stop offset="1" stop-color="${to}"/></linearGradient>`;
const defs = `<defs>${gradient('bg', ink)}${gradient('accent', accent, true)}${gradient('spark', spark, true)}
  <radialGradient id="glow"><stop offset="0.55" stop-color="${accent[1]}" stop-opacity="0.35"/><stop offset="1" stop-color="${accent[1]}" stop-opacity="0"/></radialGradient>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-opacity="0.32"/></filter>
</defs>`;
// Le badge DEV est écrit en Geist, la police de l'app.
const font = `<style>@font-face{font-family:Geist;font-weight:700;src:url(data:font/ttf;base64,${
  readFileSync(join(app, 'assets/fonts/Geist-Bold.ttf')).toString('base64')})}</style>`;

// Le chronomètre : cadran, remontoir, temps écoulé (secteur bleu) et aiguille, l'étincelle de l'IA en haut à droite.
// `mono` : silhouette d'un seul ton (icônes à thème d'Android).
const cx = 512, cy = 552, ring = 262, stroke = 66, wedge = 196, sweep = 130;
const polar = (r, deg) => [cx + r * Math.cos((deg - 90) * Math.PI / 180), cy + r * Math.sin((deg - 90) * Math.PI / 180)];
function star(x, y, r, fill) {
  const [l, t, rt, b, X, Y] = [x - r, y - r, x + r, y + r, x, y].map((v) => v.toFixed(1));
  return `<path d="M${X} ${t} Q${X} ${Y} ${rt} ${Y} Q${X} ${Y} ${X} ${b} Q${X} ${Y} ${l} ${Y} Q${X} ${Y} ${X} ${t} Z" fill="${fill}"/>`;
}
function mark({ mono = false, sparkle = true } = {}) {
  const [ex, ey] = polar(wedge, sweep), [hx, hy] = polar(wedge - 8, sweep), [sx, sy] = polar(ring + 96, 48);
  return `
  ${mono ? '' : `<circle cx="${cx}" cy="${cy}" r="${ring}" fill="url(#glow)"/>`}
  <circle cx="${cx}" cy="${cy}" r="${ring}" fill="none" stroke="${paper}" stroke-width="${stroke}"/>
  <rect x="486" y="${cy - ring - 70}" width="52" height="80" fill="${paper}"/>
  <rect x="426" y="${cy - ring - 98}" width="172" height="58" rx="29" fill="${paper}"/>
  <path d="M${cx} ${cy} L${cx} ${cy - wedge} A${wedge} ${wedge} 0 0 1 ${ex.toFixed(1)} ${ey.toFixed(1)} Z" fill="${mono ? paper : 'url(#accent)'}"/>
  ${mono ? '' : `<line x1="${cx}" y1="${cy}" x2="${hx.toFixed(1)}" y2="${hy.toFixed(1)}" stroke="${paper}" stroke-width="32" stroke-linecap="round"/>`}
  <circle cx="${cx}" cy="${cy}" r="36" fill="${paper}"/>
  ${sparkle ? star(sx, sy, 74, mono ? paper : 'url(#spark)') + star(sx + 78, sy + 70, 30, mono ? paper : 'url(#spark)') : ''}`;
}

// « Clockifai Dev » : le chronomètre remonte au-dessus d'un badge DEV (évidé dans la silhouette).
function badge(mono) {
  const pill = '<rect x="336" y="772" width="352" height="144" rx="72"';
  const label = '<text x="516" y="846" text-anchor="middle" dominant-baseline="central" font-family="Geist" font-weight="700" font-size="104" letter-spacing="8"';
  return mono
    ? `<mask id="dev"><rect width="1024" height="1024" fill="#fff"/>${label} fill="#000">DEV</text></mask>${pill} fill="${paper}" mask="url(#dev)"/>`
    : `${pill} fill="url(#spark)"/>${label} fill="${ink[1]}">DEV</text>`;
}
const art = (dev, options = {}) => dev ? scaled(0.84, mark(options), -90) + badge(options.mono) : mark(options);

// Carré arrondi continu (superellipse), comme les icônes d'Apple, sur `size` centré en (512, 512).
function squircle(size, n = 5) {
  const a = size / 2, pts = [];
  for (let i = 0; i < 360; i++) {
    const t = i * Math.PI / 180, c = Math.cos(t), s = Math.sin(t);
    pts.push(`${(512 + a * Math.sign(c) * Math.abs(c) ** (2 / n)).toFixed(2)} ${(512 + a * Math.sign(s) * Math.abs(s) ** (2 / n)).toFixed(2)}`);
  }
  return `M${pts.join(' L')} Z`;
}

const scaled = (s, body, dy = 0) => `<g transform="translate(512 ${512 + dy}) scale(${s}) translate(-512 -512)">${body}</g>`;
const svg = (body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">${defs}${body}</svg>`;

// Compositions : `opaque` = sans transparence (exigé par l'App Store pour iOS).
const compositions = (dev) => ({
  // iOS, apple-touch-icon, web « maskable » : fond plein, le système découpe la forme.
  square: { svg: svg(`<rect width="1024" height="1024" fill="url(#bg)"/>${art(dev)}`), opaque: true },
  // Web, Android avant 8, logo de l'app : la forme est dans l'image.
  rounded: { svg: svg(`<path d="${squircle(1024)}" fill="url(#bg)"/>${art(dev)}`) },
  // Onglet du navigateur, menu latéral : dessin grossi, sans l'étincelle qui n'y serait qu'un point.
  favicon: { svg: svg(`<path d="${squircle(1024)}" fill="url(#bg)"/>${scaled(1.3, mark({ sparkle: false }))}`) },
  // macOS : grille d'Apple (forme de 824 sur 1024, ombre portée).
  macos: { svg: svg(`<path d="${squircle(824)}" fill="url(#bg)" filter="url(#shadow)"/>${scaled(824 / 1024, art(dev))}`) },
  // Android 8+ (icône adaptative sur 108 dp, dont 72 visibles) : fond, dessin, et silhouette des icônes à thème.
  background: { svg: svg('<rect width="1024" height="1024" fill="url(#bg)"/>'), opaque: true },
  foreground: { svg: svg(scaled(2 / 3, art(dev))) },
  monochrome: { svg: svg(scaled(2 / 3, art(dev, { mono: true }))) },
});
const icons = { false: compositions(false), true: compositions(true) };

async function render(page, name, size, dev = false) {
  const { svg: body, opaque } = icons[dev][name];
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<html><head>${font}</head><body style="margin:0">${body.replace('<svg ', `<svg width="${size}" height="${size}" style="display:block" `)}</body></html>`);
  await page.evaluate(() => document.fonts.ready);
  const png = await page.screenshot({ omitBackground: !opaque });
  // L'App Store refuse une icône iOS qui a une couche alpha : Chromium rend un fond opaque en RGB (type 2).
  if (opaque && png[25] !== 2) throw new Error(`${name} ${size} : PNG avec couche alpha`);
  return png;
}

// Fichiers produits : chemin sous app/ → [composition, taille en pixels, Dev]. Clockifai Dev : jeux d'icônes AppIconDev
// (ASSETCATALOG_COMPILER_APPICON_NAME de la configuration Debug) et source set debug d'Android.
function targets() {
  const out = {
    'web/favicon.png': ['favicon', 32],
    'web/icons/Icon-192.png': ['rounded', 192],
    'web/icons/Icon-512.png': ['rounded', 512],
    'web/icons/Icon-maskable-192.png': ['square', 192],
    'web/icons/Icon-maskable-512.png': ['square', 512],
    'web/icons/apple-touch-icon.png': ['square', 180],
  };
  for (const k of [1, 2, 3]) {
    const dir = k === 1 ? 'assets/logo' : `assets/logo/${k}.0x`;
    out[`${dir}/logo.png`] = ['rounded', 64 * k];
    out[`${dir}/logo_small.png`] = ['favicon', 32 * k];
  }
  for (const dev of [false, true]) {
    const set = dev ? 'AppIconDev.appiconset' : 'AppIcon.appiconset';
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    for (const img of JSON.parse(readFileSync(join(app, ios, 'Contents.json'))).images) {
      out[`ios/Runner/Assets.xcassets/${set}/${img.filename}`] = ['square', Math.round(parseFloat(img.size) * parseInt(img.scale)), dev];
    }
    for (const size of [16, 32, 64, 128, 256, 512, 1024]) {
      out[`macos/Runner/Assets.xcassets/${set}/app_icon_${size}.png`] = ['macos', size, dev];
    }
    const res = `android/app/src/${dev ? 'debug' : 'main'}/res`;
    for (const [density, k] of Object.entries({ mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 })) {
      out[`${res}/mipmap-${density}/ic_launcher.png`] = ['rounded', 48 * k, dev];
      for (const layer of dev ? ['foreground', 'monochrome'] : ['background', 'foreground', 'monochrome']) {
        out[`${res}/mipmap-${density}/ic_launcher_${layer}.png`] = [layer, 108 * k, dev];
      }
    }
  }
  return out;
}

const browser = await chromium.launch({ channel: 'chromium' }); // le Chromium complet, comme demo/record.mjs
const page = await browser.newPage();
const preview = process.argv.indexOf('--preview');
if (preview >= 0) {
  // Planche : chaque composition, l'icône adaptative d'Android découpée par le lanceur (cercle, carré arrondi, à
  // thème), puis les petites tailles ; la seconde ligne pour Clockifai Dev.
  const png = async (name, size, dev) => `data:image/png;base64,${(await render(page, name, size, dev)).toString('base64')}`;
  const launcher = (radius, back, front, tint = '') =>
    `<div style="position:relative;width:192px;height:192px;overflow:hidden;border-radius:${radius};${tint}">` +
    (back ? `<img src="${back}" style="position:absolute;left:-48px;top:-48px">` : '') +
    `<img src="${front}" style="position:absolute;left:-48px;top:-48px"></div>`;
  const cells = [];
  for (const dev of [false, true]) {
    const [bg, fg, mono] = [await png('background', 288, dev), await png('foreground', 288, dev), await png('monochrome', 288, dev)];
    for (const name of ['square', 'macos']) cells.push([`<img src="${await png(name, 192, dev)}" width="192">`, name]);
    cells.push([launcher('50%', bg, fg), 'android cercle'], [launcher('30%', bg, fg), 'android carré'],
      [launcher('50%', '', mono, 'background:#3A4A6B'), 'android à thème']);
    for (const size of [60, 29]) cells.push([`<img src="${await png('square', size, dev)}" width="${size}">`, `ios ${size}`]);
    if (!dev) for (const size of [32, 16]) cells.push([`<img src="${await png('favicon', size)}" width="${size}">`, `favicon ${size}`]);
  }
  await page.setViewportSize({ width: 1400, height: 600 });
  await page.setContent(`<html><body style="margin:24px;font:13px system-ui;display:flex;flex-wrap:wrap;gap:24px;align-items:flex-end;background:linear-gradient(90deg,#F4F5F7 50%,#2B2F36 50%)">${
    cells.map(([html, label]) => `<figure style="margin:0">${html}<figcaption>${label}</figcaption></figure>`).join('')}</body></html>`);
  await page.screenshot({ path: process.argv[preview + 1], fullPage: true });
} else {
  for (const [path, [name, size, dev]] of Object.entries(targets())) {
    mkdirSync(dirname(join(app, path)), { recursive: true });
    writeFileSync(join(app, path), await render(page, name, size, dev));
  }
  for (const platform of ['ios', 'macos']) {
    const sets = join(app, platform, 'Runner/Assets.xcassets');
    copyFileSync(join(sets, 'AppIcon.appiconset/Contents.json'), join(sets, 'AppIconDev.appiconset/Contents.json'));
  }
  writeFileSync(join(app, 'web/favicon.svg'), icons.false.favicon.svg + '\n');
  console.log(`${Object.keys(targets()).length + 1} icônes écrites`);
}
await browser.close();
