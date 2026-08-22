"""
Checks whether enough new, fully-processed annotations have accumulated since
the last training run to justify kicking off training for a given target
model. Run on the same 20-minute schedule as live_poll.py (see
.github/workflows/live-poll.yml's "check-training-trigger" job), but as its
own isolated job so a bug here can never break the working audio ID +
moderation poll.

Trigger state lives in a single Firestore doc per target, Admin-SDK-only
(no firestore.rules entry needed — Firestore is default-deny for any path
with no matching `match` block, same as model_versions' write side):

    meta/combinedModelTraining   { lastTrainedCount: int, lastTrainedAt: ts }
    meta/moderationModelTraining { lastTrainedCount: int, lastTrainedAt: ts }

"Count" is the number of annotations that have cleared moderation (i.e. are
no longer "pending") — these are the ones with a usable, non-transient
verdict, so they're the right denominator for both training targets.

Right now this script only observes and logs — it does not train anything
and does not advance lastTrainedCount. The moderation classifier
(train_moderation_classifier.py) and combined detector+classifier model
(train_combined_model.py) that would actually consume this signal are a
follow-on phase, not built yet. Advancing lastTrainedCount before a real
training+publish run exists would silently lose that batch of annotations
from ever being considered once training code does land, so it's
deliberately left alone here.

Usage:
    python check_training_trigger.py --target combined
    python check_training_trigger.py --target moderation --service-account path/to/key.json
"""

import argparse
import logging

from google.cloud.firestore_v1.base_query import FieldFilter

import firestore_client

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("check_training_trigger")

TRAIN_THRESHOLD = 500


def get_processed_annotation_count(db) -> int:
    query = db.collection_group("annotations").where(filter=FieldFilter("moderation", "!=", "pending"))
    result = query.count(alias="n").get()
    return result[0][0].value


def check(db, target: str) -> None:
    doc_ref = db.collection("meta").document(f"{target}ModelTraining")
    doc = doc_ref.get()
    last_trained_count = (doc.to_dict() or {}).get("lastTrainedCount", 0) if doc.exists else 0

    total = get_processed_annotation_count(db)
    new_since_last = total - last_trained_count

    if new_since_last >= TRAIN_THRESHOLD:
        logger.info(
            "[%s] Trigger fired: %d new processed annotations since last training "
            "(>= %d) — training/publish code for this target isn't built yet, "
            "so no action is taken. lastTrainedCount stays at %d.",
            target, new_since_last, TRAIN_THRESHOLD, last_trained_count,
        )
    else:
        logger.info(
            "[%s] Not yet: %d/%d new processed annotations since last training.",
            target, new_since_last, TRAIN_THRESHOLD,
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, choices=["combined", "moderation"])
    parser.add_argument("--service-account", default=None,
                        help="Path to a Firebase service account JSON. "
                             "Falls back to GOOGLE_APPLICATION_CREDENTIALS or ADC.")
    args = parser.parse_args()

    db = firestore_client.get_db(args.service_account)
    check(db, args.target)


if __name__ == "__main__":
    main()
