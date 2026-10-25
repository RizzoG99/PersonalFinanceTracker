#!/bin/bash
# PostToolUse(Edit|Write): format the edited Swift file with the repo's .swiftformat.
command -v swiftformat >/dev/null || exit 0
F=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
case "$F" in *.swift) [ -f "$F" ] && swiftformat --quiet "$F" >/dev/null 2>&1;; esac
exit 0
