---
-- backup.lua
-- Automatic backup system with corruption detection.
-- Before writing a new save, the existing file is copied to a timestamped
-- backup. On load failure, corruption is detected and backup restoration
-- is attempted automatically.
--
-- File naming:
--   save_file.ext          -> the active save
--   save_file.ext.backup   -> the most recent backup (overwritten each save)
--   save_file.ext.bak.YYYYMMDD_HHMMSS  -> timestamped backups (configurable count)
--
-- Corruption detection: checksum (fast non-cryptographic hash) stored
-- alongside the data and verified on load.
--

local backup = {}

local serializer = require("serializer")
local fs = require("fs_utils")

--- Compute a simple hash for a string.
-- Fast, deterministic, good enough for corruption detection. Not cryptographic.
-- @param str (string): Input string.
-- @return string: Hex-encoded 64-bit hash.
function backup._hash(str)
  local h1, h2 = 0xdeadbeef, 0xcafebabe
  for i = 1, #str do
    local b = string.byte(str, i)
    h1 = ((h1 << 5) - h1 + b) & 0xFFFFFFFF
    h2 = ((h2 << 5) + h2 + b) & 0xFFFFFFFF
    h1 = h1 ~ (h2 >> 16)
    h2 = h2 ~ (h1 >> 8)
  end
  return string.format("%08x%08x", h1, h2)
end

--- Create a backup of an existing file.
-- @param path (string): Path to the file to back up.
-- @param options (table|nil):
--   - max_backups (number): Max timestamped backups to keep (default 5). 0 disables timestamped backups.
--   - backup_dir (string|nil): Directory for timestamped backups. Default: parent of path.
-- @return string|nil: Backup file path, or nil if no file existed.
function backup.create(path, options)
  options = options or {}
  local max_backups = options.max_backups ~= nil and options.max_backups or 5
  local backup_dir = options.backup_dir or path:match("^(.*/)") or "."

  local content, err = fs.read(path)
  if not content then
    return nil
  end

  -- Always create a .backup copy (overwritten each time)
  local simple_backup = path .. ".backup"
  fs.write(simple_backup, content)

  -- Create timestamped backup (rotating)
  if max_backups > 0 then
    local ts = os.date("%Y%m%d_%H%M%S")
    local filename = path:match("([^/]+)$")
    local bak_path = backup_dir .. "/" .. filename .. ".bak." .. ts
    if fs.write(bak_path, content) then
      backup._prune(filename, max_backups, backup_dir)
    end
  end

  return simple_backup
end

--- Prune old timestamped backups, keeping only the most recent N.
-- @param filename (string): Base filename to match.
-- @param keep (number): Number of backups to keep.
-- @param backup_dir (string): Directory containing backups.
function backup._prune(filename, keep, backup_dir)
  local pattern = filename .. "%.bak%."
  local all_files, err = fs.list_dir(backup_dir, pattern)
  if not all_files then return end

  -- Sort descending by name (timestamp in name makes this chronological)
  table.sort(all_files, function(a, b) return a > b end)

  for i = keep + 1, #all_files do
    fs.remove(backup_dir .. "/" .. all_files[i])
  end
end

--- Wrap raw data with metadata envelope including checksum.
-- @param raw_data (string): The raw serialized data (e.g. JSON string).
-- @return string: The enveloped data as a JSON string.
function backup.envelope(raw_data)
  local checksum = backup._hash(raw_data)
  local envelope = serializer.encode({
    __envelope = true,
    checksum = checksum,
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    data = raw_data,
  })
  return envelope
end

--- Unwrap envelope and verify checksum.
-- @param enveloped (string): The enveloped JSON string.
-- @return string|nil, string|nil: (raw_data, nil) on success, or (nil, error_message).
function backup.verify_and_extract(enveloped)
  local ok, parsed = pcall(serializer.decode, enveloped)
  if not ok then
    return nil, "Failed to parse envelope: " .. tostring(parsed)
  end
  if type(parsed) ~= "table" or not parsed.__envelope then
    -- Not an enveloped save. Return as-is for backward compatibility.
    return enveloped, nil
  end
  if not parsed.checksum or not parsed.data then
    return nil, "Envelope missing checksum or data field"
  end
  local expected = parsed.checksum
  local actual = backup._hash(parsed.data)
  if expected ~= actual then
    return nil, ("Checksum mismatch: expected %s, got %s. Data may be corrupted."):format(expected, actual)
  end
  return parsed.data, nil
end

--- Save data with envelope and automatic backup.
-- @param path (string): File path to save to.
-- @param raw_data (string): The raw serialized data.
-- @param options (table|nil): Options passed to backup.create.
-- @return boolean, string|nil: (true) or (false, error_message).
function backup.save_with_backup(path, raw_data, options)
  options = options or {}
  backup.create(path, options)

  local enveloped = backup.envelope(raw_data)
  local ok, err = fs.write(path, enveloped)
  if not ok then
    return false, "Failed to write save file: " .. (err or "unknown error")
  end
  return true, nil
end

--- Load data with automatic corruption detection and backup fallback.
-- @param path (string): File path to load from.
-- @param options (table|nil):
--   - fallback_to_backup (boolean): If true, try .backup on corruption (default true).
-- @return string|nil, string|nil: (raw_data, nil) or (nil, error_message).
function backup.load_with_fallback(path, options)
  options = options or {}
  local fallback = options.fallback_to_backup ~= false

  local content, err = fs.read(path)
  if not content then
    return nil, "Failed to open file: " .. (err or "unknown error")
  end

  if #content == 0 then
    return nil, "Empty save file"
  end

  local raw_data, err_msg = backup.verify_and_extract(content)
  if raw_data then
    return raw_data, nil
  end

  if fallback then
    local backup_path = path .. ".backup"
    local bak_content, bak_err
    if fs.exists(backup_path) then
      bak_content, bak_err = fs.read(backup_path)
      if bak_content then
        local bak_raw, bak_verify_err = backup.verify_and_extract(bak_content)
        if bak_raw then
          fs.write(path, bak_content)
          return bak_raw, "Loaded from backup (primary file was corrupted)"
        end
        bak_err = bak_verify_err
      end
    end
    return nil, err_msg .. (bak_err and ("; backup also corrupt: " .. bak_err) or "")
  end

  return nil, err_msg
end

return backup
