---
-- migration.lua
-- Versioned migration system for evolving save formats.
--
-- Usage:
--   local mig = require("migration")
--   local m = mig.new()
--
--   -- Register migrations (version -> version+1)
--   m:add(1, function(data)
--     data.player.level = data.player.level or 1
--     return data
--   end)
--   m:add(2, function(data)
--     data.player.inventory = data.player.inventory or {}
--     return data
--   end)
--
--   -- Run migrations on loaded data
--   local from = data.save_version or 0
--   local ok, migrated = m:run(data, from)
--
-- Migration functions receive the raw data table and should return the
-- mutated data table. They can also return an error as a second value.
--

local migration = {}

local migration_mt = {
  __index = migration,
}

--- Create a new migration manager.
-- @param current_version (number|nil): The current save version (default: latest registered).
-- @return table: Migration manager instance.
function migration.new(current_version)
  return setmetatable({
    _migrations = {},    -- indexed by version number
    _current_version = current_version or nil, -- set later by latest
  }, migration_mt)
end

--- Register a migration from `version` to `version + 1`.
-- @param version (number): The source version (migration runs when data version == this).
-- @param fn (function): Migration function: fn(data) -> data or data, error_string.
-- @param description (string|nil): Human-readable description of what this migration does.
-- @return table: self (for chaining).
function migration:add(version, fn, description)
  if type(version) ~= "number" then
    error("Migration version must be a number", 2)
  end
  if self._migrations[version] then
    error(("Migration for version %d already registered"):format(version), 2)
  end
  self._migrations[version] = {
    fn = fn,
    description = description or ("Migration v%d -> v%d"):format(version, version + 1),
  }
  -- Update current version to latest registered + 1
  local max_ver = 0
  for v in pairs(self._migrations) do
    if v > max_ver then max_ver = v end
  end
  self._current_version = max_ver + 1
  return self
end

--- Run all required migrations to bring data up to the current version.
-- @param data (table): The save data to migrate.
-- @param from_version (number): The version of the loaded data (default: 0).
-- @return boolean, table|string: (true, migrated_data) or (false, error_message).
function migration:run(data, from_version)
  from_version = from_version or (data and data.save_version) or 0
  if type(from_version) ~= "number" then
    return false, "Invalid version number"
  end

  local current = self._current_version
  if not current then
    return false, "No migrations registered"
  end

  if from_version == current then
    -- Already up-to-date
    data.save_version = current
    return true, data
  end

  if from_version > current then
    return false, string.format(
      "Save version (%d) is newer than the current version (%d). " ..
      "This save may have been created by a newer version of the game.",
      from_version, current
    )
  end

  -- Run migrations sequentially
  for v = from_version, current - 1 do
    local migration_info = self._migrations[v]
    if not migration_info then
      return false, string.format(
        "Missing migration from version %d to %d. Cannot upgrade save.",
        v, v + 1
      )
    end
    local results = { pcall(migration_info.fn, data) }
    local ok = results[1]
    if not ok then
      return false, string.format(
        "Migration v%d -> v%d failed: %s",
        v, v + 1, tostring(results[2])
      )
    end
    local result = results[2]
    local err_str = results[3]
    if err_str then
      return false, string.format(
        "Migration v%d -> v%d error: %s",
        v, v + 1, tostring(err_str)
      )
    end
    if result == nil then
      return false, string.format(
        "Migration v%d -> v%d returned nil. Migration function must return the data table.",
        v, v + 1
      )
    end
    data = result
    data.save_version = v + 1
  end

  return true, data
end

--- Get the current target version.
-- @return number|nil: The current version.
function migration:current_version()
  return self._current_version
end

--- Get a list of all registered migrations with descriptions.
-- @return table: Array of { from = number, to = number, description = string }.
function migration:list()
  local list = {}
  for v, info in pairs(self._migrations) do
    table.insert(list, {
      from = v,
      to = v + 1,
      description = info.description,
    })
  end
  table.sort(list, function(a, b) return a.from < b.from end)
  return list
end

--- Create a migration plan (dry run) without executing anything.
-- Useful for displaying to the user or logging.
-- @param from_version (number): The version to start from.
-- @return table: Array of { from, to, description } that would be executed.
function migration:plan(from_version)
  local plan = {}
  for v, info in pairs(self._migrations) do
    if v >= from_version and v < self._current_version then
      table.insert(plan, {
        from = v,
        to = v + 1,
        description = info.description,
      })
    end
  end
  table.sort(plan, function(a, b) return a.from < b.from end)
  return plan
end

return migration
