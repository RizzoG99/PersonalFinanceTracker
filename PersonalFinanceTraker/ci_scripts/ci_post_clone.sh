#!/bin/zsh
# Xcode Cloud runs this right after cloning, before any build action. It turns
# CHANGELOG.md's Unreleased section into TestFlight/WhatToTest.en-US.txt,
# which Xcode Cloud picks up automatically when it uploads to TestFlight —
# no API key, no script on the upload side. See CLAUDE.md/AGENTS.md's
# Changelog convention for how Unreleased gets filled in.
set -euo pipefail

# This script lives at PersonalFinanceTraker/ci_scripts/; CHANGELOG.md is two
# levels up at the repo root, TestFlight/ is a sibling of the .xcodeproj.
cd "$(dirname "$0")"
CHANGELOG=../../CHANGELOG.md
TESTFLIGHT_DIR=../TestFlight

notes=$(awk '/^## Unreleased/{flag=1; next} /^## /{flag=0} flag' "$CHANGELOG" | sed '/^$/d')
if [ -z "$notes" ]; then
  notes="General bug fixes and improvements."
fi

mkdir -p "$TESTFLIGHT_DIR"
printf '%s\n' "$notes" > "$TESTFLIGHT_DIR/WhatToTest.en-US.txt"
