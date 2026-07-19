---
-- test_backup.lua
-- Tests for backup.lua: envelope, checksum, corruption detection, fallback.
--

local T = require("tests.test_helpers")
local backup = require("backup")
local serializer = require("serializer")
local fs = require("fs_utils")

local TEST_DIR = "/tmp/save_system_test_backup/"

local function setup()
  os.execute(("rm -rf %s 2>/dev/null"):format(TEST_DIR))
  os.execute(("mkdir -p %s 2>/dev/null"):format(TEST_DIR))
end

local function teardown()
  os.execute(("rm -rf %s 2>/dev/null"):format(TEST_DIR))
end

local function write_file(path, content)
  local f, err = io.open(path, "wb")
  if f then f:write(content); f:close(); return true end
  return false, err
end

local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local c = f:read("*a"); f:close(); return c
end

T.describe("Backup hash", function()

  T.it("produces consistent hashes", function()
    local h1 = backup._hash("hello world")
    local h2 = backup._hash("hello world")
    T.assert_eq(h1, h2)
  end)

  T.it("produces different hashes for different inputs", function()
    local h1 = backup._hash("hello world")
    local h2 = backup._hash("hello world!")
    T.assert(h1 ~= h2, "different inputs should produce different hashes")
  end)

  T.it("produces hex strings", function()
    local h = backup._hash("test")
    T.assert_eq(#h, 16, "hash should be 16 hex chars")
    T.assert(h:match("^[0-9a-f]+$"), "hash should be hex")
  end)

end)

T.describe("Backup envelope", function()

  T.it("wraps data with checksum and metadata", function()
    local raw = '{"player":{"hp":100}}'
    local env = backup.envelope(raw)
    local parsed = serializer.decode(env)
    T.assert_eq(parsed.__envelope, true)
    T.assert_eq(parsed.data, raw)
    T.assert(parsed.checksum ~= nil, "should have checksum")
    T.assert(parsed.timestamp ~= nil, "should have timestamp")
  end)

  T.it("verifies and extracts valid data", function()
    local raw = '{"test":true}'
    local env = backup.envelope(raw)
    local extracted, err = backup.verify_and_extract(env)
    T.assert(extracted ~= nil, "should extract data")
    T.assert_eq(extracted, raw)
    T.assert_eq(err, nil)
  end)

  T.it("detects corrupted data", function()
    local raw = '{"player":{"hp":100}}'
    local env = backup.envelope(raw)
    -- Tamper with the data
    local parsed = serializer.decode(env)
    parsed.data = '{"player":{"hp":999}}'
    local tampered = serializer.encode(parsed)
    local extracted, err = backup.verify_and_extract(tampered)
    T.assert_eq(extracted, nil, "should fail on corrupted data")
    T.assert(err:match("Checksum"), "error should mention checksum")
  end)

  T.it("passes through non-enveloped data", function()
    local raw = '{"plain":true}'
    local extracted, err = backup.verify_and_extract(raw)
    T.assert_eq(extracted, raw, "should return non-enveloped data as-is")
    T.assert_eq(err, nil)
  end)

end)

T.describe("Backup file operations", function()

  T.it("creates backup of existing file", function()
    setup()
    local path = TEST_DIR .. "test.save"
    write_file(path, "original data")
    local bak_path = backup.create(path, { max_backups = 3, backup_dir = TEST_DIR })
    T.assert(bak_path ~= nil, "should create backup")
    local content = read_file(path .. ".backup")
    T.assert(content ~= nil, ".backup file should exist")
    T.assert_eq(content, "original data")
    teardown()
  end)

  T.it("returns nil when no file to back up", function()
    setup()
    local path = TEST_DIR .. "nonexistent.save"
    local result = backup.create(path)
    T.assert_eq(result, nil, "should return nil for missing file")
    teardown()
  end)

  T.it("save_with_backup writes enveloped file", function()
    setup()
    local path = TEST_DIR .. "test.save"
    local ok, err = backup.save_with_backup(path, "raw data", { max_backups = 0 })
    T.assert(ok, "save should succeed: " .. tostring(err))
    local content = read_file(path)
    local extracted, verr = backup.verify_and_extract(content)
    T.assert_eq(extracted, "raw data")
    teardown()
  end)

  T.it("load_with_fallback loads valid saves", function()
    setup()
    local path = TEST_DIR .. "test.save"
    backup.save_with_backup(path, "valid data")
    local data, warn = backup.load_with_fallback(path)
    T.assert_eq(data, "valid data")
    teardown()
  end)

  T.it("load_with_fallback falls back to backup on corruption", function()
    setup()
    local path = TEST_DIR .. "test.save"

    backup.save_with_backup(path, "version 1 data")
    backup.save_with_backup(path, "version 2 data")

    -- Corrupt the main file by tampering with envelope data
    local content = read_file(path)
    local parsed = serializer.decode(content)
    parsed.data = "TAMPERED DATA"
    write_file(path, serializer.encode(parsed))

    local data, warn = backup.load_with_fallback(path)
    T.assert(data ~= nil, "should load from backup: " .. tostring(warn))
    if data then
      T.assert_eq(data, "version 1 data")
    end
    teardown()
  end)

end)

T.finish()
