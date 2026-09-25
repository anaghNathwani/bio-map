# Show HN

Only post when a visitor can try something. Make sure the map has sightings first (see the plan). Post the site URL, then add
the first comment. Stay online for a few hours to answer. Don't ask anyone to upvote.

**Title:** Show HN: BirdMap, bird ID (photo + BirdNET audio) that runs on-device, with a community map

**URL:** https://birdmap-citizenscience.web.app

**First comment:**
Hi HN. BirdMap is a citizen science app: you take a photo or record up to 30 seconds of a call, the identification runs on the phone, and other people can confirm, correct or mark the ID unsure. Sightings go on a shared map.

Technical bits people may care about:
- Photos: Google's AIY Birds V1 (MobileNetV2, ~960 species) via TFLite. I tried CoreML first, but the converted model gave near-constant output regardless of input; the TFLite conversion of the same SavedModel was correct.
- Audio: BirdNET V2.4 via TFLite, plus BirdNET's location/season meta-model fed the GPS fix. Without the location filter it named implausible species for noise.
- Low-confidence results say so rather than guessing.
- Annotation moderation (does this look like a real bird name?) also runs on the device, so there's no stored verdict a client could tamper with.
- Media is embedded as base64 in Firestore to stay on free tiers.

Limitations: the iOS app is pre-release (the browser map works now), on-device models are small so accuracy is bounded, and the dataset is tiny. I'd especially like to hear how you'd evaluate identification quality and keep crowd-verified data trustworthy.

Blog posts on the design: https://birdmap-citizenscience.web.app/blog
