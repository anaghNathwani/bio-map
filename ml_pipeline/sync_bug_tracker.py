"""
Mirrors bug-type docs from the private `feedback` collection (written by the iOS app's
Profile -> Feedback) into the public `bugTracker` collection that the website's Bug tracker page
(/blog/bug-tracker) reads. Only safe fields are copied: when it was reported, a generic title and
the app version. The message, email and user id never leave `feedback`.

Each bugTracker doc has: title, reportedAt, notedAt, fixedAt, appVersion. notedAt and fixedAt start
empty. Existing docs are never overwritten, so your edits stick. Stamp them either in the Firebase
console (set the field to a timestamp, and edit `title` to describe the bug) or from here:

  python sync_bug_tracker.py --service-account key.json                  # copy new bugs
  python sync_bug_tracker.py --service-account key.json --note <id> [--title "Map overlay"]
  python sync_bug_tracker.py --service-account key.json --fix <id>
"""

import argparse
from datetime import datetime, timezone

from firestore_client import get_db


def sync(db):
    existing = {d.id for d in db.collection("bugTracker").stream()}
    created = 0
    for doc in db.collection("feedback").stream():
        data = doc.to_dict() or {}
        if data.get("type") != "bug" or doc.id in existing:
            continue
        version = data.get("appVersion") or "unknown"
        db.collection("bugTracker").document(doc.id).set({
            "title": f"Bug report ({doc.id[:6]})",
            "reportedAt": data.get("createdAt") or datetime.now(timezone.utc),
            "notedAt": None,
            "fixedAt": None,
            "appVersion": version,
        })
        created += 1
    print(f"bugTracker: {created} new bug(s) copied, {len(existing)} already tracked")


def stamp(db, bug_id, field, title=None):
    ref = db.collection("bugTracker").document(bug_id)
    if not ref.get().exists:
        raise SystemExit(f"No bugTracker doc with id {bug_id}")
    update = {field: datetime.now(timezone.utc)}
    if title:
        update["title"] = title
    ref.update(update)
    print(f"{bug_id}: {field} set")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--service-account")
    ap.add_argument("--note", metavar="ID")
    ap.add_argument("--fix", metavar="ID")
    ap.add_argument("--title")
    args = ap.parse_args()
    db = get_db(args.service_account)
    if args.note:
        stamp(db, args.note, "notedAt", args.title)
    elif args.fix:
        stamp(db, args.fix, "fixedAt", args.title)
    else:
        sync(db)


if __name__ == "__main__":
    main()
