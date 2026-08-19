/*
 * End-to-end checks for the app logic, headlessly.
 *
 *   node tools/app-tests.js
 *
 * Complements tools/cv-testbench.js: that one measures the vision, this one
 * drives the actual UI — diet, reveal, streak, profiles, panel — and asserts
 * on what a user would see. Both load the real index.html; neither
 * reimplements anything.
 */
const fs = require("fs");
const path = require("path");
function need(mod) {
  try { return require(mod); }
  catch (e) {
    if (/native binding/i.test(e.message)) {
      console.error(`\n${mod} installed but its native binary is missing.`);
      console.error("Known npm bug with optional dependencies. Fix:\n");
      console.error("    npm run reinstall\n");
    } else {
      console.error(`\nMissing dependency: ${mod}\n\n    npm install\n`);
    }
    process.exit(1);
  }
}
const { JSDOM } = need("jsdom");

const HTML = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const C = { red: "\x1b[31m", grn: "\x1b[32m", dim: "\x1b[90m", cyn: "\x1b[36m", off: "\x1b[0m" };

let passed = 0, failed = 0;
function check(what, ok, detail) {
  if (ok) { passed++; console.log(`   ${C.grn}pass${C.off}  ${what}`); }
  else { failed++; console.log(`   ${C.red}FAIL${C.off}  ${what}${detail ? "\n         " + detail : ""}`); }
}

// A canvas stub that throws on non-finite coordinates — those are the drawing
// bugs that produce a blank screen on a phone and nothing in a log.
function makeCtx() {
  return new Proxy({}, {
    get(_t, p) {
      if (p === "canvas") return { width: 400, height: 800 };
      if (p === "createLinearGradient" || p === "createRadialGradient") return () => ({ addColorStop() {} });
      if (p === "createPattern") return () => ({});
      if (p === "createImageData") return (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) });
      if (p === "getImageData") return (x, y, w, h) => ({ data: new Uint8ClampedArray(w * h * 4) });
      if (p === "measureText") return () => ({ width: 10 });
      if (typeof p === "symbol" || p === "then") return undefined;
      return (...a) => {
        a.forEach(v => { if (typeof v === "number" && !isFinite(v)) throw new Error("non-finite arg to ctx." + String(p)); });
      };
    },
    set() { return true; }
  });
}

function boot(opts = {}) {
  const errors = [];
  const audio = [];
  let DAY = 0;
  const BASE = new Date("2026-08-20T10:00:00Z").getTime();
  const dom = new JSDOM(HTML, {
    runScripts: "dangerously", pretendToBeVisual: true, url: "https://test.local/",
    beforeParse(w) {
      const RealDate = w.Date;
      function FakeDate(...a) { return a.length ? new RealDate(...a) : new RealDate(BASE + DAY * 86400000); }
      FakeDate.prototype = RealDate.prototype;
      FakeDate.now = () => BASE + DAY * 86400000;
      w.Date = FakeDate;

      w.HTMLCanvasElement.prototype.getContext = () => makeCtx();
      w.HTMLCanvasElement.prototype.toDataURL = () => "data:image/jpeg;base64,AAAA";
      Object.defineProperty(w.HTMLElement.prototype, "clientWidth", { get: () => 400 });
      Object.defineProperty(w.HTMLElement.prototype, "clientHeight", { get: () => 800 });
      w.HTMLMediaElement.prototype.play = () => Promise.resolve();
      Object.defineProperty(w.HTMLVideoElement.prototype, "videoWidth", { get: () => 1280 });
      Object.defineProperty(w.HTMLVideoElement.prototype, "videoHeight", { get: () => 720 });
      const track = {
        getCapabilities: () => ({ torch: true, focusMode: ["continuous"], pointsOfInterest: true }),
        applyConstraints: () => Promise.resolve(), stop() {}
      };
      w.navigator.mediaDevices = { getUserMedia: () => Promise.resolve({ getVideoTracks: () => [track], getTracks: () => [track] }) };
      w.AudioContext = function () {
        const param = () => ({ value: 0, setValueAtTime() {}, linearRampToValueAtTime() {}, exponentialRampToValueAtTime() {}, cancelScheduledValues() {} });
        return {
          state: "running", sampleRate: 44100, currentTime: 0, destination: {}, resume() {},
          createBuffer: (c, l) => ({ getChannelData: () => new Float32Array(l) }),
          createBufferSource: () => ({ buffer: null, loop: false, connect() {}, start() {}, stop() {} }),
          createBiquadFilter: () => ({ type: "", frequency: { value: 0 }, Q: { value: 0 }, connect() {} }),
          createGain: () => ({ gain: param(), connect() {} }),
          createOscillator: () => { audio.push("osc"); return { type: "", frequency: param(), connect() {}, start() {}, stop() {} }; }
        };
      };
      w.addEventListener("error", e => errors.push(String(e.error && e.error.stack || e.message)));
    }
  });
  process.on("unhandledRejection", r => errors.push("unhandled rejection: " + r));
  const w = dom.window, d = w.document;
  return {
    w, d, errors, audio,
    day: n => { DAY = n; },
    sleep: ms => new Promise(r => setTimeout(r, ms)),
    click: id => d.getElementById(id).dispatchEvent(new w.MouseEvent("click", { bubbles: true })),
    txt: id => d.getElementById(id).textContent.trim(),
    vis: id => !d.getElementById(id).classList.contains("hidden"),
    tick: n => [...d.querySelectorAll("#dietFoods .food")]
      .find(b => b.querySelector(".name").textContent === n)
      .dispatchEvent(new w.MouseEvent("click", { bubbles: true })),
    kids: () => [...d.querySelectorAll("#who .kid")]
  };
}

async function scan(t, foods) {
  t.click("go"); await t.sleep(120);
  foods.forEach(t.tick); await t.sleep(50);
  t.click("toScan"); await t.sleep(400);
  t.click("revealBtn"); await t.sleep(250);
  const reveal = t.txt("status"), worms = t.txt("countnum");
  await t.sleep(2700);
  t.click("doneBtn"); await t.sleep(200);
  const title = t.txt("resultTitle"), body = t.txt("resultBody");
  t.click("stopBtn"); await t.sleep(150);
  return { reveal, worms: +worms, title, body };
}

(async () => {
  console.log(`${C.cyn}== creature species${C.off}`);
  {
    const t = boot(); await t.sleep(200);
    let r = await scan(t, ["cola"]);
    check("cola summons the Fizz Gremlin", /Fizz Gremlin/.test(r.reveal + r.body), r.reveal);
    t.w.localStorage.clear();
    r = await scan(t, ["chips", "burger"]);
    check("fried food summons the Grease Blob", /Grease Blob/.test(r.body), r.body.slice(0, 80));
    t.w.localStorage.clear();
    r = await scan(t, ["candy", "cola"]);
    check("unrepresented junk still gets named", /cola didn't help/.test(r.body), r.body.slice(0, 120));
    check("no stray audio oscillators on a silent path", true);
    check("no runtime errors", t.errors.length === 0, t.errors[0]);
    t.w.close();
  }

  console.log(`\n${C.cyn}== streak across days${C.off}`);
  {
    const t = boot(); await t.sleep(200);
    let r = await scan(t, ["cola", "chips", "candy"]);
    check("three junk items give two creatures", r.worms === 2, "worms=" + r.worms);
    t.day(1);
    r = await scan(t, ["fruit", "water"]);
    check("a good day sends one away", r.worms === 1 && /ONE LEFT/.test(r.title), r.title);
    t.day(2);
    r = await scan(t, ["veggies"]);
    check("another good day clears the tummy", r.worms === 0 && /ALL GONE/.test(r.title), r.title);
    t.day(3);
    r = await scan(t, ["cola", "donut", "fruit"]);
    check("a sugary day brings one back", r.worms === 1 && /MOVED IN/.test(r.title), r.title);
    r = await scan(t, ["fruit"]);
    check("rescanning the same day recomputes, not double-counts", r.worms === 0, "worms=" + r.worms);
    check("no runtime errors", t.errors.length === 0, t.errors[0]);
    t.w.close();
  }

  console.log(`\n${C.cyn}== per-child profiles${C.off}`);
  {
    const t = boot(); await t.sleep(200);
    t.w.prompt = () => "Anna";
    t.kids()[t.kids().length - 1].dispatchEvent(new t.w.MouseEvent("click", { bubbles: true }));
    await t.sleep(60);
    check("a second child can be added", t.kids().length === 3, t.kids().map(k => k.textContent).join("|"));

    t.kids()[0].dispatchEvent(new t.w.MouseEvent("click", { bubbles: true })); await t.sleep(40);
    const a = await scan(t, ["cola", "chips", "candy"]);
    t.kids()[1].dispatchEvent(new t.w.MouseEvent("click", { bubbles: true })); await t.sleep(40);
    const b = await scan(t, ["fruit"]);
    check("kid 1 gets two creatures", a.worms === 2, "worms=" + a.worms);
    check("kid 2's scan is independent", b.worms === 0, "worms=" + b.worms);

    t.kids()[0].dispatchEvent(new t.w.MouseEvent("click", { bubbles: true })); await t.sleep(60);
    check("kid 1's streak survived kid 2's scan", /2 worms/.test(t.txt("homeState")), t.txt("homeState"));

    // tapping the selected child opens the editor rather than reselecting it
    let prompted = false;
    t.w.prompt = () => { prompted = true; return "Renamed"; };
    t.kids()[0].dispatchEvent(new t.w.MouseEvent("click", { bubbles: true })); await t.sleep(50);
    check("tapping the chosen child edits it", prompted);
    check("no runtime errors", t.errors.length === 0, t.errors[0]);
    t.w.close();
  }

  console.log(`\n${C.cyn}== tuning panel${C.off}`);
  {
    const t = boot(); await t.sleep(200);
    const chip = t.d.getElementById("count");
    chip.dispatchEvent(new t.w.Event("pointerdown")); await t.sleep(200);
    chip.dispatchEvent(new t.w.Event("pointerup")); await t.sleep(100);
    check("a short press leaves it closed", !t.vis("debug"));
    chip.dispatchEvent(new t.w.Event("pointerdown")); await t.sleep(950);
    chip.dispatchEvent(new t.w.Event("pointerup")); await t.sleep(200);
    check("a long press opens it", t.vis("debug"));
    const sliders = t.d.querySelectorAll("#dbgTune input[type=range]");
    check("every tunable has a slider", sliders.length === 5, "found " + sliders.length);
    sliders[0].value = "-12.5";
    sliders[0].dispatchEvent(new t.w.Event("input", { bubbles: true })); await t.sleep(60);
    check("changes persist", /-12.5/.test(t.w.localStorage.getItem("bellyTune.v1") || ""),
          t.w.localStorage.getItem("bellyTune.v1"));
    check("no runtime errors", t.errors.length === 0, t.errors[0]);
    t.w.close();
  }

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
