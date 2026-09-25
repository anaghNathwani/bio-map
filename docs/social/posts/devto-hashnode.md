# Dev.to and Hashnode

Publish **after** the same post is live on your own site, and always set the canonical URL so Google credits your site.
Use the matching blog post text (copy from `web/src/content/posts.js`) and lightly adjust the intro for the platform.

## Dev.to front matter (post 1)

```
---
title: How BirdMap identifies birds without the internet
published: true
description: The photo and sound models behind BirdMap run on your phone, so you get a species suggestion even with no signal.
tags: ios, machinelearning, swift, opensource
canonical_url: https://birdmap-citizenscience.web.app/blog/identify-birds-without-internet
cover_image: <upload docs/social/images/01-hero.png>
---
```

## Suggested order

1. Week 3: `identify-birds-without-internet` (canonical to your site)
2. Week 5: `keeping-bird-id-on-your-phone`
3. Week 7: `what-is-citizen-science-bird-data-for` (fits Hashnode/Medium-style audiences better)

## Hashnode

In the editor: *Article settings -> Are you republishing? -> paste the original URL*. Same posts, same order, a week after Dev.to.

## Add a developer-focused article (optional, high value)

"Why my CoreML bird classifier returned the same answer for every image, and how I fixed it with TFLite". Use the r/SwiftUI post
as the outline; add code for the resize/crop/normalize step. Canonical it to a new post on your blog (add it to `posts.js`; I can do that).
