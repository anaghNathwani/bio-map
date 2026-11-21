# Rich Results Test

**Why it helps:** Confirms Google can read the structured data (Organization/WebSite, WebApplication, BlogPosting, BreadcrumbList).

**Who does it:** you (needs your account or your judgement; it can't be done from the repo).

## Steps

1. Open https://search.google.com/test/rich-results.
2. Test `https://getbiomap.web.app/blog/identify-birds-without-internet`, `https://getbiomap.web.app/map` and `https://getbiomap.web.app/faq`.
3. Fix anything flagged as an error in `web/src/site.js`. Warnings about optional fields are fine.

**Done when:** no errors for those three URLs.

> Honest expectation: Google now shows FAQ rich results only for a small set of authoritative sites, so the FAQ markup is valid but probably won't change how the page looks in results. It still helps Google understand the page.
