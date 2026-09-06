# HardwareTest1 — Fix Log

## What was reported

From `bugs/bugreports/HardwareTest1/report.md`: while testing on a physical
device (signed in with the project's Google account), the app landed on the
Map tab and immediately showed a garbled overlay, captured in
`MapScreen.HEIC`.

## What the screenshots actually show

All four screenshots (`MapScreen`, `ProfileScreen`, `LeaderboardScreen`,
`ReportSightingScreen`) were HEIC and were converted to PNG for inspection
(`pillow-heif`, kept alongside the originals for reference — see note at the
bottom).

**`MapScreen.HEIC`** is the only one with a problem. Zooming into the overlay
shows a yellow warning-triangle icon, a reload icon, and monospaced
diagnostic text:

```
⚠ Bird Sightings   <- our own navigationTitle, rendered underneath
GameMode
key not
found in [Info.plist, clipped]
                                    ↻ <- reload icon
```

That icon pairing (⚠ + ↻) and the debug readout underneath it (visible
further down the same screenshot: `A16`, `960x1440`, `Metal: 81.15MB`,
`Available Memory`, `Refresh Rate`, `Thermal`, `Game Mode`, `Frame`, `FPS`,
`Frame Interval`) is **Apple's on-device Performance/Metal HUD** — a
developer diagnostics overlay turned on for this test device (via Settings →
Developer → Metal HUD / Performance HUD on the phone itself), not a view we
draw. Nothing in the app's own source references any of those strings
(`FPS`, `Thermal`, `Metal:`, `GameMode`, etc. — confirmed via a full-repo
search), which rules out an in-app debug overlay being accidentally shipped.

The HUD only appears on the Map tab and nowhere else because `SightingMapView`
is the only screen that renders through MapKit's `Map` view, which is
GPU/Metal-backed — the system HUD only attaches to views with a live Metal
surface, so `ProfileView`, `LeaderboardView`, and `ReportTabView` (plain
SwiftUI `List`/`ScrollView`) never trigger it. Those three screenshots show
list/scroll content passing behind the app's translucent floating tab bar,
which is expected behavior on iOS's frosted-glass tab bar, not a defect —
they were reviewed and ruled out as separate bugs.

## Root cause

The HUD's own warning — `GameMode key not found in Info.plist` — is Apple
diagnosing why BirdMap isn't eligible for iOS's automatic Game Mode: apps opt
in or explicitly opt out via the `GCSupportsGameMode` Boolean key in
`Info.plist`. BirdMap's `Info.plist` never declared this key at all, so with
the Performance HUD enabled the system prints this warning as a large,
undismissable banner directly over the current screen — which is exactly
what got captured in `MapScreen.HEIC`, overlapping the app's own "Bird
Sightings" title.

This is not a crash and doesn't affect app logic — it's purely a
diagnostics-overlay artifact that only a developer/tester with the HUD
enabled would ever see — but it does actively block the UI while visible, so
it's worth silencing at the source rather than telling every hardware tester
to go disable a device setting.

## Fix

BirdMap is a citizen-science field app, not a game, so the correct fix is an
explicit opt-out rather than leaving the key absent:

- `ios/BirdMap/BirdMap/Info.plist` — added
  ```xml
  <key>GCSupportsGameMode</key>
  <false/>
  ```
- `ios/BirdMap/project.yml` — added the matching `GCSupportsGameMode: false`
  entry under the `BirdMap` target's `info.properties`, so the key survives
  the next `xcodegen generate` instead of being silently dropped by a
  regenerate.

With the key present, the Performance HUD has an answer to report and no
longer shows the "key not found" warning, regardless of whether a given
tester's device has the HUD toggled on.

## Verification

Could not run this on physical hardware from this environment (no macOS/Xcode
available here — see chat history for that limitation). To confirm on your
Mac:

1. `cd ios/BirdMap && xcodegen generate`
2. Build and run on the same test device with the Performance HUD still
   enabled (Settings → Developer → Performance HUD, or Metal HUD).
3. Open the Map tab — the `GameMode key not found` banner should no longer
   appear; the rest of the HUD (FPS/thermal readout) is a device setting and
   will still show unless turned off separately, but it will no longer
   obscure the screen with a warning banner.

## Note on screenshots

The four `.HEIC` files were converted to `.png` for review (same folder) —
these are just decoded copies for readability and weren't otherwise
modified.

## Follow-up: app rendering "squashed" on hardware

After this fix landed, the reporter noted the app still looks squashed on
their physical device — content confined to a smaller, letterboxed
rectangle with black bars, rather than filling the real screen. That's a
second, unrelated bug, also visible (in hindsight) in all four HardwareTest1
screenshots: the black bars top and the compressed content are not the
Performance HUD.

**Root cause:** `Info.plist` never declared `UILaunchScreen` (or a launch
storyboard). Without one, iOS doesn't treat the app as opted into the
device's actual screen — it launches the app in a fixed legacy compatibility
resolution and then scales/letterboxes that fixed-size buffer to fit the
real screen, instead of laying out at native resolution. That scaling is
exactly what reads as "squashed": black bars, and everything inside them
compressed to the wrong aspect ratio.

**Fix:** added an empty `UILaunchScreen` dictionary — the modern (iOS
14+), storyboard-free way to opt in to a normal system-provided launch
screen and native full-screen layout:

- `ios/BirdMap/BirdMap/Info.plist`
  ```xml
  <key>UILaunchScreen</key>
  <dict/>
  ```
- `ios/BirdMap/project.yml` — matching `UILaunchScreen: {}` under
  `info.properties`, so it survives `xcodegen generate`.

No other file references a `LaunchScreen` storyboard, so there was nothing
to conflict with. After regenerating the project and reinstalling on
hardware, the app should render pixel-for-pixel at the device's native
resolution — no black bars, no squashing.

## Follow-up round 2: HUD still showing, reporting can't connect, model won't download

Three more reports came in after the above fixes. Investigated each — one is
a rebuild/device-setting issue, one was a real code bug (fixed), one is a
pre-existing infrastructure gap that can't be closed from code.

### 1. Thermal/yellow-triangle HUD still shows on Map

The `GCSupportsGameMode` fix removes the "key not found" *warning banner*
only. The FPS/thermal/Metal readout underneath it is the on-device
**Performance HUD**, a per-device Developer Settings toggle
(Settings → Developer → Performance HUD / Metal HUD) — turning that off on
the test device is what makes the whole readout disappear, not something
`Info.plist` controls. If the warning banner specifically is still showing,
the most likely explanation is the build on-device predates commits
`68bdc16`/`44c6376` — confirm with `xcodegen generate` + a clean rebuild
(Product → Clean Build Folder) before re-testing.

### 2. Reporting can't connect — real bug, fixed

`APIClient.baseURL` (`ios/BirdMap/BirdMap/Networking/APIClient.swift`) read
`API_BASE_URL` from `Info.plist`, which for a Debug build is
`http://localhost:8000` (`project.yml`'s `Debug` config — intended for the
Simulator, which shares the Mac's network namespace). On a **physical
device** "localhost" resolves to the phone itself, not the Mac running
`docker-compose`, so every report/upload request failed outright — this is
what read as "can't connect to Firebase" (the media broker call happens
before the Firestore write in `CameraViewModel`/`AudioRecorderViewModel`, so
the whole submission aborts before Firestore is ever touched).

**Fix:** `APIClient.baseURL` now checks `#if targetEnvironment(simulator)`.
On a real device, if the configured URL still points at
`localhost`/`127.0.0.1`, it falls back to the deployed API
(`https://birdmap-api.fly.dev`) instead of trying to reach the phone itself.
Simulator builds are unaffected and still use the local Docker backend as
before.

Caveat: this sandbox's network egress is locked down and could not reach
`birdmap-api.fly.dev` to confirm the deployed backend itself is currently up
and correctly wired to Supabase — that needs verifying from a normal
network. If it turns out that deployment isn't live/working, reporting will
still fail on device, just with a real HTTP error instead of a bogus
"can't connect," which at least makes the next failure diagnosable.

### 3. On-device model won't auto-download — not a code bug, infra gap

Queried Firestore's public `model_versions` collection directly
(`allow read: if true` in `firestore.rules`, so no credentials needed):

```
GET https://firestore.googleapis.com/v1/projects/birdmap-citizenscience/databases/(default)/documents/model_versions
→ {}
```

The collection is **empty** — no model has ever been successfully
registered. `ModelManager.checkForUpdate()` is behaving correctly: it finds
no active `"photo"` doc and logs `No active photo model published yet`,
then does nothing. There's no bundled fallback model in the app (confirmed
in `BirdClassifier.swift`), so on-device photo ID is simply unavailable
until one is published.

This matches the pre-existing gap already documented in the project's
`CLAUDE.md`: *"no Supabase project has actually been provisioned for this
app... `publish_model.py` ... can't work until `provision-supabase.sh` is
run against a real Supabase account."* `publish_model.py` only writes the
Firestore `model_versions` doc **after** the model zip successfully uploads
to Supabase Storage — with no Supabase project, that upload never happens,
so nothing is ever registered for `ModelManager` to find.

This isn't fixable by changing app code — it needs, in order:
1. `provision-supabase.sh` run against a real (free-tier) Supabase account
   to create the storage bucket and populate `backend/.env.supabase`.
2. `convert_photo_model.py` (already implemented) run once to produce the
   model zip.
3. `publish_model.py` run against the now-real Supabase credentials to
   upload the zip and register it in Firestore.

Once step 3 succeeds, `ModelManager` will pick up the new version on the
next app launch with no further code changes.
