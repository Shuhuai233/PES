# PES Scale Metrics — Figma Plugin

This plugin draws all PES scale metric diagrams directly onto your Figma canvas.

## What it draws

| Frame | Content |
|---|---|
| 01 — Character Heights | Bar chart comparing player/enemy/industry character heights with eye-height markers |
| 02 — Cover Heights | Player silhouette vs low / mid / full cover targets |
| 03 — Speed Comparison | Walk & sprint speeds across PES, Tarkov, Valorant, CoD, Hunt, CS2 |
| 04 — Prop Scale vs Real World | Microwave, wall, player — game size vs real-world size |

## How to run

1. Open Figma and go to the **PES_Metrics** file
2. Menu → **Plugins** → **Development** → **Import plugin from manifest...**
3. Select the `manifest.json` file from this folder (`figma-plugin/`)
4. Menu → **Plugins** → **Development** → **PES Scale Metrics**
5. The plugin runs once, draws all 4 frames, then closes automatically

The current page will be renamed to **Metrics** and all frames will be arranged in a 2×2 grid.
