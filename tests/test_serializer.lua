---
-- test_serializer.lua
-- Tests for serializer.lua: JSON encode/decode, encryption, and round-trips.
--

local T = require("tests.test_helpers")
local ser = require("serializer")

T.describe("JSON encoder", function()

  T.it("encodes nil as null", function()
    T.assert_eq(ser.encode(nil), "null")
  end)

  T.it("encodes booleans", function()
    T.assert_eq(ser.encode(true), "true")
    T.assert_eq(ser.encode(false), "false")
  end)

  T.it("encodes integers without decimals", function()
    T.assert_eq(ser.encode(42), "42")
    T.assert_eq(ser.encode(0), "0")
    T.assert_eq(ser.encode(-1), "-1")
  end)

  T.it("encodes floats", function()
    local out = ser.encode(3.14)
    T.assert(out:match("%."), "expected float to contain decimal point")
    T.assert(tonumber(out) ~= nil)
  end)

  T.it("encodes strings with quotes", function()
    T.assert_eq(ser.encode("hello"), '"hello"')
  end)

  T.it("encodes strings with escape characters", function()
    local out = ser.encode('he"llo')
    T.assert_eq(out, '"he\\"llo"')
  end)

  T.it("encodes empty table as object", function()
    T.assert_eq(ser.encode({}), "{}")
  end)

  T.it("encodes empty array", function()
    T.assert_eq(ser.encode({1, 2, 3}), "[1,2,3]")
  end)

  T.it("encodes mixed table with array and keys", function()
    local t = { "a", "b", key = "val" }
    local out = ser.encode(t)
    T.assert(out:match("key"))
    T.assert(out:match("val"))
  end)

  T.it("encodes nested tables", function()
    local t = { a = { b = { c = 1 } } }
    local out = ser.encode(t)
    T.assert_eq(out, '{"a":{"b":{"c":1}}}')
  end)

end)

T.describe("JSON decoder", function()

  T.it("decodes null", function()
    local val = ser.decode("null")
    T.assert_eq(val, nil)
  end)

  T.it("decodes booleans", function()
    T.assert_eq(ser.decode("true"), true)
    T.assert_eq(ser.decode("false"), false)
  end)

  T.it("decodes integers", function()
    T.assert_eq(ser.decode("42"), 42)
    T.assert_eq(ser.decode("0"), 0)
    T.assert_eq(ser.decode("-1"), -1)
  end)

  T.it("decodes floats", function()
    local val = ser.decode("3.14")
    T.assert_near(val, 3.14)
  end)

  T.it("decodes strings", function()
    T.assert_eq(ser.decode('"hello"'), "hello")
  end)

  T.it("decodes escaped strings", function()
    T.assert_eq(ser.decode('"he\\"llo"'), 'he"llo')
  end)

  T.it("decodes empty object", function()
    T.assert_eq(ser.decode("{}"), {})
  end)

  T.it("decodes simple array", function()
    local val = ser.decode("[1,2,3]")
    T.assert_eq(val[1], 1)
    T.assert_eq(val[2], 2)
    T.assert_eq(val[3], 3)
  end)

  T.it("decodes nested object", function()
    local val = ser.decode('{"a":{"b":{"c":1}}}')
    T.assert_eq(val.a.b.c, 1)
  end)

  T.it("handles whitespace", function()
    local val = ser.decode('  {  "a"  :  1  }  ')
    T.assert_eq(val.a, 1)
  end)

end)

T.describe("JSON round-trip", function()

  T.it("round-trips simple values", function()
    local cases = {
      nil,
      true,
      false,
      0,
      42,
      -1,
      3.14,
      "hello",
    }
    for _, original in ipairs(cases) do
      local encoded = ser.encode(original)
      local decoded = ser.decode(encoded)
      T.assert_eq(decoded, original)
    end
  end)

  T.it("round-trips tables", function()
    local original = {
      name = "player1",
      hp = 100,
      max_hp = 100,
      xp = 1250,
      level = 5,
      inventory = { "sword", "shield", "potion" },
      stats = { str = 10, dex = 8, int = 12 },
      quests = { active = { "q1", "q2" }, completed = { "q3" } },
    }
    local encoded = ser.encode(original)
    local decoded = ser.decode(encoded)
    T.assert_eq(decoded, original)
  end)

  T.it("round-trips empty structures", function()
    T.assert_eq(ser.decode(ser.encode({})), {})
    T.assert_eq(ser.decode(ser.encode({a = {}})), {a = {}})
  end)

end)

T.describe("Pretty-print JSON", function()

  T.it("pretty-prints with indentation", function()
    local t = { a = 1, b = { c = 2 } }
    local out = ser.encode(t, true)
    T.assert(out:match("\n"), "pretty print should contain newlines")
  end)

  T.it("pretty-printed output round-trips", function()
    local original = { a = 1, b = { c = "hello" }, d = { 1, 2, 3 } }
    local encoded = ser.encode(original, true)
    local decoded = ser.decode(encoded)
    T.assert_eq(decoded, original)
  end)

end)

T.describe("Encryption", function()

  T.it("encrypts and decrypts a string", function()
    local plain = '{"player":{"hp":100}}'
    local key = "my-secret-key"
    local encrypted = ser.encrypt(plain, key)
    T.assert(encrypted ~= plain, "encrypted should differ from plaintext")
    local decrypted = ser.decrypt(encrypted, key)
    T.assert_eq(decrypted, plain)
  end)

  T.it("produces different output with different keys", function()
    local plain = "hello world"
    local e1 = ser.encrypt(plain, "key1")
    local e2 = ser.encrypt(plain, "key2")
    T.assert(e1 ~= e2, "different keys should produce different output")
  end)

  T.it("round-trips encrypted data through serialize/deserialize", function()
    local original = { player = { name = "hero", hp = 50 }, inventory = { "potion" } }
    local opts = { encryption_key = "s3cr3t" }
    local serialized = ser.serialize(original, opts)
    T.assert(serialized ~= ser.serialize(original, { pretty = true }), "encrypted output should differ from JSON")
    local deserialized = ser.deserialize(serialized, opts)
    T.assert_eq(deserialized, original)
  end)

  T.it("serialize without key produces plain JSON", function()
    local original = { test = true }
    local out = ser.serialize(original, {})
    T.assert(out:match("test"), "plain serialize should produce JSON")
    local decoded = ser.deserialize(out, {})
    T.assert_eq(decoded, original)
  end)

  T.it("empty key is treated as no encryption", function()
    local original = { x = 1 }
    local out = ser.serialize(original, { encryption_key = "" })
    T.assert(out:match("x"), "empty key should produce plain JSON")
  end)

end)

T.describe("Edge cases", function()

  T.it("handles very large integers", function()
    -- Lua numbers are doubles, but JSON should not add decimals to integers
    local val = ser.decode("999999999999999")
    T.assert_eq(val, 999999999999999)
  end)

  T.it("handles scientific notation", function()
    local val = ser.decode("1.5e10")
    T.assert_near(val, 15000000000, 1)
  end)

  T.it("rejects malformed JSON", function()
    local ok = pcall(ser.decode, "{invalid}")
    T.assert(not ok, "should error on malformed JSON")
  end)

  T.it("ignores NaN and Inf in encoding", function()
    local t = { a = 0 / 0, b = math.huge }
    local out = ser.encode(t)
    local decoded = ser.decode(out)
    T.assert_eq(decoded.a, nil) -- NaN becomes null -> nil
    T.assert_eq(decoded.b, nil) -- Inf becomes null -> nil
  end)

end)

T.finish()
