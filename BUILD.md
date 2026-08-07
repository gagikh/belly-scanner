# Building Tummy Scanner as an Android app

`index.html` is the whole app. `build-apk.ps1` wraps it in a
[Capacitor](https://capacitorjs.com) shell and produces an installable APK.

---

## One-time setup

| Need | Where | Notes |
|---|---|---|
| **Node.js 20+** | <https://nodejs.org> | LTS installer. Reopen PowerShell afterwards. |
| **Android Studio** | <https://developer.android.com/studio> | Open it once and let it finish downloading the SDK. This also gives you the JDK and `adb`, so you don't need to install those separately. |

The script finds the SDK at `%LOCALAPPDATA%\Android\Sdk` (or `ANDROID_HOME`) and
the JDK bundled with Android Studio. If you keep them elsewhere, set `ANDROID_HOME`
and `JAVA_HOME` and it will use those instead.

---

## Build it

```powershell
cd D:\Projects\Kids
.\build-apk.ps1
```

First run scaffolds the project and downloads Gradle — expect **5–15 minutes**.
Every run after that is **~20 seconds**, because it only re-copies the HTML and rebuilds.

Result: `tummy-scanner-debug.apk` next to the script.

### Put it on the phone

```powershell
.\build-apk.ps1 -Install
```

Requires USB debugging: on the phone, *Settings → About phone → tap "Build number"
seven times*, then *Settings → Developer options → USB debugging*. Plug in and accept
the prompt.

No cable? Copy the `.apk` to the phone and tap it — Android will ask you to allow
installs from that source.

### Other switches

```powershell
.\build-apk.ps1 -Clean      # delete android-build\ and scaffold from scratch
.\build-apk.ps1 -Release    # unsigned release APK — must be signed before Play upload
.\build-apk.ps1 -AppName "Belly Scanner" -AppId com.yourname.bellyscanner
```

---

## Faster loop while tweaking the app

Rebuilding for a one-line CSS change is tedious. Instead, serve the file from your
PC and view it on the phone over USB:

```powershell
cd D:\Projects\Kids
npx http-server -p 8080 .
# in a second window:
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080
```

Then open `http://localhost:8080/index.html` in Chrome **on the phone**.
`localhost` counts as a secure origin, so the camera, flashlight and motion sensors
all work — no HTTPS certificate needed. Edit, save, pull-to-refresh.

Debugging the app inside the APK works too: with the phone plugged in, open
`chrome://inspect` on your PC. Web debugging is left on in the config.

---

## What the script changes in the Android project

- **Permissions** — `CAMERA`, `VIBRATE`; camera and flash declared `required="false"`
  so the Play listing isn't restricted to devices that have them.
- **Portrait lock** — the scanner is held upright.
- **`androidScheme: https`** — the WebView serves the app from `https://localhost`.
  Without this the origin isn't secure and `getUserMedia` refuses to start.
- **compileSdk / targetSdk → 36** — Google Play requires Android 16 (API 36) for new
  submissions from **31 August 2026**.
- **App label** — from `-AppName`.

Everything lives in `android-build\`, which is regenerated on demand. Only
`index.html`, `build-apk.ps1` and this file are worth keeping in version
control; add `android-build/` and `*.apk` to `.gitignore`.

---

## Before Google Play

The debug APK is for your own phone only. For the store you still need to:

1. Generate an upload key and sign a **release AAB** (`bundleRelease`, not `assembleDebug`).
2. Write a privacy policy URL and complete the Data safety form. The app stores saved
   scans in the WebView's local storage on the device and sends nothing anywhere,
   which makes this short.
3. Set the content rating and complete the **Families** policy questionnaire if you
   target children.
4. Make the store listing say clearly that this is a **pretend / entertainment**
   scanner. Fake body-scanner apps get rejected under Play's Deceptive Behavior
   policy when the listing implies real detection.
5. If your Play account is a personal one created after November 2023: run a closed
   test with **12 testers opted in for 14 continuous days** before you can apply for
   production access.
