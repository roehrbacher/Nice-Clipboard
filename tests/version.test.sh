#!/bin/bash
# The version Clipboard.qml puts in feedback must match manifest.json.
set -euo pipefail
cd "$(dirname "$0")/.."
m=$(jq -r .version manifest.json)
q=$(sed -n 's/.*readonly property string pluginVersion: "\([^"]*\)".*/\1/p' Clipboard.qml)
[[ -n $q && $q == "$m" ]] || { echo "FAIL: Clipboard.qml pluginVersion '$q' != manifest '$m'"; exit 1; }
grep -q "^## $m\$" CHANGELOG.md || { echo "FAIL: CHANGELOG has no ## $m"; exit 1; }
echo "ok version $m"
