// Guide utilisateur de Clockifai : liens vers les scènes des vidéos de démonstration.
//
// Le tournage (demo/record.mjs) écrit, à côté de chaque vidéo, videos/<nom>.chapters.json :
//   [{"scene": "feuille de temps", "start": 83.4}, …]
// Les liens <a class="scene" data-video="<nom>" data-scene="<scène>"> reçoivent ici leur horodatage :
// retourner une vidéo met le guide à jour sans le modifier. Sans vidéo ni chapitres, le guide reste lisible.
(() => {
  'use strict';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const chaptersCache = new Map();
  const availableCache = new Map();

  /** Chapitres d'une vidéo, ou null s'ils ne sont pas publiés. */
  function chapters(name) {
    if (!chaptersCache.has(name)) {
      chaptersCache.set(name, fetch(`videos/${encodeURIComponent(name)}.chapters.json`, { cache: 'no-cache' })
        .then((r) => (r.ok ? r.json() : null))
        .then((list) => (Array.isArray(list) ? list.filter((c) => c && typeof c.scene === 'string' && Number.isFinite(c.start)) : null))
        .catch(() => null));
    }
    return chaptersCache.get(name);
  }

  /** La vidéo est-elle publiée ? (pour les liens vers une vidéo qui n'est pas sur la page) */
  function available(name) {
    if (!availableCache.has(name)) {
      availableCache.set(name, fetch(`videos/${encodeURIComponent(name)}.mp4`, { method: 'HEAD' })
        .then((r) => r.ok)
        .catch(() => false));
    }
    return availableCache.get(name);
  }

  function formatTime(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const ss = String(s % 60).padStart(2, '0');
    return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
  }

  const capitalize = (text) => text.charAt(0).toUpperCase() + text.slice(1);

  function playerFor(name) {
    const video = document.querySelector(`video[data-video="${CSS.escape(name)}"]`);
    return video && !video.closest('.is-missing') ? video : null;
  }

  function seek(video, start) {
    const figure = video.closest('figure') || video;
    figure.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'start' });
    const go = () => {
      if (Number.isFinite(start)) video.currentTime = start;
      video.play().catch(() => {});
    };
    if (video.readyState >= 1) go();
    else video.addEventListener('loadedmetadata', go, { once: true });
  }

  function setTime(link, start) {
    link.dataset.start = String(start);
    link.href = `videos/${encodeURIComponent(link.dataset.video)}.mp4#t=${Math.floor(start)}`;
    let badge = link.querySelector('.scene-time');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'scene-time';
      link.append(badge);
    }
    badge.textContent = formatTime(start);
    badge.setAttribute('aria-label', `à ${formatTime(start).replace(':', ' min ')} s`);
  }

  function markUnavailable(link) {
    link.classList.add('is-unavailable');
    link.removeAttribute('href');
    link.setAttribute('aria-disabled', 'true');
    link.title = 'Vidéo pas encore publiée sur cette installation';
  }

  // ------------------------------------------------------------------ lecteurs

  for (const video of document.querySelectorAll('video[data-video]')) {
    const name = video.dataset.video;
    const figure = video.closest('figure');
    const missing = () => {
      if (!figure || figure.classList.contains('is-missing')) return;
      figure.classList.add('is-missing');
      for (const link of document.querySelectorAll(`a.scene[data-video="${CSS.escape(name)}"]`)) markUnavailable(link);
    };
    video.addEventListener('error', missing);
    if (video.error || video.networkState === HTMLMediaElement.NETWORK_NO_SOURCE) missing();

    chapters(name).then((list) => {
      if (!list || !figure) return;
      let ol = figure.querySelector('ol.chapters');
      if (!ol) {
        ol = document.createElement('ol');
        ol.className = 'chapters';
        figure.append(ol);
      }
      // Scènes tournées mais absentes de la liste écrite : ajoutées avec leur nom brut.
      const listed = new Set([...ol.querySelectorAll('a.scene')].map((a) => a.dataset.scene));
      for (const c of list) {
        if (listed.has(c.scene)) continue;
        const li = document.createElement('li');
        const a = document.createElement('a');
        a.className = 'scene';
        a.dataset.video = name;
        a.dataset.scene = c.scene;
        a.textContent = capitalize(c.scene);
        li.append(a);
        ol.append(li);
        wire(a);
      }

      // Chapitre en cours de lecture
      const links = [...ol.querySelectorAll('a.scene')];
      const sorted = list.slice().sort((a, b) => a.start - b.start);
      video.addEventListener('timeupdate', () => {
        const t = video.currentTime + 0.25;
        const current = sorted.filter((c) => c.start <= t).pop();
        for (const a of links) {
          if (current && a.dataset.scene === current.scene) a.setAttribute('aria-current', 'true');
          else a.removeAttribute('aria-current');
        }
      });
    });
  }

  // ------------------------------------------------------------------ liens vers les scènes

  function wire(link) {
    const name = link.dataset.video;
    const onPage = Boolean(document.querySelector(`video[data-video="${CSS.escape(name)}"]`));
    if (!onPage) {
      link.target = '_blank';
      link.rel = 'noopener';
      link.title = 'Ouvre la vidéo dans un nouvel onglet';
    }

    chapters(name).then((list) => {
      const chapter = list && list.find((c) => c.scene === link.dataset.scene);
      if (chapter) setTime(link, chapter.start);
      else if (!onPage) available(name).then((ok) => { if (!ok) markUnavailable(link); });
    });

    link.addEventListener('click', (event) => {
      if (link.classList.contains('is-unavailable')) {
        event.preventDefault();
        return;
      }
      const video = playerFor(name);
      if (!video) return; // vidéo d'une autre page : le lien ouvre le fichier à l'instant de la scène
      event.preventDefault();
      seek(video, Number.parseFloat(link.dataset.start));
    });
  }

  for (const link of document.querySelectorAll('a.scene[data-video][data-scene]')) wire(link);
})();
