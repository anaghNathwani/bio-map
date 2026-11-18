# Monthly blog cadence

**Why it helps:** Fresh, useful pages give Google more to index and give people more reasons to link.

**Who does it:** you (needs your account or your judgement; it can't be done from the repo).

## Steps

1. Add a post to `web/src/content/posts.js` (slug, title under ~55 chars, 70-170 char description, `date`, body blocks).
2. `cd web && npm run build && npm run seo:check`, deploy (playbook 71), then `npm run indexnow -- --submit`.
3. In Search Console, inspect the new URL and request indexing.
4. Ideas: how to record a bird call your phone can identify; five photo tips for birds; migration timing in your region; how BirdNET's location filter works; what to do when the AI is unsure; how to become a good annotator; a beginner's guide to bird behaviours.

**Done when:** you have a rhythm of one post a month.
