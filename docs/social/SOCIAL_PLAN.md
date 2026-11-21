# BioMap social media plan

Everything in `posts/` is ready to copy and paste. Images are in `images/` (1200x675, brand colours and fonts).
I can write and design the content, but I can't log in and post it for you, so posting is the one manual bit.

## Read this first: two things to fix before you promote

1. **The live map now holds 500 clearly-labelled SAMPLE sightings** across California (plus the 8 real ones), added with
   `ml_pipeline/seed_demo_sightings.py`. Each is flagged `isDemo`, credited to `sample_birder_N`, and its note reads "Sample data
   (not a real observation)". **Don't present them as real community sightings**: in posts and videos, say "sample data" or
   show the map as a preview. Remove them with `python seed_demo_sightings.py --remove` once real sightings arrive.
2. **The iOS app isn't installable yet.** Every post says "iOS app coming soon; live map works in your browser today",
   which is true now. Change that line the day TestFlight or the App Store goes live, and add the link.

Also worth doing: confirm BirdNET's license and credit Cornell Lab of Ornithology in the app before you promote it widely.

## Positioning (say this, consistently)

**BioMap is a citizen science app where bird photos and calls are identified on your phone, then other birders confirm the ID.**

What makes it different, and what's true today:
- Identification runs on the phone; nothing is uploaded just to get a suggestion.
- It says when it isn't sure instead of guessing.
- Sound ID uses your location to rule out birds that don't live nearby.
- Community review sits on top of the AI: confirm, correct, or mark unsure.

Never claim: accuracy numbers, "best", "most accurate", user counts, partnerships with Cornell/Google, or that it's on the App Store.
It uses Google's AIY Birds and Cornell Lab's BirdNET as released; say "uses", not "by".

## Voice

Plain, specific, curious, a little understated. Lead with something useful or a real question, not "we're excited to announce".
No emoji strings, no hype words, no engagement bait. Posts say "we"; switch to "I" if it's just you. Reply to everyone.

## Channels, in priority order

| Priority | Channel | Why | Effort |
|---|---|---|---|
| 1 | **Bluesky** | Large, friendly birding community; birding starter packs | 15 min/day |
| 2 | **Mastodon** (#birding) | Hashtag discovery works well for niches | same posts as Bluesky |
| 3 | **Reddit** r/birding, r/citizenscience | Your exact audience; read each sub's promo rules first | 1 post each, then replies |
| 4 | **Reddit** r/SwiftUI, r/iOSProgramming + **Show HN** | The CoreML-vs-TFLite story is genuinely interesting to developers | 1 post each |
| 5 | **LinkedIn** | Your network; one build-story post | 1 post |
| 6 | **YouTube** (60-90s demo) | Video shows in Google results | 1 video |
| 7 | **Dev.to / Hashnode** | Republish the blog posts with a canonical link | 3 posts |
| 8 | **Direct outreach** | Audubon chapters, bird clubs, teachers: warmest audience | 3-5 emails |

Skip for now: TikTok/Instagram/X. They need video/short-form volume and have weak links back to a site.

## 4-week calendar

**Week 1: seed (Bluesky + Mastodon + LinkedIn)**
- Mon: Bluesky launch thread (`posts/bluesky-mastodon.md`, "Launch thread") + same on Mastodon.
- Tue: follow 20-30 birders/citizen-science accounts and reply thoughtfully to their posts (no link-dropping).
- Wed: evergreen post 1 (recording tips, image 05).
- Thu: LinkedIn build-story post (`posts/linkedin.md`).
- Fri: evergreen post 2 (photo tips, image 06).

**Week 2: your audience (Reddit + outreach)**
- Mon: check r/birding rules; post from `posts/reddit.md` if promo is allowed (otherwise the question-only version).
- Wed: r/citizenscience post.
- Thu: send the first 3 outreach emails (`posts/outreach-emails.md`).
- Reply to every comment within a day. Two more evergreen posts.

**Week 3: developers**
- Tue: r/SwiftUI post (TFLite story). Wed: Show HN (`posts/hacker-news.md`); be online for 3 hours.
- Fri: publish the Dev.to article with the canonical link (`posts/devto-hashnode.md`).

**Week 4: video + follow-up**
- Record and post the demo video (`posts/youtube-script.md`). Share the clip on Bluesky/Mastodon/LinkedIn.
- Send 3 more outreach emails. Post a "what we learned from your feedback" thread (fill in from real replies).

**After week 4 (15 min/day):** three posts a week (one tip, one question, one behind-the-scenes), one blog post a month
(playbook 99 in `docs/seo/manual/`), reply to everything.

## Rules that protect the account

- Read each subreddit's rules first. If self-promotion isn't allowed, post the question-only version or skip it.
- Disclose you're the maker. Never ask for upvotes/likes, never use multiple accounts, never buy followers.
- One link per post, at the end. Don't repost the same text in multiple subreddits on the same day.
- Don't argue. Thank critics, ask what they saw, fix what's fixable.

## Measuring it

There's no analytics on the site (and adding it would mean updating the privacy page), so measure with what's free:
platform insights on each post, Reddit/HN comment quality, and Google Search Console (impressions, queries, indexed pages).
The number that matters early isn't followers, it's **how many real birders tried it and what they told you**.
Keep a simple list of feedback and turn repeated points into fixes and blog posts.

## Images

| File | Use with |
|---|---|
| `01-hero.png` | launch post, LinkedIn, link previews |
| `02-how-it-works.png` | launch thread post 2, Reddit, outreach |
| `03-photo-or-sound.png` | explainer post, r/birding |
| `04-honest-uncertainty.png` | "it says when it isn't sure" post |
| `05-tips-recording.png` | evergreen tip: recording |
| `06-tips-photo.png` | evergreen tip: photos |
| `07-on-your-phone.png` | privacy/on-device post |

Alt text (paste it into the alt field on Bluesky/Mastodon; it helps accessibility and reach):
- 01: "BioMap: Every bird you see becomes data that matters. Identify birds from photos and calls on your phone."
- 02: "How BioMap works in three steps: capture a photo or call, it is identified on your phone, the community confirms."
- 03: "Two ways to identify: by photo with Google's AIY Birds model, or by sound with Cornell Lab's BirdNET."
- 04: "When the AI isn't sure, it says so. Every suggestion can be confirmed, corrected or marked unsure."
- 05: "Tips for recording bird sound: get close and hold still, keep wind and voices out, short and clean beats long and noisy."
- 06: "Tips for bird photos: make the bird the main subject, show the whole bird, take a few frames."
- 07: "Your photo stays on your phone until you share it. Identification runs locally."
