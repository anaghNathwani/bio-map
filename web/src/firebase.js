import { initializeApp } from 'firebase/app'
import { getFirestore, collection, getDocs, orderBy, limit, query, addDoc, serverTimestamp } from 'firebase/firestore'

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
}

const app = initializeApp(firebaseConfig)
export const db = getFirestore(app)

export async function fetchSightings(maxResults = 500) {
  const q = query(
    collection(db, 'sightings'),
    orderBy('createdAt', 'desc'),
    limit(maxResults)
  )
  const snap = await getDocs(q)
  return snap.docs.map(doc => ({ id: doc.id, ...doc.data() }))
}

/**
 * Writes a "Join the waitlist" signup. Write-only from the client (see
 * firestore.rules — no one can read this collection back, including other
 * visitors); ml_pipeline/notify_waitlist_signups.py is the only thing that
 * ever reads it, via the Admin SDK on a schedule, to email new signups.
 */
export async function submitWaitlistSignup({ email, name = '', source = 'website' }) {
  await addDoc(collection(db, 'waitlist'), {
    email: email.trim().toLowerCase(),
    name,
    source,
    notified: false,
    createdAt: serverTimestamp(),
  })
}

/** Public bug tracker rows (see firestore.rules `bugTracker` and ml_pipeline/sync_bug_tracker.py). */
export async function fetchBugTracker() {
  const snap = await getDocs(query(collection(db, 'bugTracker'), orderBy('reportedAt', 'desc'), limit(200)))
  return snap.docs.map(d => {
    const x = d.data()
    const ms = t => (t && t.toMillis ? t.toMillis() : null)
    return { id: d.id, title: x.title, appVersion: x.appVersion, reportedAt: ms(x.reportedAt), notedAt: ms(x.notedAt), fixedAt: ms(x.fixedAt) }
  })
}
