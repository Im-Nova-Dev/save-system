---
-- test_migration.lua
-- Tests for migration.lua: versioned migrations, planning, error handling.
--

local T = require("tests.test_helpers")
local migration = require("migration")

T.describe("Migration manager", function()

  T.it("starts with no current version when empty", function()
    local m = migration.new()
    T.assert_eq(m:current_version(), nil)
  end)

  T.it("current_version tracks max registered migrations", function()
    local m = migration.new()
    m:add(1, function(d) return d end)
    T.assert_eq(m:current_version(), 2)
    m:add(2, function(d) return d end)
    T.assert_eq(m:current_version(), 3)
  end)

end)

T.describe("Running migrations", function()

  T.it("runs single migration", function()
    local m = migration.new()
    m:add(1, function(data)
      data.migrated = true
      return data
    end)
    local ok, result = m:run({ save_version = 1 }, 1)
    T.assert(ok, "migration should succeed")
    T.assert(result.migrated == true)
    T.assert_eq(result.save_version, 2)
  end)

  T.it("runs chain of migrations", function()
    local m = migration.new()
    m:add(1, function(d) d.step = 1; return d end)
    m:add(2, function(d) d.step = 2; return d end)
    m:add(3, function(d) d.step = 3; return d end)
    local ok, result = m:run({ save_version = 1 }, 1)
    T.assert(ok)
    T.assert_eq(result.step, 3)
    T.assert_eq(result.save_version, 4)
  end)

  T.it("skips migrations when already up-to-date", function()
    local m = migration.new()
    m:add(1, function(d) d.migrated = true; return d end)
    local ok, result = m:run({ save_version = 2, migrated = false }, 2)
    T.assert(ok)
    T.assert_eq(result.migrated, false, "should not run migration")
  end)

  T.it("handles migration from version 0 with explicit v0 migration", function()
    local m = migration.new()
    m:add(0, function(d) d.initialized = true; return d end)
    local ok, result = m:run({}, 0)
    T.assert(ok)
    T.assert(result.initialized == true)
  end)

end)

T.describe("Migration errors", function()

  T.it("rejects future versions", function()
    local m = migration.new()
    m:add(1, function(d) return d end)
    local ok, err = m:run({ save_version = 99 }, 99)
    T.assert(not ok)
    T.assert(err:match("newer"), "should mention newer version")
  end)

  T.it("reports missing migration steps", function()
    local m = migration.new()
    m:add(1, function(d) return d end)
    m:add(3, function(d) return d end) -- missing v2
    local ok, err = m:run({ save_version = 1 }, 1)
    T.assert(not ok)
    T.assert(err:match("Missing migration"), "should report missing step")
  end)

  T.it("catches errors in migration functions", function()
    local m = migration.new()
    m:add(1, function(d)
      error("Something went wrong")
    end)
    local ok, err = m:run({ save_version = 1 }, 1)
    T.assert(not ok)
    T.assert(err:match("failed"), "should report failure")
  end)

  T.it("rejects nil return from migration", function()
    local m = migration.new()
    m:add(1, function(d) return nil end)
    local ok, err = m:run({ save_version = 1 }, 1)
    T.assert(not ok)
    T.assert(err:match("returned nil"), "should mention nil return")
  end)

  T.it("captures error string as second return from migration", function()
    local m = migration.new()
    m:add(1, function(d)
      return d, "Custom error from migration"
    end)
    local ok, err = m:run({ save_version = 1 }, 1)
    T.assert(not ok, "should reject error return")
    T.assert(err:match("Custom error"), "should include custom error: " .. tostring(err))
  end)

end)

T.describe("Migration planning and listing", function()

  T.it("lists registered migrations", function()
    local m = migration.new()
    m:add(1, function(d) d.a = 1; return d end, "Add field A")
    m:add(2, function(d) d.b = 2; return d end, "Add field B")
    local list = m:list()
    T.assert_eq(#list, 2)
    T.assert_eq(list[1].from, 1)
    T.assert_eq(list[1].to, 2)
    T.assert_eq(list[1].description, "Add field A")
    T.assert_eq(list[2].from, 2)
    T.assert_eq(list[2].description, "Add field B")
  end)

  T.it("creates dry-run plans", function()
    local m = migration.new()
    m:add(1, function(d) return d end)
    m:add(2, function(d) return d end)
    m:add(3, function(d) return d end)
    local plan = m:plan(1)
    T.assert_eq(#plan, 3)
    T.assert_eq(plan[1].from, 1)
    T.assert_eq(plan[3].from, 3)
  end)

  T.it("plan only includes needed steps", function()
    local m = migration.new()
    m:add(1, function(d) return d end)
    m:add(2, function(d) return d end)
    m:add(3, function(d) return d end)
    local plan = m:plan(2)
    T.assert_eq(#plan, 2)
    T.assert_eq(plan[1].from, 2)
    T.assert_eq(plan[2].from, 3)
  end)

end)

T.finish()
