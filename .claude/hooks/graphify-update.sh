#!/bin/bash
# Stop: refresh the graph only when Swift sources changed (AST-only, free).
[ -f graphify-out/graph.json ] || exit 0
git status --porcelain -- '*.swift' | grep -q . || exit 0
timeout 120 graphify update . >/dev/null 2>&1
exit 0
