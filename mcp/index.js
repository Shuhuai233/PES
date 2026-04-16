#!/usr/bin/env node
/**
 * PES MCP Server
 * Project-specific MCP for the PES Godot 4.6 FPS game.
 * Provides tools to read scripts, search symbols, and query game constants
 * without the AI needing to re-scan the whole project every time.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, "..");
const SCRIPTS_DIR = path.join(PROJECT_ROOT, "scripts");
const SCENES_DIR = path.join(PROJECT_ROOT, "scenes");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function readFile(filePath) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch {
    return null;
  }
}

function listFiles(dir, ext) {
  try {
    return fs.readdirSync(dir).filter((f) => f.endsWith(ext));
  } catch {
    return [];
  }
}

// ---------------------------------------------------------------------------
// Hard-coded PES game constants
// ---------------------------------------------------------------------------

const PES_CONSTANTS = {
  project: {
    name: "PES",
    engine: "Godot 4.6",
    renderer: "Forward Plus",
    version: "v0.3",
    entry_scene: "walk_scene.tscn",
    language: "GDScript",
    platform: "Windows Desktop x86_64",
  },
  player: {
    speed: 5.0,
    sprint_speed: 9.0,
    jump_velocity: 4.5,
    mouse_sensitivity: 0.003,
    gravity: 9.8,
    jam_chance: 0.12,
    shoot_cooldown: 0.15,
    magazine_size: 15,
    reload_time: 2.0,
    shot_damage: 25,
    signals: ["ammo_changed", "jammed", "jam_cleared", "shot_fired", "enemy_hit"],
    input_actions: ["shoot", "clear_jam", "reload", "jump", "sprint", "move_left", "move_right", "move_forward", "move_back", "ui_cancel"],
  },
  enemy: {
    speed: 2.5,
    gravity: 9.8,
    attack_range: 1.5,
    attack_damage: 10,
    attack_cooldown: 1.5,
    max_health: 100,
    variants: ["red soldier (0.7,0.1,0.1)", "blue grunt (0.1,0.1,0.7)", "green heavy (0.15,0.5,0.15)"],
    signals: ["died", "damaged_player"],
  },
  spawner: {
    spawn_interval: 4.0,
    max_enemies: 8,
    spawn_radius: 12.0,
    first_spawn_delay: 0.5,
    signals: ["enemy_spawned", "enemy_killed"],
  },
  session_manager: {
    type: "Autoload singleton",
    tracked_fields: ["id", "start_time", "end_time", "duration", "data (key-value store)"],
    signals: ["session_started", "session_ended"],
    methods: ["start_session", "end_session", "set_value", "get_value", "get_elapsed_time", "get_session_snapshot"],
  },
  portal: {
    hold_duration: 2.0,
    states: ["idle", "active", "extracting"],
    light_colors: { idle: "cyan", active: "orange", extracting: "white" },
    interaction_key: "E",
  },
  scripts: [
    { file: "main.gd", role: "Root node - initialises SessionManager" },
    { file: "session_manager.gd", role: "Autoload singleton - tracks session data and events" },
    { file: "player_controller.gd", role: "FPS movement, mouse look, gun + jam mechanic" },
    { file: "enemy.gd", role: "Chase AI, melee attack, health, hit flash, death tween" },
    { file: "enemy_spawner.gd", role: "Procedural enemy spawning in the arena" },
    { file: "microwave_portal.gd", role: "Extraction portal - bob, rotate, hold-E extraction" },
    { file: "walk_scene.gd", role: "Scene orchestrator - wires all systems together" },
    { file: "walkthrough_ui.gd", role: "HUD + 9-step tutorial overlay" },
  ],
  tutorial_steps: [
    "WELCOME", "MOVEMENT", "LOOK_AROUND", "FIND_PORTAL",
    "ENTER_PORTAL", "SHOOT_ENEMIES", "JAM_CLEAR", "EXTRACT", "COMPLETE",
  ],
};

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

const server = new McpServer({
  name: "pes",
  version: "1.0.0",
});

// --- Tool: pes_get_project_info ---
server.tool(
  "pes_get_project_info",
  "Get a full structured summary of the PES project: what it is, its gameplay loop, all systems, and key file paths. Use this first to understand the project.",
  {},
  async () => {
    const summary = [
      "# PES - Project Summary",
      "",
      "## What it is",
      "PES is a 3D First-Person Extraction Shooter game prototype built in Godot 4.6.",
      "Inspired by the indie Steam game HOLE (see HOLE_RESEARCH.md).",
      "All 3D geometry is built procedurally at runtime - no external 3D assets.",
      "",
      "## Gameplay Loop",
      "1. Player approaches a floating microwave oven (the portal) -> stage entry",
      "2. EnemySpawner activates: spawns up to 8 enemies in a 12-unit radius arena every 4s",
      "3. Player shoots enemies (25 dmg/hit, 12% jam chance, 15-round mag, 2s reload)",
      "4. Player holds E on the portal for 2 seconds to extract and end the session",
      "",
      "## Core Tension: Gun Jam Mechanic",
      "- 12% chance per shot to jam",
      "- Clear with F key (rack animation + jam_cleared signal)",
      "",
      "## Systems",
      "- PlayerController  - FPS movement, mouse look, weapon, jam/reload",
      "- Enemy             - Chase AI, melee attack (10 dmg, 1.5s cooldown), 100 HP",
      "- EnemySpawner      - Procedural spawning, kill counting",
      "- MicrowavePortal   - Extraction mechanic with hold-E progress bar",
      "- SessionManager    - Autoload singleton (id, duration, key-value session data)",
      "- WalkthroughUI     - HUD + 9-step tutorial overlay",
      "- PSXManager        - make_psx_material() for all procedural geometry",
      "",
      "## Key Paths",
      "- Project root:  /home/shli2/PES/",
      "- Scripts:       /home/shli2/PES/scripts/",
      "- Scenes:        /home/shli2/PES/scenes/",
      "- Builds:        /home/shli2/PES/builds/",
      "- Research doc:  /home/shli2/PES/HOLE_RESEARCH.md",
      "",
      "## Godot Config",
      "- Entry scene: walk_scene.tscn",
      "- Renderer: Forward Plus",
      "- Engine: Godot 4.6",
      "- Autoloads: SessionManager (scripts/session_manager.gd)",
      "",
      "## Version History",
      "- v0.1: Initial setup + HOLE research",
      "- v0.2: Full walkthrough (playable)",
      "- v0.2-windows: First Windows build",
      "- v0.3: Bug fixes (mouse capture, hold-E portal, weapon, enemies)",
      "- chore: Gitignore cleanup, upgrade to Godot 4.6.2",
    ].join("\n");
    return { content: [{ type: "text", text: summary }] };
  }
);

// --- Tool: pes_get_constants ---
server.tool(
  "pes_get_constants",
  "Get PES game constants and hardcoded values (player stats, enemy stats, spawner config, session manager fields, etc.) without reading any files.",
  {
    category: z
      .enum(["all", "project", "player", "enemy", "spawner", "session_manager", "portal", "scripts", "tutorial_steps"])
      .optional()
      .describe("Which category to return. Defaults to 'all'."),
  },
  async ({ category }) => {
    const key = category || "all";
    const data = key === "all" ? PES_CONSTANTS : PES_CONSTANTS[key];
    if (data === undefined) {
      return { content: [{ type: "text", text: "Unknown category: " + key }] };
    }
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  }
);

// --- Tool: pes_list_scripts ---
server.tool(
  "pes_list_scripts",
  "List all GDScript files in the PES project with a one-line description of each.",
  {},
  async () => {
    const lines = PES_CONSTANTS.scripts
      .map((s) => s.file.padEnd(28) + " - " + s.role)
      .join("\n");
    return { content: [{ type: "text", text: lines }] };
  }
);

// --- Tool: pes_get_script ---
server.tool(
  "pes_get_script",
  "Read the full contents of a GDScript file from the PES project.",
  {
    name: z.string().describe("Script filename, e.g. 'player_controller.gd'. The .gd extension is optional."),
  },
  async ({ name }) => {
    const filename = name.endsWith(".gd") ? name : name + ".gd";
    const filePath = path.join(SCRIPTS_DIR, filename);
    const content = readFile(filePath);
    if (content === null) {
      const available = listFiles(SCRIPTS_DIR, ".gd").join(", ");
      return {
        content: [{ type: "text", text: "Script '" + filename + "' not found.\nAvailable: " + available }],
      };
    }
    return { content: [{ type: "text", text: content }] };
  }
);

// --- Tool: pes_get_scene ---
server.tool(
  "pes_get_scene",
  "Read the full contents of a .tscn scene file from the PES project.",
  {
    name: z.string().describe("Scene filename, e.g. 'walk_scene.tscn'. The .tscn extension is optional."),
  },
  async ({ name }) => {
    const filename = name.endsWith(".tscn") ? name : name + ".tscn";
    const filePath = path.join(SCENES_DIR, filename);
    const content = readFile(filePath);
    if (content === null) {
      const available = listFiles(SCENES_DIR, ".tscn").join(", ");
      return {
        content: [{ type: "text", text: "Scene '" + filename + "' not found.\nAvailable: " + available }],
      };
    }
    return { content: [{ type: "text", text: content }] };
  }
);

// --- Tool: pes_search_symbol ---
server.tool(
  "pes_search_symbol",
  "Search for a function, signal, variable, or any text pattern across all GDScript files in PES.",
  {
    pattern: z.string().describe("Text or regex pattern, e.g. 'jam_cleared', 'func take_damage', 'signal died'."),
  },
  async ({ pattern }) => {
    const scripts = listFiles(SCRIPTS_DIR, ".gd");
    const results = [];

    let regex;
    try {
      regex = new RegExp(pattern, "gi");
    } catch {
      const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      regex = new RegExp(escaped, "gi");
    }

    for (const filename of scripts) {
      const filePath = path.join(SCRIPTS_DIR, filename);
      const content = readFile(filePath);
      if (!content) continue;
      const lines = content.split("\n");
      const matches = [];
      for (let i = 0; i < lines.length; i++) {
        regex.lastIndex = 0;
        if (regex.test(lines[i])) {
          matches.push("  L" + (i + 1) + ": " + lines[i].trim());
        }
      }
      if (matches.length > 0) {
        results.push("--- " + filename + " ---\n" + matches.join("\n"));
      }
    }

    if (results.length === 0) {
      return { content: [{ type: "text", text: "No matches found for: " + pattern }] };
    }
    return { content: [{ type: "text", text: results.join("\n\n") }] };
  }
);

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

const transport = new StdioServerTransport();
await server.connect(transport);
