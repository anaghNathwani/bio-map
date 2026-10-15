# BioMap final ad (rename story + TestFlight walkthrough)

- `biomap-final-ad.mp4`: the Reel (1080x1920, 50 s, original synthesized score)
- `biomap-final-ad-cover.png`: cover image (the name reveal). On the Reel: Edit cover -> Add from camera roll.

It joins `birdmap-is-now-biomap.mp4` (cut before its own end card) to `testflight-is-live.mp4` with a 0.6 s crossfade, so the link appears once, at the end. Regenerate with `python3 evolve.py && python3 testflight.py && python3 final_ad.py` from `docs/social/instagram/`.

## Caption

```
BirdMap is now BioMap, and the public beta is live on TestFlight.

Four taps to get in:
1. Install TestFlight (free, from Apple)
2. Open the invite link on your iPhone
3. Tap Accept, then Install
4. Open BioMap (the orange dot means it's a beta)

Join here: https://testflight.apple.com/join/ZcyddckA

iPhone with iOS 17 or later. It's a beta, so expect rough edges. If something breaks, open Profile in the app and tap Report a bug.

#birding #citizenscience #birdwatching #testflight #betatesting
```

## Notes

- Links in Instagram captions aren't tappable, so put the TestFlight link in your bio.
- The invite link only works while the TestFlight group is open and its build is approved; the public link's tester limit is your rollout throttle.
