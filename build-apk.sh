#!/usr/bin/env bash
#
# Wraps index.html in a Capacitor Android project and builds an APK.
#
# Works on Linux, macOS, WSL and Git Bash.
#
#   ./build-apk.sh              build a debug APK
#   ./build-apk.sh --install    build, then push it to a plugged-in phone
#   ./build-apk.sh --clean      throw away the generated project and start over
#   ./build-apk.sh --release    unsigned release APK (sign it before Play)
#   ./build-apk.sh --bundle     release AAB for the Play Store
#
set -euo pipefail

INSTALL=0; CLEAN=0; RELEASE=0; BUNDLE=0
APP_ID="com.tummyscanner.app"
APP_NAME="Tummy Scanner"
TARGET_SDK=36

while [ $# -gt 0 ]; do
  case "$1" in
    --install)     INSTALL=1 ;;
    --clean)       CLEAN=1 ;;
    --release)     RELEASE=1 ;;
    --bundle)      BUNDLE=1; RELEASE=1 ;;
    --app-id)      APP_ID="$2"; shift ;;
    --app-name)    APP_NAME="$2"; shift ;;
    --target-sdk)  TARGET_SDK="$2"; shift ;;
    -h|--help)     sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$ROOT/android-build"
AND="$PROJ/android"

cyan()  { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
info()  { printf '    \033[90m%s\033[0m\n' "$1"; }
warn()  { printf '    \033[33m! %s\033[0m\n' "$1"; }
die()   { printf '\n\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

# ------------------------------------------------------------------ checks ---
cyan "Checking prerequisites"

SRC=""
for candidate in index.html belly-scanner.html; do
  [ -f "$ROOT/$candidate" ] && { SRC="$ROOT/$candidate"; break; }
done
[ -n "$SRC" ] || die "No index.html (or belly-scanner.html) next to this script."
info "app  $(basename "$SRC")"

command -v node >/dev/null 2>&1 || die "node not found. Install Node.js 20+ from https://nodejs.org"
command -v npm  >/dev/null 2>&1 || die "npm not found. It ships with Node.js."

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 20 ] || warn "Node $NODE_MAJOR detected; Capacitor wants 20+. The build may fail."
info "node $(node -v)"

# --- Android SDK ---
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ]; then
  for guess in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "$LOCALAPPDATA/Android/Sdk"; do
    [ -d "$guess" ] && { SDK="$guess"; break; }
  done
fi
[ -n "$SDK" ] && [ -d "$SDK" ] || die \
"Android SDK not found.
    Install Android Studio (https://developer.android.com/studio), open it once so it
    downloads the SDK, then re-run. Or set ANDROID_HOME to an existing SDK folder."
info "SDK  $SDK"

# --- JDK: Android Studio bundles one ---
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME:-}/bin/java" ]; then
  for guess in \
    "/opt/android-studio/jbr" \
    "/usr/local/android-studio/jbr" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "$HOME/android-studio/jbr" \
    "/c/Program Files/Android/Android Studio/jbr" \
    "/usr/lib/jvm/java-17-openjdk-amd64"
  do
    [ -x "$guess/bin/java" ] && { export JAVA_HOME="$guess"; break; }
  done
fi
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  command -v java >/dev/null 2>&1 || die "No JDK found. Install Android Studio (it bundles one) or JDK 17, then set JAVA_HOME."
  warn "JAVA_HOME unset; falling back to java on PATH"
else
  info "JDK  $JAVA_HOME"
fi

# ------------------------------------------------------------------- clean ---
if [ "$CLEAN" = "1" ] && [ -d "$PROJ" ]; then
  cyan "Removing the generated project"
  rm -rf "$PROJ"
fi

# ---------------------------------------------------------------- scaffold ---
if [ ! -f "$PROJ/package.json" ]; then
  cyan "Creating the Capacitor project (first run - takes a few minutes)"
  mkdir -p "$PROJ"
  ( cd "$PROJ"
    npm init -y >/dev/null
    info "Installing Capacitor..."
    npm install --silent @capacitor/core@latest @capacitor/android@latest
    npm install --silent --save-dev @capacitor/cli@latest )
fi

cyan "Copying the app"
mkdir -p "$PROJ/www"
cp "$SRC" "$PROJ/www/index.html"
info "$(basename "$SRC") -> www/index.html"

# androidScheme https gives the WebView a secure origin, which getUserMedia needs
cat > "$PROJ/capacitor.config.json" <<JSON
{
  "appId": "$APP_ID",
  "appName": "$APP_NAME",
  "webDir": "www",
  "server": { "androidScheme": "https" },
  "android": {
    "allowMixedContent": false,
    "backgroundColor": "#0b1220",
    "webContentsDebuggingEnabled": true
  }
}
JSON

if [ ! -d "$AND" ]; then
  cyan "Adding the Android platform"
  ( cd "$PROJ" && npm exec -- cap add android )
fi

# -------------------------------------------------------- manifest patches ---
# Done with node rather than sed: it's already a hard dependency, and sed's
# in-place and escaping behaviour differs between GNU, BSD and Git Bash.
cyan "Patching the Android manifest"
MANIFEST="$AND/app/src/main/AndroidManifest.xml"
[ -f "$MANIFEST" ] || die "AndroidManifest.xml missing - try ./build-apk.sh --clean"

node -e '
const fs = require("fs");
const p = process.argv[1];
let m = fs.readFileSync(p, "utf8");
const decls = [
  ["android.permission.CAMERA",     `<uses-permission android:name="android.permission.CAMERA" />`],
  ["android.permission.VIBRATE",    `<uses-permission android:name="android.permission.VIBRATE" />`],
  [`android.hardware.camera"`,      `<uses-feature android:name="android.hardware.camera" android:required="false" />`],
  ["android.hardware.camera.flash", `<uses-feature android:name="android.hardware.camera.flash" android:required="false" />`],
  // Motion sensors need no runtime permission on Android, but declaring them
  // optional keeps the Play listing open to devices without a gyroscope.
  ["android.hardware.sensor.accelerometer", `<uses-feature android:name="android.hardware.sensor.accelerometer" android:required="false" />`],
  ["android.hardware.sensor.gyroscope",     `<uses-feature android:name="android.hardware.sensor.gyroscope" android:required="false" />`]
];
const added = [];
for (const [key, xml] of decls) {
  if (!m.includes(key)) { m = m.replace("</manifest>", "    " + xml + "\n</manifest>"); added.push(key.split(".").pop().replace(/"/g,"")); }
}
if (!/android:screenOrientation/.test(m)) {
  m = m.replace(/(<activity\b)/, `$1\n            android:screenOrientation="portrait"`);
  added.push("portrait");
}
fs.writeFileSync(p, m);
console.log("    \x1b[90m" + (added.length ? "added: " + added.join(", ") : "already patched") + "\x1b[0m");
' "$MANIFEST"

# --- target SDK: Play requires 36 for new submissions from 31 Aug 2026 ---
VARS="$AND/variables.gradle"
if [ -f "$VARS" ]; then
  node -e '
  const fs = require("fs");
  const [p, want] = [process.argv[1], parseInt(process.argv[2], 10)];
  let v = fs.readFileSync(p, "utf8"); const before = v;
  for (const k of ["compileSdkVersion", "targetSdkVersion"]) {
    const m = v.match(new RegExp(k + "\\s*=\\s*(\\d+)"));
    if (m && parseInt(m[1], 10) < want) v = v.replace(new RegExp(k + "\\s*=\\s*\\d+"), k + " = " + want);
  }
  if (v !== before) { fs.writeFileSync(p, v); console.log("    \x1b[90mbumped compile/target SDK to " + want + "\x1b[0m"); }
  else console.log("    \x1b[90mSDK levels already at or above " + want + "\x1b[0m");
  ' "$VARS" "$TARGET_SDK"
fi

# --- launcher icons ---
RES="$AND/app/src/main/res"
if [ -d "$ROOT/android-assets" ]; then
  cyan "Installing launcher icons"
  for dir in "$ROOT/android-assets"/*/; do
    name="$(basename "$dir")"
    mkdir -p "$RES/$name"
    cp -f "$dir"* "$RES/$name/"
  done
  rm -f "$RES/drawable/ic_launcher_background.xml"   # stock vector would shadow our colour
  info "icons copied from android-assets/"
else
  warn "android-assets/ not found - run 'node tools/make-icons.js' to generate icons"
fi

# --- app label ---
STRINGS="$RES/values/strings.xml"
if [ -f "$STRINGS" ]; then
  node -e '
  const fs = require("fs");
  const [p, name] = [process.argv[1], process.argv[2]];
  let s = fs.readFileSync(p, "utf8");
  s = s.replace(/(<string name="app_name">)[^<]*(<\/string>)/, "$1" + name + "$2");
  s = s.replace(/(<string name="title_activity_main">)[^<]*(<\/string>)/, "$1" + name + "$2");
  fs.writeFileSync(p, s);
  ' "$STRINGS" "$APP_NAME"
fi

printf 'sdk.dir=%s\n' "$SDK" > "$AND/local.properties"

# -------------------------------------------------------------------- sync ---
cyan "Syncing web assets into the Android project"
( cd "$PROJ" && npm exec -- cap sync android )

# ------------------------------------------------------------------- build ---
if [ "$BUNDLE" = "1" ]; then TASK="bundleRelease"; VARIANT="release"; EXT="aab"; OUTDIR="bundle/release"
elif [ "$RELEASE" = "1" ]; then TASK="assembleRelease"; VARIANT="release"; EXT="apk"; OUTDIR="apk/release"
else TASK="assembleDebug"; VARIANT="debug"; EXT="apk"; OUTDIR="apk/debug"; fi

cyan "Running gradle $TASK (the first build downloads a lot; later ones are fast)"
chmod +x "$AND/gradlew" 2>/dev/null || true
"$AND/gradlew" -p "$AND" "$TASK" --console=plain

# -------------------------------------------------------------------- copy ---
ARTIFACT="$(find "$AND/app/build/outputs/$OUTDIR" -name "*.$EXT" -type f 2>/dev/null | head -n1)"
[ -n "$ARTIFACT" ] || die "Build reported success but no .$EXT was produced."

DEST="$ROOT/tummy-scanner-$VARIANT.$EXT"
cp -f "$ARTIFACT" "$DEST"

cyan "Done"
printf '    \033[32m%s\033[0m\n' "$DEST"
info "$(du -h "$DEST" | cut -f1)"
[ "$RELEASE" = "1" ] && warn "This release build is UNSIGNED unless you configured signing - see BUILD.md"

# ----------------------------------------------------------------- install ---
if [ "$INSTALL" = "1" ]; then
  [ "$EXT" = "apk" ] || die "--install needs an APK; drop --bundle."
  cyan "Installing on the connected phone"
  ADB="$SDK/platform-tools/adb"
  [ -x "$ADB" ] || ADB="$(command -v adb || true)"
  [ -n "$ADB" ] || die "adb not found - install 'Android SDK Platform-Tools' via Android Studio."

  if ! "$ADB" devices | awk 'NR>1 && $2=="device"' | grep -q .; then
    die "No phone detected.
    On the phone: Settings > About phone > tap 'Build number' seven times,
    then Settings > Developer options > enable USB debugging.
    Plug it in and accept the 'Allow USB debugging?' prompt."
  fi
  "$ADB" install -r "$DEST"
  printf '    \033[32mInstalled. Look for "%s" in the app drawer.\033[0m\n' "$APP_NAME"
fi
