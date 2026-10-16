#!/bin/bash
# Add Circadian to the bar next to the indicators and retire Omarchy's Night
# Light indicator, which Circadian's Night Shift replaces. Run from a clone, it
# first links the clone into the plugin directory (for development); run from
# a copy installed by `omarchy plugin add`, it uses that. Re-running is safe.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="io.github.benjaminsehl.circadian"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id"
shell_json="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"

mkdir -p "$(dirname "$dest")"
if [[ $(readlink -f "$dest" 2>/dev/null) == "$here" ]]; then
  : # already installed here (plugin add, or an existing link)
elif [[ -L $dest ]]; then
  ln -sfn "$here" "$dest"
elif [[ -e $dest ]]; then
  echo "install: $dest exists and is not a symlink; leaving it alone" >&2
  exit 1
else
  ln -s "$here" "$dest"
fi
[[ -L $dest ]] && echo "linked $dest -> $here"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 1
(($#)) || set -- --before omarchy.indicators
omarchy plugin enable "$id" "$@"
echo "enabled $id"

# Hide the Night Light indicator (Circadian shows Night Shift itself). Edited
# with jq: `omarchy bar set ... --json` splits a JSON array into arguments.
# The shell reloads shell.json on save.
set_indicator_items() {
  local tmp
  tmp=$(mktemp "$shell_json.XXXXXX")
  jq --indent 2 "$1" "$shell_json" >"$tmp" && chmod --reference="$shell_json" "$tmp" && mv "$tmp" "$shell_json"
}
if [[ -f $shell_json ]] && jq -e '[.bar.layout[]?[]? | select(.id == "omarchy.indicators") | (.items // []) | (length == 0 or index("NightLight") != null)] | any' "$shell_json" >/dev/null 2>&1; then
  set_indicator_items '
    (.bar.layout[]?[]? | select(.id == "omarchy.indicators")) |=
      (.items = ((.items // []) | if length == 0 then ["Dictation","ScreenRecording","Reminder","NightLight","Dnd","StayAwake"] else . end
                 | map(select(. != "NightLight"))))'
  echo "hid Omarchy's Night Light indicator"
fi

"$here/bin/circadian" apply >/dev/null
"$here/bin/circadian"
