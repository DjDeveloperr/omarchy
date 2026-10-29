#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# First-boot setup's progress screen, the ISO install dashboard's: the Omarchy
# icon traced in green as setup advances, then drawn whole. The screen runs as
# omarchy-provision-owner defines it, on a console whose size and font cell are
# given here instead of read from a VT.

tmp=$(cd -- "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

sed -n '/^CSI=/,/^greeter_screen() {/p' "$ROOT/bin/omarchy-provision-owner" | sed '$d' >"$tmp/screen.sh"
grep -q '^render_setup_finish() {' "$tmp/screen.sh" || fail "omarchy-provision-owner defines its setup progress screen"
LOGO_WIDTH=81 OMARCHY_PATH=$ROOT PROVISIONING_DIR=$tmp LOG_FILE=$tmp/log
# shellcheck disable=SC1091
source "$tmp/screen.sh"

# Lengths of the runs of filled icon pixels along one pixel row.
fill_runs() {
  local y=$1 x run=0 runs=()
  for ((x = 0; x < ICON_WIDTH; x++)); do
    if (( ICON_FILL[y * ICON_WIDTH + x] )); then
      run=$((run + 1))
    elif (( run )); then
      runs+=("$run")
      run=0
    fi
  done
  (( run )) && runs+=("$run")
  echo "${runs[*]}"
}

# The cells of the three fonts scale_console_font picks from (default8x16,
# sun12x22, latarcyrheb-sun32), at every size the screen draws the icon. The
# trace must paint exactly the pixels the finished icon fills, or the last
# frame pops in pixels the trace never reached. And every upright stroke must
# be as wide as the others: sun12x22's cell isn't 2:1 like the ISO's Terminus,
# and proportional columns drew its right edge and bridges at half width.
for cell in "8 16" "12 22" "16 32"; do
  read -r CELL_WIDTH CELL_HEIGHT <<<"$cell"
  for scale in 1 2 3; do
    build_icon "$scale"
    for ((pixel = 0; pixel < ICON_WIDTH * 15 * scale; pixel++)); do
      traced=0
      [[ -v ICON_TRACE[pixel] ]] && traced=1
      (( traced == ICON_FILL[pixel] )) ||
        fail "the ${CELL_WIDTH}x$CELL_HEIGHT icon at scale $scale traces exactly its own pixels" "pixel $pixel: traced $traced, filled ${ICON_FILL[pixel]}"
    done
    # Icon row 1 crosses only the two edges and the top bridge, row 4 the two
    # edges and the two inner walls.
    for row_strokes in "1 3" "4 4"; do
      read -r row strokes <<<"$row_strokes"
      read -ra runs <<<"$(fill_runs $((row * scale)))"
      (( ${#runs[@]} == strokes )) ||
        fail "the ${CELL_WIDTH}x$CELL_HEIGHT icon at scale $scale draws every upright stroke" "icon row $row strokes: ${runs[*]}"
      for run in "${runs[@]}"; do
        (( run == runs[0] )) ||
          fail "the ${CELL_WIDTH}x$CELL_HEIGHT icon at scale $scale draws every upright stroke equally wide" "icon row $row strokes: ${runs[*]}"
      done
    done
  done
done
pass "the icon traces exactly its own pixels, with even strokes, in every console font and size"

# Setup can end between two state reads, far short of the end of the trace.
# The screen still traces the rest and ends on the whole icon at 100%, the
# frame the display manager takes over from.
term_size() { echo "52 160"; }
term_cols() { echo 160; }
term_cell_size() { echo "16 32"; }
sleep() { :; }
render_setup_static >/dev/null
SETUP_POS=300
render_setup_dynamic >/dev/null
render_setup_finish >"$tmp/finish"
(( DISPLAY_PM == 1000 && ICON_DRAWN == ICON_STEPS )) ||
  fail "setup ending mid-trace still draws the whole icon" "display $DISPLAY_PM, drawn $ICON_DRAWN of $ICON_STEPS"
[[ $(grep -ao '[0-9]*%' "$tmp/finish" | tail -n1) == "100%" ]] || fail "setup ending mid-trace ends at 100%"
pass "setup ending mid-trace finishes the trace and ends on the whole icon at 100%"

# The kbd fonts the screen can pick must map the block glyphs it draws (█ ▀ ▄,
# in the logo and the icon). Terminus lacks the half blocks; the ISO patches
# them into its copy. Checked against the fonts installed here.
eval "fonts=($(sed -n 's/^ *local fonts=(\(.*\))$/\1/p' "$ROOT/bin/omarchy-provision-owner"))"
(( ${#fonts[@]} > 0 )) || fail "omarchy-provision-owner names the console fonts it picks from"
fontdir=/usr/share/kbd/consolefonts
if [[ -d $fontdir ]] && command -v psfgettable >/dev/null; then
  for name in "${fonts[@]}"; do
    file=$(compgen -G "$fontdir/$name.psf*" | head -n1) || fail "kbd ships the $name console font"
    table=$(gzip -dcf "$file" | psfgettable -)
    for codepoint in 2588 2580 2584; do
      grep -qw "U+$codepoint" <<<"$table" || fail "the $name console font maps U+$codepoint"
    done
  done
  pass "every console font first-boot setup picks from maps █ ▀ ▄"
else
  skip "kbd's console fonts or psfgettable are not installed; skipping the console font glyph check"
fi
