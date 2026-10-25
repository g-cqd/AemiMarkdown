#!/bin/sh
# Runs the TLA+ models in docs/formal with TLC and checks the verdicts: each model must pass, and each `.buggy.cfg` (the first implementation's behaviour) must
# FAIL, so the models are known to be able to catch what they are for.
#
#   Scripts/tlc.sh
#
# TLC is tla2tools.jar from the tlaplus v1.7.4 release, pinned by SHA-256 and kept outside the repository. Java is needed (Homebrew's openjdk is found).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
SHA=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
CACHE="${AEMIMARKDOWN_TLA_DIR:-$HOME/Library/Caches/aemimarkdown/tla}"
jar="$CACHE/tla2tools.jar"
java=$(command -v java || true)
[ -n "$java" ] || java=/opt/homebrew/opt/openjdk/bin/java
[ -x "$java" ] || { printf '[FAIL] no java\n' >&2; exit 2; }
if [ ! -f "$jar" ]; then
    mkdir -p "$CACHE"
    curl -fsSL --retry 3 -o "$jar.part" https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
    [ "$(shasum -a 256 "$jar.part" | cut -d' ' -f1)" = "$SHA" ] || { rm -f "$jar.part"; printf '[FAIL] tla2tools.jar does not match the pinned hash\n' >&2; exit 2; }
    mv "$jar.part" "$jar"
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
status=0
for cfg in "$root"/docs/formal/*.cfg; do
    name=$(basename "$cfg" .cfg)
    module=${name%.buggy}
    (cd "$scratch" && "$java" -cp "$jar" tlc2.TLC -config "$cfg" -workers auto -cleanup "$root/docs/formal/$module.tla" > "$scratch/$name.log" 2>&1) && ok=1 || ok=0
    case $name in
        *.buggy) if [ $ok = 0 ] && grep -q 'is violated' "$scratch/$name.log"; then printf '[OK] %s fails, as it must\n' "$name"; else printf '[FAIL] %s should fail and did not\n' "$name"; status=1; fi ;;
        *) if [ $ok = 1 ]; then printf '[OK] %s: %s\n' "$name" "$(grep -E '[0-9]+ distinct states found' "$scratch/$name.log" | head -1)"; else printf '[FAIL] %s\n' "$name"; tail -20 "$scratch/$name.log"; status=1; fi ;;
    esac
done
exit $status
