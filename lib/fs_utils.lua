---
-- fs_utils.lua
-- Cross-platform filesystem abstraction.
-- Automatically detects LÖVE (love.filesystem) and falls back to standard Lua file I/O.
-- This allows the save system to work identically in LÖVE games and plain Lua scripts.
--
-- In LÖVE, all paths are relative to the save directory (love.filesystem.getSaveDirectory()).
-- In plain Lua, paths are relative to the current working directory.
--
-- API:
--   fs.read(path)       -> string|nil, err
--   fs.write(path, str) -> boolean, err
--   fs.remove(path)     -> boolean, err
--   fs.exists(path)     -> boolean
--   fs.create_dir(dir)  -> boolean, err
--   fs.list_dir(dir)    -> table|nil, err   (filenames matching a pattern)
--   fs.size(path)       -> number|nil, err
--
-- When in LÖVE, the `love_relative` flag controls whether paths are relative
-- to the LÖVE save directory (default: true) or absolute/physical paths.
--

local fs = {}

-- Detect LÖVE environment
local love_fs = nil
if pcall(function() return love.filesystem end) then
  love_fs = love.filesystem
end

-- ────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────

--- Read a file's contents.
-- @param path (string): Path to the file.
-- @return string|nil, string|nil: (contents, nil) or (nil, error_message).
function fs.read(path)
  if love_fs then
    local ok, data = pcall(love_fs.read, love_fs, path)
    if ok then return data, nil end
    return nil, data
  end
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return content, nil
end

--- Write a string to a file.
-- @param path (string): Path to the file.
-- @param data (string): The data to write.
-- @return boolean, string|nil: (true) or (false, error_message).
function fs.write(path, data)
  if love_fs then
    local ok, err = pcall(love_fs.write, love_fs, path, data)
    if ok then return true, nil end
    return false, tostring(err)
  end
  local f, err = io.open(path, "wb")
  if not f then return false, err end
  f:write(data)
  f:close()
  return true, nil
end

--- Delete a file.
-- @param path (string): Path to the file.
-- @return boolean, string|nil: (true) or (false, error_message).
function fs.remove(path)
  if love_fs then
    local ok, err = pcall(love_fs.remove, love_fs, path)
    if ok then return true, nil end
    return false, tostring(err)
  end
  local ok, err = os.remove(path)
  if ok then return true, nil end
  return false, tostring(err)
end

--- Check if a file exists.
-- @param path (string): Path to the file.
-- @return boolean.
function fs.exists(path)
  if love_fs then
    return love_fs.getInfo(path) ~= nil
  end
  local f, err = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

--- Create a directory (and any parent directories).
-- @param dir (string): Path to the directory.
-- @return boolean, string|nil: (true) or (false, error_message).
function fs.create_dir(dir)
  if love_fs then
    local ok, err = pcall(love_fs.createDirectory, love_fs, dir)
    if ok then return true, nil end
    return false, tostring(err)
  end
  -- Plain Lua: shell-quote the path and use mkdir -p
  local quoted = dir:gsub("'", "'\\''")
  local r1 = os.execute(("mkdir -p '%s' 2>/dev/null"):format(quoted))
  if r1 == 0 or r1 == true then return true, nil end
  -- Fallback: try just mkdir
  local r2 = os.execute(("mkdir '%s' 2>/dev/null"):format(quoted))
  if r2 == 0 or r2 == true then return true, nil end
  return false, "Failed to create directory: " .. dir
end

--- Get the size of a file.
-- @param path (string): Path to the file.
-- @return number|nil, string|nil: (size) or (nil, error_message).
function fs.size(path)
  if love_fs then
    local info = love_fs.getInfo(path)
    if info then return info.size, nil end
    return nil, "File not found"
  end
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return #content, nil
end

--- List files in a directory, optionally filtering by Lua pattern.
-- NOTE: In LÖVE, uses love.filesystem.getDirectoryItems.
-- In plain Lua, uses `ls` via popen.
-- @param dir (string): Directory path.
-- @param pattern (string|nil): Optional Lua pattern to filter filenames.
-- @return table|nil, string|nil: (array of filenames) or (nil, error_message).
function fs.list_dir(dir, pattern)
  if love_fs then
    local ok, items = pcall(love_fs.getDirectoryItems, love_fs, dir)
    if not ok then return nil, tostring(items) end
    if pattern then
      local filtered = {}
      for _, name in ipairs(items) do
        if name:match(pattern) then
          table.insert(filtered, name)
        end
      end
      return filtered, nil
    end
    return items, nil
  end
  -- Plain Lua: use ls via popen (POSIX)
  local quoted = dir:gsub("'", "'\\''")
  local cmd = ("ls -1 '%s' 2>/dev/null"):format(quoted)
  local handle, err = io.popen(cmd)
  if not handle then return nil, tostring(err) end
  local items = {}
  for line in handle:lines() do
    if not pattern or line:match(pattern) then
      table.insert(items, line)
    end
  end
  handle:close()
  return items, nil
end

return fs
