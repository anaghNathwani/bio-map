#!/bin/sh
# Compiles BioLoaderTimeline + OrganismData with the checks and runs them (no simulator needed).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
V="$HERE/../../BioMap/Views/Common"
TMP="$(mktemp -d)"
cp "$V/BioLoaderTimeline.swift" "$V/OrganismData.swift" "$TMP/" && cp "$HERE/main.swift" "$TMP/main.swift"
swiftc -O "$TMP"/*.swift -o "$TMP/check"
"$TMP/check"
