# "Look up."

A brand campaign for BioMap in the spirit of a quiet, black-and-white tribute film. It isn't about the product. It's about a way
of being in the world: the ones who stop mid-sentence because something chirped, who look up when everyone else looks down, and how
a thin layer of living things (the biosphere) is telling us something all the time.

**The idea:** the living world is speaking, and noticing is how we answer.
**The line:** *Look up.*
**The sign-off:** the bird mark, made of dots, and the name BIOMAP. Nothing else. No app, no features, no availability.

Original writing and imagery. It borrows the *spirit* of that famous 1990s campaign (a hushed tribute, a montage of ideas, a
one-line ending) but none of its words, footage or tagline.

## What's here

| File | What |
|---|---|
| `film/look-up-film-9x16.mp4` | The full film, vertical (Reels, Stories, Shorts). ~75 s |
| `film/look-up-film-16x9.mp4` | The full film, widescreen (website, YouTube, presentations) |
| `film/look-up-short-9x16.mp4` | Shorter cut (two lines, then the mark) for feeds and ads |
| `film/look-up-bumper-9x16.mp4` | ~10 s bumper |
| `posters/*-4x5.png`, `*-story.png` | 5 posters (feed 1080x1350 and Story 1080x1920) |
| `vo/lines/*.wav` | The narration, one file per line (see "Voice") |
| `build_campaign.py`, `flock.js`, `vo.py`, `score.py` | Regenerate everything (edit the words, re-run) |

## How it's made

- **Picture:** a simulated flock of ~3,000 birds in pure black and white. Slow and wide, stretched across the frame like a real
  murmuration, with no sudden bursts. At the end the birds drift together and settle into the BioMap mark, dot by dot. No stock
  footage, no photos: nothing to license.
- **Type:** the brand serif, white on black, one thought at a time, timed to the voice.
- **Voice:** synthesized locally (Kokoro, an open Apache-2.0 model), slow and close. It's a stand-in: see below.
- **Score:** an original slow felt-piano figure over a warm pad that ducks under the voice, swells into the last line and hangs on
  one note. Synthesized, so also license-free.

## The words (spoken, and on screen)

The film times itself to the narration, so nothing to keep in sync by hand.

1. Above the stone, and below the stars, there is a thin, bright layer where everything is alive.
2. We call it the biosphere. The birds call it home.
3. Every morning, it clears its throat.
4. And a few of us stop mid-sentence.
5. They are the listeners. The ones who know the sky is a language.
6. Wings are its punctuation. Migration is the long sentence, written across the seasons.
7. One bird is a small fact. A thousand of them move like a single thought.
8. Nobody asked them to write it down. Someone should.
9. To the ones who look up. The world keeps a diary. You are its handwriting.
10. *(the dots become the mark)* Look up.

## Voice

The narration is a **computer-generated stand-in**. It's decent, but this piece is meant for a human. To swap it in:

1. Record each line above in a quiet room (a phone held 15 cm away is fine), warm, low, unhurried, leaving air between lines.
2. Save each as a WAV over the matching file in `vo/lines/` (same file name).
3. Run `python3 build_campaign.py film`. The picture re-times itself to your recording.

Who to ask: a birder, a teacher, a grandparent, someone who sounds like they're talking to one person, not announcing.
Check the synthetic voice's license/terms before any paid use; the model is Apache-2.0, but a human voice avoids the question.

## Rules for the campaign

1. **The thought only.** No mention of the app, its features, or "coming soon". The film sells a way of looking, not a download.
2. **Black and white.** No clay orange, no colour. The only warm thing is the voice.
3. **One thought at a time.** If a line needs a second sentence to explain it, cut it.
4. **Don't borrow.** No text, tagline or footage from anyone else's campaign, and no real people's faces or quotes.
5. **Claims stay poetic.** Nothing that reads as a statistic, a ranking or a guarantee.

## Captions (thought only)

**Film / Reel** (paste exactly):

```
Look up.

Above the stone and below the stars, there is a thin bright layer where everything is alive.

#lookup #birds #birdwatching
```

**Posters** (each under its poster):

`01-look-up`
```
Look up.

The sky is a language.

#lookup #birds #birdwatching
```

`02-clears-its-throat`
```
Every morning, it clears its throat.
And a few of us stop mid-sentence.

#lookup #birds #birdwatching
```

`03-single-thought`
```
One bird is a small fact.

#lookup #birds #birdwatching
```

`04-handwriting`
```
The world keeps a diary.

#lookup #birds #birdwatching
```

`05-mark`
```
Look up.

#lookup #birds #birdwatching
```

Keep to three hashtags and don't add any app copy.

## Posting order

1. Day 1: the full vertical film, with the film caption.
2. Day 3: poster `01-look-up`.
3. Day 5: the shorter cut as a Reel.
4. Then one poster a week; use the bumper as an intro to anything else you post.
