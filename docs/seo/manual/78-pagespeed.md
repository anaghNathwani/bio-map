# PageSpeed Insights pass

**Why it helps:** Speed and layout stability are ranking inputs and affect whether visitors stay.

**Who does it:** you (needs your account or your judgement; it can't be done from the repo).

## Steps

1. Open https://pagespeed.web.dev and test the home page and `/map` (mobile tab).
2. Already done in code: the map's Leaflet/Firebase code is split out of every other page, render-blocking CSS removed, latin-only fonts, image dimensions set, long-lived asset caching.
3. Likely remaining on `/map`: the OpenStreetMap tiles and Firebase load time. Note the numbers; only chase items that score red.

**Done when:** home page scores green on mobile; `/map` is acceptable.
