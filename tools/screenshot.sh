#!/usr/bin/env bash
#
# Render the range and save a frame, so a person can look at the weapons.
#
#   tools/screenshot.sh rifle                      # screenshots/rifle.png
#   tools/screenshot.sh sniper shots/sniper.png --wait 16
#   tools/screenshot.sh --all                      # one frame per weapon
#
# WHY THIS EXISTS
#
# Everything about a view model is motion and placement, and no assertion reaches
# either. `examples/zee_selftest.tscn` proves all twenty-seven weapons load, measure
# and simulate, and not one of its checks can tell you that a weapon is held at the
# wrong angle, that an arm is inside the gun, or that the muzzle is at the stock.
# A picture can, and this is how a machine with no screen produces one.
#
# It is NOT `--headless`. Godot's headless display driver does no rendering at all, so
# a capture under it is a black PNG — which is worse than no screenshot, because it
# looks like one. This runs the real renderer against an Xvfb framebuffer, with Mesa's
# llvmpipe standing in for a GPU.
#
# What it cannot tell you: input feel, frame pacing, and anything a real GPU driver
# does differently. Use it for "is this drawn correctly", never for "does this run
# well".
#
set -uo pipefail
cd "$(dirname "$0")/.."

command -v Xvfb >/dev/null || { echo "Xvfb not installed (apt install xvfb)" >&2; exit 3; }
command -v scrot >/dev/null || { echo "scrot not installed (apt install scrot)" >&2; exit 3; }

SIZE="1280x720"
WAIT=14
ALL=0
RACK=0
WEAPON=""
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --all)  ALL=1; shift ;;
        --rack) RACK=1; shift ;;
        --wait) WAIT="$2"; shift 2 ;;
        --size) SIZE="$2"; shift 2 ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *)  if [ -z "$WEAPON" ]; then WEAPON="$1"; else OUT="$1"; fi; shift ;;
    esac
done

# Re-import first. Adding a script with a new class_name without an --import pass
# leaves the identifier unresolvable, the scene fails to load, and the process HANGS
# rather than exiting, because nothing ever reaches get_tree().quit().
godot --headless --path . --import >/dev/null 2>&1

shoot() {
    local weapon="$1" out="$2" scene="${3:-}"
    # A display number nothing else is using, so two of these can run at once.
    local disp=$((90 + RANDOM % 8))
    local log; log="$(mktemp)"

    mkdir -p "$(dirname "$out")"

    DISPLAY=":$disp" ; export DISPLAY
    export LIBGL_ALWAYS_SOFTWARE=1

    Xvfb ":$disp" -screen 0 "${SIZE}x24" >/dev/null 2>&1 &
    local xpid=$!
    sleep 2

    # --rendering-driver opengl3 explicitly: left to choose, Godot picks a driver that
    # produces a black frame under Xvfb, and a black frame reads as a broken scene.
    timeout $((WAIT + 40)) godot --path . --resolution "$SIZE" \
        --rendering-driver opengl3 $scene \
        -- --seconds $((WAIT + 20)) --weapon "$weapon" ${EXTRA:-} >"$log" 2>&1 &
    local gpid=$!

    sleep "$WAIT"

    if scrot -o "$out" 2>/dev/null && [ -s "$out" ]; then
        echo "wrote $out ($(du -h "$out" | cut -f1))"
    else
        echo "capture failed for $weapon:" >&2
        tail -20 "$log" >&2
    fi

    kill "$gpid" "$xpid" 2>/dev/null
    wait "$gpid" 2>/dev/null
    rm -f "$log"
}

if [ $RACK -eq 1 ]; then
    # The rack takes no weapon, so a lone positional argument is the output path rather
    # than a weapon id. Without this, `--rack docs/rack.png` silently wrote the default.
    [ -z "$OUT" ] && OUT="$WEAPON"
    # Every weapon at once, with a pip on each muzzle. See tools/rack.gd.
    shoot "" "${OUT:-screenshots/rack.png}" "res://tools/rack.tscn"
    exit 0
fi

if [ $ALL -eq 1 ]; then
    for w in fists knife shiv hatchet mallet pickaxe spade \
             pistol revolver machine_pistol derringer \
             smg carbine rifle bullpup battle_rifle burst_rifle \
             shotgun drum_shotgun marksman \
             sniper minigun launcher beamer charge_rifle frag sticky; do
        shoot "$w" "screenshots/$w.png"
    done
    exit 0
fi

[ -n "$WEAPON" ] || { echo "usage: $0 <weapon-id> [out.png] [--wait N] [--size WxH] | --all" >&2; exit 2; }
shoot "$WEAPON" "${OUT:-screenshots/$WEAPON.png}"
