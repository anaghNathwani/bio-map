"""
Emails anaghnathwani@gmail.com whenever someone joins the website's waitlist, or sends a bug report /
feature request from the iOS app (Profile -> Feedback, stored in the `feedback` collection)
(web/src/components/WaitlistButton.jsx writes to the `waitlist` Firestore collection; see
firestore.rules — it's write-only from the client, so this script, running with the Admin SDK, is
the only thing that ever reads it).

Run once per invocation (like live_poll.py) — scheduled every 10 minutes by
.github/workflows/notify-waitlist.yml. Finds every waitlist doc not yet marked `notified`,
emails them all in one message (so a burst of signups is one email, not one per signup), then
marks them notified so the next run doesn't repeat them. Sends nothing, and touches no documents,
when there's nothing new — this is meant to run quietly most of the time.

Email delivery is via Resend (resend.com): a free transactional-email API, no credit card, whose
sandbox sender (onboarding@resend.dev) needs no domain setup to send to a single verified
address. One-time setup:
  1. Sign up at https://resend.com (free).
  2. Verify anaghnathwani@gmail.com as a recipient if the dashboard asks you to (sandbox mode
     only allows sending to addresses you've verified, until you verify a domain).
  3. API Keys -> Create API Key -> copy it.
  4. Add it as a repo secret named RESEND_API_KEY (Settings -> Secrets and variables -> Actions).

  python notify_waitlist_signups.py --service-account /path/to/firebase-key.json
"""

import argparse
import json
import os
import urllib.error
import urllib.request

RESEND_URL = "https://api.resend.com/emails"
DEFAULT_TO = "anaghnathwani@gmail.com"
DEFAULT_FROM = "BioMap Alerts <onboarding@resend.dev>"


def fetch_unnotified(db):
    """All waitlist docs not yet emailed. Filtered in Python rather than with a Firestore
    `== false` query, since that query silently skips docs where the field is simply absent —
    not a concern here (every doc is written with notified: false), but filtering locally also
    sidesteps needing a composite index for an inequality + orderBy."""
    docs = list(db.collection("waitlist").stream())
    pending = [d for d in docs if not d.to_dict().get("notified")]
    pending.sort(key=lambda d: d.to_dict().get("createdAt") or 0)
    return pending


def render_email(signups):
    lines_text = []
    rows_html = []
    for doc in signups:
        data = doc.to_dict()
        email = data.get("email", "(no email)")
        name = data.get("name") or "—"
        created = data.get("createdAt")
        when = created.isoformat(timespec="minutes") if hasattr(created, "isoformat") else str(created or "")
        lines_text.append(f"- {email}  (name: {name}, at: {when})")
        rows_html.append(
            f"<tr><td style='padding:4px 12px 4px 0'>{escape(email)}</td>"
            f"<td style='padding:4px 12px 4px 0'>{escape(name)}</td>"
            f"<td style='padding:4px 0;color:#6b6255'>{escape(when)}</td></tr>"
        )

    count = len(signups)
    subject = f"{count} new BioMap waitlist signup" + ("" if count == 1 else "s")
    text = f"{count} new signup(s) on the BioMap waitlist:\n\n" + "\n".join(lines_text)
    html = (
        "<div style='font-family:sans-serif'>"
        f"<p>{count} new signup(s) on the BioMap waitlist:</p>"
        "<table style='border-collapse:collapse'>"
        "<tr style='font-weight:600;text-align:left'><td style='padding:4px 12px 4px 0'>Email</td>"
        "<td style='padding:4px 12px 4px 0'>Name</td><td>Joined</td></tr>"
        + "".join(rows_html)
        + "</table></div>"
    )
    return subject, text, html


def fetch_unnotified_feedback(db):
    docs = list(db.collection("feedback").stream())
    pending = [d for d in docs if not d.to_dict().get("notified")]
    pending.sort(key=lambda d: d.to_dict().get("createdAt") or 0)
    return pending


def render_feedback_email(items):
    lines_text = []
    blocks_html = []
    for doc in items:
        d = doc.to_dict()
        kind = d.get("type", "other")
        who = d.get("username") or d.get("email") or d.get("userId", "unknown")
        meta = f"{d.get('device', '')} iOS {d.get('osVersion', '')}, v{d.get('appVersion', '?')} ({d.get('build', '?')})"
        msg = d.get("message", "")
        lines_text.append(f"[{kind}] from {who} ({meta})\n{msg}\n")
        blocks_html.append(
            f"<p style='margin:0 0 4px'><b>{escape(kind)}</b> from {escape(who)} "
            f"<span style='color:#6b6255'>({escape(meta)})</span></p>"
            f"<p style='margin:0 0 18px;white-space:pre-wrap'>{escape(msg)}</p>"
        )
    count = len(items)
    subject = f"{count} new BioMap feedback message" + ("" if count == 1 else "s")
    text = f"{count} new feedback message(s):\n\n" + "\n".join(lines_text)
    html = "<div style='font-family:sans-serif'>" + "".join(blocks_html) + "</div>"
    return subject, text, html


def escape(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def send_email(api_key, to_address, subject, text, html):
    body = json.dumps({"from": DEFAULT_FROM, "to": [to_address], "subject": subject, "text": text, "html": html}).encode()
    req = urllib.request.Request(
        RESEND_URL, data=body, method="POST",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--service-account")
    ap.add_argument("--to", default=DEFAULT_TO)
    ap.add_argument("--resend-api-key", default=os.environ.get("RESEND_API_KEY"))
    ap.add_argument("--dry-run", action="store_true", help="Print what would be sent; don't email or mark anything notified.")
    args = ap.parse_args()

    from firestore_client import get_db

    db = get_db(args.service_account)
    pending = fetch_unnotified(db)
    feedback = fetch_unnotified_feedback(db)

    if not pending and not feedback:
        print("No new waitlist signups or feedback.")
        return

    if not args.dry_run and not args.resend_api_key:
        raise SystemExit(
            "RESEND_API_KEY not set (env var or --resend-api-key). "
            "See this script's docstring for how to get one — nothing was sent, nothing was marked notified."
        )

    # Each batch is one email (a burst is one message, not one per item), then marked notified.
    batches = []
    if pending:
        batches.append((render_email(pending), pending))
    if feedback:
        batches.append((render_feedback_email(feedback), feedback))

    for (subject, text, html), docs in batches:
        print(f"{subject}:\n{text}")
        if args.dry_run:
            print("--dry-run: not sending, not marking notified.")
            continue
        status, resp_body = send_email(args.resend_api_key, args.to, subject, text, html)
        if status >= 300:
            raise SystemExit(f"Resend API error ({status}): {resp_body}")
        print(f"Email sent to {args.to} (status {status}).")
        batch = db.batch()
        for doc in docs:
            batch.update(doc.reference, {"notified": True})
        batch.commit()
        print(f"Marked {len(docs)} item(s) as notified.")


if __name__ == "__main__":
    main()
