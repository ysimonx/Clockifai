// Incrustations de la vidéo de démo : bandeau explicatif, cartes titre, curseur visible.
// Injecté avant le chargement de chaque page (page.addInitScript) ; posé au-dessus du canvas Flutter.
(() => {
  if (window.__demo) return;
  const css = `
    #demo-root { position: fixed; inset: 0; pointer-events: none; z-index: 2147483647; font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    #demo-caption { position: absolute; left: 50%; bottom: var(--demo-bottom, 26px); transform: translate(-50%, 20px); opacity: 0;
      width: min(1000px, 92vw); box-sizing: border-box; background: rgba(15, 23, 42, 0.92); color: #f8fafc; border-radius: 16px;
      padding: 16px 22px 18px; box-shadow: 0 12px 40px rgba(0,0,0,.35); transition: opacity .35s ease, transform .35s ease; border-left: 6px solid #38bdf8; }
    #demo-caption.on { opacity: 1; transform: translate(-50%, 0); }
    #demo-caption .chap { font-size: 12px; letter-spacing: .12em; text-transform: uppercase; color: #7dd3fc; font-weight: 700; margin-bottom: 6px; }
    #demo-caption .chap .role { display: inline-block; margin-left: 10px; padding: 1px 8px; border-radius: 999px; background: #f97316; color: #fff; letter-spacing: .04em; }
    #demo-caption .title { font-size: 22px; font-weight: 700; line-height: 1.25; }
    #demo-caption .text { font-size: 17px; line-height: 1.45; margin-top: 4px; color: #e2e8f0; }
    #demo-card { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; opacity: 0; transition: opacity .5s ease;
      background: radial-gradient(circle at 30% 20%, #0ea5e9 0%, #0f172a 55%); color: #fff; text-align: center; }
    #demo-card.on { opacity: 1; }
    #demo-card h1 { font-size: 64px; margin: 0 0 12px; letter-spacing: -.02em; }
    #demo-card h2 { font-size: 26px; font-weight: 500; margin: 0 0 28px; color: #bae6fd; }
    #demo-card ul { list-style: none; padding: 0; margin: 0; font-size: 21px; line-height: 1.9; color: #e0f2fe; }
    #demo-card li::before { content: "✓  "; color: #4ade80; font-weight: 700; }
    #demo-cursor { position: absolute; width: 22px; height: 22px; margin: -11px 0 0 -11px; border-radius: 50%;
      background: rgba(249, 115, 22, .35); border: 2px solid #f97316; transition: transform .12s ease; left: -100px; top: -100px; }
    #demo-cursor.down { transform: scale(.7); background: rgba(249, 115, 22, .6); }
    .demo-ripple { position: absolute; width: 16px; height: 16px; margin: -8px 0 0 -8px; border-radius: 50%; border: 3px solid #f97316;
      animation: demo-ripple .6s ease-out forwards; }
    @keyframes demo-ripple { to { transform: scale(4); opacity: 0; } }
    #demo-code { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; opacity: 0; transition: opacity .5s ease;
      background: rgba(2, 6, 23, .94); }
    #demo-code.on { opacity: 1; }
    #demo-code .panel { width: min(1180px, 92vw); background: #0b1220; border: 1px solid #1e293b; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,.5); overflow: hidden; }
    #demo-code .bar { padding: 14px 20px; background: #111a2e; color: #7dd3fc; font-size: 15px; font-weight: 700; letter-spacing: .04em; }
    #demo-code .bar span { color: #94a3b8; font-weight: 500; margin-left: 10px; }
    #demo-code pre { margin: 0; padding: 22px 26px; font: 19px/1.65 "SF Mono", Menlo, Consolas, monospace; color: #e2e8f0; white-space: pre-wrap; }
    #demo-code .c { color: #4ade80; }
    #demo-code .k { color: #fbbf24; }
  `;
  function ensure() {
    if (document.getElementById('demo-root')) return;
    const style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
    const root = document.createElement('div');
    root.id = 'demo-root';
    root.innerHTML = '<div id="demo-card"></div><div id="demo-code"></div><div id="demo-caption"></div><div id="demo-cursor"></div>';
    document.body.appendChild(root);
    const cursor = root.querySelector('#demo-cursor');
    window.addEventListener('pointermove', (e) => { cursor.style.left = e.clientX + 'px'; cursor.style.top = e.clientY + 'px'; }, true);
    window.addEventListener('pointerdown', (e) => {
      cursor.classList.add('down');
      const r = document.createElement('div');
      r.className = 'demo-ripple';
      r.style.left = e.clientX + 'px';
      r.style.top = e.clientY + 'px';
      root.appendChild(r);
      setTimeout(() => r.remove(), 700);
    }, true);
    window.addEventListener('pointerup', () => cursor.classList.remove('down'), true);
  }
  const esc = (s) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
  window.__demo = {
    caption(chapter, title, text, role, bottom) {
      ensure();
      const el = document.getElementById('demo-caption');
      if (bottom) el.style.setProperty('--demo-bottom', bottom + 'px');
      el.innerHTML = `<div class="chap">${esc(chapter)}${role ? `<span class="role">${esc(role)}</span>` : ''}</div>`
        + `<div class="title">${esc(title)}</div>` + (text ? `<div class="text">${esc(text)}</div>` : '');
      el.classList.remove('on');
      void el.offsetWidth;
      el.classList.add('on');
    },
    hide() { ensure(); document.getElementById('demo-caption').classList.remove('on'); },
    card(title, subtitle, bullets) {
      ensure();
      const el = document.getElementById('demo-card');
      el.innerHTML = `<div><h1>${esc(title)}</h1><h2>${esc(subtitle)}</h2><ul>${(bullets || []).map((b) => `<li>${esc(b)}</li>`).join('')}</ul></div>`;
      el.classList.add('on');
    },
    hideCard() { ensure(); document.getElementById('demo-card').classList.remove('on'); },
    /** Panneau de code : lignes « CLÉ=valeur   # commentaire » ou « commande   # commentaire ». */
    code(title, subtitle, lines) {
      ensure();
      const fmt = (l) => {
        const i = l.indexOf('#');
        const head = i < 0 ? l : l.slice(0, i);
        const tail = i < 0 ? '' : `<span class="c">${esc(l.slice(i))}</span>`;
        const m = head.match(/^([A-Z0-9_]+)(=)(.*)$/);
        return (m ? `<span class="k">${esc(m[1])}</span>=${esc(m[3])}` : esc(head)) + tail;
      };
      const el = document.getElementById('demo-code');
      el.innerHTML = `<div class="panel"><div class="bar">${esc(title)}<span>${esc(subtitle || '')}</span></div><pre>${lines.map(fmt).join('\n')}</pre></div>`;
      el.classList.add('on');
    },
    hideCode() { ensure(); document.getElementById('demo-code').classList.remove('on'); },
    /**
     * Repère de début de scène : carré magenta dans le coin, retrouvé dans la vidéo puis effacé au montage
     * (encode() dans helpers.mjs). L'horloge ne suffit pas : la vidéo de Playwright s'étire quand l'app anime.
     */
    mark() {
      const m = document.createElement('div');
      m.style.cssText = 'position:fixed;right:2px;bottom:2px;width:12px;height:12px;background:#f0f;z-index:2147483647;pointer-events:none';
      document.documentElement.appendChild(m);
      setTimeout(() => m.remove(), 500);
    },
    ensure,
  };
  if (document.readyState !== 'loading') ensure();
  else document.addEventListener('DOMContentLoaded', ensure);
})();
