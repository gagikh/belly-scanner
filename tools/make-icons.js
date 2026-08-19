/*
 * Draws the app icon and Play Store art, and writes the Android density set.
 *
 *   npm install
 *   node tools/make-icons.js
 *
 * Output lands in android-assets/, which build-apk.ps1 copies into the
 * generated Android project. Re-run this if you change the artwork.
 */
const fs = require("fs");
const path = require("path");
// Dependencies are dev-only; the app itself needs none. A bare "Cannot find
// module" stack trace isn't a useful thing to hand someone, so say what to do.
function need(mod) {
  try { return require(mod); }
  catch (e) {
    if (/native binding/i.test(e.message)) {
      // npm sometimes skips the platform-specific binary of a native package
      console.error(`\n${mod} installed but its native binary is missing.`);
      console.error("This is a known npm bug with optional dependencies. Fix:\n");
      console.error("    rm -rf node_modules package-lock.json");
      console.error("    npm install --include=optional\n");
    } else {
      console.error(`\nMissing dependency: ${mod}`);
      console.error("Run this once, from the project folder:\n\n    npm install\n");
    }
    process.exit(1);
  }
}
const { createCanvas } = need("@napi-rs/canvas");

const OUT = path.join(__dirname, "..", "android-assets");

const NAVY = "#0b1220";
const NAVY_LIT = "#17304d";

// The speckle needs randomness to look like ultrasound, but Math.random() would
// make every run emit byte-different PNGs — 17 binary files churning in git each
// time the script runs, for artwork that hasn't changed. A seeded generator,
// reset before each drawing, makes the output reproducible: re-running produces
// identical bytes and `git status` stays clean unless the art actually changed.
const SEED = 0x7ea5e;
let _rngState = SEED;
function resetRandom() { _rngState = SEED; }
function rnd() {
  // mulberry32
  _rngState = (_rngState + 0x6D2B79F5) | 0;
  let t = _rngState;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// ---------------------------------------------------------------- artwork ---

// The ultrasound fan, drawn into a unit box: x,y in 0..1 of the given size.
function drawFan(c, S, alpha) {
  const ax = S * 0.5, ay = -S * 0.30;          // apex above the frame
  const a0 = Math.PI / 2 - 0.62, a1 = Math.PI / 2 + 0.62;
  const rIn = S * 0.46, rOut = S * 1.18;

  c.save();
  c.beginPath();
  c.moveTo(ax + Math.cos(a0) * rIn, ay + Math.sin(a0) * rIn);
  c.arc(ax, ay, rIn, a0, a1);
  c.arc(ax, ay, rOut, a1, a0, true);
  c.closePath();
  c.clip();

  const g = c.createLinearGradient(0, S * 0.1, 0, S);
  g.addColorStop(0, `rgba(226,234,244,${0.95 * alpha})`);
  g.addColorStop(0.55, `rgba(168,182,200,${0.85 * alpha})`);
  g.addColorStop(1, `rgba(96,112,134,${0.6 * alpha})`);
  c.fillStyle = g;
  c.fillRect(0, 0, S, S);

  // speckle, so it reads as ultrasound rather than a plain wedge
  c.globalAlpha = 0.16 * alpha;
  c.fillStyle = "#0b1220";
  const step = Math.max(2, Math.round(S / 90));
  for (let y = 0; y < S; y += step) {
    for (let x = 0; x < S; x += step) {
      if (rnd() > 0.55) c.fillRect(x, y, step, step);
    }
  }
  c.globalAlpha = 1;
  c.restore();
}

// One fat cartoon worm, curled, facing left.
function drawWorm(c, cx, cy, len, thick) {
  const pts = [];
  const n = 7;
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    pts.push({
      x: cx - len * 0.5 + len * t,
      y: cy + Math.sin(t * Math.PI * 1.15) * len * 0.16
    });
  }

  // shadow
  c.save();
  c.fillStyle = "rgba(8,12,20,0.35)";
  pts.forEach((p, i) => {
    const r = thick * (1 - Math.pow(i / n, 1.6)) * 0.5 + thick * 0.5;
    c.beginPath(); c.arc(p.x + thick * 0.12, p.y + thick * 0.2, r, 0, 7); c.fill();
  });
  c.restore();

  // body segments, head last so it sits on top
  for (let i = pts.length - 1; i >= 0; i--) {
    const p = pts[i];
    const taper = 1 - Math.pow(i / n, 1.7) * 0.55;
    const r = thick * taper * 0.62;
    c.fillStyle = i === 0 ? "#e8eef7" : "#cfd8e6";
    c.beginPath(); c.arc(p.x, p.y, r, 0, 7); c.fill();
    c.strokeStyle = "rgba(20,28,40,0.5)";
    c.lineWidth = Math.max(1, thick * 0.055);
    c.stroke();
    c.fillStyle = "rgba(255,255,255,0.55)";
    c.beginPath(); c.arc(p.x - r * 0.3, p.y - r * 0.34, r * 0.32, 0, 7); c.fill();
  }

  // eyes on the head
  const h = pts[0], hr = thick * 0.62;
  [-1, 1].forEach(s => {
    const ex = h.x - hr * 0.28, ey = h.y + hr * 0.34 * s;
    c.fillStyle = "#fdfff8";
    c.beginPath(); c.arc(ex, ey, hr * 0.27, 0, 7); c.fill();
    c.fillStyle = "#151a22";
    c.beginPath(); c.arc(ex - hr * 0.08, ey, hr * 0.14, 0, 7); c.fill();
  });
}

// full-bleed square icon
function iconSquare(S) {
  resetRandom();               // same seed per drawing, so output never drifts
  const cv = createCanvas(S, S);
  const c = cv.getContext("2d");
  const g = c.createRadialGradient(S * 0.5, S * 0.34, 0, S * 0.5, S * 0.34, S * 0.8);
  g.addColorStop(0, NAVY_LIT);
  g.addColorStop(1, NAVY);
  c.fillStyle = g;
  c.fillRect(0, 0, S, S);
  drawFan(c, S, 1);
  drawWorm(c, S * 0.5, S * 0.62, S * 0.46, S * 0.2);
  return cv;
}

// circular variant for launchers that want one
function iconRound(S) {
  const cv = createCanvas(S, S);
  const c = cv.getContext("2d");
  c.save();
  c.beginPath(); c.arc(S / 2, S / 2, S / 2, 0, 7); c.clip();
  c.drawImage(iconSquare(S), 0, 0);
  c.restore();
  return cv;
}

// adaptive foreground: transparent, art inside the 66% safe circle
function iconForeground(S) {
  resetRandom();
  const cv = createCanvas(S, S);
  const c = cv.getContext("2d");
  const inner = S * 0.62;
  c.save();
  c.translate((S - inner) / 2, (S - inner) / 2);
  c.beginPath(); c.rect(0, 0, inner, inner); c.clip();
  drawFan(c, inner, 1);
  drawWorm(c, inner * 0.5, inner * 0.62, inner * 0.46, inner * 0.2);
  c.restore();
  return cv;
}

// 1024x500 Play Store feature graphic
function featureGraphic() {
  resetRandom();
  const W = 1024, H = 500;
  const cv = createCanvas(W, H);
  const c = cv.getContext("2d");
  const g = c.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, NAVY_LIT);
  g.addColorStop(1, NAVY);
  c.fillStyle = g; c.fillRect(0, 0, W, H);

  c.save();
  c.translate(W * 0.60, -H * 0.12);
  drawFan(c, H * 1.2, 0.9);
  c.restore();

  drawWorm(c, W * 0.76, H * 0.55, H * 0.42, H * 0.17);

  c.fillStyle = "#eaf6ff";
  c.font = "bold 66px Verdana, sans-serif";
  c.fillText("Tummy Scanner", 60, 210);
  c.fillStyle = "rgba(200,220,245,0.8)";
  c.font = "30px Verdana, sans-serif";
  c.fillText("A pretend ultrasound that teaches", 62, 262);
  c.fillText("kids what sugar does to their tummy", 62, 302);
  return cv;
}

// ------------------------------------------------------------------ write ---

const DENSITIES = [
  ["mdpi", 48, 108],
  ["hdpi", 72, 162],
  ["xhdpi", 96, 216],
  ["xxhdpi", 144, 324],
  ["xxxhdpi", 192, 432]
];

function write(file, cv) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, cv.toBuffer("image/png"));
  console.log("  " + path.relative(OUT, file) + "  " + cv.width + "x" + cv.height);
}

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(path.join(__dirname, "..", "icons"), { recursive: true });
console.log("writing icons to android-assets/");

for (const [name, size, fgSize] of DENSITIES) {
  const dir = path.join(OUT, "mipmap-" + name);
  write(path.join(dir, "ic_launcher.png"), iconSquare(size));
  write(path.join(dir, "ic_launcher_round.png"), iconRound(size));
  write(path.join(dir, "ic_launcher_foreground.png"), iconForeground(fgSize));
}

// solid colour behind the adaptive foreground
fs.mkdirSync(path.join(OUT, "values"), { recursive: true });
fs.writeFileSync(path.join(OUT, "values", "ic_launcher_background.xml"),
  '<?xml version="1.0" encoding="utf-8"?>\n' +
  '<resources>\n    <color name="ic_launcher_background">' + NAVY + '</color>\n</resources>\n');

fs.mkdirSync(path.join(OUT, "mipmap-anydpi-v26"), { recursive: true });
for (const n of ["ic_launcher", "ic_launcher_round"]) {
  fs.writeFileSync(path.join(OUT, "mipmap-anydpi-v26", n + ".xml"),
    '<?xml version="1.0" encoding="utf-8"?>\n' +
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n' +
    '    <background android:drawable="@color/ic_launcher_background"/>\n' +
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n' +
    '</adaptive-icon>\n');
}

// browser tab icon, written next to index.html so the page can reference it
const web = path.join(__dirname, "..");
for (const size of [16, 32, 180, 192, 512]) {
  const name = size === 180 ? "apple-touch-icon.png" : `favicon-${size}.png`;
  fs.writeFileSync(path.join(web, "icons", name), iconSquare(size).toBuffer("image/png"));
}
console.log("\nicons/favicon-*.png and apple-touch-icon.png written");

// store listing art (not copied into the project; upload these by hand)
const store = path.join(OUT, "..", "store");
fs.mkdirSync(store, { recursive: true });
fs.writeFileSync(path.join(store, "icon-512.png"), iconSquare(512).toBuffer("image/png"));
fs.writeFileSync(path.join(store, "feature-graphic-1024x500.png"), featureGraphic().toBuffer("image/png"));
console.log("\nstore/icon-512.png and store/feature-graphic-1024x500.png written");
console.log("done");
