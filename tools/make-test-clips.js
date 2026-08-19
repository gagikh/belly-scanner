/*
 * Renders synthetic test clips for the CV bench, each with exact ground truth.
 *
 *   node tools/make-test-clips.js
 *
 * A real recording tells you "it looks wrong". A synthetic clip tells you
 * "tracking is 14 px off by frame 30", because we know precisely how far the
 * content moved: the frames are cut from one large static belly texture by
 * sampling a moving, zooming window.
 *
 * Output: tools/testdata/<clip>/frame_0000.png + truth.json   (gitignored)
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
const { createCanvas, loadImage } = need("@napi-rs/canvas");

const OUT = path.join(__dirname, "testdata");
const W = 240, H = 480;            // small: the tracker downsamples anyway
const FRAMES = 40;

/*
 * --source <image>  builds every clip from a real photograph instead of the
 *                   drawn texture. Real skin, real grain, real navel — but the
 *                   motion is still ours, so ground truth stays exact. This is
 *                   the mode to prefer: a real video would be more realistic
 *                   still, but with no truth you can only say "looks wrong",
 *                   never "drifted 20 px".
 * --navel x,y       where the navel is in that photo, as fractions (0.5,0.55).
 *                   Needed for navel-accuracy numbers; tracking works without.
 */
const argv = process.argv.slice(2);
function argOf(name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : null;
}
const SOURCE_IMG = argOf("--source");
const NAVEL_ARG = argOf("--navel");

// deterministic noise, so clips are reproducible and diffs mean something
let seed = 0x51ed;
function rnd() {
  seed = (seed + 0x6D2B79F5) | 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// ---------------------------------------------------------------- source ----
// One big belly. Every clip is a window onto this, so ground truth is exact.
const SRC = 1400;

// A real photo, scaled to cover the source square. Nothing is invented: the
// clips are windows onto real pixels.
async function bellyPhoto(file) {
  const img = await loadImage(file);
  const cv = createCanvas(SRC, SRC);
  const c = cv.getContext("2d");
  const s = Math.max(SRC / img.width, SRC / img.height);
  const dw = img.width * s, dh = img.height * s;
  c.drawImage(img, (SRC - dw) / 2, (SRC - dh) / 2, dw, dh);
  return cv;
}

function bellyTexture({ texture = 1, navel = true, background = 0 } = {}) {
  seed = 0x51ed;
  const cv = createCanvas(SRC, SRC);
  const c = cv.getContext("2d");

  // skin base, brighter in the middle like a torch-lit torso
  const g = c.createRadialGradient(SRC / 2, SRC / 2, 0, SRC / 2, SRC / 2, SRC * 0.7);
  g.addColorStop(0, "#c9a892");
  g.addColorStop(0.6, "#a8866f");
  g.addColorStop(1, "#4a3a30");
  c.fillStyle = g;
  c.fillRect(0, 0, SRC, SRC);

  // soft body contours
  for (let i = 0; i < 18 * texture; i++) {
    const x = rnd() * SRC, y = rnd() * SRC, r = 60 + rnd() * 260;
    const rg = c.createRadialGradient(x, y, 0, x, y, r);
    const v = Math.round(120 + rnd() * 90);
    rg.addColorStop(0, `rgba(${v},${v - 20},${v - 34},0.35)`);
    rg.addColorStop(1, "rgba(0,0,0,0)");
    c.fillStyle = rg;
    c.beginPath(); c.arc(x, y, r, 0, 7); c.fill();
  }

  // freckles and creases give the tracker something to lock onto
  for (let i = 0; i < 260 * texture; i++) {
    const x = rnd() * SRC, y = rnd() * SRC, r = 1 + rnd() * 3.5;
    c.fillStyle = `rgba(70,50,40,${0.15 + rnd() * 0.3})`;
    c.beginPath(); c.arc(x, y, r, 0, 7); c.fill();
  }

  if (navel) {
    const nx = SRC / 2, ny = SRC / 2 + 40;
    let ng = c.createRadialGradient(nx, ny, 2, nx, ny, 34);
    ng.addColorStop(0, "rgba(24,16,12,0.95)");
    ng.addColorStop(0.55, "rgba(52,38,30,0.7)");
    ng.addColorStop(1, "rgba(0,0,0,0)");
    c.fillStyle = ng;
    c.beginPath(); c.arc(nx, ny, 34, 0, 7); c.fill();
    ng = c.createRadialGradient(nx, ny - 26, 0, nx, ny - 26, 26);
    ng.addColorStop(0, "rgba(235,215,200,0.3)");
    ng.addColorStop(1, "rgba(0,0,0,0)");
    c.fillStyle = ng;
    c.beginPath(); c.arc(nx, ny - 26, 26, 0, 7); c.fill();
  }

  // A dark room to the right of the torso, so the mask has a real edge to find.
  // background = the fraction of the source where the body stops.
  if (background) {
    const edge = SRC * background;
    const g2 = c.createLinearGradient(edge - 30, 0, edge + 40, 0);
    g2.addColorStop(0, "rgba(0,0,0,0)");
    g2.addColorStop(1, "rgba(12,10,14,0.97)");
    c.fillStyle = g2;
    c.fillRect(edge - 30, 0, SRC - edge + 30, SRC);
    c.fillStyle = "rgba(12,10,14,0.97)";
    c.fillRect(edge + 40, 0, SRC, SRC);
  }

  // sensor grain
  const id = c.getImageData(0, 0, SRC, SRC);
  for (let i = 0; i < id.data.length; i += 4) {
    const n = (rnd() - 0.5) * 26;
    id.data[i] += n; id.data[i + 1] += n; id.data[i + 2] += n;
  }
  c.putImageData(id, 0, 0);
  return cv;
}

// ----------------------------------------------------------------- clips ----
// Each returns the source window for frame i. Ground truth is derived from it.
const CLIPS = {
  // slow diagonal pan: the everyday case
  pan: {
    desc: "slow diagonal pan, constant distance",
    window: i => ({ sx: 400 + i * 4, sy: 400 + i * 2.5, sw: 480, sh: 960 })
  },
  // moving closer: the case that kills template matching
  zoom: {
    desc: "moving the phone closer (30% zoom in)",
    window: i => {
      const k = 1 - (i / FRAMES) * 0.3;
      const sw = 480 * k, sh = 960 * k;
      return { sx: 400 + (480 - sw) / 2, sy: 400 + (960 - sh) / 2, sw, sh };
    }
  },
  // hand shake: large per-frame jumps
  shake: {
    desc: "hand shake, large fast jitter",
    window: i => ({
      sx: 400 + Math.sin(i * 1.7) * 26 + Math.sin(i * 0.6) * 10,
      sy: 400 + Math.cos(i * 2.1) * 22,
      sw: 480, sh: 960
    })
  },
  // static, but the exposure ramps: must NOT be read as motion
  lighting: {
    desc: "still phone, camera re-exposing (brightness ramp)",
    window: () => ({ sx: 400, sy: 400, sw: 480, sh: 960 }),
    brightness: i => 0.65 + 0.5 * (i / FRAMES)
  },
  // the torso only fills part of the frame: the mask must find its edge and
  // must NOT claim the dark room beyond it
  edge: {
    desc: "torso edge in frame, dark room beyond",
    window: i => ({ sx: 700 + i * 2, sy: 400, sw: 480, sh: 960 }),
    background: 0.643,          // body stops at x = 900 of 1400
    navel: false
  },
  // featureless skin: tracker should refuse rather than invent motion
  flat: {
    desc: "smooth featureless skin, slow pan",
    window: i => ({ sx: 400 + i * 4, sy: 400, sw: 480, sh: 960 }),
    texture: 0.06,
    navel: false
  }
};

// ------------------------------------------------------------------ write ---
async function renderClip(name, spec, photo) {
  // a real photo replaces the drawn texture; "flat" is meaningless then, since
  // we can't remove the texture from someone's actual skin
  if (photo && name === "flat") return false;
  const src = photo || bellyTexture({ texture: spec.texture ?? 1, navel: spec.navel !== false,
                                     background: spec.background || 0 });
  const dir = path.join(OUT, name);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });

  const truth = {
    name, desc: spec.desc + (photo ? " [real photo]" : ""),
    source: photo ? path.basename(SOURCE_IMG) : "synthetic",
    width: W, height: H, frames: []
  };
  const w0 = spec.window(0);

  // where the navel sits in source coordinates
  let navelSrc = { x: SRC / 2, y: SRC / 2 + 40 };
  let navelKnown = spec.navel !== false;
  if (photo) {
    if (NAVEL_ARG) {
      const [fx, fy] = NAVEL_ARG.split(",").map(Number);
      navelSrc = { x: fx * SRC, y: fy * SRC };
      navelKnown = true;
    } else {
      navelKnown = false;      // no --navel given: skip navel-accuracy scoring
    }
  }

  for (let i = 0; i < FRAMES; i++) {
    const w = spec.window(i);
    const cv = createCanvas(W, H);
    const c = cv.getContext("2d");
    if (spec.brightness) c.filter = `brightness(${spec.brightness(i)})`;
    c.drawImage(src, w.sx, w.sy, w.sw, w.sh, 0, 0, W, H);
    c.filter = "none";
    fs.writeFileSync(path.join(dir, `frame_${String(i).padStart(4, "0")}.png`),
                     cv.toBuffer("image/png"));

    // Ground truth: where a point fixed to the body appears now, versus frame 0.
    // screen_x = (src_x - sx) * (W / sw)
    const at = (p, win) => ({
      x: (p.x - win.sx) * (W / win.sw),
      y: (p.y - win.sy) * (H / win.sh)
    });
    const p0 = at(navelSrc, w0), pi = at(navelSrc, w);
    const bodyFrac = spec.background
      ? Math.max(0, Math.min(1, ((SRC * spec.background - w.sx) * (W / w.sw)) / W))
      : 1;
    truth.frames.push({
      i,
      bodyFraction: +bodyFrac.toFixed(4),
      dx: +(pi.x - p0.x).toFixed(3),          // how far content moved since frame 0
      dy: +(pi.y - p0.y).toFixed(3),
      scale: +(w0.sw / w.sw).toFixed(4),
      navel: { x: +pi.x.toFixed(2), y: +pi.y.toFixed(2) },
      navelVisible: navelKnown && pi.x > 0 && pi.x < W && pi.y > 0 && pi.y < H
    });
  }
  truth.navelKnown = navelKnown;
  // How much of the frame is genuinely body — the mask should match this.
  // Without a background the belly fills the view, so it's all body.
  if (spec.background) {
    const w = spec.window(0);
    const edgeX = (SRC * spec.background - w.sx) * (W / w.sw);
    truth.bodyFraction = +Math.max(0, Math.min(1, edgeX / W)).toFixed(3);
  } else {
    truth.bodyFraction = 1;
  }

  fs.writeFileSync(path.join(dir, "truth.json"), JSON.stringify(truth, null, 2));
  console.log(`  ${name.padEnd(9)} ${FRAMES} frames  ${W}x${H}  ${truth.desc}`);
  return true;
}

(async () => {
  let photo = null;
  if (SOURCE_IMG) {
    if (!fs.existsSync(SOURCE_IMG)) {
      console.error(`source image not found: ${SOURCE_IMG}`);
      process.exit(1);
    }
    photo = await bellyPhoto(SOURCE_IMG);
    console.log(`using real photo: ${SOURCE_IMG}`);
    if (!NAVEL_ARG) {
      console.log("  (no --navel given, so navel accuracy won't be scored;");
      console.log("   add e.g. --navel 0.5,0.55 to enable it)");
    }
  }

  fs.mkdirSync(OUT, { recursive: true });
  console.log("rendering test clips to tools/testdata/");
  for (const [name, spec] of Object.entries(CLIPS)) await renderClip(name, spec, photo);
  console.log("\ndone - run: node tools/cv-testbench.js");
})();
