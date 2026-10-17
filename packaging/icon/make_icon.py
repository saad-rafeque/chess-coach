"""Builds the Chess Coach icon SVGs: full icon, Android adaptive background and foreground."""
import sys

OUT = sys.argv[1]

# cburnett knight (Colin M.L. Burnett, GPL-2.0-or-later), 45x45 units.
BODY = "M22 10c10.5 1 16.5 8 16 29H15c0-9 10-6.5 8-21"
HEAD = ("M24 18c.38 2.91-5.55 7.37-8 9-3 2-2.82 4.34-5 4-1.042-.94 1.41-3.04 0-3-1 0 .19 1.23-1 2-1 0-4.003 1-4-4 "
        "0-2 6-12 6-12s1.89-1.9 2-3.5c-.73-.994-.5-2-.5-3 1-1 3 2.5 3 2.5h2s.78-1.992 2.5-3c1 0 1 3 1 3")
EYES = "M9.5 25.5a.5.5 0 1 1-1 0 .5.5 0 1 1 1 0m5.433-9.75a.5 1.5 30 1 1-.866-.5.5 1.5 30 1 1 .866.5"

DEFS = """
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#2b3f6e"/><stop offset="0.5" stop-color="#141d3a"/><stop offset="1" stop-color="#070a16"/>
</linearGradient>
<radialGradient id="glow" cx="0.5" cy="0.42" r="0.5">
  <stop offset="0" stop-color="#ffd27a" stop-opacity="0.55"/>
  <stop offset="0.45" stop-color="#ff9d2e" stop-opacity="0.16"/>
  <stop offset="1" stop-color="#ff9d2e" stop-opacity="0"/>
</radialGradient>
<linearGradient id="gold" x1="0.15" y1="0" x2="0.85" y2="1">
  <stop offset="0" stop-color="#fff7da"/><stop offset="0.22" stop-color="#ffdc7d"/>
  <stop offset="0.5" stop-color="#eeaa3a"/><stop offset="0.78" stop-color="#b8731b"/><stop offset="1" stop-color="#7c470c"/>
</linearGradient>
<linearGradient id="sheen" x1="0" y1="0" x2="1" y2="0.6">
  <stop offset="0" stop-color="#ffffff" stop-opacity="0.75"/><stop offset="0.35" stop-color="#ffffff" stop-opacity="0.12"/>
  <stop offset="0.6" stop-color="#ffffff" stop-opacity="0"/>
</linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#ffe3a0" stop-opacity="0.9"/><stop offset="0.5" stop-color="#c58a2b" stop-opacity="0.35"/>
  <stop offset="1" stop-color="#ffe3a0" stop-opacity="0.7"/>
</linearGradient>
<linearGradient id="boardfade" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="0.35" stop-color="#fff" stop-opacity="0.55"/>
  <stop offset="1" stop-color="#fff" stop-opacity="1"/>
</linearGradient>
<mask id="boardmask"><rect x="0" y="540" width="1024" height="484" fill="url(#boardfade)"/></mask>
<filter id="blur" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="22"/></filter>
<filter id="soft" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="3"/></filter>
"""


def board():
    """A chessboard plane seen in perspective, fading towards the horizon."""
    horizon, vx, f = 540.0, 512.0, 300.0
    parts = []

    def proj(u, v):  # u: across, v: depth (0 = nearest)
        d = v + 0.9
        return vx + u * f / d, horizon + 520.0 / d

    for row in range(12):
        for col in range(-8, 8):
            a, b = proj(col, row), proj(col + 1, row)
            c, d = proj(col + 1, row + 1), proj(col, row + 1)
            light = (row + col) % 2 == 0
            color = "#e8c47c" if light else "#1a2547"
            op = 0.32 if light else 0.75
            pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in (a, b, c, d))
            parts.append(f'<polygon points="{pts}" fill="{color}" fill-opacity="{op}"/>')
    return f'<g mask="url(#boardmask)">{"".join(parts)}</g>'


def knight(scale, cx, cy, shadow=True):
    t = f"translate({cx - 21.75 * scale:.2f},{cy - 23.5 * scale:.2f}) scale({scale})"
    out = []
    if shadow:
        out.append(f'<ellipse cx="{cx + 25}" cy="{cy + 15.3 * scale}" rx="{14 * scale}" ry="{2.2 * scale}" '
                   'fill="#000" fill-opacity="0.65" filter="url(#blur)"/>')
        out.append(f'<g transform="translate(22,18) {t}" filter="url(#blur)" fill="#000" fill-opacity="0.45">'
                   f'<path d="{BODY}"/><path d="{HEAD}"/></g>')
    out.append(f'<g transform="{t}" stroke="#3b2205" stroke-width="1.15" stroke-linejoin="round" stroke-linecap="round">'
               f'<path d="{BODY}" fill="url(#gold)"/><path d="{HEAD}" fill="url(#gold)"/></g>')
    # Light from the top left.
    out.append(f'<g transform="{t}" fill="url(#sheen)"><path d="{BODY}"/><path d="{HEAD}"/></g>')
    out.append(f'<g transform="{t}" fill="none" stroke="#fff1c2" stroke-width="0.55" stroke-linecap="round" '
               f'stroke-opacity="0.85" filter="url(#soft)"><path d="M23.2 11.2c9.2 1.4 14.4 8.2 14 26.6"/></g>')
    # Mane line and eyes.
    out.append(f'<g transform="{t}" fill="none" stroke="#5a3507" stroke-width="0.7" stroke-linecap="round" '
               f'stroke-opacity="0.8"><path d="M24.5 13.5c4 1.5 8 5.5 9.2 13"/></g>')
    out.append(f'<g transform="{t}" fill="#2a1703" stroke="#2a1703" stroke-width="0.9"><path d="{EYES}"/></g>')
    return "".join(out)


def svg(body, rounded=True):
    clip = '<clipPath id="sq"><rect width="1024" height="1024" rx="232"/></clipPath>' if rounded else ""
    g = '<g clip-path="url(#sq)">' if rounded else "<g>"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f"<defs>{DEFS}{clip}</defs>{g}{body}</g></svg>")


background = ('<rect width="1024" height="1024" fill="url(#bg)"/>'
              '<rect width="1024" height="1024" fill="url(#glow)"/>' + board())

full = svg(background + knight(16.2, 512, 462)
           + '<rect x="10" y="10" width="1004" height="1004" rx="224" fill="none" stroke="url(#rim)" stroke-width="8"/>')
# Android adaptive icons: the system masks a 108dp square; keep the knight inside the 66dp safe zone.
adaptive_bg = svg(background, rounded=False)
adaptive_fg = svg(knight(12.6, 512, 488), rounded=False)

for name, s in (("icon", full), ("icon_bg", adaptive_bg), ("icon_fg", adaptive_fg)):
    with open(f"{OUT}/{name}.svg", "w") as fh:
        fh.write(s)
    with open(f"{OUT}/{name}.html", "w") as fh:
        fh.write('<!doctype html><html><head><style>html,body{margin:0;background:transparent}</style></head>'
                 f"<body>{s}</body></html>")
