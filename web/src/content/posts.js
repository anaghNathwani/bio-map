// Blog posts as plain data (no markdown pipeline needed). Block types:
//   { h2: 'Heading' } | { p: 'Paragraph' } | { ul: ['item', ...] }
// Titles must stay short enough that "<title> | BirdMap" fits in ~65 characters.
export const POSTS = [
{
  "slug": "identify-birds-without-internet",
  "title": "How BirdMap identifies birds without the internet",
  "description": "The photo and sound models behind BirdMap run on your phone, so you get a species suggestion in the field even with no signal.",
  "date": "2026-09-25",
  "body": [
    {
      "p": "Most bird ID apps send your photo or recording to a server and wait for an answer. BirdMap does the identification on the phone itself, which is why it still works on a trail with no signal."
    },
    {
      "h2": "Photos"
    },
    {
      "p": "Photo suggestions come from Google’s AIY Birds model, a compact MobileNetV2 network that covers about 960 species. The model ships inside the app, so classifying a photo is just a calculation on your phone. If the model is not confident enough, BirdMap tells you so instead of showing a low-quality guess."
    },
    {
      "h2": "Sound"
    },
    {
      "p": "Recordings are analysed with BirdNET, the bird-sound model from the Cornell Lab of Ornithology. It also runs on the device, right after you stop recording. BirdMap feeds it your location and the time of year so that species which do not occur near you are ruled out, a step that matters because sound models can otherwise name an unlikely bird for background noise."
    },
    {
      "h2": "What still needs a connection"
    },
    {
      "ul": [
        "Submitting a sighting to the shared map.",
        "Reading other people’s sightings and annotations.",
        "Downloading an updated photo model, which can be delivered without an App Store release."
      ]
    },
    {
      "p": "If you are offline when you submit, BirdMap keeps the sighting and retries the next time the app opens."
    },
    {
      "h2": "The trade-off"
    },
    {
      "p": "A model small enough to run on a phone is not perfect. That is why every suggestion can be confirmed, corrected or marked unsure, and why community review sits on top of the AI."
    }
  ]
},
{
  "slug": "what-is-citizen-science-bird-data-for",
  "title": "What is citizen science bird data actually for?",
  "description": "How everyday bird sightings become useful data, why verification matters, and how BirdMap approaches it.",
  "date": "2026-09-25",
  "body": [
    {
      "p": "A single sighting is a small fact: a species, a place and a time. Thousands of them, collected carefully, can show things that no single observer could see."
    },
    {
      "h2": "What sightings can reveal"
    },
    {
      "ul": [
        "Migration timing: when a species arrives and leaves a region.",
        "Population shifts: whether a species is becoming more or less common.",
        "Range changes: birds appearing in places they were not seen before."
      ]
    },
    {
      "h2": "Why verification matters"
    },
    {
      "p": "Data is only as useful as it is trustworthy. A misidentified bird is worse than no record. In BirdMap every sighting can be reviewed by other birders who confirm or correct the species, and several annotations on one sighting form a consensus. Annotations that do not look like a real bird name are flagged instead of counted."
    },
    {
      "h2": "Geotagged by design"
    },
    {
      "p": "Each BirdMap sighting carries GPS coordinates and a timestamp, which is what makes it possible to map species over space and time."
    },
    {
      "h2": "Be part of the bigger picture"
    },
    {
      "p": "BirdMap is a young project. Established programs such as eBird from the Cornell Lab of Ornithology have far larger datasets, and contributing there as well is a great idea. BirdMap’s aim is to make it easy to identify and share what you see, right from your phone."
    }
  ]
},
]
