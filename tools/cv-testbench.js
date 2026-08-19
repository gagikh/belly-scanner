/*
 * Runs the app's real computer-vision code over test clips, headlessly.
 * No phone, no camera.
 *
 *   node tools/make-test-clips.js     # once, to render the clips
 *   node tools/cv-testbench.js        # run every clip
 *   node tools/cv-testbench.js pan    # run one
 *   node tools/cv-testbench.js --video myclip.mp4
 *
 * This loads index.html in jsdom, replaces the camera with a frame sequence,
 * and calls the same functions the app calls. It is not a reimplementation:
 * if it passes here and fails on a phone, the difference is the camera, not
 * the algorithm.
 *
 * Synthetic clips carry ground truth, so tracking error is reported in pixels.
 * Real videos have no truth, so only stability is reported.
 */
const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");
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
const { JSDOM } = need("jsdom");
const { createCanvas, loadImage } = need("@napi-rs/canvas");

const ROOT = path.join(__dirname, "..");
const DATA = path.join(__dirname, "testdata");
const HTML = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");

const C = { dim: "\x1b[90m", red: "\x1b[31m", grn: "\x1b[32m", yel: "\x1b[33m", cyn: "\x1b[36m", off: "\x1b[0m" };
const pass = v => `${C.grn}${v}${C.off}`;
const fail = v => `${C.red}${v}${C.off}`;
const warn = v => `${C.yel}${v}${C.off}`;

// --------------------------------------------------------------- harness ----
// One frame at a time is pushed into `current`; the page's <video> draws from it.
function makePage(width, height) {
  const state = { current: null };

  const dom = new JSDOM(HTML, {
    runScripts: "dangerously",
    pretendToBeVisual: true,
    url: "https://test.local/",
    beforeParse(w) {
      w.__TUMMY_TEST__ = true;

      const real = new WeakMap();
      w.HTMLCanvasElement.prototype.getContext = function () {
        if (!real.has(this)) {
          const cv = createCanvas(this.width || 300, this.height || 150);
          real.set(this, { cv, ctx: cv.getContext("2d"), w: cv.width, h: cv.height });
        }
        const e = real.get(this);
        // the page resizes canvases after getContext; follow it
        if (this.width !== e.w || this.height !== e.h) {
          e.cv = createCanvas(this.width || 1, this.height || 1);
          e.ctx = e.cv.getContext("2d");
          e.w = this.width; e.h = this.height;
        }
        return new Proxy({}, {
          get: (_t, k) => {
            const cur = real.get(this);
            if (k === "__cv") return () => cur.cv;
            const v = cur.ctx[k];
            if (typeof v === "function") {
              return (...a) => {
                // substitute the current frame wherever the page draws the video
                if (k === "drawImage" && a[0] && (a[0].tagName === "VIDEO")) {
                  if (!state.current) return;
                  a[0] = state.current;
                }
                try { return cur.ctx[k](...a); } catch { return undefined; }
              };
            }
            return v;
          },
          set: (_t, k, v) => { try { real.get(this).ctx[k] = v; } catch {} return true; }
        });
      };

      Object.defineProperty(w.HTMLElement.prototype, "clientWidth",  { get: () => width });
      Object.defineProperty(w.HTMLElement.prototype, "clientHeight", { get: () => height });
      Object.defineProperty(w, "devicePixelRatio", { get: () => 1 });
      w.HTMLMediaElement.prototype.play = () => Promise.resolve();
      Object.defineProperty(w.HTMLVideoElement.prototype, "videoWidth",  { get: () => state.current ? state.current.width : 0 });
      Object.defineProperty(w.HTMLVideoElement.prototype, "videoHeight", { get: () => state.current ? state.current.height : 0 });
      w.navigator.mediaDevices = { getUserMedia: () => Promise.reject(new Error("no camera in bench")) };
    }
  });

  return { dom, state };
}

// ----------------------------------------------------------------- frames ---
async function loadFrames(dir) {
  const files = fs.readdirSync(dir).filter(f => /^frame_\d+\.png$/.test(f)).sort();
  const out = [];
  for (const f of files) out.push(await loadImage(path.join(dir, f)));
  return out;
}

// Accepts a local path or an http(s) URL. ffmpeg reads URLs natively, so a
// linked clip needs no manual download — but it must be a direct media link
// (something ending .mp4/.webm/.mov), not a web page that happens to contain
// a player. A YouTube or Pexels *page* URL will not work; the file URL will.
function framesFromVideo(src, fps = 10, max = 60) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cvbench-"));
  const isUrl = /^https?:\/\//i.test(src);
  const args = ["-hide_banner", "-loglevel", "error"];
  if (isUrl) {
    // some CDNs reject requests without a normal UA, and streams can stall
    args.push("-user_agent", "Mozilla/5.0", "-rw_timeout", "15000000");
  }
  args.push("-i", src,
            "-vf", `fps=${fps},scale=240:-2`,
            "-frames:v", String(max),
            path.join(tmp, "frame_%04d.png"));
  try {
    execFileSync("ffmpeg", args, { stdio: ["ignore", "ignore", "pipe"] });
  } catch (e) {
    const err = (e.stderr || "").toString().trim();
    fs.rmSync(tmp, { recursive: true, force: true });
    console.error(`\nffmpeg could not read ${isUrl ? "that URL" : "that file"}.`);
    if (err) console.error(err.split("\n").slice(-3).join("\n"));
    if (isUrl) {
      console.error("\nIt needs a direct link to the video file itself (…/something.mp4),");
      console.error("not the page it's embedded in. On a stock site, use the download link");
      console.error("target rather than the page URL.");
    }
    process.exit(1);
  }
  return tmp;
}

// -------------------------------------------------------------------- run ---
async function runClip(name, dir, truth) {
  const frames = await loadFrames(dir);
  if (!frames.length) throw new Error(`no frames in ${dir}`);
  const width = truth ? truth.width : frames[0].width;
  const height = truth ? truth.height : frames[0].height;

  const { dom, state } = makePage(width, height);
  await new Promise(r => setTimeout(r, 120));
  const T = dom.window.__tummy;
  if (!T) throw new Error("test seam missing - is window.__TUMMY_TEST__ set before load?");

  T.resize();
  T.resetTracking();

  const res = {
    name, desc: truth ? truth.desc : "real video (no ground truth)",
    navelFound: 0, navelErr: [], navelVisible: 0,
    maskValid: 0, maskFrac: [], maskErr: [],
    trackErr: [], lock: 0, frames: frames.length
  };

  // --- pass 1: navel + mask, the way the scanning phase does it
  for (let i = 0; i < frames.length; i++) {
    state.current = frames[i];
    T.updateNavel();
    const s = T.state();
    if (s.maskValid) res.maskValid++;
    res.maskFrac.push(s.maskFrac || 0);
    if (truth && truth.frames[i] && truth.frames[i].bodyFraction != null) {
      res.maskErr.push(Math.abs((s.maskFrac || 0) - truth.frames[i].bodyFraction));
    }
    const t = truth && truth.frames[i];
    if (s.navelScreen) res.navelFound++;
    if (t && t.navelVisible && s.navelScreen) {
      res.navelVisible++;
      res.navelErr.push(Math.hypot(s.navelScreen.x - t.navel.x, s.navelScreen.y - t.navel.y));
    }
  }

  // --- pass 2: tracking, the way the play phase does it
  T.resetTracking();
  state.current = frames[0];
  T.trackerGrab();                       // prime "previous frame"
  T.setAnchor(width / 2, height / 2);
  for (let i = 1; i < frames.length; i++) {
    state.current = frames[i];
    const f = T.trackStep();
    if (f) res.lock++;
    const s = T.state();
    const t = truth && truth.frames[i];
    if (t) {
      // Worms render at (world - camX). If the content moved by dx, a pinned
      // worm must move by dx too, so a perfect tracker has camX === -dx.
      res.trackErr.push(Math.hypot(s.camX + t.dx, s.camY + t.dy));
    }
  }
  res.bodyFraction = truth ? truth.bodyFraction : null;
  res.finalCam = T.state();
  res.finalTruth = truth ? truth.frames[frames.length - 1] : null;
  dom.window.close();
  return res;
}

// ----------------------------------------------------------------- report ---
const avg = a => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
const pct = (n, d) => (d ? (100 * n / d).toFixed(0) + "%" : "n/a");

function report(r) {
  console.log(`\n${C.cyn}== ${r.name}${C.off}  ${C.dim}${r.desc}${C.off}`);
  console.log(`   frames            ${r.frames}`);

  const nf = pct(r.navelFound, r.frames);
  console.log(`   navel found       ${r.navelFound ? pass(nf) : warn(nf)}` +
    (r.navelErr.length ? `   mean error ${avg(r.navelErr).toFixed(1)} px` : ""));

  const mv = pct(r.maskValid, r.frames);
  const cov = avg(r.maskFrac);
  let covTxt = `mean coverage ${(cov * 100).toFixed(0)}%`;
  if (r.maskErr.length) {
    const err = avg(r.maskErr) * 100;
    const col = err < 8 ? pass : err < 20 ? warn : fail;
    covTxt += `  (off by ${col(err.toFixed(0) + " pts")} vs truth)`;
  }
  console.log(`   body mask valid   ${r.maskValid ? pass(mv) : warn(mv)}   ${covTxt}`);

  const lk = pct(r.lock, r.frames - 1);
  console.log(`   tracking lock     ${r.lock ? pass(lk) : warn(lk)}`);

  if (r.trackErr.length) {
    const mean = avg(r.trackErr), last = r.trackErr[r.trackErr.length - 1];
    const colour = last < 10 ? pass : last < 30 ? warn : fail;
    console.log(`   tracking error    mean ${mean.toFixed(1)} px   final ${colour(last.toFixed(1) + " px")}`);
    console.log(`   ${C.dim}content moved (${r.finalTruth.dx.toFixed(0)}, ${r.finalTruth.dy.toFixed(0)}) px ` +
                `scale x${r.finalTruth.scale} -> wanted cam (${(-r.finalTruth.dx).toFixed(0)}, ${(-r.finalTruth.dy).toFixed(0)}), ` +
                `got (${r.finalCam.camX.toFixed(0)}, ${r.finalCam.camY.toFixed(0)})${C.off}`);
  }
}

// ------------------------------------------------------------------- main ---
(async () => {
  const args = process.argv.slice(2);
  const vi = args.indexOf("--video");

  if (vi >= 0) {
    const src = args[vi + 1];
    const isUrl = src && /^https?:\/\//i.test(src);
    if (!src || (!isUrl && !fs.existsSync(src))) {
      console.error("usage: --video <file.mp4 | https://…/clip.mp4>");
      process.exit(1);
    }
    const label = isUrl ? src.split("/").pop().split("?")[0] : path.basename(src);
    console.log(`extracting frames from ${isUrl ? "URL" : "file"}: ${label} ...`);
    const dir = framesFromVideo(src);
    report(await runClip(label, dir, null));
    fs.rmSync(dir, { recursive: true, force: true });
    console.log(`\n${C.dim}No ground truth for a real video: navel and lock rates are meaningful,${C.off}`);
    console.log(`${C.dim}tracking error is not. Use the synthetic clips for that.${C.off}`);
    return;
  }

  if (!fs.existsSync(DATA)) {
    console.error("no clips yet - run: node tools/make-test-clips.js");
    process.exit(1);
  }
  const only = args.find(a => !a.startsWith("--"));
  const clips = fs.readdirSync(DATA).filter(d => !only || d === only);
  if (!clips.length) { console.error(`no clip named "${only}"`); process.exit(1); }

  const all = [];
  for (const name of clips) {
    const dir = path.join(DATA, name);
    const tf = path.join(dir, "truth.json");
    const truth = fs.existsSync(tf) ? JSON.parse(fs.readFileSync(tf, "utf8")) : null;
    const r = await runClip(name, dir, truth);
    report(r);
    all.push(r);
  }

  console.log(`\n${C.cyn}== summary${C.off}`);
  for (const r of all) {
    const e = r.trackErr.length ? r.trackErr[r.trackErr.length - 1] : null;
    const cov = avg(r.maskFrac);
    const mErr = r.maskErr.length ? avg(r.maskErr) * 100 : null;
    console.log(`   ${r.name.padEnd(10)} navel ${pct(r.navelFound, r.frames).padStart(4)}` +
                `   lock ${pct(r.lock, r.frames - 1).padStart(4)}` +
                (e === null ? "" : `   drift ${e.toFixed(1).padStart(6)} px`) +
                (mErr === null ? "" : `   mask off ${mErr.toFixed(0).padStart(3)} pts`));
  }
})();
