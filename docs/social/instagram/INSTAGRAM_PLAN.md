# BirdMap on Instagram

Yes, I can make videos. These are **motion-graphics Reels** (animated type, shapes and a waveform, rendered from code) with an **original soundtrack I synthesized** (soft pad, a pluck on each scene change, and stylized bird-like chirps; these are synthesized whistles, not recordings of real birds, and there's nothing to license).
I can't film real footage or screen-record your phone. Once the iOS app is installable, record 10-15 seconds of the real app
and I can cut it into these. Until then, everything here is honest about what exists: an animated explainer, no fake app screens.

Files (all in `docs/social/instagram/`):

| Folder | What | Format |
|---|---|---|
| `reels/01`-`04` | 4 calm, on-brand Reels (serif type, soft pad) | MP4 1080x1920, 30 fps, H.264 + AAC stereo (~-16 LUFS) |
| `reels/05`-`08` | 4 **Gen Z-style** Reels (bold captions, hard cuts on the beat, emoji stickers, original beat), 12-15 s | same |
| `reels/covers/` | a cover image for each of the 8 Reels | PNG 1080x1920 |
| `carousels/` | 3 swipe posts (6, 8 and 6 slides) | PNG 1080x1350 (4:5) |
| `stories/` | 3 question/poll backgrounds | PNG 1080x1920 |
| `profile/` | profile picture + 4 highlight covers | PNG |
| `captions.md` | caption, hashtags and first comment for every post | |
| `build.py` | regenerates all of it (edit text, run `python3 build.py`) | needs Chrome + ffmpeg |

## Before you post anything

1. **The web map now has 500 clearly-labelled SAMPLE sightings** (see `ml_pipeline/seed_demo_sightings.py`). "Link in bio" sends
   people there, so don't describe it as real community activity: say "sample data" or "preview". Remove the samples with
   `python seed_demo_sightings.py --remove` when real sightings arrive.
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
- **Profile picture:** `profile/profile-picture.png` (paper-coloured bird on the brand clay; 1080x1080, Instagram crops it to a circle).
  It's the one that stays readable on both light and dark Instagram, even at 40px. Alternatives if you prefer:
  `profile-picture-paper.png` (dark bird on cream; fades into a white feed) and `profile-picture-ink.png` (cream bird on dark;
  disappears in dark mode).
- **Highlights:** create four (How it works, Tips, FAQ, Sightings) and use the covers in `profile/`. Fill each by posting the
  related Story and tapping *Highlight*. (Highlights need something in them before they show.)

## What to post, and when

Aim for **3 posts a week** for 4 weeks, plus a Story or two. Consistency beats volume; skip a week rather than post filler.

| Week | Mon | Wed | Fri |
|---|---|---|---|
| 1 | Reel 05: POV you hear a bird | Carousel 01: how it works | Reel 06: 3 signs you're a birder |
| 2 | Reel 07: speedrun | Carousel 02: 6 tips | Reel 01: how it works (calm) |
| 3 | Reel 08: not sure is valid | Carousel 03: citizen science | Reel 03: stays on your phone |
| 4 | Reel 02: sound tips | Story Q&A from real replies | Reel 04: says when unsure |

Lead with the Gen Z Reels (05-08): they're built for shares and the hook lands in the first second. The calm ones (01-04)
work as the "what is this?" explainers people find on your profile. Pin your best-performing Reel to the top of the grid.

After week 4, repeat with new content: reuse `build.py`, and turn each new blog post into a carousel.

## How to post each type

**Reel (from your Mac):**
1. AirDrop the MP4 to your iPhone (or use *Meta Business Suite* on the web, which can post Reels for free).
2. Instagram -> **+** -> **Reel** -> pick the file -> **Next**.
3. **Edit cover** -> *Add from camera roll* -> pick the matching PNG from `reels/covers/`.
4. Paste the caption from `captions.md`. The audio is already in the file. To swap it for Instagram's own music, tap the audio and turn the original volume down or off.
   (Business/professional accounts can be limited to a royalty-free library; don't upload outside music you don't have rights to.)
5. Share.

**Carousel:** AirDrop the slide PNGs, **+** -> **Post** -> select multiple (in order) -> caption. First slide is the hook.

**Story:** open the PNG in Stories, add the sticker named in the file name (Question or Poll) in the empty space, share.

## About the Gen Z Reels (05-08)

- **Formula:** a one-second hook, a cut every 1.5-2.5 seconds on the beat, words popping in like CapCut captions, one
  emoji sticker per scene, and a CTA end card. Relatable humor first, product second.
- **Honest by design:** the phone notification in Reel 05 and the chat bubble in Reel 08 are labelled *dramatization*. Nothing
  claims accuracy, and "works with no signal" is true for identification (you still need signal to post a sighting; the caption says so).
- **The beat is original** (synthesized in code), so there's nothing to license. If you want a trending sound for reach, turn this
  track down in the app and add one from Instagram's library (availability can be limited on business accounts).
- **Make your own versions:** edit the text in `genz.py` (it's plain strings), run `python3 build.py genz`. Good ideas to steal:
  "birds be like" jokes, "things birders say," and replies to real comments as video replies.
- No one can promise a video will take off. Post consistently, watch **saves and shares** in Insights, and make more of the winners.

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
