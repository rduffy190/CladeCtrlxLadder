#!/usr/bin/env bash
# Build the import file, validate it, trace the ladder and run every test plan.
set -euo pipefail
cd "$(dirname "$0")/.."
XML=build/MotionLad_Import.xml
python3 tools/build_import.py > /dev/null
python3 ~/.claude/skills/codesys-st/scripts/validate_plcopen.py "$XML"
if python3 ~/.claude/skills/codesys-lad/scripts/ld_trace.py "$XML" | grep -i warn; then
    echo "ld_trace warnings above"; exit 1
fi
rc=0
for t in tests/test_*.py; do
    python3 "$t" "$XML" | tail -1 || rc=1
done
exit $rc
