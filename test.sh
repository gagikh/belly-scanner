#!/usr/bin/env bash
#
# Runs every check. Nothing here needs a phone or a camera.
#
#   ./test.sh              app logic + vision (fast, offline)
#   ./test.sh --layout     also layout in a real browser (downloads Chrome once)
#   ./test.sh --all        everything, including screenshots
#   ./test.sh --shots      layout screenshots into screenshots/layout/
#
# Exit code is non-zero if anything failed, so this is safe to use in a hook.
#
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

LAYOUT=0; SHOTS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --layout) LAYOUT=1 ;;
    --shots)  LAYOUT=1; SHOTS=1 ;;
    --all)    LAYOUT=1; SHOTS=1 ;;
    -h|--help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

cyan() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
info() { printf '    \033[90m%s\033[0m\n' "$1"; }
bad()  { printf '\033[31m%s\033[0m\n' "$1" >&2; }

FAILED=0
run() {                       # run <name> <command...>
  local name="$1"; shift
  cyan "$name"
  if "$@"; then
    return 0
  else
    FAILED=1
    bad "    ^ $name failed"
    return 1
  fi
}

# ------------------------------------------------------------------ checks ---
command -v node >/dev/null 2>&1 || { bad "node not found. Install Node.js 20+."; exit 1; }

if [ ! -d node_modules ]; then
  cyan "Installing dev dependencies (first run)"
  npm install --include=optional || { bad "npm install failed"; exit 1; }
fi

# @napi-rs/canvas ships a compiled binary per platform. If this checkout is
# shared between operating systems — WSL and Windows, say — whichever installed
# last wins and the other gets a cryptic "native binding" error mid-run.
if ! node -e 'require("@napi-rs/canvas")' >/dev/null 2>&1; then
  bad ""
  bad "@napi-rs/canvas can't load its native binary."
  ls node_modules/@napi-rs 2>/dev/null | grep -q "canvas-" && \
    info "installed for: $(ls node_modules/@napi-rs | grep 'canvas-' | tr '\n' ' ')"
  info "You get this if node_modules was installed on a different OS, or from"
  info "the npm optional-dependency bug. Either way:"
  bad ""
  bad "    npm run reinstall"
  bad ""
  exit 1
fi

# The vision bench needs rendered clips. Generate them if they're missing;
# they're gitignored, so a fresh checkout won't have any.
if [ ! -d tools/testdata ]; then
  cyan "Rendering test clips (first run)"
  node tools/make-test-clips.js || { bad "could not render clips"; exit 1; }
fi

# --------------------------------------------------------------- 1. syntax ---
cyan "Syntax"
node -e '
const fs = require("fs"), vm = require("vm");
const html = fs.readFileSync("index.html", "utf8");
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new vm.Script(js, { filename: "index.html <script>" });   // throws on a syntax error

// every $("id") must correspond to a real element
const ids  = new Set([...html.matchAll(/id="([\w-]+)"/g)].map(m => m[1]));
const refs = new Set([...html.matchAll(/\$\("([\w-]+)"\)/g)].map(m => m[1]));
const missing = [...refs].filter(r => !ids.has(r));
if (missing.length) throw new Error("$() refers to missing ids: " + missing.join(", "));

const dupes = [...ids].filter(i => (html.match(new RegExp(`id="${i}"`, "g")) || []).length > 1);
if (dupes.length) throw new Error("duplicate ids: " + dupes.join(", "));

// CSS braces balanced
const css = html.slice(html.indexOf("<style>"), html.indexOf("</style>"));
const open = (css.match(/{/g) || []).length, close = (css.match(/}/g) || []).length;
if (open !== close) throw new Error(`unbalanced CSS braces: ${open} vs ${close}`);

console.log("    index.html parses, ids resolve, CSS balanced");
' || FAILED=1

for f in tools/*.js; do
  node --check "$f" || { bad "    syntax error in $f"; FAILED=1; }
done
for f in *.sh; do
  bash -n "$f" || { bad "    syntax error in $f"; FAILED=1; }
done
info "shell scripts and tools parse"

# ----------------------------------------------------------- 2. app logic ----
run "App logic  (species, streak, profiles, tuning panel)" node tools/app-tests.js

# -------------------------------------------------------------- 3. vision ----
run "Vision  (navel, body mask, tracking drift vs ground truth)" node tools/cv-testbench.js

# -------------------------------------------------------------- 4. layout ----
if [ "$LAYOUT" = "1" ]; then
  if [ "$SHOTS" = "1" ]; then
    run "Layout  (8 viewports in headless Chrome, with screenshots)" node tools/responsive-test.js --shots
  else
    run "Layout  (8 viewports in headless Chrome)" node tools/responsive-test.js
  fi
else
  cyan "Layout"
  info "skipped - run ./test.sh --layout (needs to download Chrome once)"
fi

# ------------------------------------------------------------------ result ---
echo
if [ "$FAILED" = "0" ]; then
  printf '\033[32mall checks passed\033[0m\n'
else
  printf '\033[31msomething failed - see above\033[0m\n'
fi
exit $FAILED
