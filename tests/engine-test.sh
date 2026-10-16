#!/bin/bash
# Exercises bin/circadian against stubbed Omarchy/hyprsunset commands in a
# throwaway HOME. Run: tests/engine-test.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
engine="$here/bin/circadian"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME=$T/home
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME
export CIRCADIAN_FROM_SHELL=1
mkdir -p "$HOME/.local/state/omarchy/current" "$HOME/.cache/circadian" "$T/bin" "$T/sim"
for t in shopify shopify-light tokyo-night; do mkdir -p "$HOME/.config/omarchy/themes/$t"; done
echo shopify >"$HOME/.local/state/omarchy/current/theme.name"

# Sunrise 07:00, sunset 19:00; the clock is pinned to 03:00 or noon today.
printf '%s 07:00 19:00\n' "$(date +%F)" >"$HOME/.cache/circadian/sun"
set_night() { export CIRCADIAN_NOW=$(date -d "$(date +%F) 03:00" +%s); }
set_day() { export CIRCADIAN_NOW=$(date -d "$(date +%F) 12:00" +%s); }

cat >"$T/bin/omarchy-theme-set" <<EOF
#!/bin/bash
echo "\$1" >"$HOME/.local/state/omarchy/current/theme.name"
EOF
cat >"$T/bin/omarchy-theme-dir" <<EOF
#!/bin/bash
echo "$HOME/.config/omarchy/themes/\$1"
EOF
cat >"$T/bin/omarchy-theme-color" <<'EOF'
#!/bin/bash
[[ $2 == *-light/* ]] && echo light || echo dark
EOF
# hyprsunset simulation: running flag + temperature file.
cat >"$T/bin/pgrep" <<EOF
#!/bin/bash
[[ -f $T/sim/running ]]
EOF
cat >"$T/bin/hyprctl" <<EOF
#!/bin/bash
[[ -f $T/sim/running ]] || exit 1
if [[ -n \${3:-} ]]; then echo "\$3" >$T/sim/temp; else cat $T/sim/temp; fi
EOF
cat >"$T/bin/setsid" <<EOF
#!/bin/bash
touch $T/sim/running; echo 6500 >$T/sim/temp
EOF
printf '#!/bin/bash\nexit 0\n' >"$T/bin/omarchy-shell"
chmod +x "$T"/bin/*
export PATH="$T/bin:$PATH"

pass=0 fail=0
check() {
  local what=$1 expr=$2 got
  got=$("$engine" status --json | jq -r "$expr")
  if [[ $got == "$3" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $what: $expr = '$got', want '$3'"
  fi
}
theme() { cat "$HOME/.local/state/omarchy/current/theme.name"; }
temp() { cat "$T/sim/temp" 2>/dev/null || echo none; }
eq() {
  if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1: '$2', want '$3'"; fi
}

# First run pairs shopify with shopify-light.
set_night
"$engine" apply >/dev/null
check "seeded light theme" .lightTheme shopify-light
check "seeded dark theme" .darkTheme shopify
eq "night stays dark" "$(theme)" shopify
eq "night shift starts hyprsunset at warmth" "$(temp)" 4000
check "night shift on" .nightShift true

# Manual switch at night holds (override), then expires.
"$engine" appearance light
eq "manual light" "$(theme)" shopify-light
check "override recorded" .appearanceOverride true
"$engine" apply
eq "override holds" "$(theme)" shopify-light
echo "light $((CIRCADIAN_NOW - 1))" >"$HOME/.local/state/circadian/appearance.override"
"$engine" apply
eq "expired override returns to the sun" "$(theme)" shopify
check "override cleared" .appearanceOverride false

# Choosing what the sun says is no override.
"$engine" appearance dark
check "no override when agreeing with sun" .appearanceOverride false

# Day: light, night shift off.
set_day
"$engine" apply
eq "day is light" "$(theme)" shopify-light
eq "day turns night shift off" "$(temp)" 6500

# Theme switcher picks the dark one by day: adopted as manual.
echo shopify >"$HOME/.local/state/omarchy/current/theme.name"
"$engine" apply
eq "switcher choice kept" "$(theme)" shopify
check "switcher choice is an override" .appearanceOverride true

# Another theme entirely: left alone.
echo tokyo-night >"$HOME/.local/state/omarchy/current/theme.name"
"$engine" apply
eq "other theme untouched" "$(theme)" tokyo-night
check "appearance other" .appearance other
"$engine" appearance light
eq "explicit switch from other theme" "$(theme)" shopify-light

# Omarchy's night light toggle by day: adopted.
echo 4000 >"$T/sim/temp"
"$engine" apply
eq "external night light kept" "$(temp)" 4000
check "external night light is an override" .nightShiftOverride true
"$engine" nightshift off
eq "night shift off" "$(temp)" 6500

# Warmth applies live when on.
"$engine" nightshift on
"$engine" set warmth 3000
eq "warmth applied" "$(temp)" 3000
"$engine" set warmth 100
check "warmth clamped" .warmth 2500

# Schedules off: nothing moves by itself.
"$engine" set darkAtNight off
"$engine" set nightShiftAtNight off
set_night
"$engine" apply
eq "no schedule: stays light at night" "$(theme)" shopify-light
eq "no schedule: night shift stays as set" "$(temp)" 2500
"$engine" set darkAtNight on
eq "schedule back on catches up" "$(theme)" shopify

# Swapping the showing side's theme switches to it.
mkdir -p "$HOME/.config/omarchy/themes/gruvbox"
"$engine" set darkTheme gruvbox
eq "new dark theme shown" "$(theme)" gruvbox
"$engine" set darkTheme nope 2>/dev/null
check "unknown theme rejected" .darkTheme gruvbox

# Offline with no cache: fallback times.
rm -f "$HOME/.cache/circadian/sun"
echo "$CIRCADIAN_NOW" >"$HOME/.cache/circadian/sun.failed"
check "fallback sunrise" .sunrise 07:00
check "fallback source" .sunSource fallback

echo "$pass passed, $fail failed"
((fail == 0))
