#!/usr/bin/env bash
# Generates tray icons (assets/tray/*.ico) and the Windows app icon from the
# mark described in DESIGN §4.4. Needs rsvg-convert and ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

INK='#111418'
PAPER='#F5F5F2'
ACCENT='#E0A94A'
ALERT='#C8452F'

# Tray mark on a 16 grid: ring d=12, stroke 1.5, line overhangs by 1, dot d=3
# one third down the line.
tray_svg() { # body, dot-fill, dot-stroke
  cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="none">
  <circle cx="8" cy="8" r="6" stroke="$1" stroke-width="1.5"/>
  <line x1="8" y1="1" x2="8" y2="15" stroke="$1" stroke-width="1.5"/>
  <circle cx="8" cy="5.67" r="1.75" fill="$2" stroke="$3" stroke-width="1"/>
</svg>
SVG
}

make_ico() { # svg-file out.ico sizes...
  local svg=$1 out=$2
  shift 2
  local pngs=()
  for s in "$@"; do
    rsvg-convert -w "$s" -h "$s" "$svg" -o "$tmp/$s.png"
    pngs+=("$tmp/$s.png")
  done
  convert "${pngs[@]}" "$out"
}

for theme in ink paper; do
  body=$INK; [ $theme = paper ] && body=$PAPER
  bg=$PAPER; [ $theme = paper ] && bg=$INK
  tray_svg "$body" "$bg" "$body" > "$tmp/hollow.svg"
  tray_svg "$body" "$body" "$body" > "$tmp/solid.svg"
  tray_svg "$body" "$ACCENT" "$ACCENT" > "$tmp/running.svg"
  tray_svg "$body" "$ALERT" "$ALERT" > "$tmp/alert.svg"
  for state in hollow solid running alert; do
    make_ico "$tmp/$state.svg" "assets/tray/${state}_${theme}.ico" 16 20 24 32 40 48
  done
done

# App icon: paper tile, ink mark on the 24 grid, amber dot.
cat > "$tmp/app.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 24 24" fill="none">
  <rect x="0.5" y="0.5" width="23" height="23" rx="5" fill="$PAPER" stroke="#D6D6D1" stroke-width="0.5"/>
  <circle cx="12" cy="12" r="7.5" stroke="$INK" stroke-width="1.6"/>
  <line x1="12" y1="3.5" x2="12" y2="20.5" stroke="$INK" stroke-width="1.6"/>
  <circle cx="12" cy="9.2" r="1.8" fill="$ACCENT"/>
</svg>
SVG
make_ico "$tmp/app.svg" windows/runner/resources/app_icon.ico 16 24 32 48 64 128 256
rsvg-convert -w 256 -h 256 "$tmp/app.svg" -o assets/app_icon.png
echo "icons generated"
