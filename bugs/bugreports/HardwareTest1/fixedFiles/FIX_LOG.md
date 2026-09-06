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

### 2. Reporting can't connect

**Correction — the first attempt at this fix was wrong and has been
reverted.** It fell back to `https://birdmap-api.fly.dev` on a real device,
reasoning that it was "the deployed production API" because it's what
`project.yml`'s `Release` config holds. That was never actually checked
against this repo's own deployment docs, which say the opposite:
`docs/DEPLOYMENT.md` line 16 — *"Fly.io is not used. As of 2024-2025 it
discontinued its free tier entirely — a card is required almost
immediately."* `update-api-url.sh` confirms it directly — its sed patterns
treat `birdmap-api.fly.dev` as `# Fly.io (original)`, i.e. the placeholder
string every real deploy script searches-and-replaces once a real backend
exists. It was never a live host. Redirecting hardware builds to it was
trading one dead endpoint for another, just with a slower failure (DNS
instead of connection-refused) — which is consistent with the retest still
not working.

**What's actually true, per `docs/DEPLOYMENT.md`'s own "confirmed directly"
status:** no backend is deployed anywhere for this project right now.
Render rejected the project's account for a free-tier service
(`need_payment_info`); Cloud Run needs GCP billing enabled; self-host needs
a spare always-on machine; Fly.io is ruled out entirely. So there is
currently no URL — real or guessable — that reporting can succeed against
on its own. The only backend that works today is the **local Docker Compose
stack** (`docker compose up -d` from the repo root), and only for whoever
can actually reach it on the network.

**Fix (partial, honest about the remaining limit):** reverted the fly.dev
guess. `APIClient.baseURL` now also checks a `UserDefaults` key,
`API_BASE_URL_OVERRIDE`, before falling back to the configured
`Info.plist` value. This is the standard iOS pattern for a
launch-argument-driven override — add `-API_BASE_URL_OVERRIDE
"http://<mac-lan-ip>:8000"` to the scheme's **Arguments Passed On Launch**
(Product → Scheme → Edit Scheme → Run → Arguments) to point a hardware
build at the Mac's actual LAN IP (`ipconfig getifaddr en0` on the Mac)
while `docker compose up -d` is running there and both devices are on the
same Wi-Fi. That's a real, working path to test reporting on hardware
today — it's just a per-session local setting rather than something a
commit to this repo can fix outright, since there is no stable URL to bake
in until a real backend is actually deployed (needs either billing on
Render/Cloud Run or a spare self-hosted machine — see
`docs/DEPLOYMENT.md`).

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

Re-verified this is still accurate before writing this section: the same
public Firestore query returned `{}` again just now — unchanged.

### 4. Now two warning triangles instead of one — needs a fresh screenshot

Not diagnosable from code alone. Nothing changed between the two builds
that would explain a *second* HUD warning appearing on its own — the only
Info.plist keys touched are `GCSupportsGameMode` and `UILaunchScreen`,
neither of which has a known second failure mode that would surface as an
additional triangle. Rather than guess, this needs the same treatment as
the original report: a fresh `.HEIC`/screenshot of the Map screen showing
both triangles, so the actual text of each warning can be read instead of
assumed.
