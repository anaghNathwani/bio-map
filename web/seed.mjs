import { initializeApp } from 'firebase/app'
import { getFirestore, collection, addDoc, Timestamp } from 'firebase/firestore'

const firebaseConfig = {
  apiKey: 'AIzaSyB3VisSHGhcgr70jAkCWWMttS9kjeXHLck',
  authDomain: 'birdmap-citizenscience.firebaseapp.com',
  projectId: 'birdmap-citizenscience',
  storageBucket: 'birdmap-citizenscience.firebasestorage.app',
  messagingSenderId: '857243141648',
  appId: '1:857243141648:web:53bbd34201b43f26c32c95',
}

const app = initializeApp(firebaseConfig)
const db = getFirestore(app)

const BIRDS = [
  'Anna\'s Hummingbird', 'Western Scrub-Jay', 'California Towhee', 'Acorn Woodpecker',
  'Black Phoebe', 'Say\'s Phoebe', 'Nuttall\'s Woodpecker', 'Oak Titmouse',
  'Bushtit', 'Bewick\'s Wren', 'California Thrasher', 'Wrentit',
  'Lesser Goldfinch', 'House Finch', 'Purple Finch', 'Dark-eyed Junco',
  'White-crowned Sparrow', 'Golden-crowned Sparrow', 'California Gull', 'Western Gull',
  'Heermann\'s Gull', 'Brandt\'s Cormorant', 'Pelagic Cormorant', 'Brown Pelican',
  'Great Blue Heron', 'Great Egret', 'Snowy Egret', 'Black-crowned Night-Heron',
  'Turkey Vulture', 'Red-tailed Hawk', 'Cooper\'s Hawk', 'Sharp-shinned Hawk',
  'American Kestrel', 'White-tailed Kite', 'Osprey', 'Peregrine Falcon',
  'American Crow', 'Common Raven', 'Steller\'s Jay', 'Yellow-billed Magpie',
]

const USERNAMES = ['birdwatcher42', 'featherfiend', 'ornithophile', 'sparrowfan', 'hawkeye99']

// Rough California bounding box
const LAT = [32.5, 42.0]
const LON = [-124.5, -114.1]

function rand(min, max) { return min + Math.random() * (max - min) }
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)] }

async function seed() {
  const sightings = collection(db, 'sightings')
  const now = Date.now()

  for (let i = 0; i < 100; i++) {
    const species = pick(BIRDS)
    const username = pick(USERNAMES)
    const mediaType = Math.random() < 0.8 ? 'photo' : 'audio'
    const daysAgo = Math.floor(rand(0, 90))
    const ts = Timestamp.fromMillis(now - daysAgo * 86400000)

    await addDoc(sightings, {
      latitude: rand(LAT[0], LAT[1]),
      longitude: rand(LON[0], LON[1]),
      mediaType,
      aiSpeciesSuggestion: species,
      aiConfidence: parseFloat(rand(0.55, 0.98).toFixed(2)),
      annotationCount: Math.floor(rand(0, 5)),
      topSpecies: Math.random() > 0.4 ? species : null,
      notes: null,
      photoURL: null,
      thumbnailURL: null,
      audioURL: null,
      userId: 'seed-user',
      username,
      createdAt: ts,
    })
    process.stdout.write(`\r${i + 1}/100`)
  }
  console.log('\nDone.')
  process.exit(0)
}

seed().catch(e => { console.error(e); process.exit(1) })
