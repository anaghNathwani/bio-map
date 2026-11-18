#!/bin/bash
# Build the candidate from the ORIGINAL model with Stage 2's patch tool. Run from anywhere.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ORIG="$HERE/../../../ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite"
PLAN="$HERE/../plan"
PYTHONPATH="$HERE" "$HERE/../../.venv/bin/python" -c "
import pbshim, runpy, sys
sys.argv=['apply_edits.py','$ORIG','$HERE/BirdModel_chroma14_a05.tflite','$HERE/recipe_chroma14_a05.json']
runpy.run_path('$PLAN/apply_edits.py', run_name='__main__')"
