---
-- test_save_manager.lua
-- Integration tests for save_manager.lua (the main API).
--

local T = require("tests.test_helpers")
local SaveManager = require("save_manager")
local fs = require("fs_utils")

local TEST_DIR = "/tmp/save_system_test_mgr/"

local function setup()
  os.execute(("rm -rf %s 2>/dev/null"):format(TEST_DIR))
end

T.describe("SaveManager constructor", function()

  T.it("creates instance with default config", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    T.assert(sm ~= nil)
    T.assert_eq(sm._max_slots, 20)
    T.assert_eq(sm._use_encryption, false)
  end)

  T.it("creates instance with encryption", function()
    setup()
    local sm = SaveManager:new({
      save_dir = TEST_DIR .. "saves/",
      encryption_key = "test-key-123",
    })
    T.assert(sm._use_encryption == true)
    T.assert(sm._encryption_key == "test-key-123")
  end)

  T.it("creates directories", function()
    setup()
    local dir = TEST_DIR .. "newdir/"
    local sm = SaveManager:new({ save_dir = dir })
    T.assert(fs.exists(dir), "save directory should exist")
  end)

end)

T.describe("Save and Load", function()

  T.it("saves and loads data", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    local data = { player = { name = "Alice", hp = 100 }, items = { "sword" } }
    local ok, err = sm:save("test1", data)
    T.assert(ok, "save should succeed: " .. tostring(err))

    local loaded, warn = sm:load("test1")
    T.assert(loaded ~= nil, "load should succeed: " .. tostring(warn))
    T.assert_eq(loaded.player.name, "Alice")
    T.assert_eq(loaded.player.hp, 100)
    T.assert_eq(loaded.items[1], "sword")
  end)

  T.it("saves and loads with encryption", function()
    setup()
    local sm = SaveManager:new({
      save_dir = TEST_DIR .. "saves/",
      encryption_key = "mykey",
    })
    local data = { secret = "top level", stats = { x = 42 } }
    local ok, err = sm:save("secret_slot", data)
    T.assert(ok, "encrypted save: " .. tostring(err))

    local path = sm:_slot_path("secret_slot")
    local content = fs.read(path)
    T.assert(content ~= nil, "should read encrypted file")
    T.assert(not content:match("secret"), "encrypted file should not contain plaintext")

    local loaded, warn = sm:load("secret_slot")
    T.assert(loaded ~= nil, "encrypted load: " .. tostring(warn))
    T.assert_eq(loaded.secret, "top level")
    T.assert_eq(loaded.stats.x, 42)
  end)

  T.it("load returns nil with error for missing slot", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    local data, err = sm:load("nonexistent")
    T.assert_eq(data, nil)
    T.assert(err ~= nil)
  end)

end)

T.describe("Schema validation", function()

  T.it("validates saves against schema", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    sm:set_schema({
      player = { name = "string", hp = "number" },
      save_version = "number",
      save_timestamp = "string",
    })
    -- Valid save
    local ok, err = sm:save("valid", { player = { name = "Bob", hp = 100 } })
    T.assert(ok, "valid save: " .. tostring(err))
    -- Invalid save (wrong type)
    local ok2, err2 = sm:save("invalid", { player = { name = 42 } })
    T.assert(not ok2, "should reject invalid save")
    T.assert(err2:match("Schema validation"), "error should mention schema")
  end)

  T.it("rejects load when schema validation fails", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    local data = { player = { name = "Bob", hp = 100 } }
    sm:save("test", data)
    -- Now set a stricter schema that the loaded data won't satisfy
    sm:set_schema({
      player = { name = "string", hp = "number", xp = "number" },
      save_version = "number",
      save_timestamp = "string",
    })
    local loaded, err = sm:load("test")
    T.assert(not loaded, "load should fail on schema mismatch")
    T.assert(err:match("Schema validation"), "error should mention schema validation")
  end)

end)

T.describe("Migrations", function()

  T.it("runs migrations on load", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    sm:add_migration(0, function(data)
      data.migrated = true
      return data
    end, "Add migrated flag")

    -- Manually write a save with version 0 (simulating an old save)
    local old_data = { player = { name = "Alice" }, save_version = 0 }
    local ser = require("serializer")
    local raw = ser.serialize(old_data)
    local path = sm:_slot_path("mig_test")
    local backup = require("backup")
    backup.save_with_backup(path, raw)

    -- Load with the migration registered
    local loaded, warn = sm:load("mig_test")
    T.assert(loaded ~= nil, "load after migration: " .. tostring(warn))
    T.assert(loaded.migrated == true, "migration should have run")
    T.assert_eq(loaded.save_version, 1, "version should be updated")
  end)

end)

T.describe("Slot management", function()

  T.it("lists slots with correct status", function()
    setup()
    local sm = SaveManager:new({
      save_dir = TEST_DIR .. "saves/",
      max_slots = 3,
    })
    sm:save("slot1", { test = 1 })

    local info = sm:slot_info("slot1")
    T.assert(info.exists == true)
    T.assert(info.size > 0)
    T.assert(info.save_version ~= nil)

    local info2 = sm:slot_info("slot2")
    T.assert(info2.exists == false)
  end)

  T.it("checks slot existence", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    T.assert(not sm:slot_exists("foo"))
    sm:save("foo", { data = 1 })
    T.assert(sm:slot_exists("foo"))
  end)

  T.it("deletes slots", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    sm:save("delete_me", { data = 1 })
    T.assert(sm:slot_exists("delete_me"))
    local ok, err = sm:delete("delete_me")
    T.assert(ok, "delete: " .. tostring(err))
    T.assert(not sm:slot_exists("delete_me"))
  end)

end)

T.describe("Data integrity", function()

  T.it("persists user data across save/load", function()
    setup()
    local sm = SaveManager:new({ save_dir = TEST_DIR .. "saves/" })
    local original = {
      player = { name = "Cirilla", level = 10, hp = 85 },
      inventory = { "sword", "shield", "potion" },
      quests = { active = { "q1" }, completed = {} },
      stats = { games_played = 42, high_score = 9999 },
    }
    sm:save("persist_test", original)
    local loaded, warn = sm:load("persist_test")
    T.assert(loaded ~= nil, "load should succeed: " .. tostring(warn))
    -- The save manager adds metadata fields; compare only the user fields
    T.assert_eq(loaded.player, original.player)
    T.assert_eq(loaded.inventory, original.inventory)
    T.assert_eq(loaded.quests, original.quests)
    T.assert_eq(loaded.stats, original.stats)
    -- Verify metadata was added
    T.assert(loaded.save_version ~= nil, "save_version should be set")
    T.assert(loaded.save_timestamp ~= nil, "save_timestamp should be set")
  end)

end)

T.finish()
