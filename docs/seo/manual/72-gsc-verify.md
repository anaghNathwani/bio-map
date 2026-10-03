# Verify the site in Google Search Console

**Why it helps:** Search Console is Google's free dashboard for indexing, queries and errors. You can't submit or monitor without verifying ownership.

**Who does it:** you (needs your account or your judgement; it can't be done from the repo).

## Steps

1. Go to https://search.google.com/search-console and sign in with the Google account that should own the site.
2. Click **Add property** and choose **URL prefix** (a *Domain* property needs DNS access, which a `web.app` subdomain doesn't give you). Enter `https://getbiomap.web.app/`.
3. Pick the **HTML tag** verification method. Copy only the `content="..."` value of the `<meta name="google-site-verification">` tag.
4. Paste it into `GOOGLE_SITE_VERIFICATION` in `web/src/site.js`, then redeploy (playbook 71). The build injects the tag into every page.
5. Back in Search Console, click **Verify**.

**Done when:** Search Console shows the property with no verification error.
