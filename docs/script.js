(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const els = document.querySelectorAll('.reveal, .squiggle');
  const show = (el) => el.classList.add(el.classList.contains('squiggle') ? 'drawn' : 'in');

  if (reduce || !('IntersectionObserver' in window)) {
    els.forEach(show);
  } else {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) { show(e.target); io.unobserve(e.target); }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
    els.forEach((el) => io.observe(el));
  }

  // An explicit language choice disables the first-visit redirect on the English page.
  document.querySelectorAll('.lang a[hreflang]').forEach((a) => a.addEventListener('click', () => {
    try { localStorage.setItem('lang', a.hreflang); } catch {}
  }));

  const root = document.documentElement;
  const nav = document.querySelector('.nav');
  const scenes = [...document.querySelectorAll('[data-scene]')];
  const darkScene = document.querySelector('.dark-scene');
  const themeColor = document.querySelector('meta[name="theme-color"]');
  const clamp01 = (x) => Math.min(Math.max(x, 0), 1);
  const smooth = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };
  const written = new WeakMap();
  let dark = -1;
  let twinsMade = false;

  // Each screenshot gets its dark capture stacked on top. It stays hidden until it has loaded,
  // so a missing dark file simply leaves the light image showing.
  const makeTwins = () => {
    twinsMade = true;
    document.querySelectorAll('.shot > img').forEach((img) => {
      const twin = new Image();
      twin.className = 'dark-twin';
      twin.alt = '';
      twin.decoding = 'async';
      twin.setAttribute('aria-hidden', 'true');
      twin.onload = () => twin.classList.add('ready');
      twin.onerror = () => twin.remove();
      twin.src = img.getAttribute('src').replace('assets/', 'assets/dark/');
      img.after(twin);
    });
  };

  const setDark = (d) => {
    if (d === dark) return;
    const flipped = dark < 0 || (d > 0.5) !== (dark > 0.5);
    dark = d;
    root.style.setProperty('--dark', d);
    if (flipped) {
      root.style.colorScheme = d > 0.5 ? 'dark' : 'light';
      themeColor?.setAttribute('content', d > 0.5 ? '#000000' : '#f7f7fb');
    }
  };

  // Progress of a scene: 0 when its top reaches data-start × viewport height, 1 when its bottom
  // reaches the viewport bottom (for a pinned scene: when the pin releases).
  const progress = (r, start, vh) =>
    clamp01((start * vh - r.top) / Math.max(r.height - vh + start * vh, vh * 0.4));

  const frame = () => {
    ticking = false;
    const vh = innerHeight;
    const rects = scenes.map((el) => el.getBoundingClientRect()); // all reads before any write
    nav.classList.toggle('scrolled', scrollY > 8);
    scenes.forEach((el, i) => {
      const p = progress(rects[i], +(el.dataset.start || 0), vh);
      const v = p.toFixed(4);
      if (written.get(el) !== v) { written.set(el, v); el.style.setProperty('--p', v); }
      if (el !== darkScene) return;
      if (!twinsMade && rects[i].top < 2 * vh) makeTwins();
      // The page darkens while the device settles; reduced motion switches in one step.
      setDark(reduce ? (p >= 0.4 ? 1 : 0) : Math.round(smooth(0.12, 0.58, p) * 1000) / 1000);
    });
  };

  let ticking = false;
  const schedule = () => { if (!ticking) { ticking = true; requestAnimationFrame(frame); } };
  addEventListener('scroll', schedule, { passive: true });
  addEventListener('resize', schedule, { passive: true });
  frame();
})();
