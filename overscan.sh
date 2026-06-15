#!/bin/bash
# overscan.sh — CRT overscan compensation via xrandr --transform
#
# Shrinks the desktop into the visible tube area without changing the mode
# (layout-safe: only the X-to-screen mapping changes). The center is derived
# from the framebuffer size, so it works at any resolution.
#
# Usage:
#   overscan.sh <fill>            apply uniform fill, e.g. 0.85 (= 85% of tube)
#   overscan.sh save <fill>       apply AND persist via autostart (login replay)
#   overscan.sh restore           apply the saved settings (what autostart runs)
#   overscan.sh reset | none      remove the live transform (persistence kept)
#   overscan.sh unsave | clear    remove the persisted config + autostart
#
# Options (combine with <fill> or save):
#   -x FX   horizontal fill fraction (overrides <fill> for X)
#   -y FY   vertical   fill fraction (overrides <fill> for Y)
#   -r WxH  set framebuffer + mode to this resolution (default: current)
#   -o OUT  xrandr output name        (default: first connected output)
#   -d DX   extra horizontal offset px, +right (centering nudge)
#   -e DY   extra vertical   offset px, +down
#   -f FILT bilinear | nearest        (default: bilinear)
#   -n      dry run: print, don't execute
#
# Examples:
#   overscan.sh 0.85
#   overscan.sh -x 0.86 -y 0.82 0.85
#   overscan.sh save -r 1600x1200 -d -8 0.85
#   overscan.sh restore        # used by the autostart entry
#   overscan.sh reset          # live off, keeps saved values
#   overscan.sh unsave         # forget saved values + remove autostart

set -euo pipefail

CONFIG="${OVERSCAN_CONFIG:-$HOME/.config/overscan.conf}"
AUTO_SH="$HOME/.config/autostart-scripts/set-overscan.sh"
AUTO_DESKTOP="$HOME/.config/autostart/set-overscan.desktop"
SELF="$(readlink -f "$0")"

# --- resolve X session if not already in env ---------------------------------
: "${DISPLAY:=$(who | awk '/\(:[0-9]\)/{print $NF; exit}' | tr -d '()')}"
: "${XAUTHORITY:=/run/user/$(id -u)/gdm/Xauthority}"
export DISPLAY XAUTHORITY

# --- defaults / arg parsing --------------------------------------------------
FX=""; FY=""; RES=""; OUTPUT=""; DX=0; DY=0; FILTER="bilinear"; DRY=0
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -x) FX="$2"; shift 2;;
    -y) FY="$2"; shift 2;;
    -r) RES="$2"; shift 2;;
    -o) OUTPUT="$2"; shift 2;;
    -d) DX="$2"; shift 2;;
    -e) DY="$2"; shift 2;;
    -f) FILTER="$2"; shift 2;;
    -n) DRY=1; shift;;
    -h|--help) sed -n '2,40p' "$SELF"; exit 0;;
    *)  POS+=("$1"); shift;;
  esac
done

CMD="apply"; FILL=""
case "${POS[0]:-}" in
  reset|none)        CMD="reset";;
  save)              CMD="save";   FILL="${POS[1]:-}";;
  restore)           CMD="restore";;
  unsave|clear|forget) CMD="unsave";;
  "")                CMD="apply";;
  *)                 CMD="apply";  FILL="${POS[0]}";;
esac

# --- detect output (default: first connected) --------------------------------
detect_output() { xrandr --query | awk '/ connected/{print $1; exit}'; }

# --- apply: needs FX FY RES OUTPUT DX DY FILTER; sets W H RES (resolved) ------
do_apply() {
  [ -n "$OUTPUT" ] || OUTPUT="$(detect_output)"
  [ -n "$OUTPUT" ] || { echo "overscan: no connected output found" >&2; exit 1; }

  [ -n "$FX" ] || FX="$FILL"
  [ -n "$FY" ] || FY="${FILL:-$FX}"
  [ -n "$FX" ] && [ -n "$FY" ] || { echo "overscan: need a fill fraction (e.g. 0.85)" >&2; exit 1; }

  if [ -z "$RES" ]; then
    RES=$(xrandr --query | awk -v o="$OUTPUT" '
      $1==o {f=1; next}
      f && /\*/ {print $1; exit}
      f && / connected| disconnected/ {exit}')
  fi
  [ -n "$RES" ] || { echo "overscan: could not determine resolution; pass -r WxH" >&2; exit 1; }
  W=${RES%x*}; H=${RES#*x}

  local matrix
  matrix=$(awk -v W="$W" -v H="$H" -v fx="$FX" -v fy="$FY" -v dx="$DX" -v dy="$DY" 'BEGIN{
    sx=1/fx; sy=1/fy;
    tx=(W/2)*(1-sx)-dx; ty=(H/2)*(1-sy)-dy;
    printf "%.6f,0,%.6f,0,%.6f,%.6f,0,0,1", sx, tx, sy, ty;
  }')

  local cmd=(xrandr --fb "${W}x${H}" --output "$OUTPUT" --panning "${W}x${H}+0+0" \
             --mode "${W}x${H}" --transform "$matrix" --filter "$FILTER")
  echo "+ output=$OUTPUT  res=${W}x${H}  fill=${FX}x${FY}  offset=${DX},${DY}"
  echo "+ ${cmd[*]}"
  [ "$DRY" = 1 ] || "${cmd[@]}"
}

write_config() {
  mkdir -p "$(dirname "$CONFIG")"
  cat > "$CONFIG" <<EOF
# overscan saved settings — written by overscan.sh save
FX=$FX
FY=$FY
RES=$RES
OUTPUT=$OUTPUT
DX=$DX
DY=$DY
FILTER=$FILTER
EOF
  echo "+ saved settings -> $CONFIG"
}

install_autostart() {
  mkdir -p "$(dirname "$AUTO_SH")" "$(dirname "$AUTO_DESKTOP")"
  cat > "$AUTO_SH" <<EOF
#!/bin/bash
sleep 3
exec "$SELF" restore
EOF
  chmod +x "$AUTO_SH"
  cat > "$AUTO_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=CRT Overscan Compensation
Exec=$AUTO_SH
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
  echo "+ installed autostart -> $AUTO_SH"
  echo "+ installed autostart -> $AUTO_DESKTOP"
}

# --- dispatch ----------------------------------------------------------------
case "$CMD" in
  reset)
    [ -n "$OUTPUT" ] || OUTPUT="$(detect_output)"
    echo "+ xrandr --output $OUTPUT --transform none"
    [ "$DRY" = 1 ] || xrandr --output "$OUTPUT" --transform none
    ;;
  apply)
    do_apply
    ;;
  save)
    do_apply
    [ "$DRY" = 1 ] || { write_config; install_autostart; }
    ;;
  restore)
    [ -f "$CONFIG" ] || { echo "overscan: no saved config at $CONFIG" >&2; exit 1; }
    # shellcheck disable=SC1090
    . "$CONFIG"
    do_apply
    ;;
  unsave)
    rm -f "$CONFIG" "$AUTO_SH" "$AUTO_DESKTOP"
    echo "+ removed $CONFIG"
    echo "+ removed $AUTO_SH"
    echo "+ removed $AUTO_DESKTOP"
    echo "(live transform left as-is; run 'overscan reset' to also clear it)"
    ;;
esac
