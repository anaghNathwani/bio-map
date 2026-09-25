# Run IndexNow after each deploy

**Why it helps:** IndexNow pings Bing, Yandex and others about changed URLs instantly. (Google does not use it; Search Console covers Google.)

**Who does it:** you (needs your account or your judgement; it can't be done from the repo).

## Steps

1. After deploying, confirm the key file loads: `curl -s https://birdmap-citizenscience.web.app/62259ef729e05ae65a5f78ca64f5e490.txt` prints the key.
2. Dry run: `cd web && npm run indexnow` shows what will be sent.
3. Send it: `npm run indexnow -- --submit` (expect HTTP 200 or 202).

**Done when:** the command reports `200` or `202`.
