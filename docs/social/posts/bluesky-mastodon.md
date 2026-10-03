# Bluesky and Mastodon

Bluesky limit: 300 characters. Mastodon (mastodon.social): 500. Everything below fits Bluesky, so it works on both.
Add the alt text from `../SOCIAL_PLAN.md` to every image. Pair each post with the image noted.

Hashtags: Bluesky `#birding #birdsofbluesky`. Mastodon `#birding #Birds #CitizenScience #iOSDev`.

## Launch thread (post as a thread, image on 1 and 2)

**1/** (image `01-hero.png`)
We're building BioMap: a citizen science app where a bird photo or a recorded call is identified on your phone, then other birders confirm or correct the ID.

The iOS app is coming soon. The live map works in a browser today: https://getbiomap.web.app

**2/** (image `02-how-it-works.png`)
How it works: capture a photo or up to 30 seconds of a call, the ID runs on your phone (Google's AIY Birds for photos, Cornell Lab's BirdNET for sound), then other birders confirm, correct, or mark it unsure.

**3/** (image `07-on-your-phone.png`)
Two choices we care about. Identification stays on your device until you decide to share a sighting. And when the model isn't confident, it says so instead of guessing.

**4/**
We're early and want honest feedback from people who actually watch birds. Which species does it get wrong? What would make you trust an ID? Replies open.

## Evergreen posts (one or two a week; rotate)

**Recording tip** (image `05-tips-recording.png`)
Getting a bird call your phone can identify: get close and hold still, keep wind and voices out of it, and remember a short clean clip beats a long noisy one.

**Photo tip** (image `06-tips-photo.png`)
For a bird photo that gets a good ID: make the bird the main subject, sharp and well lit, show the whole bird if you can, and take a few frames. The best one wins.

**Why location matters for sound**
Sound models can name an unlikely bird for background noise. BioMap passes your location and the time of year to BirdNET's location filter so species that don't live near you are ruled out. More: https://getbiomap.web.app/bird-sound-identification

**"Unsure" is a real answer** (image `04-honest-uncertainty.png`)
Design choice we're stubborn about: if the model isn't confident, BioMap says so instead of showing a confident-sounding guess. Marking a sighting "unsure" is a valid annotation too.

**How verification works**
Anyone can confirm the AI's guess, correct it, or mark it unsure, and several annotations on one sighting build a consensus. Annotations that don't look like a real bird name are flagged rather than counted. https://getbiomap.web.app/community

**More than one bird**
Recordings often have several birds calling. BirdNET scores every species separately for each short segment, so BioMap reports every species that clears the confidence bar, not just the loudest.

**Works without signal**
Trail with no reception? Photo and sound ID both run on the phone. Submitting a sighting waits for a connection and retries automatically the next time the app opens.

**Behind the scenes**
We ship the bird-ID models inside the app rather than calling a server. Trade-off: the models have to be small. Upside: it's private, instant, and works offline. Longer version: https://getbiomap.web.app/blog/keeping-bird-id-on-your-phone

**Question: sound**
Birders: what's the hardest bird you've tried to identify by ear? We're collecting tricky cases to test against.

**Question: photo vs sound**
Photo or sound: which do you reach for first when you can't place a bird, and why?

**Question: trust**
If an app suggests a bird ID, what makes you trust it? A confidence number, a photo to compare, other birders agreeing, something else?

**Citizen science angle**
A single sighting is a species, a place and a time. Thousands of them, checked by other people, can show migration timing and range changes. That's what BioMap's map is for. https://getbiomap.web.app/blog/what-is-citizen-science-bird-data-for

## Engagement routine (10-15 minutes a day)

- Follow birders, birding starter packs, citizen-science and bioacoustics accounts.
- Reply to 3-5 posts a day with something useful (an ID tip, a question). No links.
- Answer every reply to your posts. Thank people who point out mistakes.
