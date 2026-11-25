#!/bin/bash
# Warm accents: while the night light schedule is on and tinting the screen
# (below 6500K), the focused window's border (and notifications / the password
# prompt) turn warm orange; otherwise they use the current theme's colours.
# Inactive borders are untouched. Bar menus always use the theme's system-menu
# border (the same outline as the Keybindings / app menus).
#   warm-accents.sh on|off
#
# Run by Service.qml whenever the schedule switches. Two parts:
#  1. Hyprland: applied live with `hyprctl eval` (no reload). Off re-runs the
#     theme's own hyprland.lua, so whatever theme is active comes back.
#  2. Shell: a marked block in ~/.config/omarchy/shell.toml (user overrides,
#     merged over the theme and watched by the shell) with [popups] always,
#     plus [hyprland] active-border while on.

state="${1:-off}"
orange_lua='{ colors = { "rgba(ffb347ff)", "rgba(ff6a00ff)" }, angle = 45 }'
orange_toml='rgba(ffb347ff) rgba(ff6a00ff) 45deg'
theme_lua="$HOME/.local/state/omarchy/current/theme/hyprland.lua"
shell_toml="$HOME/.config/omarchy/shell.toml"
# Current state for Hyprland config reloads (see README: looknfeel.lua snippet)
state_file="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/nightlight-accents"
mkdir -p "$(dirname "$state_file")" && printf '%s\n' "$state" >"$state_file"
begin='# >>> albertus.nightlight accents (managed by the Night Light plugin)'
end='# <<< albertus.nightlight accents'
old_begin='# >>> albertus.nightlight warm accents (managed: removed when the schedule is off)'
old_end='# <<< albertus.nightlight warm accents'

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
awk -v b="$begin" -v e="$end" -v ob="$old_begin" -v oe="$old_end" \
  '$0==b||$0==ob{skip=1;next} $0==e||$0==oe{skip=0;next} !skip' "$shell_toml" >"$tmp"
# trim trailing blank lines
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
{
  printf '\n%s\n' "$begin"
  printf '[popups]\nborder = "hyprland.active-border-foreground"\n'
  [[ $state == on ]] && printf '[hyprland]\nactive-border = "%s"\n' "$orange_toml"
  printf '%s\n' "$end"
} >>"$tmp"
if ! cmp -s "$tmp" "$shell_toml"; then
  cat "$tmp" >"$shell_toml"
fi
rm -f "$tmp"
