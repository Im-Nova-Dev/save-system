---
-- example.lua
-- Complete example showing all features of the save system.
--
-- Run with: lua example.lua (from the save_system directory)
-- Or: lua /path/to/save_system/example.lua (resolves paths automatically)
--

-- Add this script's directory to package.path so requires resolve correctly
local script_dir = (arg and arg[0] and arg[0]:match("^(.*/)")) or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "lib/?.lua;" .. package.path

local SaveManager = require("save_manager")

-- ─── 1. Create a manager ──────────────────────────────────
local sm = SaveManager:new({
  save_dir = "./save_demo/",
  max_slots = 5,
  -- encryption_key = "my-secret",  -- uncomment to encrypt all saves
})

-- ─── 2. Define a schema ───────────────────────────────────
sm:set_schema({
  player = {
    name = "string",
    level = "number",
    hp = "number",
    max_hp = "number",
    xp = "number",
    inventory = {"string"},
    stats = {
      str = "number",
      dex = "number",
      int = "number",
    },
  },
  quests = {
    active = {"string"},
    completed = {"table"},
  },
  meta = {
    play_time = "number",
    version = "number",
    slot_description = {"string", optional = true},
  },
  save_version = "number",
  save_timestamp = "string",
})

-- ─── 3. Register migrations ───────────────────────────────
sm:add_migration(0, function(data)
  -- v0 -> v1: add default stats
  data.player = data.player or {}
  data.player.stats = data.player.stats or { str = 5, dex = 5, int = 5 }
  data.meta = data.meta or { play_time = 0, version = 1 }
  return data
end, "Add default stats and meta")

sm:add_migration(1, function(data)
  -- v1 -> v2: add quest system
  data.quests = data.quests or { active = {}, completed = {} }
  return data
end, "Add quest system")

-- ─── 4. Save ──────────────────────────────────────────────
local game_data = {
  player = {
    name = "Aria",
    level = 5,
    hp = 80,
    max_hp = 100,
    xp = 1250,
    inventory = { "sword", "shield", "potion", "key" },
    stats = { str = 10, dex = 8, int = 12 },
  },
  quests = {
    active = { "defend_village", "find_artifact" },
    completed = { { id = "tutorial", name = "Tutorial" } },
  },
  meta = {
    play_time = 3600,
    version = 2,
  },
}

local ok, err = sm:save("slot1", game_data, { description = "Aria's adventure" })
if ok then
  print("Saved successfully!")
else
  print("Save failed: " .. err)
  return
end

-- ─── 5. List slots ────────────────────────────────────────
print("\n" .. sm:summary())

-- ─── 6. Load ──────────────────────────────────────────────
local loaded, warn = sm:load("slot1")
if loaded then
  print("\nLoaded: " .. loaded.player.name .. " (level " .. loaded.player.level .. ")")
  print("  HP: " .. loaded.player.hp .. "/" .. loaded.player.max_hp)
  print("  Inventory: " .. table.concat(loaded.player.inventory, ", "))
  print("  Stats: STR=" .. loaded.player.stats.str .. " DEX=" .. loaded.player.stats.dex .. " INT=" .. loaded.player.stats.int)
  print("  Active quests: " .. #loaded.quests.active)
  print("  Play time: " .. loaded.meta.play_time .. "s")
  if warn then print("  (Warning: " .. warn .. ")") end
else
  print("Load failed: " .. tostring(warn))
end

-- ─── 7. Delete ────────────────────────────────────────────
-- sm:delete("slot1")

-- ─── 8. Get schema description (LLM-friendly) ─────────────
print("\nSchema description:")
print(sm:describe_schema())

-- ─── 9. List migrations ───────────────────────────────────
print("\nRegistered migrations:")
for _, m in ipairs(sm:list_migrations()) do
  print("  v" .. m.from .. " -> v" .. m.to .. ": " .. m.description)
end
