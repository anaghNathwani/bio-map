#!/usr/bin/env bash
# Compiles the on-device annotation moderator for the Mac and scores it. Run from anywhere.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../BioMap"
out="$(mktemp -d)"
swiftc -O -o "$out/eval" "$app/ML/AnnotationModerator.swift" "$here/main.swift"
"$out/eval" "$here" "$app/ML/Bundled"
