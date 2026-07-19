---
-- run.lua
-- Test runner entry point. Run with: lua save_system/tests/run.lua
-- Runs ALL test files found in save_system/tests/test_*.lua
--
-- This script sets up the Lua package path so tests can require() the
-- save_system modules without needing LÖVE or luarocks.
--
-- Usage:
--   lua save_system/tests/run.lua                        # run all tests
--   lua save_system/tests/run.lua serializer              # run only serializer tests
--   lua save_system/tests/run.lua serializer backup       # run specific test files
--

-- Set up package path to find the save_system modules
local save_path = "/home/sleep/save_system"
package.path = save_path .. "/?.lua;" .. save_path .. "/lib/?.lua;" .. package.path

local filter = { ... }
local function matches_filter(filename)
  if #filter == 0 then return true end
  local name = filename:match("test_(.+)%.lua$") or filename
  for _, f in ipairs(filter) do
    if name:find(f, 1, true) then return true end
  end
  return false
end

-- Find and run test files
local i = 1
local function scandir(dir)
  local handle = io.popen("find " .. dir .. " -name 'test_*.lua' 2>/dev/null")
  if not handle then return {} end
  local files = {}
  for file in handle:lines() do
    files[#files + 1] = file
  end
  handle:close()
  table.sort(files)
  return files
end

local test_files = scandir(save_path .. "/tests")
if #test_files == 0 then
  print("No test files found in " .. save_path .. "/tests/")
  os.exit(0)
end

print(("=== Save System Test Runner ===\nFound %d test file(s)\n"):format(#test_files))

for _, filepath in ipairs(test_files) do
  local filename = filepath:match("([^/]+)$")
  if matches_filter(filename) then
    print(("Running: %s"):format(filename))
    local ok, err = pcall(dofile, filepath)
    if not ok then
      print(("  ERROR loading %s: %s\n"):format(filename, err))
    end
    print("")
  end
end

-- Always exit cleanly in runner; individual tests call os.exit on failure.
print("=== All test files processed ===")
