# BirdMap on Instagram

Yes, I can make videos. These are **motion-graphics Reels** (animated type, shapes and a waveform, rendered from code).
I can't film real footage or screen-record your phone. Once the iOS app is installable, record 10-15 seconds of the real app
and I can cut it into these. Until then, everything here is honest about what exists: an animated explainer, no fake app screens.

Files (all in `docs/social/instagram/`):

| Folder | What | Format |
|---|---|---|
| `reels/` | 4 Reels, silent, 12-17 seconds | MP4 1080x1920, 30 fps, H.264 |
| `reels/covers/` | a cover image for each Reel | PNG 1080x1920 |
| `carousels/` | 3 swipe posts (6, 8 and 6 slides) | PNG 1080x1350 (4:5) |
| `stories/` | 3 question/poll backgrounds | PNG 1080x1920 |
| `profile/` | profile picture + 4 highlight covers | PNG |
| `captions.md` | caption, hashtags and first comment for every post | |
| `build.py` | regenerates all of it (edit text, run `python3 build.py`) | needs Chrome + ffmpeg |

## Before you post anything

1. **The web map shows "0 sightings."** "Link in bio" sends people to it. Add real sightings first (or tell me and I'll debug it).
2. Everything says "iOS app coming soon." Change it when TestFlight/App Store is live (edit `build.py`, re-run, re-upload).
3. Credit BirdNET/Cornell properly in the app and check its license before promoting.

## Set up the account (15 minutes)

- **Account type:** Instagram -> Settings -> *Account type and tools* -> *Switch to professional account* (free; gives Insights).
- **Name:** `BirdMap | Bird ID & Sightings` (29 characters).
- **Handle** (check availability in the app): `birdmap.app`, `getbirdmap`, or `birdmapcitizenscience`.
- **Bio** (limit 150 characters):
  ```
  Citizen science for bird lovers.
  Bird IDs on your phone, checked by birders.
  iOS app coming soon. Live map below.
  ```
- **Link:** https://birdmap-citizenscience.web.app
- **Profile picture:** `profile/profile-picture.png` (Instagram crops it to a circle; the bird is centred).
- **Highlights:** create four (How it works, Tips, FAQ, Sightings) and use the covers in `profile/`. Fill each by posting the
  related Story and tapping *Highlight*. (Highlights need something in them before they show.)

## What to post, and when

Aim for **3 posts a week** for 4 weeks, plus a Story or two. Consistency beats volume; skip a week rather than post filler.

| Week | Mon | Wed | Fri |
|---|---|---|---|
| 1 | Reel 01: how it works | Carousel 01: how it works | Story: question 01 |
| 2 | Reel 02: sound tips | Carousel 02: 6 tips | Story: poll 02 |
| 3 | Reel 03: stays on your phone | Carousel 03: citizen science | Story: question 03 |
| 4 | Reel 04: says when unsure | Re-share your best post as a Story | Post a reply Reel/Story answering a real question you got |

After week 4, repeat with new content: reuse `build.py`, and turn each new blog post into a carousel.

## How to post each type

**Reel (from your Mac):**
1. AirDrop the MP4 to your iPhone (or use *Meta Business Suite* on the web, which can post Reels for free).
2. Instagram -> **+** -> **Reel** -> pick the file -> **Next**.
3. **Edit cover** -> *Add from camera roll* -> pick the matching PNG from `reels/covers/`.
4. Paste the caption from `captions.md`. Leave audio off, or add music from Instagram's own library inside the app.
   (Business/professional accounts can be limited to a royalty-free library; don't upload outside music you don't have rights to.)
5. Share.

**Carousel:** AirDrop the slide PNGs, **+** -> **Post** -> select multiple (in order) -> caption. First slide is the hook.

**Story:** open the PNG in Stories, add the sticker named in the file name (Question or Poll) in the empty space, share.

## What works on Instagram (and what doesn't)

- The **first 1-2 seconds** decide if someone keeps watching; each Reel opens on its point, not a logo.
- Keep text inside the middle of the screen: Instagram's buttons and caption cover the top and bottom. These are already laid out for that.
- **Saves and shares** matter more than likes. Tips carousels are built to be saved.
- Links in captions aren't clickable. The only link is the bio, so every post says "link in bio".
- Use **3-5 relevant hashtags**, not 30.
- Reply to comments, and spend 10 minutes a day commenting thoughtfully on other birding accounts. That's how a new account gets seen.
- There's no magic posting time. After two weeks, check Insights for when your followers are online.

## Rules that keep the account safe

Don't buy followers or engagement, don't use engagement pods, don't claim accuracy numbers, awards or partnerships,
and don't say the app is available until it is. Say "coming soon."

## Measure it

Insights (free on a professional account): **reach**, **saves**, **shares**, **profile visits** and **link taps**.
After four weeks, look at which post got the most saves and shares and make more like it.
The number that matters early is how many real birders tried the map and told you what was wrong.
