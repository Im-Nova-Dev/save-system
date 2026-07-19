---
-- save_manager.lua
-- The main Save System API. This is the only file games need to require().
--
-- Usage (LÖVE):
--   local SaveManager = require("save_manager")
--
--   local sm = SaveManager:new({
--     save_dir = "saves",
--     max_slots = 10,
--     encryption_key = "optional-key",
--   })
--
--   sm:set_schema({
--     player = { name = "string", level = "number" },
--   })
--
--   -- Save / Load
--   local ok, err = sm:save("slot1", game_data)
--   local data, err = sm:load("slot1")
--
--   -- List / Delete
--   local slots = sm:list_slots()
--   sm:delete("slot1")
--
-- All paths use love.filesystem when in LÖVE, or the physical filesystem
-- in standalone Lua. No external dependencies required.
--

local SaveManager = {}
SaveManager.__index = SaveManager

local serializer = require("serializer")
local backup = require("backup")
local validation = require("validation")
local migration = require("migration")
local fs = require("fs_utils")

-- ────────────────────────────────────────────
-- Constructor
-- ────────────────────────────────────────────

--- Create a new SaveManager instance.
-- @param config (table): Configuration:
--   - save_dir (string): Save directory (default: "saves"). Created automatically.
--   - max_slots (number): Maximum save slots (default: 20).
--   - encryption_key (string|nil): If set, encrypts all saves with this key.
--   - use_encryption (boolean|nil): Explicit toggle; auto-detected from encryption_key.
--   - max_backups (number): Max timestamped backups per slot (default: 5). 0 disables.
--   - fallback_to_backup (boolean): Auto-restore from .backup on corruption (default: true).
--   - auto_migrate (boolean): Auto-run migrations on load (default: true).
-- @return table: SaveManager instance.
function SaveManager:new(config)
  config = config or {}
  local save_dir = config.save_dir or "saves"
  if save_dir:sub(-1) ~= "/" then save_dir = save_dir .. "/" end

  local use_encryption = config.use_encryption
  if use_encryption == nil then
    use_encryption = config.encryption_key ~= nil and #config.encryption_key > 0
  end

  local mgr = {
    _save_dir = save_dir,
    _max_slots = config.max_slots or 20,
    _encryption_key = use_encryption and config.encryption_key or nil,
    _use_encryption = use_encryption,
    _max_backups = config.max_backups ~= nil and config.max_backups or 5,
    _fallback_to_backup = config.fallback_to_backup ~= false,
    _auto_migrate = config.auto_migrate ~= false,
    _schema = nil,
    _migration = migration.new(),
    _backup_dir = save_dir .. ".backups/",
  }

  local instance = setmetatable(mgr, SaveManager)
  instance:_ensure_dirs()
  return instance
end

--- Ensure save and backup directories exist.
function SaveManager:_ensure_dirs()
  if not fs.exists(self._save_dir) then
    fs.create_dir(self._save_dir)
  end
  if not fs.exists(self._backup_dir) then
    fs.create_dir(self._backup_dir)
  end
end

-- ────────────────────────────────────────────
-- Schema
-- ────────────────────────────────────────────

--- Define the expected shape of save data for validation.
-- @param schema (table): Schema definition (see validation.lua).
-- @return table: self (for chaining).
function SaveManager:set_schema(schema)
  self._schema = schema
  return self
end

-- ────────────────────────────────────────────
-- Migrations
-- ────────────────────────────────────────────

--- Register a migration step to transform save data between versions.
-- @param version (number): Source version number (migration runs when data version == this).
-- @param fn (function): Migration function: fn(data) -> data.
-- @param description (string|nil): Human-readable description.
-- @return table: self (for chaining).
function SaveManager:add_migration(version, fn, description)
  self._migration:add(version, fn, description)
  return self
end

--- Get the current target save version (latest migration + 1).
-- @return number|nil: Current version, or nil if no migrations registered.
function SaveManager:current_save_version()
  return self._migration:current_version()
end

--- List all registered migrations.
-- @return table: Array of { from, to, description }.
function SaveManager:list_migrations()
  return self._migration:list()
end

-- ────────────────────────────────────────────
-- File paths
-- ────────────────────────────────────────────

--- Get the file path for a slot.
-- @param slot_id (string|number): Slot identifier.
-- @return string.
function SaveManager:_slot_path(slot_id)
  return self._save_dir .. tostring(slot_id) .. ".save"
end

-- ────────────────────────────────────────────
-- Save / Load / Delete
-- ────────────────────────────────────────────

--- Save data to a slot.
-- @param slot_id (string|number): Slot identifier (e.g. "slot1", 1, "autosave").
-- @param data (table): The data to save. Must be a table.
-- @param options (table|nil): Per-save options:
--   - description (string|nil): Optional human-readable description for this slot.
-- @return boolean, string|nil: (true) or (false, error_message).
function SaveManager:save(slot_id, data, options)
  options = options or {}
  if type(data) ~= "table" then
    return false, "Save data must be a table"
  end
  if not slot_id then
    return false, "Slot ID is required"
  end

  local save_data = {}
  for k, v in pairs(data) do
    save_data[k] = v
  end
  save_data.save_version = self._migration:current_version() or 1
  save_data.save_timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
  save_data.slot_description = options.description or save_data.slot_description

  if self._schema then
    local valid, err = validation.validate(save_data, self._schema)
    if not valid then
      return false, "Schema validation failed: " .. err
    end
  end

  local serialized = serializer.serialize(save_data, {
    encryption_key = self._encryption_key,
  })

  local path = self:_slot_path(slot_id)
  local ok, err = backup.save_with_backup(path, serialized, {
    max_backups = self._max_backups,
    backup_dir = self._backup_dir,
  })
  if not ok then
    return false, err
  end

  return true, nil
end

--- Load data from a slot.
-- @param slot_id (string|number): Slot identifier.
-- @param options (table|nil):
--   - skip_migration (boolean): Skip migration even if versions differ.
--   - skip_validation (boolean): Skip schema validation.
-- @return table|nil, string|nil: (data, nil) or (nil, error_message).
--   The second return value may contain a warning string even on success
--   (e.g. "Loaded from backup").
function SaveManager:load(slot_id, options)
  options = options or {}
  if not slot_id then
    return nil, "Slot ID is required"
  end

  local path = self:_slot_path(tostring(slot_id))

  local raw_data, warn = backup.load_with_fallback(path, {
    fallback_to_backup = self._fallback_to_backup,
  })
  if not raw_data then
    return nil, warn
  end

  local ok, data = pcall(serializer.deserialize, raw_data, {
    encryption_key = self._encryption_key,
  })
  if not ok then
    return nil, "Failed to deserialize save data: " .. tostring(data)
  end
  if type(data) ~= "table" then
    return nil, "Deserialized data is not a table"
  end

  if self._auto_migrate and not options.skip_migration then
    local current_ver = self._migration:current_version()
    if current_ver then
      local from_ver = data.save_version or 0
      local mig_ok, mig_result = self._migration:run(data, from_ver)
      if mig_ok then
        data = mig_result
        local save_ok, save_err = self:save(slot_id, data, { description = data.slot_description })
        if not save_ok then
          warn = (warn and warn .. "; " or "") .. "Failed to save migrated data: " .. save_err
        end
      else
        return nil, "Migration failed: " .. tostring(mig_result)
      end
    end
  end

  if self._schema and not options.skip_validation then
    local valid, err = validation.validate(data, self._schema)
    if not valid then
      return nil, "Schema validation failed: " .. err
    end
  end

  return data, warn
end

--- Delete a save slot and its associated backup files.
-- @param slot_id (string|number): Slot identifier.
-- @return boolean, string|nil: (true) or (false, error_message).
function SaveManager:delete(slot_id)
  if not slot_id then
    return false, "Slot ID is required"
  end
  local path = self:_slot_path(tostring(slot_id))
  local ok, err = fs.remove(path)
  if not ok then
    if not fs.exists(path) then
      return true, nil
    end
    return false, "Failed to delete save file: " .. (err or "unknown error")
  end
  fs.remove(path .. ".backup")
  return true, nil
end

-- ────────────────────────────────────────────
-- Slot management
-- ────────────────────────────────────────────

--- List all save slots with metadata.
-- @return table: Array of slot info tables { id, path, exists, size, description, save_version }.
function SaveManager:list_slots()
  local slots = {}
  for i = 1, self._max_slots do
    local slot_id = "slot" .. i
    table.insert(slots, self:slot_info(slot_id))
  end
  return slots
end

--- Get detailed info about a specific slot.
-- @param slot_id (string|number): Slot identifier.
-- @return table: { id, path, exists, size, description, save_version }.
function SaveManager:slot_info(slot_id)
  local path = self:_slot_path(tostring(slot_id))
  local info = {
    id = tostring(slot_id),
    path = path,
    exists = false,
    size = 0,
    description = nil,
    save_version = nil,
  }

  if not fs.exists(path) then
    return info
  end

  local content, err = fs.read(path)
  if not content then return info end

  info.exists = true
  info.size = #content

  local raw_data, extract_err = backup.verify_and_extract(content)
  if raw_data then
    local ok_partial, partial = pcall(serializer.deserialize, raw_data, {
      encryption_key = self._encryption_key,
    })
    if ok_partial and type(partial) == "table" then
      info.save_version = partial.save_version
      info.description = partial.slot_description
    end
  end

  return info
end

--- Check if a slot exists.
-- @param slot_id (string|number): Slot identifier.
-- @return boolean.
function SaveManager:slot_exists(slot_id)
  local info = self:slot_info(slot_id)
  return info.exists
end

-- ────────────────────────────────────────────
-- Utility
-- ────────────────────────────────────────────

--- Get a human-readable description of the expected schema.
-- @return string|nil.
function SaveManager:describe_schema()
  if not self._schema then return nil end
  return validation.describe(self._schema)
end

--- Get a formatted summary of all slots.
-- @return string.
function SaveManager:summary()
  local slots = self:list_slots()
  local lines = { "=== Save Slots ===" }
  for _, slot in ipairs(slots) do
    local status = slot.exists and ("used, v%d, %d bytes"):format(slot.save_version or 0, slot.size) or "empty"
    lines[#lines + 1] = ("  %s: %s"):format(slot.id, status)
  end
  return table.concat(lines, "\n")
end

return SaveManager
