#!/bin/bash
# Remove the plugin link and bring back Omarchy's Night Light indicator.
# Settings in ~/.config/circadian and state in ~/.local/state/circadian stay.
set -euo pipefail
id="io.github.benjaminsehl.circadian"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id"
shell_json="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"

omarchy plugin disable "$id" || true
[[ -L $dest ]] && rm "$dest" && echo "removed $dest"

if [[ -f $shell_json ]] && jq -e '[.bar.layout[]?[]? | select(.id == "omarchy.indicators") | .items // empty | index("NightLight") == null] | any' "$shell_json" >/dev/null 2>&1; then
  tmp=$(mktemp "$shell_json.XXXXXX")
  jq --indent 2 '(.bar.layout[]?[]? | select(.id == "omarchy.indicators" and .items != null)) |= (.items |= (if index("NightLight") then . else . + ["NightLight"] end))' \
    "$shell_json" >"$tmp" && chmod --reference="$shell_json" "$tmp" && mv "$tmp" "$shell_json"
  echo "restored Omarchy's Night Light indicator"
fi
