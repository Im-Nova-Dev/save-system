---
-- example.lua
-- Complete demo exercising every feature of the save system.
-- Logs all operations to save_demo/demo.log.
--
-- Run: lua example.lua (from save_system/ directory)
--

local script_dir = (arg and arg[0] and arg[0]:match("^(.*/)")) or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "lib/?.lua;" .. package.path

local SaveManager = require("save_manager")
local fs = require("fs_utils")
local serializer = require("serializer")

local DEMO_DIR = script_dir .. "save_demo/"
local LOG_FILE = DEMO_DIR .. "demo.log"

local log_lines = {}

local function log(fmt, ...)
  local msg = string.format(fmt, ...)
  table.insert(log_lines, ("[%s] %s"):format(os.date("!%Y-%m-%dT%H:%M:%SZ"), msg))
  print(msg)
end

local function flush_log()
  if not fs.exists(DEMO_DIR) then fs.create_dir(DEMO_DIR) end
  local f, err = io.open(LOG_FILE, "a")
  if f then
    for _, line in ipairs(log_lines) do
      f:write(line, "\n")
    end
    f:close()
  end
  log_lines = {}
end

local function cleanup()
  os.execute(("rm -rf '%s' 2>/dev/null"):format(DEMO_DIR:gsub("'", "'\\''")))
end

-- Start fresh each run
cleanup()

-- ════════════════════════════════════════════════════════════
-- 1. Basic save/load (unencrypted)
-- ════════════════════════════════════════════════════════════
log("═══ 1. Basic Save/Load ═══")
local sm = SaveManager:new({
  save_dir = DEMO_DIR .. "plain/",
  max_slots = 5,
})

local game_data = {
  player = {
    name = "Aria",
    level = 5,
    hp = 80, max_hp = 100, xp = 1250,
    inventory = { "sword", "shield", "potion", "key" },
    stats = { str = 10, dex = 8, int = 12 },
  },
  quests = {
    active = { "defend_village", "find_artifact" },
    completed = { { id = "tutorial", name = "Tutorial" } },
  },
  meta = { play_time = 3600, version = 2 },
}

local ok, err = sm:save("slot1", game_data, { description = "Aria's adventure" })
assert(ok, "Save failed: " .. tostring(err))
log("  save('slot1'): OK")

local loaded, warn = sm:load("slot1")
assert(loaded, "Load failed: " .. tostring(warn))
assert(loaded.player.name == "Aria")
log("  load('slot1'): name=%s, level=%d, warn=%s", loaded.player.name, loaded.player.level, warn or "nil")

-- ════════════════════════════════════════════════════════════
-- 2. Encrypted save/load
-- ════════════════════════════════════════════════════════════
log("═══ 2. Encrypted Save/Load ═══")
local sm_enc = SaveManager:new({
  save_dir = DEMO_DIR .. "encrypted/",
  encryption_key = "s3cr3t-k3y",
})

ok, err = sm_enc:save("secret", { message = "classified", level = 99 })
assert(ok, "Encrypted save: " .. tostring(err))

local secret_path = sm_enc:_slot_path("secret")
local raw_content = fs.read(secret_path)
assert(raw_content, "should read encrypted file")
assert(not raw_content:match("classified"), "plaintext should not appear in file")
log("  encrypted file does not contain plaintext: verified")

local loaded_enc, warn_enc = sm_enc:load("secret")
assert(loaded_enc, "Encrypted load: " .. tostring(warn_enc))
assert(loaded_enc.message == "classified")
log("  encrypted load('secret'): message=%s", loaded_enc.message)

-- ════════════════════════════════════════════════════════════
-- 3. Schema validation (success and rejection)
-- ════════════════════════════════════════════════════════════
log("═══ 3. Schema Validation ═══")
sm:set_schema({
  player = { name = "string", level = "number" },
  save_version = "number",
  save_timestamp = "string",
})

ok, err = sm:save("validated", { player = { name = "Bob", level = 10 } })
assert(ok, "Valid save rejected: " .. tostring(err))
log("  schema validation passes: OK")

local ok_bad, err_bad = sm:save("bad", { player = { name = 42 } })
assert(not ok_bad, "Invalid save should be rejected")
assert(err_bad:match("Schema validation"), "error should mention schema")
log("  schema validation rejects bad data: %s", err_bad)

-- ════════════════════════════════════════════════════════════
-- 4. Migrations
-- ════════════════════════════════════════════════════════════
log("═══ 4. Migrations ═══")
local sm_mig = SaveManager:new({ save_dir = DEMO_DIR .. "migrate/", auto_migrate = true })
sm_mig:add_migration(0, function(d)
  d.version = 1; d.player = d.player or {}; d.player.stats = { str = 5, dex = 5 }
  return d
end, "v0 -> v1: add stats")
sm_mig:add_migration(1, function(d)
  d.version = 2; d.quests = d.quests or {}
  return d
end, "v1 -> v2: add quests")

-- Write a v0 save manually (before migration was registered)
local bak = require("backup")
local ser = require("serializer")
local old_data = { name = "Legacy", save_version = 0 }
bak.save_with_backup(sm_mig:_slot_path("legacy"), ser.serialize(old_data))

local mig_loaded, mig_warn = sm_mig:load("legacy")
assert(mig_loaded, "Migrated load: " .. tostring(mig_warn))
assert(mig_loaded.version == 2, "should be at version 2")
assert(mig_loaded.player.stats.str == 5, "migration should have added stats")
log("  migration from v0 to v2: version=%d, stats.str=%d", mig_loaded.version, mig_loaded.player.stats.str)

-- Migration plan (dry-run)
local plan = sm_mig._migration:plan(0)
assert(#plan == 2, "plan should include 2 steps")
log("  migration dry-run plan: %d steps", #plan)
for _, p in ipairs(plan) do
  log("    v%d -> v%d: %s", p.from, p.to, p.description)
end

-- ════════════════════════════════════════════════════════════
-- 5. Slot management
-- ════════════════════════════════════════════════════════════
log("═══ 5. Slot Management ═══")
local sm_slots = SaveManager:new({ save_dir = DEMO_DIR .. "slots/", max_slots = 3 })
sm_slots:save("slot1", { name = "Hero" })
sm_slots:save("slot2", { name = "Save2" })

local info = sm_slots:slot_info("slot1")
assert(info.exists, "slot1 should exist")
assert(info.size > 0, "size should be positive")
log("  slot_info('slot1'): exists=%s, size=%d, version=%s", info.exists, info.size, tostring(info.save_version))

local exists = sm_slots:slot_exists("slot1")
assert(exists == true)
local exists_fake = sm_slots:slot_exists("nope")
assert(exists_fake == false)
log("  slot_exists('slot1')=%s, slot_exists('nope')=%s", exists, exists_fake)

local slots = sm_slots:list_slots()
assert(#slots == 3, "should list 3 slots")
local used = 0
for _, s in ipairs(slots) do used = s.exists and used + 1 or used end
assert(used == 2, "two slots should be used")
log("  list_slots(): %d slots, %d used", #slots, used)

-- Delete
ok, err = sm_slots:delete("slot2")
assert(ok, "Delete: " .. tostring(err))
assert(not sm_slots:slot_exists("slot2"))
log("  delete('slot2'): OK")

-- Delete nonexistent (should succeed)
ok, err = sm_slots:delete("nonexistent")
assert(ok, "delete nonexistent should succeed: " .. tostring(err))
log("  delete('nonexistent'): OK")

-- ════════════════════════════════════════════════════════════
-- 6. Corruption detection and backup fallback
-- ════════════════════════════════════════════════════════════
log("═══ 6. Corruption Detection ═══")
local sm_corrupt = SaveManager:new({ save_dir = DEMO_DIR .. "corrupt/" })
local demo_data = { value = 42 }
sm_corrupt:save("safe", demo_data)
-- Save again so a .backup exists (first save has no prior file to copy)
sm_corrupt:save("safe", demo_data)

-- Tamper with the file: corrupt inner data but keep stale checksum
local safe_path = sm_corrupt:_slot_path("safe")
local envelope = serializer.decode(fs.read(safe_path))
local corrupt_data = envelope.data:gsub('"value":42', '"value":99') -- still a string
local tampered = '{"__envelope":true,"checksum":"' .. envelope.checksum .. '","timestamp":"' .. (envelope.timestamp or "") .. '","data":' .. serializer.encode(corrupt_data) .. '}'
fs.write(safe_path, tampered)

local corrupted, c_warn = sm_corrupt:load("safe")
assert(corrupted, "should fall back to backup: " .. tostring(c_warn))
assert(c_warn:match("backup"), "warning should mention backup fallback")
log("  corruption fallback: loaded value=%d, warn=%s", corrupted.value, c_warn)

-- ════════════════════════════════════════════════════════════
-- 7. Load nonexistent slot
-- ════════════════════════════════════════════════════════════
log("═══ 7. Load Nonexistent Slot ═══")
local no_data, no_err = sm:load("does_not_exist")
assert(no_data == nil, "should return nil")
assert(no_err ~= nil, "should return error")
log("  load('does_not_exist'): %s", no_err)

-- ════════════════════════════════════════════════════════════
-- 8. LLM-friendly schema description
-- ════════════════════════════════════════════════════════════
log("═══ 8. Schema Description ═══")
local desc = sm:describe_schema()
assert(desc ~= nil and #desc > 0)
assert(desc:match("player"))
log("  describe_schema(): %d characters", #desc)

-- ════════════════════════════════════════════════════════════
-- 9. List migrations
-- ════════════════════════════════════════════════════════════
log("═══ 9. List Migrations ═══")
local mig_list = sm_mig:list_migrations()
assert(#mig_list == 2)
log("  list_migrations():")
for _, m in ipairs(mig_list) do
  log("    v%d -> v%d: %s", m.from, m.to, m.description)
end

-- ════════════════════════════════════════════════════════════
-- 10. Summary
-- ════════════════════════════════════════════════════════════
log("═══ 10. Summary ═══")
log(sm:summary())

-- ════════════════════════════════════════════════════════════
-- All done
-- ════════════════════════════════════════════════════════════
flush_log()
log("\nAll demo features verified successfully.")
flush_log()
cleanup()
