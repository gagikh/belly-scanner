# Plans — parked ideas and open questions

Things considered and deliberately deferred, with the reasoning, so we don't
re-litigate them from scratch later. Ordered roughly by expected value.

---

## Parked

### Recognise which child is being scanned, automatically
**Status:** postponed — hard, and the manual picker already solves it.

With three kids, whoever gets scanned second would inherit the first one's streak.
That's fixed: each child is a profile with its own history, chosen on the home screen.

Doing it automatically means face recognition (camera is pointed at a belly, not a face)
or identifying a child by their torso, which is unreliable, and it means storing
biometric data about minors — which drags in a large amount of privacy law and would
force the "collects nothing" privacy policy to become something much more complicated.
The manual tap costs one second and carries none of that.

**Revisit if:** picking the child every time becomes annoying in practice. A cheaper
middle ground would be remembering the last child scanned and defaulting to the next one
in the list, or a "scan all three" mode that walks through them in turn.

---

### Mask matching for tracking
**Status:** promising, unstarted — the best answer to the zoom problem.

The body silhouette is strongly visible, and matching it has a real advantage over the
current approach:

- Current tracking integrates frame-to-frame motion, so error accumulates with nothing
  to correct it, and it only measures translation.
- Template matching a saved patch was rejected because moving the phone closer rescales
  the patch and the match fails.
- **Mask statistics dodge both problems.** The mask centroid gives absolute position, not
  an integral, so drift cannot accumulate. The square root of the mask area gives scale
  directly, which is exactly the zoom that breaks template matching. Second moments give
  approximate rotation.

Likely architecture: keep optical flow for fine, fast motion, and use mask centroid,
area and orientation as a slow absolute correction — dead reckoning corrected by GPS.

**Caveats to solve:** the centroid shifts when the torso is partly out of frame, so it
needs a "mask touches the frame edge" check before trusting it. The mask itself is
currently a single global brightness threshold, which is the weakest link and would
probably need an adaptive local threshold first.

**Revisit when:** we have real `TRK` / drift numbers from a phone. No point optimising
tracking that might already be adequate.

---

### ~~An alert sound when a worm is found~~
**Status:** done — two-note sonar ping, synthesised, repeating every 3.2s while a worm
is on screen. Silent the moment the tummy is clear or the scan ends. Reasoning below.

Tuning lives in one place if it needs adjusting: `sonarPing()` for the tone, `PING_EVERY`
for the interval, and the `noiseGain` values for the scanner hiss.

Currently the app makes only the scanner hiss, by deliberate choice.

**Recommendation: synthesise it rather than bundle an audio file.** The app is one
self-contained HTML file with an existing WebAudio engine. A downloaded clip means an
asset to ship, a licence to comply with and attribution to track, for a sound we can
generate in about fifteen lines. Synthesised also means we can tune it precisely rather
than picking the least-bad clip from a library.

**The real question is how alarming it should be.** A harsh medical-alarm sound attached
to "there is something wrong inside your body" is a plausible way to make a young child
anxious about eating, which is the exact opposite of the point. Suggested instead: a soft
two-note sonar ping at the moment of the reveal — noticeable and a bit dramatic, over in
half a second, closer to a game sound than a hospital one. And nothing repeating: a
looping alarm while a worm is on screen would be genuinely distressing.

**Open:** confirm the tone, then implement.

---

### Rotation and zoom in tracking
**Status:** unstarted, partly superseded by mask matching above.

Block matching sees translation only. Rotate the phone and the worms stay upright; move
closer and they don't grow. The gyroscope measures roll well and is unused for this, so a
hybrid — vision for position, gyro for rotation — would be cheap. Zoom is better handled
by mask area, per the section above.

---

### Translation (Armenian / Russian)
**Status:** unstarted.

Every string is inline in `index.html`. Lifting them into one table would make adding a
language an afternoon's work, and matters for a Play listing beyond English speakers.

---

## Done, for reference

- Ultrasound rendering, worms clipped inside the beam
- Manual scan reveal — the scan never stops on its own
- Optical-flow tracking with confidence gating
- Navel detection, with tap-to-place override (essential for toddlers)
- Body mask, keeping worms on the tummy
- On-device CV tuning panel
- Per-child profiles with independent daily streaks
- Launcher icons and Play Store art
- Privacy policy

---

## Before Google Play

- [x] App icon and adaptive icon at all densities
- [x] Feature graphic, 1024x500
- [x] Privacy policy, hosted
- [ ] Screenshots — at least 2, phone-sized
- [ ] Signed release AAB (see `BUILD.md`)
- [ ] Data safety form — answer "no data collected" throughout
- [ ] Content rating questionnaire
- [ ] Store listing must say **pretend / entertainment**, never imply real detection
- [ ] 12 testers opted in for 14 continuous days, if the Play account is personal and
      was created after November 2023
- [ ] Target API 36, required for new submissions from 31 August 2026
