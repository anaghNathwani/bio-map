# LinkedIn

Post as yourself, one image (`01-hero.png` or `02-how-it-works.png`), link in the first comment (LinkedIn reduces reach of posts with links in the body).

## Build-story post

I've been building BioMap, a citizen science app for bird sightings, and one technical detour is worth sharing.

The idea: take a bird photo or record a call, get an ID on your phone, then let other birders confirm or correct it. Everything identification-related runs on the device, so nothing is uploaded just to get a suggestion.

The detour: I converted Google's bird classifier to CoreML and it silently returned nearly the same output for a black image, a white image and a real bird photo. No error, just a model that looked like it worked. The same model in TensorFlow and TFLite was fine, so the app now runs it through TFLite.

What I took from it: with on-device ML, test the converted model against inputs where you know the answer, before you trust any output.

The app is still pre-release; the live map works in a browser. I'd love feedback from anyone who birds or works with citizen science data.

**First comment:** Live map and how it works: https://getbiomap.web.app

Hashtags (max 3): #CitizenScience #MachineLearning #iOSDevelopment
