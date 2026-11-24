#!/bin/bash
# Warm accents: while the night light schedule is on, the focused window's
# border and the shell's menu/popup borders turn warm orange; when it's off,
# both go back to the current theme's colours. Inactive borders are untouched.
#   warm-accents.sh on|off
#
# Run by Service.qml whenever the schedule switches. Two parts:
#  1. Hyprland: applied live with `hyprctl eval` (no reload). Off re-runs the
#     theme's own hyprland.lua, so whatever theme is active comes back.
#  2. Shell menus: a marked [hyprland] block in ~/.config/omarchy/shell.toml
#     (user overrides, merged over the theme and watched by the shell).

state="${1:-off}"
orange_lua='{ colors = { "rgba(ffb347ff)", "rgba(ff6a00ff)" }, angle = 45 }'
orange_toml='rgba(ffb347ff) rgba(ff6a00ff) 45deg'
theme_lua="$HOME/.local/state/omarchy/current/theme/hyprland.lua"
shell_toml="$HOME/.config/omarchy/shell.toml"
begin='# >>> albertus.nightlight warm accents (managed: removed when the schedule is off)'
end='# <<< albertus.nightlight warm accents'

# ---- Hyprland borders ----
if [[ $state == on ]]; then
  hyprctl eval "local c = $orange_lua
hl.config({ general = { col = { active_border = c } }, group = { col = { border_active = c } } })" >/dev/null
elif [[ -r $theme_lua ]]; then
  hyprctl eval "dofile(\"$theme_lua\")" >/dev/null
fi

# ---- shell menus/popups ----
touch "$shell_toml"
tmp=$(mktemp)
# drop any previous managed block
awk -v b="$begin" -v e="$end" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$shell_toml" >"$tmp"
# trim trailing blank lines
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
if [[ $state == on ]]; then
  printf '\n%s\n[hyprland]\nactive-border = "%s"\n%s\n' "$begin" "$orange_toml" "$end" >>"$tmp"
fi
if ! cmp -s "$tmp" "$shell_toml"; then
  cat "$tmp" >"$shell_toml"
fi
rm -f "$tmp"
