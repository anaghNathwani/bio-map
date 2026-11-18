// Blog posts as plain data (no markdown pipeline needed). Block types:
//   { h2: 'Heading' } | { p: 'Paragraph' } | { ul: ['item', ...] }
// Set "pinned": true to list a post under "Important" in the blog sidebar (the Bug tracker is a fixed entry there); the rest appear under "General".
// Titles must stay short enough that "<title> | BioMap" fits in ~65 characters.
export const POSTS = [
{
  "slug": "install-biomap-testflight",
  "pinned": true,
  "title": "How to install BioMap with TestFlight",
  "description": "A step-by-step guide to getting the BioMap beta on your iPhone using Apple's TestFlight app.",
  "date": "2026-10-18",
  "body": [
    { "p": "BioMap is in beta, so it is installed through TestFlight, Apple's free app for trying apps before they are on the App Store. It takes about five minutes." },
    { "h2": "Before you start" },
    { "ul": [
      "An iPhone or iPad running a recent version of iOS.",
      "An Apple ID. TestFlight sends your invite to the email address on your Apple ID, which is why the waitlist asks for an iCloud address.",
      "A little free storage space for two apps: TestFlight and BioMap."
    ] },
    { "h2": "Step 1: Join the waitlist" },
    { "p": "Use the Join the waitlist button on the BioMap home page and enter your iCloud email address. We send invitations in batches, so it can take a little while." },
    { "h2": "Step 2: Install TestFlight" },
    { "p": "Open the App Store on your phone, search for TestFlight, and install it. It is made by Apple and is free." },
    { "h2": "Step 3: Open your invitation" },
    { "p": "When your invite is ready you will get an email from TestFlight. Open that email on the same iPhone, then tap View in TestFlight or Start Testing. If you have a public invite link instead, tapping it on your phone does the same thing." },
    { "h2": "Step 4: Accept and install" },
    { "p": "TestFlight opens and shows BioMap. Tap Accept if it asks, then tap Install. When it finishes, the button changes to Open." },
    { "h2": "Step 5: Open BioMap" },
    { "p": "Tap Open, or find the BioMap icon on your home screen. The first time, iOS asks for permission to use your camera, microphone and location. These are only used for identifying and mapping the birds you choose to report." },
    { "h2": "Keeping it up to date" },
    { "p": "TestFlight tells you when a new build is available. Open TestFlight and tap Update next to BioMap. Beta builds also expire after a while, so update regularly." },
    { "h2": "Reporting a problem" },
    { "p": "In the app, go to Profile and open Feedback to report a bug or suggest a feature. Reported bugs show up on the Bug tracker page here on the blog." },
    { "h2": "If something goes wrong" },
    { "ul": [
      "No invite email: check your spam folder, and make sure you signed up with the email address on your Apple ID.",
      "The invite link does nothing: open it on your iPhone, not a computer, and make sure TestFlight is installed first.",
      "Install button missing: the beta may be full. Check back later or stay on the waitlist.",
      "The app stopped opening: its beta build has probably expired, so update it in TestFlight."
    ] }
  ]
},
{
  "slug": "finding-several-birds-in-one-photo",
  "title": "Finding several birds in one photo",
  "description": "A bug report said BioMap missed birds when more than one was in the frame. Here is what was wrong, how we fixed it, and how well it works.",
  "date": "2026-11-17",
  "body": [
    { "p": "A tester reported that BioMap fails to notice when there is more than one bird in a photo. We measured the problem, fixed it, and measured again. This post covers what we found and what we have not yet been able to check." },
    { "h2": "What was wrong" },
    { "p": "The photo model looks at the whole picture and gives one answer. For a second species, the app was meant to use a bird detector that finds each bird in the frame. That detector had never been published to the app, so BioMap fell back to a simpler method that picks out the most eye-catching regions of the photo. We tested that fallback on 160 photos containing several birds, and it found no additional species in any of them." },
    { "p": "There was a second effect. When two birds shared a frame, the whole-picture answer was often empty because the model was not sure which bird to name. In our test set that happened for 54% of the two-bird photos." },
    { "h2": "What we changed" },
    { "p": "BioMap now also looks at overlapping square windows across the photo, about fifteen for a typical phone photo, and classifies each window with the same on-device model. The answers are combined into one list with a species and its best window each. A species is shown as an extra only when the evidence is strong:" },
    { "ul": [
      "one window is at least 70% sure, or two or more windows agree and the best is at least 60% sure;",
      "the window is not mostly inside the region already explained by the main species, which is usually the same bird with a different label;",
      "at most three extra species are shown."
    ] },
    { "p": "When the whole photo gets no answer at all, the best window answer becomes the main suggestion instead of leaving the screen empty. Everything still runs on the phone." },
    { "h2": "How we tested it" },
    { "p": "We do not have a large set of labelled photos with several birds, so we built one. We took single-bird photos with known species and placed two or three of them in a frame, 320 frames in total, in four layouts: pairs, triples, a large bird beside a small one, and two birds of the same species. We also ran single-bird photos to see how often the app invents a second species. The same frames were run before and after the change." },
    { "h2": "Results" },
    { "ul": [
      "Pairs: every bird found in 96% of frames, up from 0%.",
      "Triples: every bird found in 100% of frames, up from 0%.",
      "A large bird beside a small one: every bird found in 65% of frames, up from 0%. Small birds are the hard case.",
      "Wrong extra species: about 0.06 per single-bird photo, and none on the frames with two birds of the same species."
    ] },
    { "p": "We chose the thresholds from these numbers. A lower bar finds more small birds, but it also adds wrong species to ordinary single-bird photos, and we would rather miss a bird than invent one." },
    { "h2": "What we have not checked" },
    { "ul": [
      "These are composite frames, not real photos of flocks. Real photos have overlapping birds, motion blur and cluttered backgrounds that our frames do not.",
      "We have not tried it on a phone yet. The fix ships in the next beta build, so the first real-world test will be yours.",
      "Scanning many windows takes longer than classifying one photo. We have not yet measured the delay on a phone."
    ] },
    { "p": "If BioMap still misses a bird or names one that is not there, please report it from Profile, then Feedback. Reports appear on the Bug tracker page, with the time each one was noted and fixed." }
  ]
},
{
  "slug": "identify-birds-without-internet",
  "title": "How BioMap identifies birds without the internet",
  "description": "The photo and sound models behind BioMap run on your phone, so you get a species suggestion in the field even with no signal.",
  "date": "2026-09-25",
  "body": [
    {
      "p": "Most bird ID apps send your photo or recording to a server and wait for an answer. BioMap does the identification on the phone itself, which is why it still works on a trail with no signal."
    },
    {
      "h2": "Photos"
    },
    {
      "p": "Photo suggestions come from Google’s AIY Birds model, a compact MobileNetV2 network that covers about 960 species. The model ships inside the app, so classifying a photo is just a calculation on your phone. If the model is not confident enough, BioMap tells you so instead of showing a low-quality guess."
    },
    {
      "h2": "Sound"
    },
    {
      "p": "Recordings are analysed with BirdNET, the bird-sound model from the Cornell Lab of Ornithology. It also runs on the device, right after you stop recording. BioMap feeds it your location and the time of year so that species which do not occur near you are ruled out, a step that matters because sound models can otherwise name an unlikely bird for background noise."
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
      "p": "If you are offline when you submit, BioMap keeps the sighting and retries the next time the app opens."
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
  "description": "How everyday bird sightings become useful data, why verification matters, and how BioMap approaches it.",
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
      "p": "Data is only as useful as it is trustworthy. A misidentified bird is worse than no record. In BioMap every sighting can be reviewed by other birders who confirm or correct the species, and several annotations on one sighting form a consensus. Annotations that do not look like a real bird name are flagged instead of counted."
    },
    {
      "h2": "Geotagged by design"
    },
    {
      "p": "Each BioMap sighting carries GPS coordinates and a timestamp, which is what makes it possible to map species over space and time."
    },
    {
      "h2": "Be part of the bigger picture"
    },
    {
      "p": "BioMap is a young project. Established programs such as eBird from the Cornell Lab of Ornithology have far larger datasets, and contributing there as well is a great idea. BioMap’s aim is to make it easy to identify and share what you see, right from your phone."
    }
  ]
},
{
  "slug": "keeping-bird-id-on-your-phone",
  "title": "Why we keep bird identification on your phone",
  "description": "Privacy, speed and reliability: the reasons BioMap runs its identification models on the device instead of a server.",
  "date": "2026-09-25",
  "body": [
    {
      "p": "It would have been simpler to upload every photo and recording to a server and run bigger models there. We chose not to, for three reasons."
    },
    {
      "h2": "Privacy"
    },
    {
      "p": "A photo of your garden or a recording near your home can reveal a lot. With on-device identification, nothing is uploaded just to get a suggestion. A sighting is only shared when you decide to submit it."
    },
    {
      "h2": "Speed and reliability"
    },
    {
      "p": "Birds do not wait. On-device models answer right away and work without a signal, which is exactly when you are outdoors."
    },
    {
      "h2": "Keeping it sustainable"
    },
    {
      "p": "Running models on the phone means there is no per-request server cost to pay for, which lets a community project stay free to use."
    },
    {
      "h2": "What it costs us"
    },
    {
      "p": "On-device models have to be compact, so they cannot match the largest server models. We are open about that: BioMap reports low confidence honestly and relies on the community to correct mistakes. Read more about the limits on the on-device AI page."
    }
  ]
},
]
