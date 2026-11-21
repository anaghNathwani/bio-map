# Releasing the iOS app (TestFlight)

How a build of BioMap gets from this repo to testers' iPhones. Everything here is done from a Mac with Xcode; none of it
runs in CI.

| | |
|---|---|
| App bundle ID | `com.biomap.BioMap` |
| Widget extension bundle ID | `com.biomap.BioMap.Widgets` |
| Team ID | `2JN5C47MQT` (set in `ios/BioMap/project.yml`) |
| Minimum iOS | 17.0 (the Lock Screen corner controls need iOS 18) |
| Devices | iPhone only |

> **You need a paid Apple Developer Program membership** ($99/year). With a free "Personal Team" Xcode signs development
> builds fine, but it cannot talk to App Store Connect: uploads fail with `DistributionAppRecordProviderError error 0`.
> A free team shows up in the archive's embedded profile as `iOS Team Provisioning Profile: *`.

---

## Trying a build on your own iPhone first (no TestFlight)

You don't need TestFlight to test. This is the fast loop while developing:

1. Plug the iPhone in, unlock it, and turn on **Settings → Privacy & Security → Developer Mode** (one time).
2. `cd ios/BioMap && xcodegen generate`, then open **`BioMap.xcworkspace`** (not the `.xcodeproj`).
3. Pick your iPhone as the run destination and press **⌘R**. Re-run after every code change: the phone keeps the old build
   until you do.

Widgets and the Lock Screen controls work in these builds too. Debug builds point at `API_BASE_URL` `http://localhost:8000`,
which only matters for the legacy backend; the live app talks to Firebase directly.

---

## One-time setup

1. **Xcode account.** Xcode → Settings → Accounts → sign in with the Apple ID that belongs to the paid program, and confirm
   the team shows as a paid team.
2. **App Store Connect record.** [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → **+ → New App**:
   iOS, a name that is unique on the App Store, bundle ID `com.biomap.BioMap`, and any unique SKU (e.g. `biomap-ios`).
   Make **exactly one** record. Duplicates cause "SKU / bundle ID / name already used" errors; remove extras under the app's
   **App Information → Remove App**.
3. **Widget App ID.** `com.biomap.BioMap.Widgets` is registered automatically the first time Xcode archives with automatic
   signing. If it isn't, add it at developer.apple.com → Certificates, Identifiers & Profiles → Identifiers.
4. **Agreements.** Accept any banner at the top of App Store Connect, and complete the EU trader status under Business if it
   asks (only needed for public App Store release, not TestFlight).
5. **Firebase.** `ios/BioMap/BioMap/GoogleService-Info.plist` belongs to the Firebase iOS app registered for
   `com.biomap.BioMap`. The Google Sign-In URL scheme in `project.yml` must equal that plist's `REVERSED_CLIENT_ID`. If the
   bundle ID ever changes, register a new Firebase iOS app and update both. Note that a bundle ID can never change once its
   App Store Connect record exists.

---

## Every release

### 1. Bump the version

Version numbers live in one place, `ios/BioMap/project.yml`, under the top-level `settings`:

```yaml
settings:
  base:
    MARKETING_VERSION: "1.1"      # the user-visible version
    CURRENT_PROJECT_VERSION: 5    # the build number
```

- **Every upload needs a higher build number than the last** (or App Store Connect rejects it), even if the version stays the
  same.
- The app and the widget extension share these values and must match, which is why they sit at the top level.
- Bump `MARKETING_VERSION` for a release with new features (1.0 → 1.1), and only `CURRENT_PROJECT_VERSION` for a fix to a build
  you've already uploaded.

### 2. Regenerate and archive

```bash
cd ios/BioMap
xcodegen generate        # rebuilds the .xcodeproj and re-runs `pod install`
open BioMap.xcworkspace  # the workspace, never the .xcodeproj
```

In Xcode: set the destination to **Any iOS Device (arm64)**, then **Product → Archive**. When the Organizer opens, select the
new archive and check the details panel shows the bundle ID, version and build you expect.

### 3. Get the build to App Store Connect

**Option A: upload directly.** Distribute App → **App Store Connect** → **Upload**, accepting the defaults.

**Option B: export, then Transporter** (more reliable, and it shows clearer errors):

1. Distribute App → **Custom** → **App Store Connect** → **Export**. Keep automatic signing and the defaults, and let Xcode
   create the **Apple Distribution** certificate if it asks. Choose a folder.
2. In the exported folder you'll find **`BioMap.ipa`**.
3. Open **Transporter** (free, Mac App Store), sign in, drag `BioMap.ipa` in, and click **Deliver**.

The "Upload Symbols Failed" warnings for `grpc`, `absl`, `openssl_grpc` and similar are harmless: those libraries ship
without debug symbols.

### 4. Wait for processing

The build appears under App Store Connect → your app → **TestFlight** as "Processing" for about 5 to 30 minutes. Apple emails
you if it's rejected. `ITSAppUsesNonExemptEncryption` is set to `false` in the app, so the export-compliance question
normally doesn't appear. If it does, answer that the app uses only standard encryption (HTTPS).

### 5. Choose who gets it

- **Internal testing** (no review): create an Internal Testing group, add yourself and other users on your App Store Connect
  account (up to 100), add the build, and install it through Apple's free **TestFlight** app.
- **External testing** (needs Beta App Review): create an External Testing group, add the build, fill in **Test Information**
  (what to test, feedback email, contact) and the **App Privacy** answers, then **Submit for Review**. The first build usually
  takes a day or two; later builds are often faster.
- **Public link**: in the external group, turn on **Public Link** and set the **tester limit**. Share the link; each person
  installs TestFlight, opens the link on their iPhone, taps **Accept** then **Install**. The limit is your rollout throttle.
  Raise it in App Store Connect as you go. See "Knowing when to raise the cap" below.

TestFlight builds **expire after 90 days**, so upload a fresh build before then.

---

## Knowing when to raise the tester cap

`ml_pipeline/notify_waitlist_signups.py` (run every 10 minutes by `.github/workflows/notify-waitlist.yml`) emails new waitlist
signups, in-app feedback and **new BioMap accounts**, with the running account total against your cap. Set the cap once as a
GitHub repo **variable** (or secret) named `TESTFLIGHT_CAP`; it flags "nearly full" at 80% and "raise the cap" at 100%. This
counts Firebase accounts, not TestFlight testers (Apple doesn't share that), so treat it as an early warning and confirm the
real count in App Store Connect → TestFlight → your group → Testers. Setup and the Resend key are in
[DEPLOYMENT.md](DEPLOYMENT.md#github-actions-workflows).

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `DistributionAppRecordProviderError error 0` | Free Personal Team, no App Store Connect record, or Xcode signed in to a different Apple ID than the one that owns the record. See the requirements above. |
| "SKU / Bundle ID / app name has already been used" when uploading | An app record already exists (possibly several). Open the existing one instead of creating another, and remove duplicates. |
| "Invalid bundle. No orientations were specified … iPad multitasking" | The app must be iPhone-only (`TARGETED_DEVICE_FAMILY: "1"` in `project.yml`); leaving iPad enabled demands all four iPad orientations. |
| Upload rejected: build number already used | Raise `CURRENT_PROJECT_VERSION` in `project.yml` and archive again. |
| Archive still shows the old bundle ID or version | You archived from a stale project. Run `xcodegen generate` and reopen the **workspace**. |
| Lock Screen controls do nothing | The control intents (`BioMapWidgets/ControlIntents.swift`) must be compiled into the app as well as the widget extension. Re-add the control on the Lock Screen after updating. |
| Missing Compliance on a build | Answer standard (HTTPS-only) encryption, or confirm `ITSAppUsesNonExemptEncryption` is false in the app. |
| Link says the beta is full | The public link's tester limit is reached; raise it in App Store Connect. |
| App icon missing / rejected | The icon must be 1024×1024 with no transparency (`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`). |
