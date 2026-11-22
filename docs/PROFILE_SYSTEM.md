# Profiles, following, messaging and notifications (design)

Status: design only, nothing built yet. Written against the code as of build 6.

## What exists today

- `users/{uid}` holds `username` and `annotationCount`. The leaderboard (`FirebaseService.fetchLeaderboard`) lists the top 50 by `annotationCount`; rows are not tappable.
- `ProfileView` is your own settings screen. There is no public profile, no follow or friend concept, no messaging, and no onboarding after sign-up.
- Annotations live under `sightings/{id}/annotations`, so "all annotations by one person" needs a collection-group query.
- The app has no push entitlement and no notification code. There is no backend (Firebase Auth + Firestore only, no card on file, so no Cloud Functions).

## Product shape

1. **Leaderboard row -> public profile.** Avatar, username, bio, counts (sightings, annotations, followers, following), a Follow button, and a Message button when allowed. Two tabs: **Sightings** and **Annotations**. Tapping an item opens the normal sighting detail.
2. **Follow is one-way; friends are mutual follows.** Nobody needs to approve anything. If A follows B and B follows A, they are friends and can message each other. This is the main anti-spam control: a stranger cannot message you.
3. **Notifications** for new posts by people you follow, plus the other topics below. Chosen during onboarding, changeable later.
4. **Onboarding** (after first sign-up, and once for existing users): **Terms of Service acceptance (built; `TermsAcceptanceView`)**, then choose what to be notified about, then the iOS permission prompt only if at least one topic was chosen.

## Data model (Firestore)

```
users/{uid}                      public profile (any signed-in user can read)
  username, annotationCount      (existing)
  bio                            string, max 160
  avatar                         tiny base64 JPEG, 128 px, max ~20 KB (same embed-in-Firestore pattern as photos)
  createdAt

users/{uid}/private/prefs        owner only
  notify: { followedPosts, newFollowers, messages, annotationsOnMyPosts, aiReviewOnMine, weeklyDigest }
  onboardedAt, lastFeedCheck

users/{uid}/private/devices/{id} owner only; FCM token if server push is added later

users/{uid}/blocks/{otherUid}    owner only: people I blocked

follows/{followerUid}_{followeeUid}
  followerId, followeeId, createdAt        deterministic id = no duplicate follows

conversations/{uidA}_{uidB}      ids are the two uids sorted
  members: [uidA, uidB], lastMessage, lastAt, unread: { uidA: n, uidB: n }
conversations/{id}/messages/{msgId}
  senderId, text (max 1000), createdAt

reports/{id}                     write-only from clients (reporter, target, reason); read in the console
```

Counts (followers, following) come from Firestore `count()` aggregate queries on `follows`, not stored counters. A stored counter would have to be writable by other users, which the rules cannot make safe.

### Queries

| Screen | Query |
|---|---|
| Following list | `follows` where `followerId == me` |
| Followers list | `follows` where `followeeId == uid` |
| A user's sightings | `sightings` where `userId == uid` order by `createdAt` desc, limit 30 (composite index) |
| A user's annotations | collection group `annotations` where `userId == uid` order by `createdAt` desc, limit 30 (collection-group index) |
| Feed check (for notifications) | `sightings` where `userId in [up to 30 followed ids]` and `createdAt > lastFeedCheck` |
| Inbox | `conversations` where `members` array-contains me order by `lastAt` desc |

`in` is capped at 30 ids, so someone following more than 30 people is checked in batches of 30.

### Rules (sketch)

```
match /follows/{id} {
  allow read: if request.auth != null;
  allow create: if request.auth != null
    && request.resource.data.followerId == request.auth.uid
    && id == request.auth.uid + '_' + request.resource.data.followeeId
    && request.resource.data.followeeId != request.auth.uid;
  allow delete: if request.auth != null && resource.data.followerId == request.auth.uid;
}
match /conversations/{cid} {
  allow read: if request.auth != null && request.auth.uid in resource.data.members;
  allow create: if request.auth != null && request.auth.uid in request.resource.data.members;   // + friendship check below
  match /messages/{mid} {
    allow read: if request.auth != null && request.auth.uid in get(/databases/$(database)/documents/conversations/$(cid)).data.members;
    allow create: if request.auth != null
      && request.resource.data.senderId == request.auth.uid
      && request.resource.data.text.size() <= 1000
      && /* both follow docs exist */ exists(...) && exists(...)
      && /* recipient has not blocked the sender */ !exists(...);
  }
}
match /{path=**}/annotations/{id} { allow read: if true; }   // needed for the collection-group query
match /users/{uid}/private/{doc=**} { allow read, write: if request.auth.uid == uid; }
```

The existing `users` rule already lets any signed-in user read profiles and only the owner write. `annotationCount` is currently owner-writable, so a determined user could fake leaderboard rank; that is an existing weakness this design does not worsen.

## Notifications: the constraint that shapes everything

A notification about someone else's post or message has to come from something that is running when it happens. The app is not running, and there is no server. Options:

| Option | How | Delay | Cost / catch |
|---|---|---|---|
| **A. Local, app open** | Firestore snapshot listeners fire while the app is in use; show an in-app banner and a local notification | instant | only while the app is open |
| **B. Local, background refresh** | `BGAppRefreshTask` wakes the app now and then, it runs the feed check, and posts local notifications | iOS decides: roughly a few times a day, never if the app was force-quit | free, no server, unreliable timing |
| **C. Server push (FCM/APNs)** | something sends a push when a followed user posts | seconds | needs a sender. Cloud Functions needs Blaze (a card). A GitHub Actions poller (like `live_poll.py`) works free but delays up to its schedule (20 min) and Actions are currently blocked by billing. Also needs the Push Notifications capability and an APNs key uploaded to Firebase |

**Recommendation:** build A + B first. They are free and need no backend. Store FCM tokens from day one (`users/{uid}/private/devices`) so C can be added later without changing the data model, once a sender exists (Cloud Run funding, a self-hosted machine, or fixed Actions).

State this honestly in the app: "Notifications may arrive with a delay." Instant message and post alerts are not possible under the no-card rule.

### Topics (what onboarding offers)

| Topic | Default | Meaning |
|---|---|---|
| `followedPosts` | off | New sightings from people you follow |
| `newFollowers` | off | Someone followed you |
| `messages` | off | New messages from friends |
| `annotationsOnMyPosts` | off | Someone annotated your sighting |
| `aiReviewOnMine` | off | Your photo's species got a community vote |
| `weeklyDigest` | off | A weekly summary: your rank, followed activity |

Everything defaults to **off** (opt-in), and the system permission prompt appears only when at least one is on, with a sentence explaining why, at that moment.

## Screens and code

New: `Views/Profile/UserProfileView.swift` (public profile), `FollowListView.swift`, `Views/Messages/InboxView.swift` + `ConversationView.swift`, `Views/Onboarding/OnboardingView.swift` + `NotificationTopicsView.swift`, `Networking/SocialService.swift` (follows, conversations, reports, blocks), `Notifications/NotificationManager.swift` (permission, listeners, background task, local notifications), `Notifications/NotificationPrefs.swift`.

Changed: `LeaderboardView` (rows become `NavigationLink`s), `ProfileView` (edit bio/avatar, Following/Followers, Messages, Notification settings, Blocked users), `ContentView` (onboarding gate), `firestore.rules` and `firestore.indexes.json` (the two new indexes), `project.yml` (`BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes: fetch`, later `aps-environment`).

## App Store requirement you must plan for

An app with user-generated content and messaging must, under App Review guideline 1.2, offer: **report content and users, block users, terms that forbid abusive content, and a way to remove offenders.** Messaging between friends does not exempt it. The design includes block and report from the first version, and `reports` is read from the Firebase console until there is something better. The Terms page needs a clause covering messages and profiles.

## Privacy

- A profile shows only what is already public: username, optional bio and avatar, and sightings that are already on the public map.
- Add a "Hide my profile from non-followers" switch only if you want it; it needs a `private` flag on `users/{uid}` and the sightings query to respect it, which Firestore rules can do with a `get()` on the owner.
- Never expose email. Messages are readable by the two members and by you in the console; say so in the privacy policy.

## Cost on the free tier

Firestore's free quota is 50,000 reads and 20,000 writes a day. A message listener costs one read per new message per open conversation; a feed check is one read per new post plus one query; counts use aggregate queries (one read per 1,000 index entries). This is fine for a beta of hundreds of users; the 30-id `in` batches and the 20-minute floor on background checks keep it bounded.

## Build order

1. Public profile + tappable leaderboard (read-only; needs the annotations rule and two indexes).
2. Follow / unfollow, followers and following lists, counts.
3. Onboarding with notification topics, stored prefs, and the Settings screen for them.
4. Notifications A + B (listeners, background refresh, local notifications).
5. Friends + messaging, with block and report.
6. Server push, when a sender exists.

Steps 1 to 3 are about a week of work and carry no moderation risk; messaging (step 5) is the step that triggers the App Store requirement above, so it is last.
