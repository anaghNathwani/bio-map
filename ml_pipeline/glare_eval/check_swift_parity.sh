#!/bin/sh
# Checks that ios/BioMap/BioMap/ML/GlareCorrector.swift reproduces glare_lib.adaptive() (same flags, same pixels).
#   ./check_swift_parity.sh /path/to/glare_set
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SET="${1:?usage: check_swift_parity.sh /path/to/glare_set}"
TMP="$(mktemp -d)"
"$HERE/../.venv/bin/python" "$HERE/dump_parity_cases.py" --set "$SET" --out "$TMP/cases"
mkdir "$TMP/swift" && cp "$HERE/../../ios/BioMap/BioMap/ML/GlareCorrector.swift" "$TMP/swift/" && cp "$HERE/parity_main.swift" "$TMP/swift/main.swift"
swiftc -O "$TMP/swift/GlareCorrector.swift" "$TMP/swift/main.swift" -o "$TMP/parity"
"$TMP/parity" "$TMP/cases"
