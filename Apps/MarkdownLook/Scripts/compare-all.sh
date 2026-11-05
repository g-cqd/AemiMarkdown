#!/bin/bash
# Scripts/compare-all.sh [--dark] [name-filter]: every component fixture drawn by WebKit and by the native view, with how alike they are (build first: swift build -c release --product markdown-look-compare).
cd "$(dirname "$0")/.." || exit 1
dark=""; [ "$1" = "--dark" ] && { dark="--dark"; shift; }
for f in Fixtures/components/*${1}*.md; do
    .build/release/markdown-look-compare "$f" $dark --out "${OUT:-/tmp/ql/compare}" | head -1
done
