---
-- test_helpers.lua
-- Minimal test framework designed for LLM/agent consumption.
-- Every test produces structured JSON output so agents can parse results.
-- Also supports verbose human-readable output.
--

local test_helpers = {}

local results = { suites = {}, passed = 0, failed = 0, errors = {} }
local current_suite = nil

function test_helpers.describe(name, fn)
  current_suite = { name = name, tests = {}, passed = 0, failed = 0 }
  local ok, err = pcall(fn)
  if not ok then
    current_suite.error = err
    current_suite.failed = current_suite.failed + 1
  end
  table.insert(results.suites, current_suite)
  current_suite = nil
end

function test_helpers.it(name, fn)
  local test = { name = name, passed = false, error = nil }
  local ok, err = pcall(fn)
  if ok then
    test.passed = true
    current_suite.passed = current_suite.passed + 1
    results.passed = results.passed + 1
  else
    test.passed = false
    test.error = tostring(err)
    current_suite.failed = current_suite.failed + 1
    results.failed = results.failed + 1
    table.insert(results.errors, { suite = current_suite.name, test = name, error = tostring(err) })
  end
  table.insert(current_suite.tests, test)
end

--- Assertion: check value is truthy
function test_helpers.assert(cond, msg)
  if not cond then
    error(msg or "Assertion failed", 2)
  end
end

--- Assertion: deep equality for tables
function test_helpers.assert_eq(a, b, path)
  path = path or "root"
  if type(a) ~= type(b) then
    error(("Type mismatch at %s: %s vs %s"):format(path, type(a), type(b)), 2)
  end
  if type(a) == "table" then
    local seen_a, seen_b = {}, {}
    for k in pairs(a) do
      seen_a[k] = true
      test_helpers.assert_eq(a[k], b[k], path .. "." .. tostring(k))
    end
    for k in pairs(b) do
      if not seen_a[k] then
        error(("Extra key at %s: %s"):format(path, tostring(k)), 2)
      end
    end
  elseif a ~= b then
    error(("Mismatch at %s: %s vs %s"):format(path, tostring(a), tostring(b)), 2)
  end
end

--- Assertion: approximately equal for floats
function test_helpers.assert_near(a, b, eps)
  eps = eps or 0.0001
  if math.abs(a - b) > eps then
    error(("Not near: %s vs %s (eps=%s)"):format(tostring(a), tostring(b), tostring(eps)), 2)
  end
end

--- Print results as structured JSON (machine-readable)
function test_helpers.report_json()
  local report = {
    summary = {
      total = results.passed + results.failed,
      passed = results.passed,
      failed = results.failed,
    },
    suites = {},
  }
  for _, suite in ipairs(results.suites) do
    local s = { name = suite.name, passed = suite.passed, failed = suite.failed, tests = {} }
    for _, test in ipairs(suite.tests) do
      table.insert(s.tests, { name = test.name, passed = test.passed, error = test.error })
    end
    table.insert(report.suites, s)
  end
  if #results.errors > 0 then
    report.errors = results.errors
  end
  print("---TEST_JSON_START---")
  local ser = require("serializer")
  print(ser.encode(report, true))
  print("---TEST_JSON_END---")
end

--- Print results as human-readable summary
function test_helpers.report_human()
  local total = results.passed + results.failed
  print(("\n=== Test Results: %d passed, %d failed (total %d) ==="):format(results.passed, results.failed, total))
  for _, suite in ipairs(results.suites) do
    local status = suite.failed == 0 and "PASS" or "FAIL"
    print(("  [%s] %s (%d/%d)"):format(status, suite.name, suite.passed, suite.passed + suite.failed))
    for _, test in ipairs(suite.tests) do
      local icon = test.passed and "  ✓" or "  ✗"
      print(("    %s %s"):format(icon, test.name))
      if test.error then
        print(("        └─ %s"):format(test.error))
      end
    end
    if suite.error then
      print(("      └─ SUITE ERROR: %s"):format(suite.error))
    end
  end
  if #results.errors > 0 then
    print("\nFailed tests:")
    for _, err in ipairs(results.errors) do
      print(("  %s / %s: %s"):format(err.suite, err.test, err.error))
    end
  end
  print("")
end

--- Run all tests and print both JSON and human-readable output
function test_helpers.finish()
  test_helpers.report_json()
  test_helpers.report_human()
  if results.failed > 0 then
    os.exit(1)
  end
end

return test_helpers
