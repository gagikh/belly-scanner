# 🪱 Tummy Scanner 3000

A pretend ultrasound for your phone. Point the camera at your kid's belly, scan,
and watch a wriggler show up on screen — because of what they ate today.

**▶ [Try it: gagikh.github.io/belly-scanner](https://gagikh.github.io/belly-scanner/index.html)**

> Open it on an **Android phone in Chrome**. It needs camera permission, and the
> flashlight button only works where the browser exposes torch control (Android does,
> iOS Safari doesn't).

![The scanner with two wrigglers](preview.png)

*An actual frame from the app — the tissue here is a stand-in image, since the render
was captured without a camera attached.*

---

## The idea

Telling a five-year-old that sugar is bad does nothing. Showing them a worm in their
own belly, live, on a scanner that responds to what they ate — that lands.

The lesson is in the cause and effect, not in the scare. So:

1. **A grown-up ticks off what the child ate today** — before the scan, out of sight
   of the punchline.
2. **The scan runs** with a moving beam and a hiss, for as long as you like.
3. **You tap "SEE INSIDE"** when the suspense peaks.
4. **0, 1 or 2 wrigglers appear.** Never more — a swarm is frightening rather than
   instructive, and the point is that this is fixable.
5. **The verdict names the actual food**: *"Today you had cola and chips. That's exactly
   what the wrigglers like to eat. Swap one sugary thing for water tomorrow and scan again."*

All healthy? The tummy comes back clear, and the app says why.

---

## How to use it

**Set up.** Dim the room a little and use bare skin — the app turns the flashlight on
by itself, and the torch on skin is what gives it something to lock onto. Have the child
lie down. Tick the food list *before* you hand the phone over, so the result isn't
given away.

**Hold the phone flat**, screen up, roughly **20–30 cm above the tummy**, parallel to
the belly rather than tilted at it. Too close and it can't focus; too far and the navel
gets too small to detect.

**Put the navel in the middle of the screen** and hold still for a second or two. The
footer reads `SEEKING…` while it looks, then `NAVEL LOCK` with a dashed target ring over
the belly button. That's your cue.

**Tap 👁️ SEE INSIDE** when the suspense has built — the scan never stops on its own, so
take as long as you like.

**Keep the navel in view afterwards.** The worms are pinned to the belly, not to the
screen, and the app holds them there by tracking the picture. Move the phone slowly and
smoothly. Sweep away and the worms slide off the edge; come back and they're still where
they were.

**Tap anywhere on the tummy** to send the nearest worm to that spot and pin it there —
handy for putting one right on the belly button. Tapping also re-points the autofocus.

**❄️ Hold** freezes the picture so you can lift the phone away and show the other child.
**📸** saves the scan, and every reveal saves one automatically — **📁 Saved scans** on
the home screen keeps the last 8.

**WHAT DOES IT MEAN?** ends the scan with the verdict and the food that caused it.

### If it isn't working

The footer readout tells you which part is struggling:

| Footer shows | What it means | What to do |
|---|---|---|
| `SEEKING…` | No navel found yet | More light, bare skin, move to 20–30 cm, centre the navel, hold still |
| `NAVEL LOCK` | Belly button found | Go ahead and reveal |
| `TRK WEAK` | Too little detail to track | Keep the torch on; back off if the skin is blown out white; move slower |
| `TRK LOCK` | Worms are holding position | Nothing to do |
| `** MOVING **` | Being shaken | Slow down — fast movement outruns the tracker |

Other things worth knowing:

- **Flashlight button does nothing?** Some browsers don't allow torch control. Android
  Chrome does; iOS Safari doesn't. The installed APK always does.
- **Worms drift slowly off the spot?** Point at an area with some texture — a freckle,
  a fold, the navel itself. A perfectly flat, evenly lit patch of skin has nothing to
  track against.
- **Camera won't start?** It only works on `https://` or `localhost`. Opening the file
  directly from the filesystem won't do.

---

## What's in it

**Ultrasound, not sci-fi.** The camera feed is desaturated and contrast-pushed, masked
into a curved-probe fan, grained with speckle, and framed with a depth ruler and machine
readouts. Worms render in the same greyscale and sit *under* the speckle pass, so they
read as being in the tissue rather than stickers on the glass.

**Motion sensors.** Tilting the phone pans the image; the worms slide with it at 82% of
that, which gives them depth. The tilt shows live in the readout as `Probe -9°`. Shake it
and the image blurs, the readout flips to `** MOVING **`, and it tells you to hold steadier.

**Hold and keep.** ❄️ freezes the frame (parallax and all) so you can take the phone off
the belly and show it around. 📸 saves a scan, and every reveal auto-saves — the last 8 live
in the gallery, so the second kid can see the same scan later.

**Runs on cheap phones.** Watches its own frame rate and sheds resolution and blur once if
it can't hold 26fps.

**One file, no dependencies.** No frameworks, no CDN, no build step for the web version.
Nothing leaves the device — saved scans sit in the browser's local storage.

---

## Build an Android APK

```powershell
.\build-apk.ps1 -Install
```

Wraps the HTML in a Capacitor shell, patches the manifest, builds, and pushes it to a
plugged-in phone. First run takes a few minutes; later ones about 20 seconds.

Prerequisites and the faster edit-test loop are in **[BUILD.md](BUILD.md)**.

---

## Files

| | |
|---|---|
| `index.html` | The entire app. |
| `build-apk.ps1` | Scaffolds a Capacitor project and builds an APK. |
| `BUILD.md` | Setup, switches, and Play Store notes. |
| `preview.png` | The screenshot above. |

`android-build/` is generated and gitignored.

---

## Not a medical device

This is a game. It does not detect anything, look inside anyone, or emit ultrasound —
it's the phone camera with a filter over it. Don't let a child believe otherwise, and
don't use it to talk about actual illness.

The nutrition messages are deliberately gentle: no food is called bad, nothing is
forbidden, and every result ends with something the child can do tomorrow. Kids form
lasting attitudes to food early, and fear isn't the tool you want.
