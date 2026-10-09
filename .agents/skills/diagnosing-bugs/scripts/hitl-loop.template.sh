#!/usr/bin/env bash
# Human-in-the-loop reproduction loop.
# Copy this file, edit the steps below, and run it.
# The agent runs the script; the user follows prompts in their terminal.
#
# Usage:
#   bash hitl-loop.template.sh
#
# Two helpers:
#   step "<instruction>"          → show instruction, wait for Enter
#   capture VAR "<question>"      → show question, read response into VAR
#
# At the end, captured values are printed as KEY=VALUE for the agent to parse.
#
# `capture` prints its value back to the terminal, where the agent reads it,
# so capture observations, and leave signing in to the user as a `step`.

set -euo pipefail

step() {
  printf '\n>>> %s\n' "$1"
  read -r -p "    [Enter when done] " _
}

capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p "    > " answer
  printf -v "$var" '%s' "$answer"
}

# --- edit below ---------------------------------------------------------

step "Run scripts/xcb which-sim, launch the app on that worktree simulator, and navigate to the affected screen."

capture REPRODUCED "Perform the minimal reproduction steps. Did the reported symptom occur? (y/n)"

capture OBSERVATION "Describe exactly what appeared, including visible text and timing (or 'none'):"

# --- edit above ---------------------------------------------------------

printf '\n--- Captured ---\n'
printf 'REPRODUCED=%s\n' "$REPRODUCED"
printf 'OBSERVATION=%s\n' "$OBSERVATION"
