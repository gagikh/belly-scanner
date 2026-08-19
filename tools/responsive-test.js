/*
 * Layout checks in a real browser, at real phone sizes.
 *
 *   npm i -D puppeteer
 *   node tools/responsive-test.js            # check every size
 *   node tools/responsive-test.js --shots    # also write screenshots
 *
 * jsdom can't do layout, so the other test files can't see a button pushed off
 * the screen or text overflowing. This launches headless Chrome with a fake
 * camera, walks the app's screens at a range of viewport sizes, and asserts on
 * measured geometry.
 */
const fs = require("fs");
const path = require("path");
const http = require("http");

function need(mod) {
  try { return require(mod); }
  catch (e) {
    console.error(`\nMissing dependency: ${mod}`);
    console.error("Run:  npm install --save-dev puppeteer\n");
    process.exit(1);
  }
}
const puppeteer = need("puppeteer");

const ROOT = path.join(__dirname, "..");
const SHOTS = process.argv.includes("--shots");
const SHOT_DIR = path.join(ROOT, "screenshots", "layout");

const C = { red: "\x1b[31m", grn: "\x1b[32m", yel: "\x1b[33m", dim: "\x1b[90m", cyn: "\x1b[36m", off: "\x1b[0m" };
let passed = 0, failed = 0;
function check(what, ok, detail) {
  if (ok) { passed++; console.log(`     ${C.grn}pass${C.off}  ${what}`); }
  else { failed++; console.log(`     ${C.red}FAIL${C.off}  ${what}${detail ? `  ${C.dim}${detail}${C.off}` : ""}`); }
}

// Sizes chosen for what they stress, not for brand names.
const VIEWPORTS = [
  { name: "320x568  smallest still in use", w: 320, h: 568 },
  { name: "360x640  common budget Android", w: 360, h: 640 },
  { name: "375x667  small iPhone",          w: 375, h: 667 },
  { name: "390x844  iPhone 14",             w: 390, h: 844 },
  { name: "412x915  Pixel",                 w: 412, h: 915 },
  { name: "406x904  Xiaomi 14T",            w: 406, h: 904 },
  { name: "768x1024 tablet",                w: 768, h: 1024 },
  { name: "844x390  landscape",             w: 844, h: 390 }
];

// getUserMedia needs a secure context; http://localhost counts, file:// doesn't.
function serve() {
  return new Promise(resolve => {
    const srv = http.createServer((req, res) => {
      const rel = decodeURIComponent(req.url.split("?")[0]);
      const file = path.join(ROOT, rel === "/" ? "index.html" : rel);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); return res.end("no");
      }
      const type = file.endsWith(".html") ? "text/html"
                 : file.endsWith(".png") ? "image/png"
                 : file.endsWith(".webmanifest") ? "application/manifest+json" : "text/plain";
      res.writeHead(200, { "Content-Type": type });
      fs.createReadStream(file).pipe(res);
    });
    srv.listen(0, "127.0.0.1", () => resolve({ srv, port: srv.address().port }));
  });
}

// Anything sticking out past the right edge, or wider than the viewport.
async function overflow(page, vw) {
  return page.evaluate((vw) => {
    const bad = [];
    const seen = new Set();
    document.querySelectorAll("body *").forEach(el => {
      const cs = getComputedStyle(el);
      if (cs.display === "none" || cs.visibility === "hidden" || cs.opacity === "0") return;
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) return;
      if (r.right > vw + 1 || r.left < -1) {
        const id = el.id || el.className || el.tagName;
        if (seen.has(id)) return;
        seen.add(id);
        bad.push(`${id} [${Math.round(r.left)}..${Math.round(r.right)}]`);
      }
    });
    return {
      elements: bad,
      docScrollW: document.documentElement.scrollWidth,
      bodyScrollW: document.body.scrollWidth
    };
  }, vw);
}

// Android's accessibility guidance is 48dp; anything under ~40 is a miss for a
// child's finger.
async function tapTargets(page) {
  return page.evaluate(() => {
    const small = [];
    document.querySelectorAll("button, .chip, .kid, .food").forEach(el => {
      const cs = getComputedStyle(el);
      if (cs.display === "none" || !el.offsetParent) return;
      const r = el.getBoundingClientRect();
      if (r.width === 0) return;
      if (r.height < 40 || r.width < 40) {
        small.push(`${el.id || el.className}: ${Math.round(r.width)}x${Math.round(r.height)}`);
      }
    });
    return small;
  });
}

// Is anything scrollable actually reachable, or is content clipped away?
async function clipped(page) {
  return page.evaluate(() => {
    const out = [];
    document.querySelectorAll(".screen").forEach(el => {
      if (el.classList.contains("hidden")) return;
      if (el.scrollHeight > el.clientHeight + 2) {
        const canScroll = getComputedStyle(el).overflowY;
        out.push(`${el.id}: content ${el.scrollHeight}px in ${el.clientHeight}px, overflow-y:${canScroll}`);
      }
    });
    return out;
  });
}

(async () => {
  const { srv, port } = await serve();
  const browser = await puppeteer.launch({
    args: [
      "--no-sandbox", "--disable-setuid-sandbox",
      "--use-fake-ui-for-media-stream",       // auto-accept the camera prompt
      "--use-fake-device-for-media-stream"    // synthetic camera feed
    ]
  });

  if (SHOTS) fs.mkdirSync(SHOT_DIR, { recursive: true });
  const consoleErrors = [];

  for (const vp of VIEWPORTS) {
    console.log(`\n${C.cyn}== ${vp.name}${C.off}`);
    const page = await browser.newPage();
    page.on("pageerror", e => consoleErrors.push(`${vp.name}: ${e.message}`));
    await page.setViewport({ width: vp.w, height: vp.h, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
    await page.goto(`http://127.0.0.1:${port}/index.html`, { waitUntil: "domcontentloaded" });
    await new Promise(r => setTimeout(r, 250));

    // --- home
    let o = await overflow(page, vp.w);
    check("home: nothing overflows sideways", o.elements.length === 0, o.elements.slice(0, 2).join("; "));
    check("home: no horizontal scroll", o.docScrollW <= vp.w + 1, `scrollWidth ${o.docScrollW} > ${vp.w}`);
    let small = await tapTargets(page);
    check("home: tap targets >= 40px", small.length === 0, small.slice(0, 3).join("; "));
    let clip = await clipped(page);
    check("home: content fits or scrolls", clip.every(c => /auto|scroll/.test(c)), clip.slice(0, 2).join("; "));
    if (SHOTS) await page.screenshot({ path: path.join(SHOT_DIR, `home-${vp.w}x${vp.h}.png`) });

    // --- diet checklist: the densest screen, 12 items plus chrome
    await page.click("#go");
    await new Promise(r => setTimeout(r, 200));
    o = await overflow(page, vp.w);
    check("diet: nothing overflows sideways", o.elements.length === 0, o.elements.slice(0, 2).join("; "));
    small = await tapTargets(page);
    check("diet: food buttons >= 40px", small.length === 0, small.slice(0, 3).join("; "));
    clip = await clipped(page);
    check("diet: content fits or scrolls", clip.every(c => /auto|scroll/.test(c)), clip.slice(0, 2).join("; "));
    const btn = await page.evaluate(() => {
      const b = document.getElementById("toScan").getBoundingClientRect();
      return { bottom: Math.round(b.bottom), top: Math.round(b.top) };
    });
    check("diet: the scan button is on screen", btn.bottom <= vp.h + 1 && btn.top >= 0,
          `button at ${btn.top}..${btn.bottom}, viewport ${vp.h}`);
    if (SHOTS) await page.screenshot({ path: path.join(SHOT_DIR, `diet-${vp.w}x${vp.h}.png`) });

    // --- scanning, with the fake camera running
    await page.evaluate(() => {
      document.querySelectorAll("#dietFoods .food").forEach((b, i) => { if (i < 4) b.click(); });
    });
    await page.click("#toScan");
    await new Promise(r => setTimeout(r, 2500));
    o = await overflow(page, vp.w);
    check("scan: HUD stays inside the screen", o.elements.length === 0, o.elements.slice(0, 2).join("; "));
    const hud = await page.evaluate(() => {
      const s = document.getElementById("status").getBoundingClientRect();
      const row = document.querySelector(".hudrow").getBoundingClientRect();
      return { statusBottom: Math.round(s.bottom), rowRight: Math.round(row.right), rowTop: Math.round(row.top) };
    });
    check("scan: status sits above the bottom edge", hud.statusBottom <= vp.h + 1,
          `status bottom ${hud.statusBottom} vs ${vp.h}`);
    check("scan: chip row inside the width", hud.rowRight <= vp.w + 1, `row right ${hud.rowRight}`);
    if (SHOTS) await page.screenshot({ path: path.join(SHOT_DIR, `scan-${vp.w}x${vp.h}.png`) });

    // --- result, the longest text on any screen
    await page.evaluate(() => {
      const b = document.getElementById("revealBtn");
      if (b) b.click();
    });
    await new Promise(r => setTimeout(r, 3200));
    await page.evaluate(() => {
      const b = document.getElementById("doneBtn");
      if (b) b.click();
    });
    await new Promise(r => setTimeout(r, 300));
    o = await overflow(page, vp.w);
    check("result: nothing overflows sideways", o.elements.length === 0, o.elements.slice(0, 2).join("; "));
    clip = await clipped(page);
    check("result: long text fits or scrolls", clip.every(c => /auto|scroll/.test(c)), clip.slice(0, 2).join("; "));
    if (SHOTS) await page.screenshot({ path: path.join(SHOT_DIR, `result-${vp.w}x${vp.h}.png`) });

    await page.close();
  }

  await browser.close();
  srv.close();

  if (consoleErrors.length) {
    console.log(`\n${C.red}page errors:${C.off}`);
    consoleErrors.slice(0, 5).forEach(e => console.log("   " + e));
  }
  console.log(`\n${passed} passed, ${failed} failed`);
  if (SHOTS) console.log(`${C.dim}screenshots in screenshots/layout/${C.off}`);
  process.exit(failed ? 1 : 0);
})();
