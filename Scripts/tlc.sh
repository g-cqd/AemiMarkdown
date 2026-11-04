#!/bin/sh
# Runs the TLA+ models in docs/formal with TLC and checks the verdicts: each model must pass, and each `.buggy.cfg` (the first implementation's behaviour) must
# FAIL, so the models are known to be able to catch what they are for.
#
#   Scripts/tlc.sh
#
# swift-ci does it (the `tla-models` command of .ci/action.json, as CI runs it): TLC is tla2tools.jar from the tlaplus v1.7.4 release, pinned by SHA-256 in
# swift-ci and kept in its tool cache; each model runs with a state directory of its own outside the repository. Java is needed (JAVA_HOME, the path, or
# Homebrew's openjdk).
exec "$(dirname "$0")/../.ci/swift-ci" run tla-models
