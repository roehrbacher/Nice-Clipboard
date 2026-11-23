#!/usr/bin/env bash
# Nice Clipboard optional update check (Settings > General >
# "Check for updates", OFF by default). Runs at most once a day, only while
# the setting is on. Asks the public GitHub API for the newest release (or,
# without releases, the highest version tag) of roehrbacher/Nice-Clipboard:
# a plain anonymous GET, no token, no cookies, nothing about the machine or
# the user is sent (fixed User-Agent). While the repository is private (or
# offline, rate limited, ...) GitHub answers 404/error and this prints
# {"latest":"",...}: no notice, no error.
#   update-check.sh     print {"latest":"1.31.0","git":true}
# "git": the plugin folder is a git clone (then `omarchy plugin update
# timon.clipboard` can update it).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
api=https://api.github.com/repos/roehrbacher/Nice-Clipboard
proto='=https'
# Tests only: a local fake API (never GitHub from tests).
if [[ -n ${NICE_CLIPBOARD_UPDATE_API:-} ]]; then api=$NICE_CLIPBOARD_UPDATE_API; proto='=http,https'; fi
git=false
[[ -e $here/.git ]] && git=true
get() {
  curl -fsSL --max-time 8 --max-filesize 1000000 --proto "$proto" --proto-redir '=https' \
    -H 'Accept: application/vnd.github+json' -A 'Nice-Clipboard-update-check' "$1" 2>/dev/null
}
latest=$(get "$api/releases/latest" | jq -r '.tag_name // empty' 2>/dev/null)
if [[ -z $latest ]]; then
  latest=$(get "$api/tags?per_page=100" | jq -r '.[]?.name // empty' 2>/dev/null |
    sed 's/^v//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
fi
latest=${latest#v}
[[ $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || latest=""
jq -cn --arg latest "$latest" --argjson git "$git" '{latest: $latest, git: $git}'
