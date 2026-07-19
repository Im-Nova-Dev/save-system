---
-- validation.lua
-- Schema-based validation for save data.
-- Define the expected shape of your save data, and validation will ensure
-- required fields exist with correct types.
--
-- Schema format:
--   {
--     player = {
--       name = "string",
--       level = "number",
--       is_alive = "boolean",
--       stats = {            -- nested objects
--         str = "number",
--         dex = "number",
--       },
--       inventory = {"string"},   -- array of strings
--       tags = {"string", optional = true},  -- optional field
--     },
--     quests = {"table"},   -- array of tables (any table)
--   }
--
-- Field types: "string", "number", "boolean", "table", "nil", or a table
-- for nested objects. Arrays are denoted by a single-element table: {"type"}.
--

local validation = {}

local VALID_PRIMITIVES = { string = true, number = true, boolean = true, table = true }
VALID_PRIMITIVES["nil"] = true

--- Validate a single value against a schema type spec.
-- @param value: The value to validate.
-- @param spec: The schema type specification.
-- @param path (string): Current path for error reporting.
-- @return boolean, string|nil: (is_valid, error_message).
function validation._validate(value, spec, path)
  path = path or "root"

  if type(spec) == "string" then
    -- Primitive type check
    if spec == "any" then
      return true, nil
    end
    if not VALID_PRIMITIVES[spec] then
      return false, ("Unknown type '%s' at %s"):format(spec, path)
    end
    local actual = type(value)
    if spec == "nil" and actual ~= "nil" then
      return false, ("Expected nil at %s, got %s"):format(path, actual)
    end
    if actual ~= "nil" and actual ~= spec then
      return false, ("Type mismatch at %s: expected %s, got %s"):format(path, spec, actual)
    end
    return true, nil

  elseif type(spec) == "table" then
    if #spec == 1 then
      -- Array type: {"element_type"}
      local elem_spec = spec[1]
      if type(value) ~= "table" then
        return false, ("Expected array at %s, got %s"):format(path, type(value))
      end
      -- Check if it's array-like (sequential integer keys)
      local i = 1
      while value[i] ~= nil do
        local ok, err = validation._validate(value[i], elem_spec, path .. "[" .. i .. "]")
        if not ok then return false, err end
        i = i + 1
      end
      -- Check for non-array keys
      for k in pairs(value) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k or k >= i then
          return false, ("Expected array at %s, found non-sequential key %s"):format(path, tostring(k))
        end
      end
      return true, nil

    else
      -- Object type: { field = spec, ... }
      if type(value) ~= "table" then
        return false, ("Expected object at %s, got %s"):format(path, type(value))
      end
      for field, field_spec in pairs(spec) do
        if type(field) == "string" then
          local field_path = path .. "." .. field
          local is_optional = field_spec.optional
          local actual_spec = is_optional and field_spec[1] or field_spec

          local has_value = value[field] ~= nil
          if not has_value then
            if not is_optional then
              return false, ("Missing required field '%s' at %s"):format(field, path)
            end
          else
            local ok, err = validation._validate(value[field], actual_spec, field_path)
            if not ok then return false, err end
          end
        end
      end
      return true, nil
    end
  end

  return false, ("Invalid schema at %s"):format(path)
end

--- Validate data against a schema.
-- @param data (table): The data to validate.
-- @param schema (table): The schema definition.
-- @return boolean, string|nil: (is_valid, error_message_or_nil).
function validation.validate(data, schema)
  if not data or type(data) ~= "table" then
    return false, "Data must be a non-nil table"
  end
  if not schema or type(schema) ~= "table" then
    return false, "Schema must be a non-nil table"
  end
  return validation._validate(data, schema, "root")
end

--- Create a validator function for a schema. Cached for performance.
-- @param schema (table): The schema definition.
-- @return function: A function(data) -> boolean, string|nil.
function validation.validator(schema)
  return function(data)
    return validation.validate(data, schema)
  end
end

--- Get a human-readable description of a schema.
-- Useful for LLMs/agents to understand the expected data format.
-- @param schema (table): The schema definition.
-- @param indent (string|nil): Indentation prefix.
-- @return string: Description of the schema.
function validation.describe(schema, indent)
  indent = indent or ""
  if type(schema) == "string" then
    return schema
  end
  if type(schema) ~= "table" then
    return tostring(schema)
  end
  if #schema == 1 then
    return "array of " .. validation.describe(schema[1])
  end
  local lines = {}
  for k, v in pairs(schema) do
    if type(k) == "string" then
      local suffix = ""
      if type(v) == "table" and v.optional then
        suffix = " (optional)"
      end
      local spec = type(v) == "table" and v.optional and v[1] or v
      lines[#lines + 1] = indent .. "  " .. k .. ": " .. validation.describe(spec) .. suffix
    end
  end
  table.sort(lines)
  return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
end

return validation
