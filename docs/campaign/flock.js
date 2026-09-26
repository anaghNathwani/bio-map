// Murmuration: 3D boids with topological neighbours, projected to 2D, drawn as short strokes with motion trails.
// Deterministic (seeded) and stepped once per rendered frame, so a re-render is pixel-identical.
(function () {
  const CFG = window.CFG;
  const W = innerWidth, H = innerHeight;
  const cv = document.getElementById('cv'); cv.width = W; cv.height = H;
  const ctx = cv.getContext('2d');
  const rnd = (s => () => { s |= 0; s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296 })(CFG.seed);
  const N = CFG.n, P = new Float32Array(N * 3), V = new Float32Array(N * 3);
  for (let i = 0; i < N; i++) {
    const r = 200 * Math.cbrt(rnd()), a = rnd() * 6.283, b = Math.acos(2 * rnd() - 1);
    P[i * 3] = r * Math.sin(b) * Math.cos(a); P[i * 3 + 1] = r * Math.sin(b) * Math.sin(a) * .6; P[i * 3 + 2] = r * Math.cos(b);
    const s = 3, u = rnd() * 6.283; V[i * 3] = s * Math.cos(u); V[i * 3 + 1] = (rnd() - .5); V[i * 3 + 2] = s * Math.sin(u);
  }
  const PR = Object.assign({ coh: .004, ali: .09, sep: 16, sepR2: 196, att: .00075, attY: .0011, R: 380, speed: 3.1, k: 9, cell: 60 }, CFG.p || {});
  const CELL = PR.cell, G = 24, HEAD = new Int32Array(G * G * G), NEXT = new Int32Array(N);
  const cidx = (x) => Math.min(G - 1, Math.max(0, Math.floor(x / CELL + G / 2)));
  let simT = 0;
  function attractor(t) {
    const lift = CFG.lift ? CFG.lift(t) : 0;
    return [Math.sin(t * .23) * 260 + Math.sin(t * .11) * 120, Math.sin(t * .31 + 1) * 90 - lift, Math.cos(t * .19) * 260 + Math.cos(t * .07) * 100];
  }
  function step() {
    HEAD.fill(-1);
    for (let i = 0; i < N; i++) {
      const c = (cidx(P[i * 3]) * G + cidx(P[i * 3 + 1])) * G + cidx(P[i * 3 + 2]);
      NEXT[i] = HEAD[c]; HEAD[c] = i;
    }
    const A = attractor(simT);
    const NV = new Float32Array(N * 3);
    for (let i = 0; i < N; i++) {
      const x = P[i * 3], y = P[i * 3 + 1], z = P[i * 3 + 2];
      const cx = cidx(x), cy = cidx(y), cz = cidx(z);
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
      const r = Math.hypot(x, y * 1.4, z); if (r > PR.R) { const k = (r - PR.R) * .0009; ax -= x * k; ay -= y * k; az -= z * k }
      let ux = V[i * 3] + ax, uy = V[i * 3 + 1] + ay, uz = V[i * 3 + 2] + az;
      const sp = Math.hypot(ux, uy, uz), tgt = PR.speed; const f = (sp + (tgt - sp) * .12) / (sp || 1);
      NV[i * 3] = ux * f; NV[i * 3 + 1] = uy * f; NV[i * 3 + 2] = uz * f;
    }
    for (let i = 0; i < N * 3; i++) { V[i] = NV[i]; P[i] += V[i]; }
    simT += 1 / 30;
  }
  for (let k = 0; k < (CFG.warm || 420); k++) step();
  const ease = x => 1 - Math.pow(1 - Math.min(1, Math.max(0, x)), 3);
  window.ease = ease;
  let lastFrame = -1;

  let camC = null, camR = 0;
  function draw(t, still) {
    const cam = CFG.cam ? CFG.cam(t) : { yaw: t * .05, off: 0 };
    // Frame the flock: track its centroid and spread (smoothed) so it is always centred and the same apparent size.
    let mx = 0, my = 0, mz = 0;
    for (let i = 0; i < N; i++) { mx += P[i * 3]; my += P[i * 3 + 1]; mz += P[i * 3 + 2]; }
    mx /= N; my /= N; mz /= N;
    let r2 = 0; for (let i = 0; i < N; i++) { const a = P[i * 3] - mx, b = P[i * 3 + 1] - my, c = P[i * 3 + 2] - mz; r2 += a * a + b * b + c * c }
    const rr = Math.sqrt(r2 / N);
    if (!camC) { camC = [mx, my, mz]; camR = rr } else { const k = still ? 1 : .04; camC = camC.map((v, q) => v + ([mx, my, mz][q] - v) * k); camR += (rr - camR) * k }
    const S = Math.min(W, H), f = 1100, cd = 1000;
    const k = (CFG.frame || .26) * S / camR;
    const cy0 = H * (CFG.cy || .40) + (cam.off || 0) * H, cx0 = W / 2;
    ctx.globalCompositeOperation = 'source-over'; ctx.globalAlpha = 1;
    if (still) { ctx.fillStyle = CFG.bg; ctx.fillRect(0, 0, W, H) } else { ctx.fillStyle = CFG.bgFade; ctx.fillRect(0, 0, W, H) }
    const yaw = cam.yaw, cs = Math.cos(yaw), sn = Math.sin(yaw);
    const vis = CFG.visible ? Math.floor(CFG.visible(t)) : N;
    const buckets = [[], [], []];
    for (let i = 0; i < vis; i++) {
      const x = P[i * 3] - camC[0], y = P[i * 3 + 1] - camC[1], z = P[i * 3 + 2] - camC[2];
      const rx = x * cs - z * sn, rz = x * sn + z * cs;
      const s = f / (f + rz + cd); if (s <= 0) continue;
      const vx = V[i * 3] * cs - V[i * 3 + 2] * sn, vy = V[i * 3 + 1];
      const X = cx0 + rx * s * k, Y = cy0 + y * s * k * 1.05;
      const len = (CFG.len || .014) * S * s, m = Math.hypot(vx, vy) || 1;
      const b = s > 1.06 ? 2 : s > .97 ? 1 : 0;
      buckets[b].push(X, Y, X - vx / m * len, Y - vy / m * len, s);
    }
    ctx.lineCap = 'round';
    ctx.globalCompositeOperation = CFG.blend || 'lighter';
    buckets.forEach((bk, bi) => {
      ctx.strokeStyle = CFG.fg; ctx.globalAlpha = CFG.alpha[bi]; ctx.lineWidth = CFG.lw[bi] * (S / 900);
      ctx.beginPath();
      for (let q = 0; q < bk.length; q += 5) { ctx.moveTo(bk[q], bk[q + 1]); ctx.lineTo(bk[q + 2], bk[q + 3]) }
      ctx.stroke();
    });
    ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
  }
  window.flock = { step, draw, get simT() { return simT } };

  // text lines
  const lines = CFG.lines || [];
  const els = lines.map(l => { const d = document.createElement('div'); d.className = 'line ' + (l.cls || ''); d.innerHTML = l.html; document.getElementById('txt').appendChild(d); return d });
  window.render = function (t) {
    if (CFG.still) { for (let k = 0; k < (CFG.stillSteps || 0); k++) step(); draw(CFG.stillT || 0, !CFG.trails); return }
    const target = Math.round(t * 30);
    if (target - lastFrame > 6) camC = null; // big jump (a test still): re-frame instantly
    while (lastFrame < target) { step(); lastFrame++; }
    draw(t, false);
    lines.forEach((l, i) => {
      const inn = ease((t - l.a) / (l.fi || 1.1)), out = ease((t - l.b) / (l.fo || .8));
      const o = inn * (1 - out); els[i].style.opacity = o;
      els[i].style.filter = `blur(${(1 - inn) * 10 + out * 8}px)`;
      els[i].style.transform = `translateY(${(1 - inn) * 14 - out * 8}px)`;
    });
    if (CFG.end) CFG.end(t, ease);
  };
  window.render(0);
})();
