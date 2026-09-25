// Plain data so it can be rendered on /faq, teased on the landing page and
// emitted as FAQPage JSON-LD (site.js) from one source of truth.
export const FAQ = [
  {
    q: 'What is BirdMap?',
    a: 'BirdMap is a citizen science app and live map for bird sightings. You photograph or record a bird, on-device AI suggests the species, and the community can confirm or correct it.',
  },
  {
    q: 'Is BirdMap free?',
    a: 'Yes. BirdMap does not currently charge for anything: no purchases and no subscriptions.',
  },
  {
    q: 'Where can I get the app?',
    a: 'The iOS app is coming soon to the App Store. The live sighting map already works in any web browser.',
  },
  {
    q: 'Do I need an internet connection to identify a bird?',
    a: 'No. Photo and sound identification both run on your phone. You need a connection to submit the sighting; if you are offline, submissions are queued and retried the next time the app opens.',
  },
  {
    q: 'How does BirdMap identify birds from photos?',
    a: 'A model on your phone based on Google\u2019s AIY Birds (about 960 species) suggests a species. If it is not confident it says so instead of guessing, and when a photo contains several birds it reviews each one separately.',
  },
  {
    q: 'How does BirdMap identify birds from sound?',
    a: 'Recordings are analysed on your phone with Cornell Lab of Ornithology\u2019s BirdNET. Your location is used to rule out species that do not live nearby, and every species it hears above the confidence threshold is reported, not just the loudest.',
  },
  {
    q: 'How accurate is it?',
    a: 'Best results come from clear, well-lit photos where the bird is the main subject, and from recordings made close to the bird, away from wind and voices. Distant, blurry or partly hidden birds get lower confidence. That is why community review exists.',
  },
  {
    q: 'Who can see my photos and location?',
    a: 'Identification happens on your phone, but when you submit a sighting it is shared with the BirdMap community along with its location, your username and any notes. Your email address is never shown publicly.',
  },
  {
    q: 'What are annotations?',
    a: 'An annotation is your own ID for a sighting: you can confirm the AI\u2019s guess, correct it, or mark it unsure, and add behaviour or plumage details. Annotations count toward the community leaderboard.',
  },
  {
    q: 'What happens to joke or spam annotations?',
    a: 'BirdMap checks on each device whether an annotation looks like a real bird name. Anything that does not is flagged with a label and left out of the consensus species. It is never deleted automatically.',
  },
  {
    q: 'Does BirdMap work outside the United States?',
    a: 'Yes. The identification models cover a global species list rather than one country, and audio results are narrowed using wherever you actually are.',
  },
  {
    q: 'Is there an Android version?',
    a: 'Not at the moment. BirdMap is iOS-first.',
  },
]
