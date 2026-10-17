"""Packs rendered piece sets (tool/pieces/staunton.py) into Flutter assets.

  python3 tool/pieces/package.py <render dir> <style>[,<style>...]

Writes assets/pieces/<style>/{w,b}{K,Q,R,B,N,P}.webp at 128 px, plus 2.0x/ and 3.0x/ variants, so each
screen loads the size it needs.
"""
import os
import sys

from PIL import Image

src, styles = sys.argv[1], sys.argv[2].split(",")
root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "pieces")
for style in styles:
    for name in [f"{c}{p}" for c in "wb" for p in "KQRBNP"]:
        im = Image.open(os.path.join(src, style, f"{name}.png")).convert("RGBA")
        for folder, size in (("", 128), ("2.0x", 256), ("3.0x", 384)):
            out = os.path.join(root, style, folder)
            os.makedirs(out, exist_ok=True)
            im.resize((size, size), Image.LANCZOS).save(os.path.join(out, f"{name}.webp"), "WEBP", quality=88,
                                                         method=6)
    print("packed", style)
