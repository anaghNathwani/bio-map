# GitHub repo description, website URL and topics

**Why it helps:** A public repo with a good description and topics ranks for its own name and is a legitimate backlink to the site.

**Who does it:** you (needs your account or your judgement; it can't be done from the repo).

## Steps

1. **The repo is currently PRIVATE, so none of this helps until you decide to make it public.** Making it public is your call.
2. Before going public: search history for secrets (`gitleaks detect` or `trufflehog git file://.`). `firebase-service-account.json` is gitignored, but `GoogleService-Info.plist` is committed on purpose. Rotate anything that ever leaked.
3. Then set the metadata: `gh repo edit anaghNathwani/bird-map --description "Citizen science bird sightings, identified on your phone" --homepage https://getbiomap.web.app --add-topic birding --add-topic citizen-science --add-topic swiftui --add-topic tensorflow-lite --add-topic birdnet`.

**Done when:** the repo is public with a description, website link and topics (or you've decided to keep it private).
