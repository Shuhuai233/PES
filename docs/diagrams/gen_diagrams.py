"""
Generate SVG scale diagrams for PES SCALE_METRICS.md
Run: python3 gen_diagrams.py
"""

# ── helpers ────────────────────────────────────────────────────────────────────

def svg_open(w, h, bg="#1a1a2e"):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'style="background:{bg};font-family:monospace">\n'
    )

def svg_close():
    return "</svg>\n"

def rect(x, y, w, h, fill, stroke="none", rx=0, opacity=1.0):
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="1.5" '
        f'rx="{rx}" opacity="{opacity}"/>\n'
    )

def line(x1, y1, x2, y2, color="#555", dash=""):
    dash_attr = f'stroke-dasharray="{dash}"' if dash else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="1" {dash_attr}/>\n'

def text(x, y, s, size=12, color="#e0e0e0", anchor="middle", weight="normal"):
    return (
        f'<text x="{x}" y="{y}" text-anchor="{anchor}" '
        f'font-size="{size}" fill="{color}" font-weight="{weight}">{s}</text>\n'
    )

def dim_arrow(x, y1, y2, color="#aaa", label="", lx=None, ly=None):
    """Vertical dimension arrow from y1 to y2 at x."""
    svg = ""
    svg += f'<line x1="{x}" y1="{y1}" x2="{x}" y2="{y2}" stroke="{color}" stroke-width="1.5"/>\n'
    # arrowheads
    for yy, dy in [(y1, -5), (y2, 5)]:
        svg += f'<polygon points="{x},{yy} {x-4},{yy+dy} {x+4},{yy+dy}" fill="{color}"/>\n'
    if label:
        lx = lx or x + 10
        ly = ly or (y1 + y2) / 2
        svg += text(lx, ly + 4, label, size=11, color=color, anchor="start")
    return svg

# ── 1. Character Heights ────────────────────────────────────────────────────────

def make_character_heights():
    W, H = 900, 560
    FLOOR_Y = 460
    SCALE = 160  # pixels per metre

    # columns: (label, height_m, eye_m, fill, text_col)
    chars = [
        ("PES\nPlayer",   1.80, 1.70, "#4fc3f7", "#0d1b2a"),
        ("PES\nEnemy",    1.60, 1.08, "#ef5350", "#fff"),
        ("Tarkov",        1.85, 1.70, "#66bb6a", "#0d1b2a"),
        ("Hunt",          1.90, 1.75, "#ffa726", "#0d1b2a"),
        ("Valorant\n(UE)", 1.76, 1.52, "#ab47bc", "#fff"),
        ("CS2\n(Source)", 1.83, 1.63, "#26c6da", "#0d1b2a"),
    ]

    col_w = 100
    spacing = 120
    start_x = 80

    svg = svg_open(W, H)

    # title
    svg += text(W // 2, 34, "Character Height Comparison", size=18, color="#e0e0e0", weight="bold")
    svg += text(W // 2, 54, "1 grid square = 0.5 m", size=12, color="#777")

    # grid lines every 0.5 m up to 2.5 m
    for m in [x * 0.5 for x in range(6)]:
        gy = FLOOR_Y - m * SCALE
        svg += line(40, gy, W - 20, gy, color="#2a2a4a", dash="4 4")
        svg += text(34, gy + 4, f"{m:.1f}m", size=10, color="#555", anchor="end")

    # floor line
    svg += line(40, FLOOR_Y, W - 20, FLOOR_Y, color="#888")
    svg += text(W // 2, FLOOR_Y + 18, "Floor  (Y = 0)", size=11, color="#666")

    for i, (label, h, eye, fill, tcol) in enumerate(chars):
        cx = start_x + i * spacing
        bar_h = h * SCALE
        bar_y = FLOOR_Y - bar_h
        bw = col_w - 16

        # body bar
        svg += rect(cx - bw // 2, bar_y, bw, bar_h, fill, stroke="#fff", rx=4, opacity=0.88)

        # eye height dash
        ey = FLOOR_Y - eye * SCALE
        svg += line(cx - bw // 2 - 6, ey, cx + bw // 2 + 6, ey, color="#ffe082", dash="5 3")

        # label inside bar
        lines = label.split("\n")
        ly = bar_y + bar_h / 2 - (len(lines) - 1) * 8
        for j, ln in enumerate(lines):
            svg += text(cx, ly + j * 16, ln, size=11, color=tcol, weight="bold")

        # height annotation
        svg += text(cx, bar_y - 8, f"{h:.2f}m", size=11, color="#ccc")

    # eye height legend
    svg += line(W - 160, 80, W - 120, 80, color="#ffe082", dash="5 3")
    svg += text(W - 115, 84, "Eye height", size=11, color="#ffe082", anchor="start")

    svg += svg_close()
    return svg


# ── 2. Cover Heights ────────────────────────────────────────────────────────────

def make_cover_heights():
    W, H = 760, 520
    FLOOR_Y = 420
    SCALE = 160

    svg = svg_open(W, H)
    svg += text(W // 2, 34, "Cover Height Reference  (PES)", size=18, color="#e0e0e0", weight="bold")
    svg += text(W // 2, 54, "relative to PES player capsule (1.8 m)", size=12, color="#777")

    # grid
    for m in [x * 0.5 for x in range(5)]:
        gy = FLOOR_Y - m * SCALE
        svg += line(40, gy, W - 20, gy, color="#2a2a4a", dash="4 4")
        svg += text(34, gy + 4, f"{m:.1f}m", size=10, color="#555", anchor="end")

    svg += line(40, FLOOR_Y, W - 20, FLOOR_Y, color="#888")

    # player silhouette
    PAX = 120
    PAW = 50
    player_h = 1.80 * SCALE
    svg += rect(PAX - PAW // 2, FLOOR_Y - player_h, PAW, player_h,
                "#4fc3f7", stroke="#81d4fa", rx=6, opacity=0.5)
    # eye line
    ey = FLOOR_Y - 1.70 * SCALE
    svg += line(PAX - PAW // 2 - 4, ey, PAX + PAW // 2 + 4, ey, color="#ffe082", dash="5 3")
    svg += text(PAX, FLOOR_Y - player_h - 10, "Player 1.8m", size=11, color="#81d4fa")

    # cover types
    covers = [
        # (label, height_m, x_centre, fill, note)
        ("Low\nCover", 0.90, 260, "#43a047", "0.8–1.0 m\ncrouched only"),
        ("Mid\nCover", 1.35, 400, "#fb8c00", "1.2–1.5 m\ntorso hidden"),
        ("Full\nCover", 1.95, 545, "#e53935", "≥ 1.9 m\nfully hidden"),
    ]

    CW = 90
    for label, hm, cx, fill, note in covers:
        ch = hm * SCALE
        cy = FLOOR_Y - ch
        svg += rect(cx - CW // 2, cy, CW, ch, fill, stroke="#fff", rx=3, opacity=0.82)
        lns = label.split("\n")
        for j, ln in enumerate(lns):
            svg += text(cx, cy + ch / 2 - 8 + j * 16, ln, size=12, color="#fff", weight="bold")
        svg += text(cx, cy - 10, f"{hm:.2f}m", size=11, color="#ccc")

        # note below floor
        note_lns = note.split("\n")
        for j, ln in enumerate(note_lns):
            svg += text(cx, FLOOR_Y + 22 + j * 16, ln, size=10, color="#aaa")

        # dimension arrow on right side
        svg += dim_arrow(cx + CW // 2 + 18, FLOOR_Y, cy, color="#666",
                         label=f"{hm:.2f}m", lx=cx + CW // 2 + 22, ly=(FLOOR_Y + cy) / 2)

    # legend eye line
    svg += line(W - 170, 76, W - 130, 76, color="#ffe082", dash="5 3")
    svg += text(W - 125, 80, "Player eye (1.70m)", size=11, color="#ffe082", anchor="start")

    svg += svg_close()
    return svg


# ── 3. Speed Comparison (horizontal bar chart) ─────────────────────────────────

def make_speed_chart():
    W, H = 680, 400
    MAX_SPEED = 10.0
    BAR_SCALE = 480 / MAX_SPEED  # pixels per m/s
    LEFT = 160
    BAR_H = 28
    ROW_H = 52

    games = [
        ("PES (current)",  5.0, 9.0,  "#4fc3f7"),
        ("Valorant",       5.4, 6.6,  "#ab47bc"),
        ("Call of Duty",   5.8, 8.5,  "#ffa726"),
        ("Hunt: Showdown", 4.0, 6.5,  "#66bb6a"),
        ("Tarkov",         3.5, 5.5,  "#ef5350"),
        ("CS2",            2.5, 5.5,  "#26c6da"),
    ]

    svg = svg_open(W, H)
    svg += text(W // 2, 34, "Movement Speed Comparison  (m/s)", size=18,
                color="#e0e0e0", weight="bold")

    # x-axis ticks
    for v in range(0, 11, 1):
        gx = LEFT + v * BAR_SCALE
        svg += line(gx, 55, gx, H - 40, color="#2a2a4a", dash="3 4")
        svg += text(gx, H - 24, f"{v}", size=10, color="#666")
    svg += text(LEFT + 5 * BAR_SCALE, H - 10, "m/s", size=11, color="#555")

    for i, (label, walk, sprint, col) in enumerate(games):
        y = 68 + i * ROW_H

        # walk bar (lighter)
        ww = walk * BAR_SCALE
        svg += rect(LEFT, y, ww, BAR_H, col, rx=3, opacity=0.45)
        svg += text(LEFT + ww + 5, y + BAR_H / 2 + 4, f"walk {walk}", size=10, color="#aaa", anchor="start")

        # sprint bar (full)
        sw = sprint * BAR_SCALE
        svg += rect(LEFT, y, sw, BAR_H, col, rx=3, opacity=0.88)
        svg += text(LEFT + sw + 5, y + BAR_H / 2 + 4, f"sprint {sprint}", size=10, color=col, anchor="start")

        # label
        svg += text(LEFT - 8, y + BAR_H / 2 + 4, label, size=11, color="#ccc", anchor="end")

    # legend
    svg += rect(LEFT, H - 40, 18, 12, "#888", rx=2, opacity=0.45)
    svg += text(LEFT + 22, H - 30, "Walk", size=11, color="#aaa", anchor="start")
    svg += rect(LEFT + 80, H - 40, 18, 12, "#888", rx=2, opacity=0.88)
    svg += text(LEFT + 104, H - 30, "Sprint", size=11, color="#ccc", anchor="start")

    svg += svg_close()
    return svg


# ── write files ────────────────────────────────────────────────────────────────

import os
OUT = os.path.dirname(os.path.abspath(__file__))

files = {
    "character_heights.svg": make_character_heights(),
    "cover_heights.svg":     make_cover_heights(),
    "speed_comparison.svg":  make_speed_chart(),
}

for name, content in files.items():
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        f.write(content)
    print(f"Written: {path}")

print("Done.")
