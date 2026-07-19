-- LÖVE entry point for the save system example.
-- Build with: ./scripts/build_love.sh
-- Run: love save_system/love_example/

local SaveManager = require("save_manager")

-- ─── 1. Create a manager ──────────────────────────────────
local sm = SaveManager:new({
  save_dir = "saves",
  max_slots = 5,
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
  },
  save_version = "number",
  save_timestamp = "string",
})

-- ─── 3. Register migrations ───────────────────────────────
sm:add_migration(0, function(data)
  data.player = data.player or {}
  data.player.stats = data.player.stats or { str = 5, dex = 5, int = 5 }
  data.meta = data.meta or { play_time = 0, version = 1 }
  return data
end, "Add default stats and meta")

sm:add_migration(1, function(data)
  data.quests = data.quests or { active = {}, completed = {} }
  return data
end, "Add quest system")

-- ─── 4. Game data ─────────────────────────────────────────
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

local output_lines = {}

function love.load()
  local ok, err = sm:save("slot1", game_data, { description = "Aria's adventure" })
  table.insert(output_lines, ok and "Saved successfully!" or "Save failed: " .. err)

  table.insert(output_lines, "")
  table.insert(output_lines, sm:summary())

  local loaded, warn = sm:load("slot1")
  if loaded then
    local line = ("\nLoaded: %s (level %d)"):format(loaded.player.name, loaded.player.level)
    table.insert(output_lines, line)
    table.insert(output_lines, ("  HP: %d/%d"):format(loaded.player.hp, loaded.player.max_hp))
    table.insert(output_lines, "  Inventory: " .. table.concat(loaded.player.inventory, ", "))
    table.insert(output_lines, ("  Stats: STR=%d DEX=%d INT=%d"):format(
      loaded.player.stats.str, loaded.player.stats.dex, loaded.player.stats.int))
    table.insert(output_lines, ("  Active quests: %d"):format(#loaded.quests.active))
    table.insert(output_lines, ("  Play time: %ds"):format(loaded.meta.play_time))
    if warn then table.insert(output_lines, "  (Warning: " .. warn .. ")") end
  else
    table.insert(output_lines, "Load failed: " .. tostring(warn))
  end

  table.insert(output_lines, "\nSchema description:")
  table.insert(output_lines, sm:describe_schema())

  table.insert(output_lines, "\nRegistered migrations:")
  for _, m in ipairs(sm:list_migrations()) do
    table.insert(output_lines, ("  v%d -> v%d: %s"):format(m.from, m.to, m.description))
  end
end

function love.draw()
  local y = 20
  for _, line in ipairs(output_lines) do
    love.graphics.print(line, 20, y)
    y = y + 16
  end
end
