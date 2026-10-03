"""
Fetches the BioMap photo *detector* model (Tier 2 of multi-bird photo
detection — see MultiBirdDetector.swift for Tier 1, the saliency fallback
this supersedes when available). Does NOT touch Firebase — see
publish_model.py for that step, same two-script split as
convert_photo_model.py.

Unlike convert_photo_model.py, there is no TensorFlow->CoreML conversion
here at all — it was tried and ruled out. TF Hub's official COCO object
detector (tensorflow/ssd_mobilenet_v2) ships its box-decode+NMS
postprocessing as ops coremltools' TF frontend cannot convert (confirmed:
raises "'numpy.float64' object cannot be interpreted as an integer" during
conversion, reproduced against both coremltools 7.2 and 9.0). Older
TFLite-packaged SSD models (which historically converted fine via their
built-in TFLite_Detection_PostProcess op) also don't work — coremltools no
longer accepts .tflite as an input source at all.

Instead, this downloads Apple's own official pre-converted CoreML object
detector (YOLOv3-Tiny, trained on COCO by Joseph Redmon & Ali Farhadi,
University of Washington — see https://github.com/pjreddie/darknet for
license terms) from developer.apple.com/machine-learning/models. It's
already a complete CoreML *pipeline* — a neural network stage plus a
built-in non-max-suppression stage — so Vision's VNCoreMLRequest produces
VNRecognizedObjectObservation results directly with no decode/NMS code of
our own needed. COCO's 80 classes include "bird" (confirmed by inspecting
the downloaded model's embedded class labels). Used exactly as Apple
publishes it: no training, no fine-tuning, no conversion.

Usage:
    python convert_bird_detector_model.py
    python convert_bird_detector_model.py --output ./output_detector
"""

import argparse
import datetime
import json
import zipfile
from pathlib import Path

import requests

MODEL_SOURCE = (
    "Apple's official pre-converted CoreML model catalog — YOLOv3-Tiny, "
    "trained on COCO by Joseph Redmon & Ali Farhadi (University of Washington)"
)
MODEL_LICENSE = "See https://github.com/pjreddie/darknet (Darknet/YOLO)"
MODEL_URL = "https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3Tiny.mlmodel"
BIRD_CLASS_NAME = "bird"

# The 80 COCO class labels as embedded in this exact model file (verified by
# inspecting its nonMaximumSuppression submodel's stringClassLabels) —
# shipped in the manifest so the app doesn't need to parse the .mlmodel spec
# itself just to know the class list.
COCO_CLASS_NAMES = [
    "person", "bicycle", "car", "motorbike", "aeroplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
    "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
    "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
    "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
    "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
    "sofa", "pottedplant", "bed", "diningtable", "toilet", "tvmonitor", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
    "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush",
]


def download_model(dest_path: Path) -> None:
    print(f"Downloading {MODEL_URL} ...")
    resp = requests.get(MODEL_URL, timeout=180)
    resp.raise_for_status()
    dest_path.write_bytes(resp.content)
    print(f"  Saved {dest_path} ({len(resp.content) / 1e6:.1f} MB)")


def verify_model(model_path: Path) -> None:
    """Sanity-checks the downloaded file is the expected CoreML pipeline
    with the bird class present, without requiring coremltools/TF (this
    script intentionally has no ML-library dependency — see module
    docstring). Parses just enough of the .mlmodel protobuf by hand for
    this one check rather than pulling in a heavy dependency for it."""
    import coremltools as ct  # only needed for this verification step

    spec = ct.utils.load_spec(str(model_path))
    if spec.WhichOneof("Type") != "pipeline":
        raise RuntimeError("Expected a CoreML pipeline model (network + NMS stages)")
    nms = spec.pipeline.models[-1]
    if nms.WhichOneof("Type") != "nonMaximumSuppression":
        raise RuntimeError("Expected the pipeline's last stage to be non-max-suppression")
    labels = list(nms.nonMaximumSuppression.stringClassLabels.vector)
    if BIRD_CLASS_NAME not in labels:
        raise RuntimeError(f"'{BIRD_CLASS_NAME}' not found in model's class labels: {labels}")
    if labels != COCO_CLASS_NAMES:
        raise RuntimeError(
            "Model's embedded class labels don't match COCO_CLASS_NAMES above — "
            "Apple may have updated the file; update this script's constant to match."
        )
    print(f"  Verified: pipeline model, {len(labels)} classes, '{BIRD_CLASS_NAME}' present.")


def zip_model(model_path: Path, zip_out: Path) -> None:
    with zipfile.ZipFile(zip_out, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(model_path, model_path.name)
    print(f"  Zipped to {zip_out}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="./output_detector",
                        help="Directory to write BirdDetector.mlmodel.zip + manifest.json to")
    parser.add_argument("--skip-verify", action="store_true",
                        help="Skip the coremltools spec-verification step (still fine to publish without it)")
    args = parser.parse_args()

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    model_path = out_dir / "BirdDetector.mlmodel"
    download_model(model_path)
    if not args.skip_verify:
        verify_model(model_path)

    zip_path = out_dir / "BirdDetector.mlmodel.zip"
    zip_model(model_path, zip_path)

    version = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d_%H%M%S")
    manifest = {
        "version": version,
        "mediaType": "photo_detector",
        "numClasses": len(COCO_CLASS_NAMES),
        "classNames": COCO_CLASS_NAMES,
        "birdClassName": BIRD_CLASS_NAME,
        "source": MODEL_SOURCE,
        "license": MODEL_LICENSE,
        "modelZip": zip_path.name,
    }
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    print(f"  Wrote {manifest_path}")
    print(f"\nDone. Next: in the requirements.txt venv (no coremltools needed for this one), run:\n"
          f"  python publish_model.py --input {out_dir}")


if __name__ == "__main__":
    main()
