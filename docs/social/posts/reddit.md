# Reddit

Read each subreddit's rules and any pinned "self-promotion" or "app" thread before posting. If promotion isn't allowed,
use the **question-only** version (no link; put the link in your profile) or skip that sub. Don't post the same text in
several subs on the same day. Reply to every comment.

## r/birding

**Title:** I'm building a free bird ID + sightings app that identifies on your phone. What would make you trust it?

**Body:**
I'm working on BioMap, a citizen science app. You take a photo or record up to 30 seconds of a call, and the ID runs on your phone (Google's AIY Birds model for photos, Cornell Lab's BirdNET for sound). Then other birders can confirm the ID, correct it, or mark it unsure.

A few things I care about: it says when it isn't confident instead of guessing, sound ID uses your location to rule out species that don't live nearby, and nothing is uploaded until you choose to share a sighting.

The iOS app isn't out yet, but there's a live map in the browser: https://getbiomap.web.app/map

I'd really value honest feedback from people who actually bird. What makes you trust or distrust an app's ID? Which species or situations do these apps get wrong for you?

**Question-only version (if links/promo aren't allowed):**
**Title:** What makes you trust (or distrust) a bird ID app's suggestion?
**Body:** I'm working on an app where bird photos and calls are identified on the phone and other birders confirm the ID. I'm trying to understand what makes an ID believable to people who actually bird: a confidence score, a reference photo, others agreeing, something else? And which situations do these apps get wrong for you?

## r/citizenscience

**Title:** Building a bird-sighting app where AI suggests and people verify. How would you keep the data trustworthy?

**Body:**
BioMap is a citizen science project: photos and calls get an on-device ID suggestion, and other people can confirm, correct or mark it unsure. Each sighting is geotagged and timestamped, and annotations from several people form a consensus. Annotations that don't look like a real bird name are flagged instead of counted.

I'm interested in the data-quality side. What would you add to make crowd-verified sightings more useful to researchers? (We're early and don't want to overclaim.)

Write-up on why verification matters: https://getbiomap.web.app/blog/what-is-citizen-science-bird-data-for

## r/SwiftUI (also fits r/iOSProgramming: check the flair/showcase rules)

**Title:** Running BirdNET and a MobileNet bird classifier fully on-device in a SwiftUI app (and why I dropped CoreML for TFLite)

**Body:**
I'm building BioMap (SwiftUI + Firebase), a bird ID / sightings app where all identification runs on the phone. A few things I learned that might save someone time:

- **CoreML conversion of a TF Hub model silently broke.** Converting Google's AIY Birds V1 SavedModel to `.mlpackage` produced near-identical output for a black image, white image, noise and real photos. Raw TensorFlow and a TFLite conversion of the same model were correct (>90% confidence on a real bird). So the photo classifier now runs through TensorFlowLiteSwift (CocoaPods) with my own resize/crop/normalize and label lookup.
- **BirdNET runs on-device too**, plus its location/season meta-model fed the real GPS fix. Without that filter it named a European woodpecker for white noise. Bundled models are ~52 MB + ~15 MB.
- **Mixing CocoaPods and SPM** means always building the `.xcworkspace`; regenerating the project with XcodeGen wipes the Pods integration unless a post-gen command re-runs `pod install`.
- Sightings embed compressed media as base64 in Firestore to avoid needing paid storage.

Happy to go deeper on any of it. Site (iOS app still pre-release): https://getbiomap.web.app

## Comment reply cheat sheet

- "Is it on the App Store?" -> "Not yet. Coming soon; the browser map works today."
- "How accurate is it?" -> "I don't have a number I'd trust yet, which is why every ID can be confirmed or corrected and low-confidence results say so."
- "Why not Merlin?" -> "Merlin is great. BioMap is aimed at a shared, community-verified map of sightings; identification is a means to that."
