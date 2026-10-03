# Deploy the site to Firebase Hosting

**Why it helps:** Nothing in steps 1-70 reaches Google until the built site is live. The live site was last deployed in August and still has the old empty-shell HTML.

**Who does it:** you (needs your account or your judgement; it can't be done from the repo).

## Steps

1. From the repo root: `cd web && npm run build && npm run seo:check` (must print `SEO check passed`).
2. Deploy: `firebase deploy --only hosting` (the CLI on this Mac is already logged in as your Google account; project alias is in `web/.firebaserc`).
3. Or use GitHub: add the `FIREBASE_SERVICE_ACCOUNT_JSON` secret with the Hosting Admin role, then run the *Deploy web to Firebase Hosting* workflow from the Actions tab.
4. Check it: `curl -sI https://getbiomap.web.app/faq` should be `200`, `curl -sI https://getbiomap.web.app/definitely-not-a-page` should be `404`, and `curl -s https://getbiomap.web.app/ | grep '<h1'` should show real text.
5. Open https://getbiomap.web.app/sitemap.xml and https://getbiomap.web.app/robots.txt in a browser.

**Done when:** the three curl checks behave as described.

> Deploying publishes to the public internet, which is why it was not done for you.
