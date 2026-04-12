// ============================================================
// PES Scale Metrics — Figma Plugin
// Draws all scale metric diagrams onto the current page.
// ============================================================

// ── Colour palette ───────────────────────────────────────────
const C = {
  bg:        { r: 0.102, g: 0.102, b: 0.180, a: 1 },  // #1a1a2e
  bgCard:    { r: 0.122, g: 0.122, b: 0.220, a: 1 },  // #1f1f38
  grid:      { r: 0.165, g: 0.165, b: 0.290, a: 1 },  // #2a2a4a
  floor:     { r: 0.533, g: 0.533, b: 0.533, a: 1 },  // #888
  text:      { r: 0.878, g: 0.878, b: 0.878, a: 1 },  // #e0e0e0
  textDim:   { r: 0.467, g: 0.467, b: 0.467, a: 1 },  // #777
  textMuted: { r: 0.667, g: 0.667, b: 0.667, a: 1 },  // #aaa
  eyeLine:   { r: 1.000, g: 0.886, b: 0.510, a: 1 },  // #ffe082
  // characters
  player:    { r: 0.310, g: 0.765, b: 0.969, a: 1 },  // #4fc3f7
  enemy:     { r: 0.937, g: 0.329, b: 0.314, a: 1 },  // #ef5350
  tarkov:    { r: 0.400, g: 0.733, b: 0.416, a: 1 },  // #66bb6a
  hunt:      { r: 1.000, g: 0.655, b: 0.149, a: 1 },  // #ffa726
  valorant:  { r: 0.671, g: 0.282, b: 0.737, a: 1 },  // #ab47bc
  cs2:       { r: 0.149, g: 0.776, b: 0.855, a: 1 },  // #26c6da
  // cover
  coverLow:  { r: 0.263, g: 0.627, b: 0.278, a: 1 },  // #43a047
  coverMid:  { r: 0.984, g: 0.549, b: 0.000, a: 1 },  // #fb8c00
  coverFull: { r: 0.898, g: 0.224, b: 0.208, a: 1 },  // #e53935
  white:     { r: 1, g: 1, b: 1, a: 1 },
  accent:    { r: 0.000, g: 0.773, b: 1.000, a: 1 },  // #00c5ff
};

// ── helpers ──────────────────────────────────────────────────

function solid(color) {
  return [{ type: 'SOLID', color: { r: color.r, g: color.g, b: color.b }, opacity: (color.a !== undefined ? color.a : 1) }];
}

function rgb(hex) {
  const n = parseInt(hex.replace('#',''), 16);
  return { r: ((n>>16)&255)/255, g: ((n>>8)&255)/255, b: (n&255)/255, a: 1 };
}

async function loadFont(family = 'Inter', style = 'Regular') {
  await figma.loadFontAsync({ family, style });
}

function makeRect(parent, x, y, w, h, color, name = 'rect', cornerRadius = 0, opacity = 1) {
  const r = figma.createRectangle();
  r.name = name;
  r.x = x; r.y = y; r.resize(w, h);
  r.fills = solid(color);
  r.opacity = opacity;
  if (cornerRadius) r.cornerRadius = cornerRadius;
  parent.appendChild(r);
  return r;
}

function makeLine(parent, x1, y1, x2, y2, color, dash = false, strokeW = 1) {
  const v = figma.createVector();
  v.name = 'line';
  const path = `M ${x1} ${y1} L ${x2} ${y2}`;
  v.vectorPaths = [{ windingRule: 'NONE', data: path }];
  v.strokes = solid(color);
  v.strokeWeight = strokeW;
  v.fills = [];
  if (dash) v.dashPattern = [6, 4];
  parent.appendChild(v);
  return v;
}

async function makeText(parent, x, y, content, size = 12, color = C.text, align = 'LEFT', bold = false) {
  const t = figma.createText();
  t.x = x; t.y = y;
  t.characters = String(content);
  t.fontSize = size;
  t.fills = solid(color);
  t.textAlignHorizontal = align;
  if (bold) t.fontName = { family: 'Inter', style: 'Bold' };
  parent.appendChild(t);
  return t;
}

function makeFrame(parent, x, y, w, h, name, bg = C.bg) {
  const f = figma.createFrame();
  f.name = name;
  f.x = x; f.y = y;
  f.resize(w, h);
  f.fills = solid(bg);
  f.clipsContent = false;
  if (parent) parent.appendChild(f);
  return f;
}

// ── Section title ─────────────────────────────────────────────
async function sectionTitle(parent, x, y, title, subtitle = '') {
  await makeText(parent, x, y, title, 22, C.text, 'LEFT', true);
  if (subtitle) await makeText(parent, x, y + 28, subtitle, 13, C.textDim, 'LEFT');
}

// ── Grid lines (horizontal, by metre) ────────────────────────
function drawGrid(parent, originX, originY, scaleY, maxM, width, color = C.grid) {
  for (let m = 0; m <= maxM; m += 0.5) {
    const gy = originY - m * scaleY;
    makeLine(parent, originX, gy, originX + width, gy, color, true);
  }
}

// ============================================================
// DIAGRAM 1 — Character Heights
// ============================================================
async function drawCharacterHeights(parent, ox, oy) {
  const W = 860, H = 520;
  const frame = makeFrame(parent, ox, oy, W, H, '01 — Character Heights');
  makeRect(frame, 0, 0, W, H, C.bg, 'bg', 8);

  await sectionTitle(frame, 24, 20, 'Character Heights Comparison', '1 grid square = 0.5 m  |  floor at Y = 0');

  const FLOOR_Y = 420;
  const SCALE   = 150;   // px per metre
  const LEFT    = 70;
  const COL_W   = 80;
  const SPACING = 120;

  const chars = [
    { label: 'PES\nPlayer',    h: 1.80, eye: 1.70, col: C.player  },
    { label: 'PES\nEnemy',     h: 1.60, eye: 1.08, col: C.enemy   },
    { label: 'Tarkov',         h: 1.85, eye: 1.70, col: C.tarkov  },
    { label: 'Hunt:\nShowdown',h: 1.90, eye: 1.75, col: C.hunt    },
    { label: 'Valorant\n(UE)', h: 1.76, eye: 1.52, col: C.valorant},
    { label: 'CS2\n(Source)',  h: 1.83, eye: 1.63, col: C.cs2     },
  ];

  // grid
  drawGrid(frame, LEFT - 10, FLOOR_Y, SCALE, 2.5, W - LEFT - 10);

  // metre labels on left axis
  for (let m = 0; m <= 2.5; m += 0.5) {
    const gy = FLOOR_Y - m * SCALE;
    await makeText(frame, LEFT - 42, gy - 7, `${m.toFixed(1)}m`, 11, C.textDim, 'RIGHT');
  }

  // floor line
  makeLine(frame, LEFT - 10, FLOOR_Y, W - 20, FLOOR_Y, C.floor, false, 2);
  await makeText(frame, W / 2 - 40, FLOOR_Y + 10, 'Floor  (Y = 0)', 11, C.textDim);

  // bars
  for (let i = 0; i < chars.length; i++) {
    const { label, h, eye, col } = chars[i];
    const cx   = LEFT + i * SPACING + COL_W / 2;
    const barH = h * SCALE;
    const barY = FLOOR_Y - barH;
    const bw   = COL_W - 10;

    // body bar
    makeRect(frame, cx - bw / 2, barY, bw, barH, col, label, 4, 0.85);

    // eye height dash
    const ey = FLOOR_Y - eye * SCALE;
    makeLine(frame, cx - bw / 2 - 6, ey, cx + bw / 2 + 6, ey, C.eyeLine, true, 1.5);

    // height label above bar
    await makeText(frame, cx - 20, barY - 20, `${h.toFixed(2)}m`, 11, C.textMuted);

    // character label (split lines)
    const lines = label.split('\n');
    const ly = barY + barH / 2 - (lines.length - 1) * 9;
    for (let j = 0; j < lines.length; j++) {
      await makeText(frame, cx - bw / 2 + 4, ly + j * 16, lines[j], 11, C.white, 'LEFT', true);
    }
  }

  // legend
  const lx = W - 200, ly2 = 20;
  makeLine(frame, lx, ly2 + 6, lx + 36, ly2 + 6, C.eyeLine, true, 1.5);
  await makeText(frame, lx + 42, ly2, 'Eye / camera height', 11, C.eyeLine);

  return frame;
}

// ============================================================
// DIAGRAM 2 — Cover Heights
// ============================================================
async function drawCoverHeights(parent, ox, oy) {
  const W = 720, H = 500;
  const frame = makeFrame(parent, ox, oy, W, H, '02 — Cover Heights');
  makeRect(frame, 0, 0, W, H, C.bg, 'bg', 8);

  await sectionTitle(frame, 24, 20, 'Cover Height Reference', 'Relative to PES player capsule (1.8 m)');

  const FLOOR_Y = 400;
  const SCALE   = 155;
  const LEFT    = 70;

  // grid
  drawGrid(frame, LEFT - 10, FLOOR_Y, SCALE, 2.0, W - LEFT - 10);
  for (let m = 0; m <= 2.0; m += 0.5) {
    const gy = FLOOR_Y - m * SCALE;
    await makeText(frame, LEFT - 42, gy - 7, `${m.toFixed(1)}m`, 11, C.textDim, 'RIGHT');
  }
  makeLine(frame, LEFT - 10, FLOOR_Y, W - 20, FLOOR_Y, C.floor, false, 2);

  // Player silhouette
  const PAX = 120, PAW = 52;
  const playerH = 1.80 * SCALE;
  makeRect(frame, PAX - PAW / 2, FLOOR_Y - playerH, PAW, playerH, C.player, 'player', 6, 0.45);
  const ey = FLOOR_Y - 1.70 * SCALE;
  makeLine(frame, PAX - PAW / 2 - 6, ey, PAX + PAW / 2 + 6, ey, C.eyeLine, true, 1.5);
  await makeText(frame, PAX - 30, FLOOR_Y - playerH - 18, 'Player  1.8m', 12, C.player, 'LEFT', true);

  // covers
  const covers = [
    { label: 'Low\nCover',  h: 0.90, cx: 270, col: C.coverLow,  note: '0.8 – 1.0 m\ncrouched only' },
    { label: 'Mid\nCover',  h: 1.35, cx: 420, col: C.coverMid,  note: '1.2 – 1.5 m\ntorso hidden'  },
    { label: 'Full\nCover', h: 1.95, cx: 570, col: C.coverFull, note: '≥ 1.9 m\nfully hidden'      },
  ];

  const CW = 88;
  for (const { label, h, cx, col, note } of covers) {
    const ch = h * SCALE;
    const cy = FLOOR_Y - ch;
    makeRect(frame, cx - CW / 2, cy, CW, ch, col, label, 3, 0.85);

    // label inside
    const lines = label.split('\n');
    const ly = cy + ch / 2 - (lines.length - 1) * 9;
    for (let j = 0; j < lines.length; j++) {
      await makeText(frame, cx - CW / 2 + 4, ly + j * 16, lines[j], 12, C.white, 'LEFT', true);
    }

    // height above
    await makeText(frame, cx - 18, cy - 20, `${h.toFixed(2)}m`, 12, C.textMuted);

    // note below floor
    const nls = note.split('\n');
    for (let j = 0; j < nls.length; j++) {
      await makeText(frame, cx - CW / 2, FLOOR_Y + 18 + j * 16, nls[j], 10, C.textDim);
    }

    // dimension line on right
    const dx = cx + CW / 2 + 16;
    makeLine(frame, dx, FLOOR_Y, dx, cy, { r: 0.4, g: 0.4, b: 0.4, a: 1 }, false, 1);
  }

  // legend
  makeLine(frame, W - 230, 22, W - 190, 22, C.eyeLine, true, 1.5);
  await makeText(frame, W - 184, 16, 'Player eye height (1.70m)', 11, C.eyeLine);

  return frame;
}

// ============================================================
// DIAGRAM 3 — Speed Comparison
// ============================================================
async function drawSpeedComparison(parent, ox, oy) {
  const W = 680, H = 420;
  const frame = makeFrame(parent, ox, oy, W, H, '03 — Speed Comparison');
  makeRect(frame, 0, 0, W, H, C.bg, 'bg', 8);

  await sectionTitle(frame, 24, 20, 'Movement Speed Comparison', 'm/s  |  light bar = walk  |  full bar = sprint');

  const MAX_SPD = 10.0;
  const LEFT    = 168;
  const BAR_H   = 22;
  const ROW_H   = 52;
  const BAR_W   = 460;

  const games = [
    { label: 'PES (current)',   walk: 5.0, sprint: 9.0, col: C.player   },
    { label: 'Valorant',        walk: 5.4, sprint: 6.6, col: C.valorant },
    { label: 'Call of Duty',    walk: 5.8, sprint: 8.5, col: C.hunt     },
    { label: 'Hunt: Showdown',  walk: 4.0, sprint: 6.5, col: C.tarkov   },
    { label: 'Tarkov',          walk: 3.5, sprint: 5.5, col: C.enemy    },
    { label: 'CS2',             walk: 2.5, sprint: 5.5, col: C.cs2      },
  ];

  // grid verticals
  for (let v = 0; v <= 10; v++) {
    const gx = LEFT + (v / MAX_SPD) * BAR_W;
    makeLine(frame, gx, 62, gx, H - 50, C.grid, true);
    await makeText(frame, gx - 4, H - 36, `${v}`, 10, C.textDim);
  }
  await makeText(frame, LEFT + BAR_W / 2 - 10, H - 18, 'm/s', 11, C.textDim);

  for (let i = 0; i < games.length; i++) {
    const { label, walk, sprint, col } = games[i];
    const y = 68 + i * ROW_H;

    // walk bar (dim)
    const ww = (walk / MAX_SPD) * BAR_W;
    makeRect(frame, LEFT, y, ww, BAR_H, col, 'walk', 3, 0.35);

    // sprint bar (full)
    const sw = (sprint / MAX_SPD) * BAR_W;
    makeRect(frame, LEFT, y, sw, BAR_H, col, 'sprint', 3, 0.88);

    // labels
    await makeText(frame, LEFT - 8, y + BAR_H / 2 - 6, label, 12, C.textMuted, 'RIGHT');
    await makeText(frame, LEFT + sw + 8, y + BAR_H / 2 - 6, `${sprint} m/s`, 11, col);
  }

  return frame;
}

// ============================================================
// DIAGRAM 4 — Prop Scale Comparison
// ============================================================
async function drawPropScale(parent, ox, oy) {
  const W = 680, H = 380;
  const frame = makeFrame(parent, ox, oy, W, H, '04 — Prop Scale vs Real World');
  makeRect(frame, 0, 0, W, H, C.bg, 'bg', 8);

  await sectionTitle(frame, 24, 20, 'Prop Scale vs Real World', 'Heights to scale — all compared to PES player (1.8 m)');

  const FLOOR_Y = 300;
  const SCALE   = 110;
  const LEFT    = 70;

  drawGrid(frame, LEFT - 10, FLOOR_Y, SCALE, 2.5, W - LEFT - 10);
  for (let m = 0; m <= 2.5; m += 0.5) {
    const gy = FLOOR_Y - m * SCALE;
    await makeText(frame, LEFT - 42, gy - 7, `${m.toFixed(1)}m`, 11, C.textDim, 'RIGHT');
  }
  makeLine(frame, LEFT - 10, FLOOR_Y, W - 20, FLOOR_Y, C.floor, false, 2);

  const props = [
    { label: 'PES\nPlayer',       h: 1.80, col: C.player,   note: '1.80m\n(reference)' },
    { label: 'PES\nMicrowave',    h: 0.75, col: C.accent,   note: '0.75m\n(game)' },
    { label: 'Real\nMicrowave',   h: 0.35, col: { r: 0.4, g: 0.4, b: 0.4, a: 1 }, note: '0.35m\n(real)' },
    { label: 'PES\nWall',         h: 4.00, col: C.hunt,     note: '4.0m\n(game)' },
    { label: 'Real\nWall',        h: 2.40, col: { r: 0.5, g: 0.4, b: 0.3, a: 1 }, note: '2.4m\n(real)' },
    { label: 'PES\nEnemy',        h: 1.60, col: C.enemy,    note: '1.60m\n(game)' },
  ];

  const CW = 62;
  const SPACING = 98;
  for (let i = 0; i < props.length; i++) {
    const { label, h, col, note } = props[i];
    const cx = LEFT + 30 + i * SPACING;
    const ch = Math.min(h, 2.5) * SCALE;
    const cy = FLOOR_Y - ch;
    makeRect(frame, cx - CW / 2, cy, CW, ch, col, label, 3, 0.85);

    const lines = label.split('\n');
    const ly = cy + 8;
    for (let j = 0; j < lines.length; j++) {
      await makeText(frame, cx - CW / 2 + 4, ly + j * 14, lines[j], 10, C.white, 'LEFT', true);
    }

    const nls = note.split('\n');
    for (let j = 0; j < nls.length; j++) {
      await makeText(frame, cx - CW / 2, FLOOR_Y + 14 + j * 14, nls[j], 10, C.textDim);
    }
  }

  // inflation callout
  const callX = LEFT + 2 * SPACING + 30 + CW / 2 + 10;
  await makeText(frame, 280, FLOOR_Y - 0.75 * SCALE - 30, '~2× inflated\nfor readability', 11, C.accent);

  return frame;
}

// ============================================================
// MAIN
// ============================================================
async function main() {
  await loadFont('Inter', 'Regular');
  await loadFont('Inter', 'Bold');

  const page = figma.currentPage;
  page.name = 'Metrics';

  // Place frames in a 2×2 grid with padding
  const PAD = 60;
  const frames = [];

  frames.push(await drawCharacterHeights(page, PAD,              PAD));
  frames.push(await drawCoverHeights(    page, PAD + 900 + PAD,  PAD));
  frames.push(await drawSpeedComparison( page, PAD,              PAD + 560 + PAD));
  frames.push(await drawPropScale(       page, PAD + 900 + PAD,  PAD + 560 + PAD));

  // Fit viewport to show all frames
  figma.viewport.scrollAndZoomIntoView(frames);

  figma.notify('PES Metrics drawn! ✓', { timeout: 3000 });
  figma.closePlugin();
}

main().catch(err => {
  figma.notify('Error: ' + err.message, { error: true });
  figma.closePlugin();
});
