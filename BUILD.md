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

```bash
cd /d/Projects/Kids     # Git Bash spells D:\ as /d/
./build-apk.sh
```

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

No cable? Copy the `.apk` to the phone and tap it — Android will ask you to allow
installs from that source.

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

Debug APKs install on your own phone but Play will not accept them. Create an upload key
once:

```bash
"$JAVA_HOME/bin/keytool" -genkeypair -v \
    -keystore tummy-upload.jks -alias upload \
    -keyalg RSA -keysize 2048 -validity 10000
```

**Back that file up and never commit it.** Losing it means you can never update the app
under the same listing. `.gitignore` already excludes `*.jks`.

Then create `android-build/android/keystore.properties`:

```properties
storeFile=/d/Projects/Kids/tummy-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

and add the signing config to `android-build/android/app/build.gradle`, inside `android { }`:

```groovy
def keyProps = new Properties()
def keyFile = rootProject.file("keystore.properties")
if (keyFile.exists()) { keyProps.load(new FileInputStream(keyFile)) }

signingConfigs {
    release {
        storeFile file(keyProps['storeFile'])
        storePassword keyProps['storePassword']
        keyAlias keyProps['keyAlias']
        keyPassword keyProps['keyPassword']
    }
}
buildTypes {
    release { signingConfig signingConfigs.release }
}
```

Then build the bundle Play wants:

```bash
./build-apk.sh --bundle
# -> tummy-scanner-release.aab
```

Note that `--clean` deletes `android-build/`, including these edits. Keep a copy of the
gradle snippet and `keystore.properties` somewhere outside that folder.

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
