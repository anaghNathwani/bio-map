"""
Mirrors bug-type docs from the private `feedback` collection (written by the iOS app's
Profile -> Feedback) into the public `bugTracker` collection that the website's Bug tracker page
(/blog/bug-tracker) reads. Only safe fields are copied: when it was reported, a generic title and
the app version. The message, email and user id never leave `feedback`.

Each bugTracker doc has: title, reportedAt, notedAt, fixedAt, appVersion. notedAt and fixedAt start
empty. Existing docs are never overwritten, so your edits stick. Stamp them either in the Firebase
console (set the field to a timestamp, and edit `title` to describe the bug) or from here:

  python sync_bug_tracker.py --service-account key.json                  # copy new bugs
  python sync_bug_tracker.py --service-account key.json --list           # show bugs + the private report text
  python sync_bug_tracker.py --service-account key.json --note <id> --title "Brief description"
  python sync_bug_tracker.py --service-account key.json --title "New title" --id <id>   # rename only
  python sync_bug_tracker.py --service-account key.json --fix <id>
  python sync_bug_tracker.py --service-account key.json --only <id>      # copy just this one bug (not every new one)
  ... --note <id> --title "..." --at "2026-11-16 16:17"                  # stamp a specific local time instead of now
  ... --fix <id> --at "2026-11-17 19:55" [--tz America/Los_Angeles]

The title is shown publicly, so write it yourself (no names, emails or other personal details).
"""

import argparse
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from firestore_client import get_db


def parse_when(text, tz):
    """'2026-11-16 16:17' in the given timezone -> an aware UTC datetime."""
    return datetime.strptime(text, "%Y-%m-%d %H:%M").replace(tzinfo=ZoneInfo(tz)).astimezone(timezone.utc)


def sync(db, only=None):
    existing = {d.id for d in db.collection("bugTracker").stream()}
    created = 0
    for doc in db.collection("feedback").stream():
        data = doc.to_dict() or {}
        if data.get("type") != "bug" or doc.id in existing:
            continue
        if only and doc.id != only:
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


def stamp(db, bug_id, field, title=None, when=None):
    ref = db.collection("bugTracker").document(bug_id)
    if not ref.get().exists:
        raise SystemExit(f"No bugTracker doc with id {bug_id}")
    update = {field: when or datetime.now(timezone.utc)}
    if title:
        update["title"] = title
    ref.update(update)
    print(f"{bug_id}: {field} set")


def list_bugs(db):
    for doc in db.collection("bugTracker").order_by("reportedAt").stream():
        d = doc.to_dict()
        status = "fixed" if d.get("fixedAt") else "noted" if d.get("notedAt") else "reported"
        message = ((db.collection("feedback").document(doc.id).get().to_dict() or {}).get("message") or "").strip()
        print(f"{doc.id}  [{status}]  {d.get('reportedAt'):%Y-%m-%d}  title: {d.get('title')}")
        print(f"    report (private): {message[:300]}\n")


def rename(db, bug_id, title):
    ref = db.collection("bugTracker").document(bug_id)
    if not ref.get().exists:
        raise SystemExit(f"No bugTracker doc with id {bug_id}")
    ref.update({"title": title})
    print(f"{bug_id}: title set")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--service-account")
    ap.add_argument("--note", metavar="ID")
    ap.add_argument("--fix", metavar="ID")
    ap.add_argument("--title")
    ap.add_argument("--id", metavar="ID", help="with --title alone: the bug to rename")
    ap.add_argument("--only", metavar="ID", help="when copying new bugs, copy just this one")
    ap.add_argument("--at", metavar="'YYYY-MM-DD HH:MM'", help="with --note/--fix: the time to record, instead of now")
    ap.add_argument("--tz", default="America/Los_Angeles", help="timezone of --at (default: Pacific)")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    db = get_db(args.service_account)
    if args.list:
        list_bugs(db)
    elif args.id and args.title:
        rename(db, args.id, args.title)
    elif args.note:
        if not args.title:
            raise SystemExit('--note needs --title "brief description of the bug"')
        stamp(db, args.note, "notedAt", args.title, parse_when(args.at, args.tz) if args.at else None)
    elif args.fix:
        stamp(db, args.fix, "fixedAt", args.title, parse_when(args.at, args.tz) if args.at else None)
    else:
        sync(db, args.only)


if __name__ == "__main__":
    main()
