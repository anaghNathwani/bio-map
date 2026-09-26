// Murmuration: 3D boids with topological neighbours, projected to 2D, drawn as short strokes.
// Deterministic (seeded) and stepped once per rendered frame, so a re-render is pixel-identical.
// At the end of the film the birds drift together and settle into the BirdMap mark (CFG.form).
(function () {
  const CFG = window.CFG;
  const W = innerWidth, H = innerHeight, S = Math.min(W, H);
  const cv = document.getElementById('cv'); cv.width = W; cv.height = H;
  const ctx = cv.getContext('2d');
  const rnd = (s => () => { s |= 0; s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296 })(CFG.seed);
  const N = CFG.n, P = new Float32Array(N * 3), V = new Float32Array(N * 3);
  const PR = Object.assign({ coh: .0007, ali: .10, sep: 26, sepR2: 1100, att: .0016, attY: .0020, R: 900, speed: 1.9, k: 7, cell: 70, spread: 420 }, CFG.p || {});
  for (let i = 0; i < N; i++) {
    const r = 320 * Math.cbrt(rnd()), a = rnd() * 6.283, b = Math.acos(2 * rnd() - 1);
    P[i * 3] = r * Math.sin(b) * Math.cos(a) * 1.5; P[i * 3 + 1] = r * Math.sin(b) * Math.sin(a) * .7; P[i * 3 + 2] = r * Math.cos(b);
    const s = PR.speed, u = rnd() * 6.283; V[i * 3] = s * Math.cos(u); V[i * 3 + 1] = (rnd() - .5) * .3; V[i * 3 + 2] = s * Math.sin(u);
  }
  const CELL = PR.cell, G = 32, HEAD = new Int32Array(G * G * G), NEXT = new Int32Array(N);
  const cidx = x => Math.min(G - 1, Math.max(0, Math.floor(x / CELL + G / 2)));
  let simT = 0;
  // Two slow, wide attractors keep the flock stretched across the frame instead of balled up.
  function attractor(t) {
    const lift = CFG.lift ? CFG.lift(t) : 0;
    return [Math.sin(t * .12) * PR.spread + Math.sin(t * .05) * 160, Math.sin(t * .17 + 1) * 110 - lift, Math.cos(t * .09) * PR.spread * .8];
  }
  function step() {
    HEAD.fill(-1);
    for (let i = 0; i < N; i++) { const c = (cidx(P[i * 3]) * G + cidx(P[i * 3 + 1])) * G + cidx(P[i * 3 + 2]); NEXT[i] = HEAD[c]; HEAD[c] = i; }
    const A = attractor(simT), NV = new Float32Array(N * 3);
    for (let i = 0; i < N; i++) {
      const x = P[i * 3], y = P[i * 3 + 1], z = P[i * 3 + 2], cx = cidx(x), cy = cidx(y), cz = cidx(z);
      let n = 0, sx = 0, sy = 0, sz = 0, vx = 0, vy = 0, vz = 0, px = 0, py = 0, pz = 0;
      for (let dx = -1; dx <= 1 && n < PR.k; dx++) for (let dy = -1; dy <= 1 && n < PR.k; dy++) for (let dz = -1; dz <= 1 && n < PR.k; dz++) {
        const X = cx + dx, Y = cy + dy, Z = cz + dz;
        if (X < 0 || Y < 0 || Z < 0 || X >= G || Y >= G || Z >= G) continue;
        for (let j = HEAD[(X * G + Y) * G + Z]; j >= 0 && n < PR.k; j = NEXT[j]) {
          if (j === i) continue;
          const ex = P[j * 3] - x, ey = P[j * 3 + 1] - y, ez = P[j * 3 + 2] - z, d2 = ex * ex + ey * ey + ez * ez;
          if (d2 > CELL * CELL) continue;
          n++; px += ex; py += ey; pz += ez; vx += V[j * 3]; vy += V[j * 3 + 1]; vz += V[j * 3 + 2];
          if (d2 < PR.sepR2) { const w = 1 / (d2 + 1); sx -= ex * w; sy -= ey * w; sz -= ez * w; }
        }
      }
      let ax = 0, ay = 0, az = 0;
      if (n) {
        ax += px / n * PR.coh + (vx / n - V[i * 3]) * PR.ali + sx * PR.sep;
        ay += py / n * PR.coh + (vy / n - V[i * 3 + 1]) * PR.ali + sy * PR.sep;
        az += pz / n * PR.coh + (vz / n - V[i * 3 + 2]) * PR.ali + sz * PR.sep;
      }
      ax += (A[0] - x) * PR.att; ay += (A[1] - y) * PR.attY; az += (A[2] - z) * PR.att;
      const r = Math.hypot(x, y * 1.4, z); if (r > PR.R) { const k = (r - PR.R) * .0006; ax -= x * k; ay -= y * k; az -= z * k }
      const lim = .05;                       // never let a bird change velocity abruptly: no bursts, no "fireworks"
      const am = Math.hypot(ax, ay, az); if (am > lim) { ax *= lim / am; ay *= lim / am; az *= lim / am }
      const ux = V[i * 3] + ax, uy = V[i * 3 + 1] + ay, uz = V[i * 3 + 2] + az;
      const sp = Math.hypot(ux, uy, uz), f = (sp + (PR.speed - sp) * .08) / (sp || 1);
      NV[i * 3] = ux * f; NV[i * 3 + 1] = uy * f; NV[i * 3 + 2] = uz * f;
    }
    for (let i = 0; i < N * 3; i++) { V[i] = NV[i]; P[i] += V[i]; }
    simT += 1 / 30;
  }
  for (let k = 0; k < (CFG.warm || 500); k++) step();
  const clamp = x => Math.min(1, Math.max(0, x));
  const ease = x => 1 - Math.pow(1 - clamp(x), 3);
  const inOut = x => { x = clamp(x); return x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2 };
  window.ease = ease;

  // ---- the BirdMap mark, as N dots ---------------------------------------------------------------------------
  const F = CFG.form || null;
  let targets = null, assign = null, order = null;
  function buildTargets() {
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path'); path.setAttribute('d', CFG.logoPath);
    const L = path.getTotalLength(), M = Math.min(N, CFG.logoDots || 2400), eyeN = 46, out = [];
    const u = F.size / 40, cx = F.cx * W, cy = F.cy * H;
    for (let q = 0; q < M - eyeN; q++) {
      const p = path.getPointAtLength((q + .5) / (M - eyeN) * L), sw = CFG.logoSw || 2.2;
      out.push([cx + (p.x + (rnd() - .5) * sw - 25.5) * u, cy + (p.y + (rnd() - .5) * sw - 25) * u]);
    }
    for (let q = 0; q < eyeN; q++) { const a = rnd() * 6.283, r = 1.5 * Math.sqrt(rnd()); out.push([cx + (33.5 + r * Math.cos(a) - 25.5) * u, cy + (14.5 + r * Math.sin(a) - 25) * u]) }
    return out;
  }
  const stagger = new Float32Array(N); for (let i = 0; i < N; i++) stagger[i] = rnd() * .32;

  let camC = null, camR = 0, frozen = null;
  function project(i, cam, k, cx0, cy0, cs, sn) {
    const x = P[i * 3] - cam.c[0], y = P[i * 3 + 1] - cam.c[1], z = P[i * 3 + 2] - cam.c[2];
    const rx = x * cs - z * sn, rz = x * sn + z * cs, f = 1100, cd = 1000, s = f / (f + rz + cd);
    return [cx0 + rx * s * k, cy0 + y * s * k * 1.05, s, V[i * 3] * cs - V[i * 3 + 2] * sn, V[i * 3 + 1]];
  }

  function draw(t, still, tf) {
    const cam0 = CFG.cam ? CFG.cam(t) : { yaw: t * .02, off: 0 };
    let mx = 0, my = 0, mz = 0;
    for (let i = 0; i < N; i++) { mx += P[i * 3]; my += P[i * 3 + 1]; mz += P[i * 3 + 2]; }
    mx /= N; my /= N; mz /= N;
    // Frame on the *typical* bird (60th percentile distance), so a few strays don't shrink the flock on screen.
    const dd = new Float32Array(N); for (let i = 0; i < N; i++) { const a = P[i * 3] - mx, b = P[i * 3 + 1] - my, c = P[i * 3 + 2] - mz; dd[i] = Math.sqrt(a * a + b * b + c * c) }
    dd.sort(); const rr = dd[Math.floor(N * .6)];
    if (!camC) { camC = [mx, my, mz]; camR = rr } else if (!frozen) { const k = still ? 1 : .025; camC = camC.map((v, q) => v + ([mx, my, mz][q] - v) * k); camR += (rr - camR) * (still ? 1 : .006) }
    if (tf > 0 && !frozen) frozen = { c: camC.slice(), r: camR };   // hold the camera still while the mark forms
    const cam = frozen || { c: camC, r: camR };
    const k = (CFG.frame || .40) * S / cam.r;
    const cy0 = H * (CFG.cy || .40) + (cam0.off || 0) * H, cx0 = W / 2, yaw = cam0.yaw, cs = Math.cos(yaw), sn = Math.sin(yaw);
    const reveal = CFG.reveal ? CFG.reveal(t) : 1;
    ctx.globalCompositeOperation = 'source-over'; ctx.globalAlpha = 1;
    const fadeA = still ? 1 : (tf > .5 ? .55 : CFG.trail || .24);
    ctx.fillStyle = CFG.bg; if (!still) { ctx.globalAlpha = fadeA; }
    ctx.fillRect(0, 0, W, H); ctx.globalAlpha = 1;

    // decide who becomes a dot of the mark (once, when forming starts)
    if (F && tf > 0 && !assign) {
      targets = buildTargets();
      const pos = []; for (let i = 0; i < N; i++) { const p = project(i, cam, k, cx0, cy0, cs, sn); pos.push([i, Math.atan2(p[1] - cy0, p[0] - cx0)]) }
      pos.sort((a, b) => a[1] - b[1]);
      const tg = targets.map((p, q) => [q, Math.atan2(p[1] - F.cy * H, p[0] - F.cx * W)]).sort((a, b) => a[1] - b[1]);
      assign = new Int32Array(N).fill(-1);
      const M = tg.length;
      for (let q = 0; q < M; q++) assign[pos[Math.floor(q * N / M)][0]] = tg[q][0];
    }
    const buckets = [[], [], []], dots = [], back = [[], [], []];
    for (let i = 0; i < N; i++) {
      const p = project(i, cam, k, cx0, cy0, cs, sn); if (p[2] <= 0) continue;
      const len = (CFG.len || .010) * S * p[2], m = Math.hypot(p[3], p[4]) || 1;
      const b = p[2] > 1.06 ? 2 : p[2] > .97 ? 1 : 0;
      if (tf > 0 && assign && assign[i] >= 0) {
        const e = inOut((tf - stagger[i]) / (1 - .32)), tp = targets[assign[i]];
        const wob = (1 - e) * 22 * Math.sin(t * 1.3 + i), br = e >= 1 ? 1.1 * Math.sin(t * .9 + i * .37) : 0;
        const X = p[0] * (1 - e) + tp[0] * e + wob + br, Y = p[1] * (1 - e) + tp[1] * e + wob * .6 + br;
        if (e > .7) dots.push(X, Y); else buckets[b].push(X, Y, X - p[3] / m * len * (1 - e), Y - p[4] / m * len * (1 - e));
      } else {
        (tf > 0 ? back : buckets)[b].push(p[0], p[1], p[0] - p[3] / m * len, p[1] - p[4] / m * len);
      }
    }
    ctx.lineCap = 'round'; ctx.globalCompositeOperation = CFG.blend || 'lighter'; ctx.strokeStyle = CFG.fg;
    const stroke = (bk, alpha, lw) => { if (!bk.length || alpha <= .01) return; ctx.globalAlpha = alpha; ctx.lineWidth = lw * (S / 900); ctx.beginPath(); for (let q = 0; q < bk.length; q += 4) { ctx.moveTo(bk[q], bk[q + 1]); ctx.lineTo(bk[q + 2], bk[q + 3]) } ctx.stroke() };
    buckets.forEach((bk, bi) => stroke(bk, CFG.alpha[bi] * reveal, CFG.lw[bi]));
    const bgFade = 1 - ease(tf * 1.4);
    back.forEach((bk, bi) => stroke(bk, CFG.alpha[bi] * reveal * bgFade, CFG.lw[bi]));
    if (dots.length) {   // the mark: crisp dots
      ctx.globalAlpha = .95; ctx.fillStyle = CFG.fg; ctx.globalCompositeOperation = 'source-over';
      const r = (CFG.dot || 1.7) * (S / 1080);
      ctx.beginPath(); for (let q = 0; q < dots.length; q += 2) { ctx.moveTo(dots[q] + r, dots[q + 1]); ctx.arc(dots[q], dots[q + 1], r, 0, 6.2832) } ctx.fill();
    }
    ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
  }
  window.flock = { step, draw, get simT() { return simT } };

  // ---- text lines ---------------------------------------------------------------------------------------------
  const lines = CFG.lines || [];
  const els = lines.map(l => { const d = document.createElement('div'); d.className = 'line ' + (l.cls || ''); d.innerHTML = l.html; document.getElementById('txt').appendChild(d); return d });
  let lastFrame = -1;
  const formProg = t => F ? clamp((t - F.a) / F.dur) : 0;
  window.render = function (t) {
    if (CFG.still) { for (let q = 0; q < (CFG.stillSteps || 0); q++) step(); draw(CFG.stillT || 0, !CFG.trails, CFG.stillForm || 0); return }
    const target = Math.round(t * 30);
    if (target - lastFrame > 6) { camC = null; frozen = null; assign = null }   // big jump (a test still): re-frame instantly
    while (lastFrame < target) { step(); lastFrame++; }
    draw(t, false, formProg(t));
    lines.forEach((l, i) => {
      const inn = ease((t - l.a) / (l.fi || 1.4)), out = ease((t - l.b) / (l.fo || 1.2));
      const o = inn * (1 - out); els[i].style.opacity = o;
      els[i].style.filter = `blur(${(1 - inn) * 8 + out * 6}px)`;
      els[i].style.transform = `translateY(${(1 - inn) * 10 - out * 6}px)`;
    });
    if (CFG.end) CFG.end(t, ease);
  };
  window.render(0);
})();
