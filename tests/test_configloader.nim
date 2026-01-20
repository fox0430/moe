import std/[unittest, os, strutils, tables]
import pkg/results
import ../src/moepkg/[configloader, config]

var testFileCounter {.global.} = 0

# Helper proc to load config from a TOML string using a temp file
proc loadFromTomlString(tomlStr: string): (EditorConfig, ValidationResult) =
  inc testFileCounter
  let testFile = "/tmp/moe_test_config_" & $testFileCounter & ".toml"
  writeFile(testFile, tomlStr)
  defer:
    removeFile(testFile)

  let loadResult = loadConfigFromToml(testFile)
  if loadResult.isOk:
    return loadResult.get
  else:
    # Return defaults with an error in validation result
    var vr = newValidationResult()
    vr.addError("parse", loadResult.error, "valid TOML")
    return (newEditorConfig(), vr)

suite "Config Validation - InvalidItem and ValidationResult":
  test "Empty validation result has no errors":
    let vr = newValidationResult()
    check not vr.hasErrors

  test "Adding error creates error entry":
    var vr = newValidationResult()
    vr.addError("Standard.tabStop", "0", "integer >= 1")
    check vr.hasErrors
    check vr.errors.len == 1
    check vr.errors[0].name == "Standard.tabStop"
    check vr.errors[0].val == "0"
    check vr.errors[0].expected == "integer >= 1"

  test "toErrorMessage generates readable message":
    let item =
      InvalidItem(name: "Standard.tabStop", val: "invalid", expected: "integer >= 1")
    let msg = item.toErrorMessage
    check "Standard.tabStop" in msg
    check "invalid" in msg
    check "integer >= 1" in msg

suite "Config Validation - Standard section":
  test "Valid Standard config passes validation":
    let tomlStr =
      """
[Standard]
number = true
currentNumber = false
tabStop = 4
colorMode = "24bit"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.number == true
    check config.standard.tabStop == 4
    check config.standard.colorMode == cm24bit

  test "Invalid bool type is detected":
    let tomlStr =
      """
[Standard]
number = "true"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check vr.errors.len == 1
    check "Standard.number" in vr.errors[0].name

  test "Invalid tabStop (zero) is detected":
    let tomlStr =
      """
[Standard]
tabStop = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.tabStop" in vr.errors[0].name
    # Invalid value should be skipped, default used
    check config.standard.tabStop == 2 # Default value

  test "Invalid tabStop (negative) is detected":
    let tomlStr =
      """
[Standard]
tabStop = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.tabStop" in vr.errors[0].name
    check config.standard.tabStop == 2 # Default value

  test "Invalid colorMode enum is detected":
    let tomlStr =
      """
[Standard]
colorMode = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.colorMode" in vr.errors[0].name
    check config.standard.colorMode == cm24bit # Default value

  test "Invalid cursorType enum is detected":
    let tomlStr =
      """
[Standard]
defaultCursor = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.defaultCursor" in vr.errors[0].name
    check config.standard.defaultCursor == ctTerminalDefault # Default value

suite "Config Validation - Clipboard section":
  test "Valid Clipboard config passes validation":
    let tomlStr =
      """
[Clipboard]
enable = true
tool = "xsel"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.clipboard.enable == true
    check config.clipboard.tool == ctXsel

  test "Invalid clipboard tool is detected":
    let tomlStr =
      """
[Clipboard]
tool = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Clipboard.tool" in vr.errors[0].name
    check config.clipboard.tool == ctXsel # Default value

suite "Config Validation - AutoBackup section":
  test "Valid AutoBackup config passes validation":
    let tomlStr =
      """
[AutoBackup]
enable = true
idleTime = 10
interval = 5
dirToExclude = ["/etc", "/tmp"]
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.autoBackup.enable == true
    check config.autoBackup.idleTime == 10
    check config.autoBackup.interval == 5
    check config.autoBackup.dirToExclude == @["/etc", "/tmp"]

  test "Invalid idleTime (zero) is detected":
    let tomlStr =
      """
[AutoBackup]
idleTime = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "AutoBackup.idleTime" in vr.errors[0].name
    check config.autoBackup.idleTime == 10 # Default value

  test "Invalid dirToExclude type (not array) is detected":
    let tomlStr =
      """
[AutoBackup]
dirToExclude = "/etc"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "AutoBackup.dirToExclude" in vr.errors[0].name

suite "Config Validation - SmoothScroll section":
  test "Valid SmoothScroll config passes validation":
    let tomlStr =
      """
[SmoothScroll]
enable = true
friction = 80.0
airDrag = 2.0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.smoothScroll.enable == true
    check config.smoothScroll.friction == 80.0
    check config.smoothScroll.airDrag == 2.0

  test "Negative friction is detected":
    let tomlStr =
      """
[SmoothScroll]
friction = -1.0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "SmoothScroll.friction" in vr.errors[0].name
    check config.smoothScroll.friction == 80.0 # Default value

suite "Config Validation - Highlight section":
  test "Valid Highlight config passes validation":
    let tomlStr =
      """
[Highlight]
currentLine = true
reservedWord = ["TODO", "FIXME"]
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.highlight.currentLine == true
    check config.highlight.reservedWord == @["TODO", "FIXME"]

  test "Invalid reservedWord (not array) is detected":
    let tomlStr =
      """
[Highlight]
reservedWord = "TODO"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Highlight.reservedWord" in vr.errors[0].name

suite "Config Validation - LSP section":
  test "Valid LSP config passes validation":
    let tomlStr =
      """
[Lsp]
enable = true
timeout = 5000

[Lsp.Completion]
enable = true

[Lsp.Definition]
enable = true
openWindow = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.lsp.enable == true
    check config.lsp.timeout == 5000
    check config.lsp.completion.enable == true
    check config.lsp.definition.enable == true
    check config.lsp.definition.openWindow == false

  test "Invalid LSP timeout is detected":
    let tomlStr =
      """
[Lsp]
timeout = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Lsp.timeout" in vr.errors[0].name
    check config.lsp.timeout == 5000 # Default value

  test "Language server config validation":
    let tomlStr =
      """
[Lsp.nim]
extensions = [".nim"]
command = "nimlsp"
trace = "verbose"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.lsp.servers.hasKey("nim")
    check config.lsp.servers["nim"].extensions == @[".nim"]
    check config.lsp.servers["nim"].command == "nimlsp"
    check config.lsp.servers["nim"].trace == ltVerbose

  test "Invalid LSP trace level is detected":
    let tomlStr =
      """
[Lsp.nim]
trace = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Lsp.nim.trace" in vr.errors[0].name
    check config.lsp.servers["nim"].trace == ltOff # Default value

suite "Config Validation - Multiple errors":
  test "Multiple errors are collected":
    let tomlStr =
      """
[Standard]
tabStop = 0
colorMode = "invalid"
number = "not_bool"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check vr.errors.len == 3

  test "Error messages are generated for all errors":
    let tomlStr =
      """
[Standard]
tabStop = 0
colorMode = "invalid"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    let messages = vr.toErrorMessages
    check messages.len == 2

suite "Config Loading - Integration":
  test "loadConfigFromToml with valid config":
    let testFile = "/tmp/moe_test_valid_config.toml"
    writeFile(
      testFile,
      """
[Standard]
number = true
tabStop = 4
colorMode = "24bit"

[Clipboard]
enable = true
tool = "xsel"
""",
    )
    defer:
      removeFile(testFile)

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (config, vr) = loadResult.get
    check not vr.hasErrors
    check config.standard.number == true
    check config.standard.tabStop == 4
    check config.standard.colorMode == cm24bit
    check config.clipboard.enable == true
    check config.clipboard.tool == ctXsel

  test "loadConfigFromToml with invalid values uses defaults":
    let testFile = "/tmp/moe_test_invalid_config.toml"
    writeFile(
      testFile,
      """
[Standard]
tabStop = 0
colorMode = "invalid"
""",
    )
    defer:
      removeFile(testFile)

    # Should still load successfully, using defaults for invalid values
    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (config, vr) = loadResult.get
    check vr.hasErrors # Has validation errors
    check vr.errors.len == 2 # tabStop and colorMode
    check config.standard.tabStop == 2 # Default value (invalid value skipped)
    check config.standard.colorMode == cm24bit # Default value

  test "loadConfigFromToml with non-existent file returns defaults":
    let loadResult = loadConfigFromToml("/nonexistent/path/config.toml")
    check loadResult.isOk
    let (config, vr) = loadResult.get
    check not vr.hasErrors # No errors for non-existent file
    check config.standard.tabStop == 2 # Default value
