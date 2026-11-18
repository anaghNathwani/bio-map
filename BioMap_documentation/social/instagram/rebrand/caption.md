# Rebrand announcement: "Our new name"

Files in this folder:

- `our-new-name.mp4`: the Reel (1080x1920, 17.4 s, original synthesized score)
- `our-new-name-cover.png`: cover image (the name reveal). On the Reel: Edit cover -> Add from camera roll.

Regenerate with `python3 build.py rebrand` from `docs/social/instagram/`.

## Caption

```
We're changing our name: BirdMap is now BioMap.

Same community, same sightings, same citizen science. Just a new name.

Bio for life, Map for where it's found.

The iOS app is coming soon. The live map works in your browser now (link in bio).

#birding #citizenscience #birdwatching #birdsofinstagram
```

## First comment (optional)

```
New home on the web: getbiomap.web.app. The old links forward there, so nothing you saved breaks.
```

## Notes

- Only the name is changing. The Reel deliberately claims nothing new about the app.
- Post it once the new name is final everywhere you can control: the Instagram handle and display name (the old handle suggestions in `INSTAGRAM_PLAN.md` were renamed too), the App Store listing, and the profile link.
- If the bio link or handle changes, update the on-screen URL in `build.py`'s `brandbar()` and re-render.
