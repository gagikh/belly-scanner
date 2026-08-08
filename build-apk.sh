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
#   ./build-apk.sh --accept-licenses   accept the Android SDK licences, then build
#   ./build-apk.sh --doctor     list every JDK found and stop
#
set -euo pipefail

INSTALL=0; CLEAN=0; RELEASE=0; BUNDLE=0; ACCEPT_LICENSES=0; DOCTOR=0

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-lib.sh
. "$_SELF_DIR/build-lib.sh"
load_build_conf "$_SELF_DIR"

while [ $# -gt 0 ]; do
  case "$1" in
    --install)     INSTALL=1 ;;
    --clean)       CLEAN=1 ;;
    --accept-licenses) ACCEPT_LICENSES=1 ;;
    --doctor)      DOCTOR=1 ;;
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

# WINHOST, native_path and posix_path come from build-lib.sh: on Git Bash the shell
# speaks POSIX paths but Java, Gradle and adb are Windows-native and reject them.

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
# env vars may already hold Windows paths; normalise to POSIX for shell use
SDK="$(posix_path "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}")"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  SDK=""
  for guess in \
    "$HOME/Android/Sdk" \
    "$HOME/Library/Android/sdk" \
    "$(posix_path "${LOCALAPPDATA:-}")/Android/Sdk" \
    "$HOME/AppData/Local/Android/Sdk"
  do
    [ -n "$guess" ] && [ -d "$guess" ] && { SDK="$guess"; break; }
  done
fi
if [ -n "$SDK" ] && [ -d "$SDK" ]; then
  info "SDK  $SDK"
elif [ "$DOCTOR" = "1" ]; then
  warn "Android SDK not found"      # keep going: the whole point of --doctor is to report
else
  die "Android SDK not found.
    Install Android Studio (https://developer.android.com/studio), open it once so it
    downloads the SDK, then re-run. Or set ANDROID_HOME to an existing SDK folder."
fi

# --- JDK: Android Studio bundles one, wherever it happens to be installed ---
detect_java || true
JAVA_DIR="$JAVA_FOUND"
if [ -n "$JAVA_DIR" ] && [ -d "$JAVA_DIR/bin" ]; then
  # Gradle and the JVM launcher need this in native form, not /c/...
  export JAVA_HOME="$(native_path "$JAVA_DIR")"
  info "JDK  $JAVA_HOME (Java $(java_major "$JAVA_DIR" 2>/dev/null || echo '?'))"
  if [ "$JAVA_OUT_OF_RANGE" = "1" ]; then
    warn "This JDK is outside the Java $JAVA_MIN-$JAVA_MAX range Android tooling expects."
    warn "Trying anyway. If Gradle says 'Unsupported class file major version',"
    warn "install JDK 17 or 21 and set JAVA_HOME in build.local.conf."
  elif [ -n "$JAVA_REJECTED" ]; then
    info "skipped $JAVA_REJECTED - outside the Java $JAVA_MIN-$JAVA_MAX range"
  fi
elif [ "$DOCTOR" != "1" ]; then
  die "No JDK found at all.
    Install Android Studio (it bundles one), or set JAVA_HOME,
    or put the path in build.local.conf next to this script:
      JAVA_HOME=/path/to/Android Studio/jbr"
fi

# --- doctor: show every JDK found, then stop ---
if [ "$DOCTOR" = "1" ]; then
  cyan "JDKs found (Gradle needs Java $JAVA_MIN-$JAVA_MAX)"
  if [ "${#JAVA_CANDIDATES[@]}" -eq 0 ]; then
    echo "    none"
  else
    printf '%s\n' "${JAVA_CANDIDATES[@]}" | sort -t'|' -k1,1n -u | while IFS='|' read -r v p; do
      mark="  "
      [ "$v" != "?" ] && [ "$v" -ge "$JAVA_MIN" ] 2>/dev/null && [ "$v" -le "$JAVA_MAX" ] 2>/dev/null && mark="ok"
      printf '    [%s] Java %-3s %s\n' "$mark" "$v" "$p"
    done
  fi
  cyan "Chosen"
  echo "    JAVA_HOME = ${JAVA_HOME:-<none>}"
  [ "$JAVA_OUT_OF_RANGE" = "1" ] && echo "    (out of range - Gradle will probably fail)"
  cyan "Gradle wrapper"
  if [ -f "$AND/gradle/wrapper/gradle-wrapper.properties" ]; then
    grep distributionUrl "$AND/gradle/wrapper/gradle-wrapper.properties" | sed 's/^/    /'
  else
    echo "    not generated yet (run a build first)"
  fi
  cyan "Android SDK"
  echo "    ${SDK:-<not found>}"
  exit 0
fi

# --- SDK packages and licences ---
# Gradle downloads whatever platform/build-tools it needs, but it refuses to do so
# until the SDK licences have been accepted, and the error it gives is unhelpful.
find_sdkmanager() {
  for p in \
    "$SDK/cmdline-tools/latest/bin/sdkmanager" \
    "$SDK/cmdline-tools/bin/sdkmanager" \
    "$SDK/tools/bin/sdkmanager"
  do
    [ -f "$p" ]     && { printf '%s' "$p"; return 0; }
    [ -f "$p.bat" ] && { printf '%s' "$p.bat"; return 0; }
  done
  return 1
}

run_sdkmanager() {
  local sm; sm="$(find_sdkmanager)" || return 1
  case "$sm" in
    *.bat) ( cd "$(dirname "$sm")" && cmd //c "$(basename "$sm")" "$@" ) ;;
    *)     "$sm" "$@" ;;
  esac
}

if [ "$ACCEPT_LICENSES" = "1" ]; then
  cyan "Accepting Android SDK licences"
  if find_sdkmanager >/dev/null; then
    yes 2>/dev/null | run_sdkmanager --licenses || true
  else
    die "sdkmanager not found. In Android Studio: Settings > Languages & Frameworks >
    Android SDK > SDK Tools, tick 'Android SDK Command-line Tools', then re-run."
  fi
fi

if [ ! -d "$SDK/licenses" ] || [ -z "$(ls -A "$SDK/licenses" 2>/dev/null)" ]; then
  warn "No accepted SDK licences found - the build will stall. Run: ./build-apk.sh --accept-licenses"
fi
if [ ! -d "$SDK/platforms/android-$TARGET_SDK" ]; then
  warn "SDK platform android-$TARGET_SDK is not installed; Gradle will download it (needs licences)."
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

# Gradle reads this as a Java .properties file: backslashes would be escapes, so we
# write the native path with forward slashes (C:/Users/... works fine on Windows).
printf 'sdk.dir=%s\n' "$(native_path "$SDK")" > "$AND/local.properties"
info "sdk.dir=$(native_path "$SDK")"

# --- release signing --------------------------------------------------------
# If keystore.properties sits next to this script, wire signing in automatically.
# Doing it here rather than by hand matters because --clean regenerates
# app/build.gradle, which would silently throw away a manual edit.
if [ -f "$ROOT/keystore.properties" ]; then
  cyan "Configuring release signing"
  cp -f "$ROOT/keystore.properties" "$AND/keystore.properties"
  node -e '
  const fs = require("fs");
  const p = process.argv[1];
  let g = fs.readFileSync(p, "utf8");
  if (g.includes("// generated-signing-config")) { console.log("    \x1b[90malready configured\x1b[0m"); process.exit(0); }
  const block = `
    // generated-signing-config
    signingConfigs {
        release {
            def kp = new Properties()
            def kf = rootProject.file("keystore.properties")
            if (kf.exists()) { kp.load(new FileInputStream(kf)) }
            storeFile file(kp["storeFile"])
            storePassword kp["storePassword"]
            keyAlias kp["keyAlias"]
            keyPassword kp["keyPassword"]
        }
    }
`;
  if (!/android\s*\{/.test(g)) { console.error("    ! could not find the android block in build.gradle"); process.exit(1); }
  g = g.replace(/android\s*\{/, m => m + block);
  const before = g;
  g = g.replace(/(buildTypes\s*\{[\s\S]*?release\s*\{)/, "$1\n            signingConfig signingConfigs.release");
  if (g === before) { console.error("    ! no buildTypes.release block to attach the signing config to"); process.exit(1); }
  fs.writeFileSync(p, g);
  console.log("    \x1b[90msigning wired into app/build.gradle\x1b[0m");
  ' "$AND/app/build.gradle"
elif [ "$RELEASE" = "1" ]; then
  warn "No keystore.properties found - this release build will be UNSIGNED and will not install."
  warn "See BUILD.md, or just use the debug build for testing."
fi

# Pin Gradle to the JDK we chose. Relying on JAVA_HOME alone isn't enough: a
# Gradle daemon started earlier on a different JDK gets reused, so the build can
# fail on a JVM the script never selected.
if [ -n "${JAVA_HOME:-}" ]; then
  GP="$AND/gradle.properties"
  touch "$GP"
  grep -v '^org\.gradle\.java\.home=' "$GP" > "$GP.tmp" 2>/dev/null || true
  mv -f "$GP.tmp" "$GP" 2>/dev/null || true
  printf 'org.gradle.java.home=%s\n' "$JAVA_HOME" >> "$GP"

  # if the JDK changed since last time, kill stale daemons
  STAMP="$AND/.last-java-home"
  if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$JAVA_HOME" ]; then
    if [ -f "$AND/gradlew" ] || [ -f "$AND/gradlew.bat" ]; then
      info "JDK changed - stopping old Gradle daemons"
      if [ "$WINHOST" = "1" ]; then ( cd "$AND" && cmd //c gradlew.bat --stop >/dev/null 2>&1 ) || true
      else ( cd "$AND" && ./gradlew --stop >/dev/null 2>&1 ) || true; fi
    fi
    printf '%s' "$JAVA_HOME" > "$STAMP"
  fi
fi

# -------------------------------------------------------------------- sync ---
cyan "Syncing web assets into the Android project"
( cd "$PROJ" && npm exec -- cap sync android )

# ------------------------------------------------------------------- build ---
if [ "$BUNDLE" = "1" ]; then TASK="bundleRelease"; VARIANT="release"; EXT="aab"; OUTDIR="bundle/release"
elif [ "$RELEASE" = "1" ]; then TASK="assembleRelease"; VARIANT="release"; EXT="apk"; OUTDIR="apk/release"
else TASK="assembleDebug"; VARIANT="debug"; EXT="apk"; OUTDIR="apk/debug"; fi

cyan "Running gradle $TASK (the first build downloads a lot; later ones are fast)"
if [ "$WINHOST" = "1" ]; then
  # Use the Windows wrapper: the POSIX gradlew launches a native JVM that then gets
  # handed /c/... paths it cannot resolve.
  ( cd "$AND" && cmd //c gradlew.bat "$TASK" --console=plain )
else
  chmod +x "$AND/gradlew" 2>/dev/null || true
  "$AND/gradlew" -p "$AND" "$TASK" --console=plain
fi

# -------------------------------------------------------------------- copy ---
ARTIFACT="$(find "$AND/app/build/outputs/$OUTDIR" -name "*.$EXT" -type f 2>/dev/null | head -n1)"
[ -n "$ARTIFACT" ] || die "Build reported success but no .$EXT was produced."

DEST="$ROOT/$APP_SLUG-$VARIANT.$EXT"
cp -f "$ARTIFACT" "$DEST"

# --- verify it's actually installable ---------------------------------------
# An unsigned APK installs with the useless message "App not installed as package
# appears to be invalid", so check here where we can say something useful.
if [ "$EXT" = "apk" ]; then
  APKSIGNER=""
  for cand in "$SDK"/build-tools/*/apksigner "$SDK"/build-tools/*/apksigner.bat; do
    [ -f "$cand" ] && APKSIGNER="$cand"
  done
  if [ -n "$APKSIGNER" ]; then
    case "$APKSIGNER" in
      *.bat) SIGN_OK=$( ( cd "$(dirname "$APKSIGNER")" && cmd //c apksigner.bat verify "$(native_path "$DEST")" >/dev/null 2>&1 ) && echo yes || echo no ) ;;
      *)     SIGN_OK=$( "$APKSIGNER" verify "$DEST" >/dev/null 2>&1 && echo yes || echo no ) ;;
    esac
    if [ "$SIGN_OK" = "yes" ]; then
      info "signature OK"
    else
      warn "This APK is NOT SIGNED. Android will refuse it with 'package appears to be invalid'."
      warn "Use a debug build for testing, or set up signing - see BUILD.md."
    fi
  fi
fi

cyan "Done"
printf '    \033[32m%s\033[0m\n' "$DEST"
info "$(du -h "$DEST" | cut -f1)"

# ----------------------------------------------------------------- install ---
if [ "$INSTALL" = "1" ]; then
  [ "$EXT" = "apk" ] || die "--install needs an APK; drop --bundle."
  cyan "Installing on the connected phone"
  ADB="$SDK/platform-tools/adb"
  [ -x "$ADB" ] || ADB="$SDK/platform-tools/adb.exe"
  [ -x "$ADB" ] || ADB="$(command -v adb || true)"
  [ -n "$ADB" ] && [ -x "$ADB" ] || die "adb not found - install 'Android SDK Platform-Tools' via Android Studio."

  if ! "$ADB" devices | awk 'NR>1 && $2=="device"' | grep -q .; then
    die "No phone detected.
    On the phone: Settings > About phone > tap 'Build number' seven times,
    then Settings > Developer options > enable USB debugging.
    Plug it in and accept the 'Allow USB debugging?' prompt."
  fi
  "$ADB" install -r "$DEST"
  printf '    \033[32mInstalled. Look for "%s" in the app drawer.\033[0m\n' "$APP_NAME"
fi
