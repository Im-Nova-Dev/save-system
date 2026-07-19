---
-- test_validation.lua
-- Tests for validation.lua: schemas, type checking, nested objects, arrays.
--

local T = require("tests.test_helpers")
local val = require("validation")

T.describe("Validation primitives", function()

  T.it("validates correct primitive types", function()
    local ok, err = val.validate({ name = "Alice" }, { name = "string" })
    T.assert(ok, "string should pass: " .. tostring(err))
  end)

  T.it("rejects wrong primitive types", function()
    local ok = val.validate({ level = "high" }, { level = "number" })
    T.assert(not ok, "should reject string for number field")
  end)

  T.it("validates booleans", function()
    T.assert(val.validate({ alive = true }, { alive = "boolean" }))
    T.assert(val.validate({ alive = false }, { alive = "boolean" }))
    T.assert(not val.validate({ alive = 1 }, { alive = "boolean" }))
  end)

  T.it("validates 'any' type", function()
    local ok, err = val.validate({ anything = 42 }, { anything = "any" })
    T.assert(ok, "any type should pass: " .. tostring(err))
    local ok2, err2 = val.validate({ anything = "hello" }, { anything = "any" })
    T.assert(ok2, "any type with string: " .. tostring(err2))
  end)

end)

T.describe("Validation nested objects", function()

  T.it("validates nested object structure", function()
    local data = {
      player = {
        name = "Alice",
        stats = { str = 10, dex = 8 },
      },
    }
    local schema = {
      player = {
        name = "string",
        stats = {
          str = "number",
          dex = "number",
        },
      },
    }
    local ok, err = val.validate(data, schema)
    T.assert(ok, "nested objects should pass: " .. tostring(err))
  end)

  T.it("rejects nested type mismatches", function()
    local data = { player = { name = 42 } }
    local schema = { player = { name = "string" } }
    T.assert(not val.validate(data, schema))
  end)

  T.it("reports missing required fields", function()
    local data = { player = {} }
    local schema = { player = { name = "string" } }
    local ok, err = val.validate(data, schema)
    T.assert(not ok, "should reject missing field")
    T.assert(err:match("Missing required"), "error should mention missing")
  end)

end)

T.describe("Validation arrays", function()

  T.it("validates array of primitives", function()
    local data = { items = { "sword", "shield", "potion" } }
    local schema = { items = {"string"} }
    local ok, err = val.validate(data, schema)
    T.assert(ok, "array of strings should pass: " .. tostring(err))
  end)

  T.it("validates array of objects", function()
    local data = { npcs = { { name = "Bob" }, { name = "Alice" } } }
    local schema = { npcs = {{ name = "string" }} }
    local ok, err = val.validate(data, schema)
    T.assert(ok, "array of objects should pass: " .. tostring(err))
  end)

  T.it("rejects array with wrong element type", function()
    local data = { items = { "sword", 42 } }
    local schema = { items = {"string"} }
    T.assert(not val.validate(data, schema))
  end)

end)

T.describe("Validation optional fields", function()

  T.it("allows missing optional fields", function()
    local data = { name = "Alice" }
    local schema = { name = "string", level = {"number", optional = true} }
    local ok, err = val.validate(data, schema)
    T.assert(ok, "missing optional should pass: " .. tostring(err))
  end)

  T.it("validates type when optional field is present", function()
    local data = { name = "Alice", level = "high" }
    local schema = { name = "string", level = {"number", optional = true} }
    T.assert(not val.validate(data, schema))
  end)

end)

T.describe("Schema describe", function()

  T.it("produces readable description", function()
    local schema = {
      player = {
        name = "string",
        level = "number",
        inventory = {"string"},
      },
      save_version = "number",
    }
    local desc = val.describe(schema)
    T.assert(type(desc) == "string")
    T.assert(#desc > 0)
    T.assert(desc:match("player"))
    T.assert(desc:match("string"))
  end)

end)

T.describe("Validator factory", function()

  T.it("creates reusable validator functions", function()
    local schema = { name = "string" }
    local validate = val.validator(schema)
    T.assert(validate({ name = "Alice" }))
    T.assert(not validate({ name = 42 }))
  end)

end)

T.finish()
