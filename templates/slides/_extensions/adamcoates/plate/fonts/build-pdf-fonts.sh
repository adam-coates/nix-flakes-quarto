#!/usr/bin/env bash
# Regenerate ttf/: unpack the Inter woff2 files into plain TrueType.
#
# The handout format (plate-pdf) sets its type with fontspec, and fontspec cannot
# read woff2 — that container exists for browsers. The glyphs are identical; only
# the compression wrapper differs, so this is a repackage, not a conversion, and
# the PDF ends up with exactly the typeface the deck uses.
#
# Note the difference from build-fonts.sh next door: that one *subsets* the fonts
# for the web, where every byte ships over the wire. Here the whole face is kept.
# A PDF embeds only the glyphs it actually uses, so subsetting up front would buy
# nothing and would silently drop any character a future deck happens to need.
#
# Run from anywhere, inside the nix devShell (needs fontTools and brotli):
#   ./_extensions/adamcoates/plate/fonts/build-pdf-fonts.sh
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p ttf

python3 - <<'PY'
from fontTools.ttLib import TTFont
import glob, os

for woff in sorted(glob.glob("*.woff2")):
    font = TTFont(woff)
    font.flavor = None  # drop the woff2 wrapper; the tables are untouched
    out = os.path.join("ttf", woff.replace(".woff2", ".ttf"))
    font.save(out)
    print(f"  {out}  ({os.path.getsize(out) // 1024} KB)")
PY

echo
echo "ttf/ rebuilt — plate-pdf picks these up by path, no system install needed."
