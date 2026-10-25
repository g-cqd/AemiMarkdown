#!/bin/sh
# Rewrites Tests/AemiMarkdownTests/Fixtures/known-failing.txt from a run of the spec suite, after a fix.
#
#   Scripts/update-ratchet.sh          drop the examples that now pass; refuse if any example is newly failing
#   Scripts/update-ratchet.sh --init   write the whole list from nothing (only for the first baseline)
#
# The ratchet shrinks and never gains an entry (ADR-0001, decision 6). The suite itself fails for an example that fails and is not listed,
# and for one that passes and is listed, so this script is how the second kind is cleared.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
file="$root/Tests/AemiMarkdownTests/Fixtures/known-failing.txt"
proposal=$(mktemp)
trap 'rm -f "$proposal"' EXIT

cd "$root"
# The suite fails while the ratchet is stale; the proposal is complete either way.
AEMIMARKDOWN_RATCHET_PROPOSAL="$proposal" swift test -c release --enable-testable-imports --filter SpecConformanceTests >/dev/null 2>&1 || true

header=$(grep '^#' "$file" | head -1)
if [ "${1:-}" != "--init" ]; then
    cut -d' ' -f1,2 "$proposal" | sort -u > "$proposal.ids"
    grep -v '^#' "$file" | cut -d' ' -f1,2 | sort -u > "$proposal.known"
    added=$(comm -23 "$proposal.ids" "$proposal.known")
    rm -f "$proposal.ids" "$proposal.known"
    if [ -n "$added" ]; then
        printf 'refused: these examples fail and are not on the ratchet:\n%s\n' "$added" >&2
        exit 1
    fi
fi
{ printf '%s\n' "$header"; sort -t' ' -k1,1 -k2,2n "$proposal"; } > "$file.new"
mv "$file.new" "$file"
printf '%s entries\n' "$(grep -vc '^#' "$file")"
