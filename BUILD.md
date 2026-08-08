# Building Tummy Scanner as an Android app

`index.html` is the whole app. `build-apk.sh` wraps it in a
[Capacitor](https://capacitorjs.com) shell and produces an installable APK.

The script runs on Linux, macOS, WSL and Git Bash. On Windows, **Git Bash** ships with
[Git for Windows](https://git-scm.com/download/win) and is the easiest option.

---

## One-time setup

| Need | Where | Notes |
|---|---|---|
| **Node.js 20+** | <https://nodejs.org> | LTS installer. Reopen your shell afterwards. |
| **Android Studio** | <https://developer.android.com/studio> | Open it once and let it finish downloading the SDK. This also gives you the JDK and `adb`, so you don't need to install those separately. |

The script looks for the SDK in `ANDROID_HOME`, then `~/Android/Sdk`,
`~/Library/Android/sdk` and `%LOCALAPPDATA%/Android/Sdk`, and finds the JDK bundled with
Android Studio. If you keep them elsewhere, set `ANDROID_HOME` and `JAVA_HOME`.

---

## Build it

Two wrappers cover everything; you shouldn't need `build-apk.sh` directly.

```bash
cd /path/to/Kids             # Git Bash spells D:\Projects\Kids as /d/Projects/Kids

./build-debug.sh             # APK for your own phone — no signing needed
./build-release.sh           # signed AAB for Play + signed APK, key created on first run
```

`build-apk.sh` is the engine underneath and still takes all the options below if you
need one of them.

### Settings

Everything configurable lives in **`build.conf`** beside the scripts — app id, display
name, output filename prefix, target SDK, keystore name and alias, privacy URL. Any of
them can be overridden per-run by an environment variable of the same name:

```bash
APP_NAME="Belly Scanner" APP_ID=com.yourname.belly ./build-debug.sh
```

No absolute path is written down anywhere. Locations are resolved relative to the
scripts, or discovered from `ANDROID_HOME` / `JAVA_HOME` (falling back to the standard
Android Studio install locations for your OS).

First run scaffolds the project and downloads Gradle — expect **5–15 minutes**.
Every run after that is **~20 seconds**, because it only re-copies the HTML and rebuilds.

Result: `tummy-scanner-debug.apk` next to the script.

### Put it on the phone

```bash
./build-apk.sh --install
```

Requires USB debugging: on the phone, *Settings → About phone → tap "Build number"
seven times*, then *Settings → Developer options → USB debugging*. Plug in and accept
the prompt.

No cable? Copy `tummy-scanner-debug.apk` to the phone and tap it — Android will ask you
to allow installs from that source. This needs no developer mode at all and is the
easiest route.

### Xiaomi / HyperOS

Xiaomi renames things. There is no "Build number":

1. *Settings → About phone →* tap **HyperOS version** seven times.
2. Developer options then live under *Settings → **Additional settings** → Developer
   options* — not at the top level.
3. Turn on **USB debugging**, and also **Install via USB** if you want `--install` to
   work. The second one often insists you sign in to a Mi account first.
4. Plug in, then pull down the notification shade and switch the USB mode from
   *Charging* to **File transfer**. `adb` won't see the phone in charging mode.

If "Install via USB" gives you trouble — it's the usual sticking point on Xiaomi — skip
`--install` and just copy the debug APK across and tap it.

### Options

```bash
./build-apk.sh --clean                          # delete android-build/ and start over
./build-apk.sh --release                        # release APK (sign it before Play upload)
./build-apk.sh --bundle                         # release AAB, the format Play wants
./build-apk.sh --app-name "Belly Scanner" --app-id com.yourname.bellyscanner
./build-apk.sh --target-sdk 36
./build-apk.sh --help
```

If bash reports `permission denied`, run `chmod +x build-apk.sh` once.

### Windows path handling

Under Git Bash the shell speaks POSIX paths (`/c/Users/...`) while Java, Gradle and adb
are Windows programs that reject them. The script detects this and converts: `JAVA_HOME`
and `sdk.dir` are written as `C:/Users/...`, and the build runs through `gradlew.bat`
rather than the POSIX `gradlew`.

If you see this, that conversion is what failed:

```
Could not determine the dependencies of task ':app:compileDebugJavaWithJavac'.
> java.io.IOException: The filename, directory name, or volume label syntax is incorrect
```

Check `android-build/android/local.properties` — `sdk.dir` must look like
`C:/Users/you/AppData/Local/Android/Sdk`, with forward slashes and a drive letter. Never
`/c/Users/...`, and never backslashes (a `.properties` file treats `\` as an escape, so
`C:\Users` silently becomes `C:Users`).

The `WARNING: Using flatDir should be avoided` line above it comes from Capacitor's own
Cordova compatibility module. It's harmless and not related.

### SDK licences

On a fresh machine the first build stops while "Checking the license for package …".
Gradle will happily download the SDK pieces it needs, but not until the licences have
been accepted:

```bash
./build-apk.sh --accept-licenses
```

That runs `sdkmanager --licenses` and answers yes, then carries on with the build. If it
reports that `sdkmanager` is missing, install it in Android Studio: *Settings → Languages
& Frameworks → Android SDK → SDK Tools → **Android SDK Command-line Tools***.

You only need to do this once per machine. The script warns you up front if `licenses/`
is empty or the `android-36` platform isn't installed, rather than letting the build
stall halfway.

### "App not installed as package appears to be invalid"

Android's catch-all for "I won't accept this file". In order of likelihood:

1. **You installed the release build.** `--release` produces an *unsigned* APK, and
   Android rejects unsigned packages with exactly this message. For testing on your own
   phone use the plain debug build:

   ```bash
   ./build-apk.sh --install
   ```

   The script now runs `apksigner verify` after every build and warns if the APK is
   unsigned, so you'll see it before copying anything to the phone.

2. **You installed the `.aab`.** A bundle is for uploading to Play, not for installing.
   Only `tummy-scanner-debug.apk` (or a properly signed release APK) can be sideloaded.

3. **A previous version is installed with a different signing key** — for example a debug
   build followed by a release one. Uninstall the old app first.

**Get the real reason** by installing over USB instead of tapping the file. `adb` prints
the actual failure code, which is far more specific than the phone's message:

```bash
adb install -r tummy-scanner-debug.apk
# e.g. INSTALL_PARSE_FAILED_NO_CERTIFICATES  -> unsigned
#      INSTALL_FAILED_UPDATE_INCOMPATIBLE    -> signature mismatch, uninstall first
#      INSTALL_FAILED_INSUFFICIENT_STORAGE   -> phone is full
```

Also check the file actually transferred completely — a truncated copy produces the same
message. The APK should be a few megabytes; the script prints the size when it finishes.

### "SDK XML file of version 4 was encountered"

Harmless. Your command-line tools are newer than the Android Gradle Plugin that
Capacitor pins, so AGP's parser doesn't recognise the newest repository format. It
doesn't affect the build. It goes away if you upgrade AGP in
`android-build/android/build.gradle`, which isn't worth doing unless something else
needs it.

---

## Faster loop while tweaking the app

Rebuilding for a one-line CSS change is tedious. Instead, serve the file from your
computer and view it on the phone over USB:

```bash
npx http-server -p 8080 .
# in a second terminal:
adb reverse tcp:8080 tcp:8080
```

Then open `http://localhost:8080` in Chrome **on the phone**. `localhost` counts as a
secure origin, so the camera, flashlight and motion sensors all work — no HTTPS
certificate needed. Edit, save, pull-to-refresh.

Debugging the app inside the APK works too: with the phone plugged in, open
`chrome://inspect` on your computer. Web debugging is left on in the config.

---

## What the script changes in the Android project

- **Permissions** — `CAMERA`, `VIBRATE`. Camera, flash, accelerometer and gyroscope are
  declared `required="false"` so the Play listing isn't narrowed to devices that have
  them. Motion sensors need no runtime permission on Android.
- **Portrait lock** — the scanner is held upright.
- **`androidScheme: https`** — the WebView serves the app from `https://localhost`.
  Without this the origin isn't secure and `getUserMedia` refuses to start.
- **compileSdk / targetSdk → 36** — Google Play requires Android 16 (API 36) for new
  submissions from **31 August 2026**.
- **Launcher icons** — copied from `android-assets/`.
- **App label** — from `--app-name`.

Everything lives in `android-build/`, which is regenerated on demand. Only
`index.html`, `build-apk.sh`, `tools/`, `android-assets/`, `store/` and the docs are
worth keeping in version control; `android-build/` and `*.apk` are gitignored.

---

## Icons

`android-assets/` holds the launcher icons at every density, and `store/` holds the
512x512 listing icon and the 1024x500 feature graphic. `build-apk.sh` copies
`android-assets/` into the project on every build; the `store/` files are uploaded to
Play by hand.

To change the artwork, edit `tools/make-icons.js` and re-run it:

```bash
npm i @napi-rs/canvas
node tools/make-icons.js
```

---

## Signing a release build

Debug APKs install on your own phone but Play will not accept them, and an *unsigned*
release APK won't install anywhere. `build-release.sh` handles all of it:

```bash
./build-release.sh              # AAB for Play + APK you can sideload
./build-release.sh --aab-only
./build-release.sh --apk-only
```

On the **first** run it creates an upload key (`tummy-upload.jks`, RSA 2048, ~27 years)
with a randomly generated password, writes `keystore.properties`, and locks both files
down. Every run after that reuses them. `build-apk.sh` picks the properties file up and
injects the gradle signing config on each build, so `--clean` can't lose it.

> **Back up `tummy-upload.jks` and `keystore.properties`, off this machine.**
> Play ties your listing to this key. Lose it and you can never publish an update to the
> same app — you'd start a new listing and every existing install would be orphaned.

Both files are gitignored. Never commit them.

Overrides, if you'd rather supply your own:

```bash
KEYSTORE_FILE=my.jks KEY_ALIAS=upload KEYSTORE_PASSWORD=secret ./build-release.sh
```

If you point it at a keystore that already exists but has no `keystore.properties`, it
asks for the password rather than overwriting anything.

After every build `apksigner verify` runs and reports the result, so an unsigned APK is
caught before it reaches a phone.

---

## Data safety form

The app collects nothing, so every answer is the simple one:

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data encrypted in transit? | N/A — no data is transmitted |
| Do you provide a way for users to request that their data is deleted? | N/A — uninstalling removes everything |

Camera permission is declared, but the camera feed is processed on-device and never
leaves it, which is not "collection" under Play's definition. Privacy policy URL:
`https://gagikh.github.io/belly-scanner/privacy.html`

---

## Before Google Play

The debug APK is for your own phone only. For the store you still need to:

1. Sign a **release AAB** (above), not a debug APK.
2. Publish the privacy policy URL and complete the Data safety form.
3. Set the content rating and complete the **Families** policy questionnaire if you
   target children.
4. Make the store listing say clearly that this is a **pretend / entertainment**
   scanner. Fake body-scanner apps get rejected under Play's Deceptive Behavior
   policy when the listing implies real detection.
5. If your Play account is a personal one created after November 2023: run a closed
   test with **12 testers opted in for 14 continuous days** before you can apply for
   production access.
