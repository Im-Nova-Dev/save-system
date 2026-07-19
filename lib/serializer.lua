---
-- serializer.lua
-- Pure-Lua JSON encoder/decoder + optional XOR encryption with Base64.
-- No external dependencies. Embeds a minimal JSON implementation.
--

local serializer = {}

-- ────────────────────────────────────────────
-- JSON encoder / decoder (pure Lua, no deps)
-- ────────────────────────────────────────────

local json_encode
local json_decode

do
  local escape_map = {
    ["\""] = "\\\"",
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
  }

  local function escape_char(c)
    if escape_map[c] then return escape_map[c] end
    return string.format("\\u%04x", string.byte(c))
  end

  local function is_nan_or_inf(v)
    return v ~= v or v == math.huge or v == -math.huge
  end

  function json_encode(v, pretty, indent)
    indent = indent or ""
    local t = type(v)
    if t == "nil" then
      return "null"
    elseif t == "boolean" then
      return tostring(v)
    elseif t == "string" then
      return "\"" .. v:gsub("[%c\\\"]", escape_char) .. "\""
    elseif t == "number" then
      if is_nan_or_inf(v) then return "null" end
      if v == math.floor(v) and v < 9007199254740992 and v > -9007199254740992 then
        return string.format("%.0f", v)
      end
      return string.format("%.17g", v)
    elseif t == "table" then
      local keys = {}
      local is_array = nil
      local max_idx = 0
      for k in pairs(v) do
        if is_array == nil then is_array = true end
        if type(k) == "number" and k >= 1 and math.floor(k) == k then
          if k > max_idx then max_idx = k end
        else
          is_array = false
        end
        keys[#keys + 1] = k
      end
      -- Empty table defaults to object
      if is_array == nil then is_array = false end
      table.sort(keys, function(a, b)
        if type(a) == "number" and type(b) == "number" then return a < b end
        if type(a) ~= "number" and type(b) ~= "number" then return tostring(a) < tostring(b) end
        return type(a) == "number"
      end)
      if is_array then
        local parts = {}
        for i = 1, max_idx do
          parts[i] = json_encode(v[i], pretty, indent .. "  ")
        end
        if pretty then
          return "[\n" .. indent .. "  " .. table.concat(parts, ",\n" .. indent .. "  ") .. "\n" .. indent .. "]"
        end
        return "[" .. table.concat(parts, ",") .. "]"
      else
        local parts = {}
        for _, k in ipairs(keys) do
          local k_str
          if type(k) == "number" then
            k_str = json_encode(k)
          else
            k_str = "\"" .. tostring(k):gsub("[%c\\\"]", escape_char) .. "\""
          end
          parts[#parts + 1] = k_str .. (pretty and ": " or ":") .. json_encode(v[k], pretty, indent .. "  ")
        end
        if pretty then
          return "{\n" .. indent .. "  " .. table.concat(parts, ",\n" .. indent .. "  ") .. "\n" .. indent .. "}"
        end
        return "{" .. table.concat(parts, ",") .. "}"
      end
    end
    error(("Cannot serialize type '%s'"):format(type(v)))
  end

  local function json_scan(str, pos)
    while pos <= #str do
      local c = str:sub(pos, pos)
      if c == " " or c == "\t" or c == "\n" or c == "\r" then
        pos = pos + 1
      else
        return pos
      end
    end
    return pos
  end

  function json_decode(str, pos)
    pos = pos or 1
    pos = json_scan(str, pos)
    if pos > #str then error("Unexpected end of JSON input") end
    local c = str:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local result = {}
      pos = json_scan(str, pos)
      if pos <= #str and str:sub(pos, pos) == "}" then
        return result, pos + 1
      end
      while true do
        pos = json_scan(str, pos)
        local key, next_pos = json_decode(str, pos)
        pos = next_pos
        pos = json_scan(str, pos)
        if str:sub(pos, pos) ~= ":" then error("Expected ':' in JSON object") end
        pos = pos + 1
        local val, next_pos2 = json_decode(str, pos)
        pos = next_pos2
        result[key] = val
        pos = json_scan(str, pos)
        local comma = str:sub(pos, pos)
        if comma == "}" then return result, pos + 1 end
        if comma ~= "," then error("Expected ',' or '}' in JSON object") end
        pos = pos + 1
      end
    elseif c == "[" then
      pos = pos + 1
      local result = {}
      local idx = 1
      pos = json_scan(str, pos)
      if pos <= #str and str:sub(pos, pos) == "]" then
        return result, pos + 1
      end
      while true do
        local val, next_pos = json_decode(str, pos)
        pos = next_pos
        result[idx] = val
        idx = idx + 1
        pos = json_scan(str, pos)
        local comma = str:sub(pos, pos)
        if comma == "]" then return result, pos + 1 end
        if comma ~= "," then error("Expected ',' or ']' in JSON array") end
        pos = pos + 1
      end
    elseif c == "\"" then
      pos = pos + 1
      local parts = {}
      while pos <= #str do
        local c2 = str:sub(pos, pos)
        if c2 == "\"" then
          return table.concat(parts), pos + 1
        elseif c2 == "\\" then
          pos = pos + 1
          local esc = str:sub(pos, pos)
          if esc == "\"" then parts[#parts + 1] = "\""
          elseif esc == "\\" then parts[#parts + 1] = "\\"
          elseif esc == "/" then parts[#parts + 1] = "/"
          elseif esc == "b" then parts[#parts + 1] = "\b"
          elseif esc == "f" then parts[#parts + 1] = "\f"
          elseif esc == "n" then parts[#parts + 1] = "\n"
          elseif esc == "r" then parts[#parts + 1] = "\r"
          elseif esc == "t" then parts[#parts + 1] = "\t"
          elseif esc == "u" then
            local hex = str:sub(pos + 1, pos + 4)
            if #hex < 4 then error("Invalid unicode escape") end
            local codepoint = tonumber(hex, 16)
            if codepoint <= 0x7F then
              parts[#parts + 1] = string.char(codepoint)
            elseif codepoint <= 0x7FF then
              parts[#parts + 1] = string.char(0xC0 | (codepoint >> 6), 0x80 | (codepoint & 0x3F))
            elseif codepoint <= 0xFFFF then
              parts[#parts + 1] = string.char(0xE0 | (codepoint >> 12), 0x80 | ((codepoint >> 6) & 0x3F), 0x80 | (codepoint & 0x3F))
            elseif codepoint <= 0x10FFFF then
              parts[#parts + 1] = string.char(0xF0 | (codepoint >> 18), 0x80 | ((codepoint >> 12) & 0x3F), 0x80 | ((codepoint >> 6) & 0x3F), 0x80 | (codepoint & 0x3F))
            end
            pos = pos + 4
          else
            parts[#parts + 1] = "\\" .. esc
          end
          pos = pos + 1
        else
          parts[#parts + 1] = c2
          pos = pos + 1
        end
      end
      error("Unterminated JSON string")
    elseif c == "t" then
      if str:sub(pos, pos + 3) == "true" then return true, pos + 4 end
      error("Invalid JSON token")
    elseif c == "f" then
      if str:sub(pos, pos + 4) == "false" then return false, pos + 5 end
      error("Invalid JSON token")
    elseif c == "n" then
      if str:sub(pos, pos + 3) == "null" then return nil, pos + 4 end
      error("Invalid JSON token")
    elseif c == "-" or c >= "0" and c <= "9" then
      local start = pos
      if str:sub(pos, pos) == "-" then pos = pos + 1 end
      while pos <= #str and str:sub(pos, pos) >= "0" and str:sub(pos, pos) <= "9" do pos = pos + 1 end
      if pos <= #str and str:sub(pos, pos) == "." then
        pos = pos + 1
        while pos <= #str and str:sub(pos, pos) >= "0" and str:sub(pos, pos) <= "9" do pos = pos + 1 end
      end
      if pos <= #str and (str:sub(pos, pos) == "e" or str:sub(pos, pos) == "E") then
        pos = pos + 1
        if pos <= #str and (str:sub(pos, pos) == "+" or str:sub(pos, pos) == "-") then pos = pos + 1 end
        while pos <= #str and str:sub(pos, pos) >= "0" and str:sub(pos, pos) <= "9" do pos = pos + 1 end
      end
      local num_str = str:sub(start, pos - 1)
      local num = tonumber(num_str)
      if num == nil then error(("Invalid number: %s"):format(num_str)) end
      return num, pos
    end
    error(("Unexpected character '%s' at position %d"):format(c, pos))
  end
end

-- ────────────────────────────────────────────
-- Base64 (for encrypted payload encoding)
-- ────────────────────────────────────────────

local function base64_encode(data)
  local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local result = {}
  for i = 1, #data, 3 do
    local bytes = { string.byte(data, i, i + 2) }
    local n = #bytes
    local pad = 3 - n
    for _ = 1, pad do bytes[#bytes + 1] = 0 end
    local b = (bytes[1] << 16) + (bytes[2] << 8) + bytes[3]
    for j = 1, 4 do
      local idx = (b >> (6 * (4 - j))) & 0x3F
      result[#result + 1] = b64chars:sub(idx + 1, idx + 1)
    end
    for j = 1, pad do result[#result - pad + j] = "=" end
  end
  return table.concat(result)
end

local function base64_decode(data)
  local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local lookup = {}
  for i = 1, 64 do lookup[b64chars:sub(i, i)] = i - 1 end
  data = data:gsub("=+", "")
  local result = {}
  for i = 1, #data, 4 do
    local chars = {}
    for j = i, i + 3 do
      local c = data:sub(j, j)
      chars[#chars + 1] = lookup[c] or 0
    end
    local b = (chars[1] << 18) + (chars[2] << 12) + (chars[3] << 6) + chars[4]
    result[#result + 1] = string.char((b >> 16) & 0xFF)
    result[#result + 1] = string.char((b >> 8) & 0xFF)
    result[#result + 1] = string.char(b & 0xFF)
  end
  return table.concat(result):sub(1, #data * 3 // 4 - (data:sub(-2, -2) == "=" and 1 or 0))
end

-- ────────────────────────────────────────────
-- XOR encryption
-- ────────────────────────────────────────────

local function xor_cipher(data, key)
  if not key or #key == 0 then return data end
  local result = {}
  for i = 1, #data do
    local byte = string.byte(data, i)
    local key_byte = string.byte(key, ((i - 1) % #key) + 1)
    result[i] = string.char(byte ~ key_byte)
  end
  return table.concat(result)
end

-- ────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────

--- Serialize a Lua table to a JSON string.
-- @param data (table): The data to serialize.
-- @param pretty (boolean|nil): If true, format with indentation.
-- @return string: The JSON string.
function serializer.encode(data, pretty)
  return json_encode(data, pretty)
end

--- Deserialize a JSON string to a Lua table.
-- @param str (string): The JSON string.
-- @return table: The deserialized data.
function serializer.decode(str)
  local result = json_decode(str)
  return result
end

--- Encrypt a string using XOR cipher and encode as Base64.
-- @param data (string): The plaintext string.
-- @param key (string): The encryption key.
-- @return string: Base64-encoded ciphertext.
function serializer.encrypt(data, key)
  local ciphered = xor_cipher(data, key)
  return base64_encode(ciphered)
end

--- Decrypt a Base64-encoded XOR-ciphered string.
-- @param b64 (string): The Base64 ciphertext.
-- @param key (string): The encryption key.
-- @return string: The plaintext string.
function serializer.decrypt(b64, key)
  local decoded = base64_decode(b64)
  return xor_cipher(decoded, key)
end

--- Serialize data to a savable string (JSON, optionally encrypted).
-- @param data (table): The data to save.
-- @param opts (table|nil): Options. May contain:
--   - encryption_key (string|nil): If provided, encrypts the JSON output.
--   - pretty (boolean|nil): Pretty-print JSON before encryption.
-- @return string: The serialized string (plain JSON or Base64).
function serializer.serialize(data, opts)
  opts = opts or {}
  local json = json_encode(data, opts.pretty or false)
  if opts.encryption_key and #opts.encryption_key > 0 then
    return serializer.encrypt(json, opts.encryption_key)
  end
  return json
end

--- Deserialize a string back to a Lua table (handles both plain and encrypted).
-- @param str (string): The string to deserialize.
-- @param opts (table|nil): Options. May contain:
--   - encryption_key (string|nil): If provided, attempts to decrypt first.
-- @return table: The deserialized data.
function serializer.deserialize(str, opts)
  opts = opts or {}
  local json
  if opts.encryption_key and #opts.encryption_key > 0 then
    json = serializer.decrypt(str, opts.encryption_key)
  else
    json = str
  end
  return json_decode(json)
end

return serializer
