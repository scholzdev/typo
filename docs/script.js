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

  const nav = document.querySelector('.nav');
  const shot = document.querySelector('.hero-shot img');
  let ticking = false;
  const onScroll = () => {
    ticking = false;
    nav.classList.toggle('scrolled', scrollY > 8);
    if (reduce || !shot) return;
    // Hero screenshot tilts flat as it scrolls toward the middle of the viewport.
    const r = shot.getBoundingClientRect();
    const p = Math.min(Math.max(1 - (r.top - innerHeight * 0.2) / (innerHeight * 0.6), 0), 1);
    shot.style.setProperty('--tilt', `${14 * (1 - p)}deg`);
    shot.style.setProperty('--scale', `${0.94 + 0.06 * p}`);
  };
  addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(onScroll); } }, { passive: true });
  onScroll();
})();
