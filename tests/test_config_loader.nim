#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, os, strutils, tables, options, sequtils, json]

import pkg/results

import ../src/moepkg/[config_loader, config, color, theme, modes]

import config_test_helper

var testFileCounter {.global.} = 0

# Helper proc to load config from a TOML string using a temp file
proc loadFromTomlString(tomlStr: string): (EditorConfig, ValidationResult) =
  inc testFileCounter
  let testFile = getTempDir() / "moe_test_config_" & $testFileCounter & ".toml"
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

suite "Config Validation - Standard section validKeys completeness":
  test "All StandardConfig fields are accepted in TOML":
    ## Every field in StandardConfig should be loadable from TOML without
    ## triggering an "unknown key" warning. The validKeys list is derived from
    ## the type by generateConfigLoader, so adding a field keeps this passing;
    ## this test guards against the macro/type wiring regressing.
    let tomlStr = """
[Standard]
number = true
statusLine = true
syntax = true
indentationLines = true
tabStop = 4
shiftWidth = 0
softTabStop = 0
expandTab = false
sidebar = true
autoCloseParen = true
autoIndent = true
ignorecase = true
smartcase = true
disableChangeCursor = false
defaultCursor = "terminalDefault"
normalModeCursor = "blinkBlock"
insertModeCursor = "blinkIbeam"
liveReloadOfConf = false
incrementalSearch = true
popupWindowInExmode = true
autoDeleteParen = true
liveReloadOfFile = true
colorMode = "24bit"
mouse = false
lineWrap = true
timeoutlen = 1000
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors

  test "All StandardConfig fields round-trip through save/load":
    ## Set every field to a non-default value, save, reload, and verify.
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_standard_roundtrip_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.standard.number = false
    config.standard.statusLine = false
    config.standard.syntax = false
    config.standard.indentationLines = false
    config.standard.tabStop = 8
    config.standard.shiftWidth = 4
    config.standard.softTabStop = 4
    config.standard.expandTab = true
    config.standard.sidebar = false
    config.standard.autoCloseParen = false
    config.standard.autoIndent = false
    config.standard.ignorecase = false
    config.standard.smartcase = false
    config.standard.disableChangeCursor = true
    config.standard.liveReloadOfConf = true
    config.standard.incrementalSearch = false
    config.standard.popupWindowInExmode = false
    config.standard.autoDeleteParen = false
    config.standard.liveReloadOfFile = false
    config.standard.mouse = true
    config.standard.lineWrap = false
    config.standard.timeoutlen = 500
    config.theme.kind = tkDefault
    config.theme.path = ""

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors

    check loaded.standard.number == false
    check loaded.standard.statusLine == false
    check loaded.standard.syntax == false
    check loaded.standard.indentationLines == false
    check loaded.standard.tabStop == 8
    check loaded.standard.shiftWidth == 4
    check loaded.standard.softTabStop == 4
    check loaded.standard.expandTab == true
    check loaded.standard.sidebar == false
    check loaded.standard.autoCloseParen == false
    check loaded.standard.autoIndent == false
    check loaded.standard.ignorecase == false
    check loaded.standard.smartcase == false
    check loaded.standard.disableChangeCursor == true
    check loaded.standard.liveReloadOfConf == true
    check loaded.standard.incrementalSearch == false
    check loaded.standard.popupWindowInExmode == false
    check loaded.standard.autoDeleteParen == false
    check loaded.standard.liveReloadOfFile == false
    check loaded.standard.mouse == true
    check loaded.standard.lineWrap == false
    check loaded.standard.timeoutlen == 500

suite "Config Validation - Standard section":
  test "Valid Standard config passes validation":
    let tomlStr = """
[Standard]
number = true
tabStop = 4
colorMode = "24bit"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.number == true
    check config.standard.tabStop == 4
    check config.standard.colorMode == cm24bit

  test "lineWrap loads from TOML":
    let tomlStr = """
[Standard]
lineWrap = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.lineWrap == false

  test "lineWrap defaults to true when not specified":
    let tomlStr = """
[Standard]
number = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.lineWrap == true

  test "timeoutlen loads from TOML":
    let tomlStr = """
[Standard]
timeoutlen = 500
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.timeoutlen == 500

  test "timeoutlen defaults to 1000 when not specified":
    let tomlStr = """
[Standard]
number = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.timeoutlen == 1000

  test "timeoutlen = 0 is valid (no timeout)":
    let tomlStr = """
[Standard]
timeoutlen = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.timeoutlen == 0

  test "timeoutlen negative value is detected":
    let tomlStr = """
[Standard]
timeoutlen = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.timeoutlen" in vr.errors[0].name
    check config.standard.timeoutlen == 1000 # Default value

  test "Invalid bool type is detected":
    let tomlStr = """
[Standard]
number = "true"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check vr.errors.len == 1
    check "Standard.number" in vr.errors[0].name

  test "shiftWidth loads from TOML":
    let tomlStr = """
[Standard]
shiftWidth = 4
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.shiftWidth == 4

  test "softTabStop loads from TOML":
    let tomlStr = """
[Standard]
softTabStop = 4
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.softTabStop == 4

  test "shiftWidth defaults to 0 when not specified":
    let tomlStr = """
[Standard]
number = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.shiftWidth == 0

  test "softTabStop defaults to 0 when not specified":
    let tomlStr = """
[Standard]
number = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.softTabStop == 0

  test "Invalid shiftWidth (negative) is detected":
    let tomlStr = """
[Standard]
shiftWidth = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check config.standard.shiftWidth == 0 # Default value

  test "Invalid softTabStop (negative) is detected":
    let tomlStr = """
[Standard]
softTabStop = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check config.standard.softTabStop == 0 # Default value

  test "Invalid tabStop (zero) is detected":
    let tomlStr = """
[Standard]
tabStop = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.tabStop" in vr.errors[0].name
    # Invalid value should be skipped, default used
    check config.standard.tabStop == 2 # Default value

  test "Invalid tabStop (negative) is detected":
    let tomlStr = """
[Standard]
tabStop = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.tabStop" in vr.errors[0].name
    check config.standard.tabStop == 2 # Default value

  test "Invalid colorMode enum is detected":
    let tomlStr = """
[Standard]
colorMode = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.colorMode" in vr.errors[0].name
    check config.standard.colorMode == cm256color # Default value

  test "Invalid cursorType enum is detected":
    let tomlStr = """
[Standard]
defaultCursor = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.defaultCursor" in vr.errors[0].name
    check config.standard.defaultCursor == ctTerminalDefault # Default value

suite "Config Validation - BufferBackend section":
  test "Valid bufferBackend auto":
    let tomlStr = """
[BufferBackend]
kind = "auto"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.bufferBackend.kind == bbcAuto

  test "Valid bufferBackend gapBuffer":
    let tomlStr = """
[BufferBackend]
kind = "gapBuffer"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.bufferBackend.kind == bbcGapBuffer

  test "Valid bufferBackend sqrtDecomp":
    let tomlStr = """
[BufferBackend]
kind = "sqrtDecomp"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.bufferBackend.kind == bbcSqrtDecomp

  test "Valid bufferBackend rope":
    let tomlStr = """
[BufferBackend]
kind = "rope"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.bufferBackend.kind == bbcRope

  test "Valid bufferBackend pieceTable":
    let tomlStr = """
[BufferBackend]
kind = "pieceTable"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.bufferBackend.kind == bbcPieceTable

  test "Invalid bufferBackend enum is detected":
    let tomlStr = """
[BufferBackend]
kind = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "BufferBackend.kind" in vr.errors[0].name
    check config.bufferBackend.kind == bbcAuto # Default value

suite "Config Validation - Clipboard section":
  test "Valid Clipboard config passes validation":
    let tomlStr = """
[Clipboard]
enable = true
tool = "xsel"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.clipboard.enable == true
    check config.clipboard.tool == cbtXsel

  test "Invalid clipboard tool is detected":
    let tomlStr = """
[Clipboard]
tool = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Clipboard.tool" in vr.errors[0].name
    # Default value depends on system (detectClipboardTool), just check it's a valid enum
    check config.clipboard.tool in {cbtXsel, cbtXclip, cbtWlClipboard}

suite "Config Validation - AutoBackup section":
  test "Valid AutoBackup config passes validation":
    let tomlStr = """
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
    let tomlStr = """
[AutoBackup]
idleTime = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "AutoBackup.idleTime" in vr.errors[0].name
    check config.autoBackup.idleTime == 10 # Default value

  test "Invalid dirToExclude type (not array) is detected":
    let tomlStr = """
[AutoBackup]
dirToExclude = "/etc"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "AutoBackup.dirToExclude" in vr.errors[0].name

suite "Config Validation - SmoothScroll section":
  test "Valid SmoothScroll config passes validation":
    let tomlStr = """
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
    let tomlStr = """
[SmoothScroll]
friction = -1.0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "SmoothScroll.friction" in vr.errors[0].name
    check config.smoothScroll.friction == 80.0 # Default value

suite "Config Validation - Highlight section":
  test "Valid Highlight config passes validation":
    let tomlStr = """
[Highlight]
currentLine = true
reservedWord = ["TODO", "FIXME"]
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.highlight.currentLine == true
    check config.highlight.reservedWord == @["TODO", "FIXME"]

  test "findCharHighlight loads from TOML":
    let tomlStr = """
[Highlight]
findCharHighlight = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.highlight.findCharHighlight == false

  test "Invalid reservedWord (not array) is detected":
    let tomlStr = """
[Highlight]
reservedWord = "TODO"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Highlight.reservedWord" in vr.errors[0].name

  test "colorCodeHighlight loads true from TOML":
    let tomlStr = """
[Highlight]
colorCodeHighlight = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.highlight.colorCodeHighlight == true

  test "colorCodeHighlight loads false from TOML":
    let tomlStr = """
[Highlight]
colorCodeHighlight = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.highlight.colorCodeHighlight == false

  test "colorCodeHighlight defaults to true":
    let tomlStr = """
[Highlight]
currentLine = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.highlight.colorCodeHighlight == true

suite "Config Validation - LSP section":
  test "Valid LSP config passes validation":
    let tomlStr = """
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
    let tomlStr = """
[Lsp]
timeout = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Lsp.timeout" in vr.errors[0].name
    check config.lsp.timeout == 30000 # Default value

  test "Negative LSP timeout is rejected":
    let tomlStr = """
[Lsp]
timeout = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Lsp.timeout" in vr.errors[0].name
    check config.lsp.timeout == 30000 # Default value

  test "Loader accepts any positive LSP timeout (no upper bound)":
    # timeout has no upper bound anywhere: only correctness matters (> 0), and
    # any positive value is safe (no overflow/crash).
    for v in [1, 60001, 600000]:
      let tomlStr =
        """
[Lsp]
timeout = """ & $v & "\n"
      let (config, vr) = loadFromTomlString(tomlStr)
      check not vr.hasErrors
      check config.lsp.timeout == v

  test "Language server config validation":
    let tomlStr = """
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
    let tomlStr = """
[Lsp.nim]
trace = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Lsp.nim.trace" in vr.errors[0].name
    check config.lsp.servers["nim"].trace == ltOff # Default value

  test "Every feature sub-table is loaded":
    ## Every table must be accepted and must drive its own `enable`. Both
    ## values are exercised: one feature defaults to false, so a single pass
    ## cannot tell "loaded" from "left at its default".
    for want in [false, true]:
      var tomlStr = "[Lsp]\nenable = true\n"
      for name in LspFeatureTableNames:
        tomlStr &= "\n[Lsp." & name & "]\nenable = " & $want & "\n"

      let (config, vr) = loadFromTomlString(tomlStr)
      check not vr.hasErrors
      for name, value in fieldPairs(config.lsp):
        when value is LspFeatureConfig or value is LspOpenWindowConfig or
            value is LspDiagnosticsConfig:
          if value.enable != want:
            echo "Lsp feature table not loaded: " & name
          check value.enable == want

  test "Scalar value where a feature sub-table is expected is reported":
    ## `getTable` returns an empty default for a non-table and the name is a
    ## known key, so without a kind check the line would vanish with no notice.
    let tomlStr = """
[Lsp]
Hover = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.errors.anyIt(
      it.kind == iikInvalidValue and it.name == "Lsp.Hover" and it.expected == "table"
    )
    check config.lsp.hover.enable # Default kept

  test "Unknown key inside a feature sub-table is reported under that table":
    let tomlStr = """
[Lsp.Hover]
enabel = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check vr.errors.anyIt(it.kind == iikUnknownKey and it.name == "Lsp.Hover.enabel")

  test "Misspelled feature table is not absorbed as a language server":
    ## `[Lsp.Completin]` has no language-server key, so it must surface as an
    ## unknown key rather than silently becoming a server entry.
    let tomlStr = """
[Lsp.Completin]
enable = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check vr.errors.anyIt(it.kind == iikUnknownKey and it.name == "Lsp.Completin")
    check not config.lsp.servers.hasKey("Completin")

  test "Negative Lsp.Diagnostics.autoHoverDelay is rejected":
    let tomlStr = """
[Lsp.Diagnostics]
autoHoverDelay = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Lsp.Diagnostics.autoHoverDelay" in vr.errors[0].name
    check config.lsp.diagnostics.autoHoverDelay == 300 # Default value

suite "Config Validation - Multiple errors":
  test "Multiple errors are collected":
    let tomlStr = """
[Standard]
tabStop = 0
colorMode = "invalid"
number = "not_bool"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check vr.errors.len == 3

  test "Error messages are generated for all errors":
    let tomlStr = """
[Standard]
tabStop = 0
colorMode = "invalid"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    let messages = vr.toErrorMessages
    check messages.len == 2

suite "Config Loading - Integration":
  test "loadConfigFromToml with valid config":
    let testFile = getTempDir() / "moe_test_valid_config.toml"
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
    check config.clipboard.tool == cbtXsel

  test "loadConfigFromToml with invalid values uses defaults":
    let testFile = getTempDir() / "moe_test_invalid_config.toml"
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
    check config.standard.colorMode == cm256color # Default value

  test "loadConfigFromToml with non-existent file returns defaults":
    let loadResult = loadConfigFromToml("/nonexistent/path/config.toml")
    check loadResult.isOk
    let (config, vr) = loadResult.get
    check not vr.hasErrors # No errors for non-existent file
    check config.standard.tabStop == 2 # Default value

suite "Config Validation - BuildOnSave section":
  test "Valid BuildOnSave config passes validation":
    let tomlStr = """
[BuildOnSave]
enable = true
command = "make build"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.buildOnSave.enable == true
    check config.buildOnSave.command == some("make build")

  test "Invalid enable type is detected":
    let tomlStr = """
[BuildOnSave]
enable = "true"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "BuildOnSave.enable" in vr.errors[0].name

  test "Invalid command type is detected":
    let tomlStr = """
[BuildOnSave]
command = 123
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "BuildOnSave.command" in vr.errors[0].name

  test "timeout is loaded and zero means no timeout":
    let tomlStr = """
[BuildOnSave]
timeout = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.buildOnSave.timeout == 0

  test "Invalid timeout (negative) is detected":
    let tomlStr = """
[BuildOnSave]
timeout = -5
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "BuildOnSave.timeout" in vr.errors[0].name
    check config.buildOnSave.timeout == 300 # Default value

suite "Config Validation - StatusLine section":
  test "Valid StatusLine config passes validation":
    let tomlStr = """
[StatusLine]
multipleStatusLine = true
merge = false
mode = true
filename = true
changedMark = true
directory = true
gitChangedLines = true
gitBranchName = true
showGitInactive = false
showModeInactive = false
setupText = "{lineNumber}/{totalLines}"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.statusLine.multipleStatusLine == true
    check config.statusLine.merge == false
    check config.statusLine.mode == true
    check config.statusLine.setupText == "{lineNumber}/{totalLines}"

  test "Invalid setupText type is detected":
    let tomlStr = """
[StatusLine]
setupText = 123
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "StatusLine.setupText" in vr.errors[0].name

suite "Config Validation - Git section":
  test "Valid Git config passes validation":
    let tomlStr = """
[Git]
showChangedLine = true
updateInterval = 500
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.git.showChangedLine == true
    check config.git.updateInterval == 500

  test "Invalid updateInterval (zero) is detected":
    let tomlStr = """
[Git]
updateInterval = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Git.updateInterval" in vr.errors[0].name
    check config.git.updateInterval == 1000 # Default value

  test "Invalid updateInterval (negative) is detected":
    let tomlStr = """
[Git]
updateInterval = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Git.updateInterval" in vr.errors[0].name
    check config.git.updateInterval == 1000 # Default value

suite "Config Validation - SyntaxChecker section":
  test "Valid SyntaxChecker config passes validation":
    let tomlStr = """
[SyntaxChecker]
enable = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.syntaxChecker.enable == true

  test "Invalid enable type is detected":
    let tomlStr = """
[SyntaxChecker]
enable = "yes"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "SyntaxChecker.enable" in vr.errors[0].name

  test "timeout is loaded and zero means no timeout":
    let tomlStr = """
[SyntaxChecker]
timeout = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.syntaxChecker.timeout == 0

  test "Invalid timeout (negative) is detected":
    let tomlStr = """
[SyntaxChecker]
timeout = -5
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "SyntaxChecker.timeout" in vr.errors[0].name
    check config.syntaxChecker.timeout == 60 # Default value

suite "Config Validation - Theme section":
  test "Valid Theme config with default kind passes validation":
    let tomlStr = """
[Theme]
kind = "default"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.theme.kind == tkDefault

  test "Invalid theme kind is detected":
    let tomlStr = """
[Theme]
kind = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Theme.kind" in vr.errors[0].name
    check config.theme.kind == tkConfig # Default value

suite "Config Validation - AutoSave section":
  test "Valid AutoSave config passes validation":
    let tomlStr = """
[AutoSave]
enable = true
interval = 10
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.autoSave.enable == true
    check config.autoSave.interval == 10

  test "Invalid interval (zero) is detected":
    let tomlStr = """
[AutoSave]
interval = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "AutoSave.interval" in vr.errors[0].name
    check config.autoSave.interval == 5 # Default value

suite "Config Validation - Notification section":
  test "Valid Notification config passes validation":
    let tomlStr = """
[Notification]
screenNotifications = true
logNotifications = false
autoBackupScreenNotify = true
autoBackupLogNotify = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.notification.screenNotifications == true
    check config.notification.logNotifications == false
    check config.notification.autoBackupScreenNotify == true
    check config.notification.autoBackupLogNotify == false

  test "lspForcePopup config loads correctly":
    let tomlStr = """
[Notification]
lspForcePopup = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.notification.lspForcePopup == true

  test "lspForcePopup disabled":
    let tomlStr = """
[Notification]
lspForcePopup = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.notification.lspForcePopup == false

  test "Invalid bool type is detected":
    let tomlStr = """
[Notification]
screenNotifications = "yes"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Notification.screenNotifications" in vr.errors[0].name

suite "Config Validation - Filer section":
  test "Valid Filer config passes validation":
    let tomlStr = """
[Filer]
showIcons = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.filer.showIcons == true

  test "Invalid showIcons type is detected":
    let tomlStr = """
[Filer]
showIcons = "yes"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Filer.showIcons" in vr.errors[0].name

suite "Config Validation - Autocomplete section":
  test "Valid Autocomplete config passes validation":
    let tomlStr = """
[Autocomplete]
enable = true
windowBorder = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.autocomplete.enable == true
    check config.autocomplete.windowBorder == false

  test "Invalid enable type is detected":
    let tomlStr = """
[Autocomplete]
enable = 1
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Autocomplete.enable" in vr.errors[0].name

suite "Config Validation - Persist section":
  test "Valid Persist config passes validation":
    let tomlStr = """
[Persist]
commandHistory = true
commandHistoryLimit = 500
search = true
searchHistoryLimit = 500
cursorPosition = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.persist.commandHistory == true
    check config.persist.commandHistoryLimit == 500
    check config.persist.search == true
    check config.persist.searchHistoryLimit == 500
    check config.persist.cursorPosition == true

  test "Invalid commandHistoryLimit (zero) is detected":
    let tomlStr = """
[Persist]
commandHistoryLimit = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Persist.commandHistoryLimit" in vr.errors[0].name
    check config.persist.commandHistoryLimit == 1000 # Default value

  test "Invalid searchHistoryLimit (negative) is detected":
    let tomlStr = """
[Persist]
searchHistoryLimit = -10
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Persist.searchHistoryLimit" in vr.errors[0].name
    check config.persist.searchHistoryLimit == 1000 # Default value

suite "Config Validation - QuickRun section":
  test "Valid QuickRun config passes validation":
    let tomlStr = """
[QuickRun]
saveBufferWhenQuickRun = true
command = "make run"
timeout = 60
nimAdvancedCommand = "c"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.quickRun.saveBufferWhenQuickRun == true
    check config.quickRun.command == some("make run")
    check config.quickRun.timeout == 60
    check config.quickRun.nimAdvancedCommand == some("c")

  test "timeout of zero is accepted and means no timeout":
    let tomlStr = """
[QuickRun]
timeout = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.quickRun.timeout == 0

  test "Invalid timeout (negative) is detected":
    let tomlStr = """
[QuickRun]
timeout = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "QuickRun.timeout" in vr.errors[0].name
    check config.quickRun.timeout == 30 # Default value

  test "Invalid command type is detected":
    let tomlStr = """
[QuickRun]
command = 123
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "QuickRun.command" in vr.errors[0].name

suite "Config Validation - TabLine section":
  test "Valid TabLine config passes validation":
    let tomlStr = """
[TabLine]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.tabLine.enable == false

  test "Invalid enable type is detected":
    let tomlStr = """
[TabLine]
enable = "no"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "TabLine.enable" in vr.errors[0].name

suite "Config Validation - StartUp.FileOpen section":
  test "Valid StartUp.FileOpen config passes validation":
    let tomlStr = """
[StartUp.FileOpen]
autoSplit = true
splitType = "horizontal"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.startUpFileOpen.autoSplit == true
    check config.startUpFileOpen.splitType == stHorizontal

  test "Invalid splitType is detected":
    let tomlStr = """
[StartUp.FileOpen]
splitType = "diagonal"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "StartUp.FileOpen.splitType" in vr.errors[0].name
    check config.startUpFileOpen.splitType == stVertical # Default value

suite "Config Validation - StartUp.FileTree section":
  test "Valid StartUp.FileTree config passes validation":
    let tomlStr = """
[StartUp.FileTree]
enable = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.startUpFileTree.enable == true

  test "Default StartUp.FileTree config":
    let tomlStr = ""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.startUpFileTree.enable == false

  test "StartUp.FileTree enable = false":
    let tomlStr = """
[StartUp.FileTree]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.startUpFileTree.enable == false

  test "Unknown key in StartUp.FileTree is detected":
    let tomlStr = """
[StartUp.FileTree]
enable = true
unknownKey = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "StartUp.FileTree.unknownKey":
        found = true
    check found

  test "Unknown key in StartUp section is detected":
    let tomlStr = """
[StartUp.Unknown]
enable = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "StartUp.Unknown":
        found = true
    check found

suite "Config Validation - Debug section":
  test "Valid Debug.WindowNode config passes validation":
    let tomlStr = """
[Debug.WindowNode]
enable = true
currentWindow = true
index = false
windowIndex = true
bufferIndex = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.windowNode.enable == true
    check config.debug.windowNode.currentWindow == true
    check config.debug.windowNode.index == false
    check config.debug.windowNode.windowIndex == true
    check config.debug.windowNode.bufferIndex == false

  test "Valid Debug.EditorView config passes validation":
    let tomlStr = """
[Debug.EditorView]
enable = false
widthOfLineNum = true
height = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.editorView.enable == false
    check config.debug.editorView.widthOfLineNum == true
    check config.debug.editorView.height == false

  test "Valid Debug.BufferStatus config passes validation":
    let tomlStr = """
[Debug.BufferStatus]
enable = true
bufferIndex = false
path = true
openDir = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.bufferStatus.enable == true
    check config.debug.bufferStatus.bufferIndex == false
    check config.debug.bufferStatus.path == true
    check config.debug.bufferStatus.openDir == false

  test "Valid Debug.Search config passes validation":
    let tomlStr = """
[Debug.Search]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.search.enable == false

  test "Valid Debug.MacroState config passes validation":
    let tomlStr = """
[Debug.MacroState]
enable = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.macroState.enable == true

  test "Valid Debug.Visual config passes validation":
    let tomlStr = """
[Debug.Visual]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.visual.enable == false

  test "Valid Debug.JumpList config passes validation":
    let tomlStr = """
[Debug.JumpList]
enable = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.jumpList.enable == true

  test "Valid Debug.Lsp config passes validation":
    let tomlStr = """
[Debug.Lsp]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.lsp.enable == false

  test "Invalid Debug.WindowNode bool type is detected":
    let tomlStr = """
[Debug.WindowNode]
enable = "yes"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Debug.WindowNode.enable" in vr.errors[0].name

suite "Config Validation - Standard section extended":
  test "Valid cursor types pass validation":
    let tomlStr = """
[Standard]
normalModeCursor = "blinkBlock"
insertModeCursor = "blinkIbeam"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.normalModeCursor == ctBlinkBlock
    check config.standard.insertModeCursor == ctBlinkIbeam

  test "All valid colorMode values pass validation":
    for mode in ["8", "16", "256", "24bit", "none"]:
      let tomlStr = "[Standard]\ncolorMode = \"" & mode & "\""
      let (_, vr) = loadFromTomlString(tomlStr)
      check not vr.hasErrors

  test "Invalid integer type (string) is detected":
    let tomlStr = """
[Standard]
tabStop = "four"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.tabStop" in vr.errors[0].name

suite "Config Validation - scrollbarWidth":
  test "Valid scrollbarWidth 0":
    let tomlStr = """
[Standard]
scrollbarWidth = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.scrollbarWidth == 0

  test "Valid scrollbarWidth 1":
    let tomlStr = """
[Standard]
scrollbarWidth = 1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.scrollbarWidth == 1

  test "Valid scrollbarWidth 3":
    let tomlStr = """
[Standard]
scrollbarWidth = 3
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.standard.scrollbarWidth == 3

  test "Invalid scrollbarWidth negative":
    let tomlStr = """
[Standard]
scrollbarWidth = -1
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors

  test "Invalid scrollbarWidth string type":
    let tomlStr = """
[Standard]
scrollbarWidth = "wide"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors

  test "Default scrollbarWidth is 1":
    let config = newEditorConfig()
    check config.standard.scrollbarWidth == 1

suite "Config - getConfigPath":
  test "Path ends with moerc.toml":
    let path = getConfigPath()
    check path.endsWith("moerc.toml")

  test "Path contains moe directory":
    let path = getConfigPath()
    check "moe" in path

  test "Path is not empty":
    let path = getConfigPath()
    check path.len > 0

suite "Config - loadConfig":
  test "loadConfig returns Ok":
    let result = loadConfig()
    check result.isOk

  test "loadConfig returns default values":
    let result = loadConfig()
    check result.isOk
    let (config, _) = result.get
    # tabStop default is 2
    check config.standard.tabStop == 2
    check config.standard.number == true

suite "Config - loadThemeFromToml":
  test "Non-existent file returns error with 'not found'":
    let result = loadThemeFromToml("/nonexistent/path/theme.toml")
    check result.isErr
    check "not found" in result.error.toLowerAscii

  test "Invalid TOML returns error with 'parse'":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_invalid_" & $testFileCounter & ".toml"
    writeFile(testFile, "this is not valid = = = toml [[[")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isErr
    check "parse" in result.error.toLowerAscii

  test "Missing [Colors] section returns error":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_nocolor_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Other]\nkey = \"value\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isErr
    check "Colors" in result.error

  test "Valid [Colors] section returns Ok":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_valid_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"#ff0000\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk

  test "Foreground color override":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_fg_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"#ff0000\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.default].foreground.rgb.red == 255
    check colors[EditorColorPairIndex.default].foreground.rgb.green == 0
    check colors[EditorColorPairIndex.default].foreground.rgb.blue == 0

  test "Background color override":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_bg_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nbackground = \"#00ff00\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.default].background.rgb.green == 255

  test "Keyword foreground via inline table":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_kw_" & $testFileCounter & ".toml"
    writeFile(
      testFile, "[Colors]\nforeground = \"#ffffff\"\nkeyword = { fg = \"#0000ff\" }\n"
    )
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.keyword].foreground.rgb.blue == 255
    check colors[EditorColorPairIndex.keyword].foreground.rgb.red == 0

  test "Keyword background-only via inline table":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_kwbg_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nkeyword = { bg = \"#112233\" }\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.keyword].background.rgb.red == 0x11
    check colors[EditorColorPairIndex.keyword].background.rgb.green == 0x22
    check colors[EditorColorPairIndex.keyword].background.rgb.blue == 0x33

  test "Inline table with fg and bg":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_pair_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nlineNum = { fg = \"#aabbcc\", bg = \"#112233\" }\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.lineNum].foreground.rgb.red == 0xaa
    check colors[EditorColorPairIndex.lineNum].foreground.rgb.green == 0xbb
    check colors[EditorColorPairIndex.lineNum].foreground.rgb.blue == 0xcc
    check colors[EditorColorPairIndex.lineNum].background.rgb.red == 0x11
    check colors[EditorColorPairIndex.lineNum].background.rgb.green == 0x22
    check colors[EditorColorPairIndex.lineNum].background.rgb.blue == 0x33

  test "currentLine sets background of currentLineBg enum":
    # The bg-only enum `currentLineBg` is keyed as `currentLine` in TOML
    # because the new inline-table format expresses bg explicitly.
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_curln_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\ncurrentLine = { bg = \"#3e4452\" }\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.currentLineBg].background.rgb.red == 0x3e
    check colors[EditorColorPairIndex.currentLineBg].background.rgb.green == 0x44
    check colors[EditorColorPairIndex.currentLineBg].background.rgb.blue == 0x52

  test "currentColumn sets background of currentColumnBg enum":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_curcol_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\ncurrentColumn = { bg = \"#3e4452\" }\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.currentColumnBg].background.rgb.red == 0x3e
    check colors[EditorColorPairIndex.currentColumnBg].background.rgb.green == 0x44
    check colors[EditorColorPairIndex.currentColumnBg].background.rgb.blue == 0x52

  test "configModePopup sets both fg and bg of configModePopupBg enum":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_cmpop_" & $testFileCounter & ".toml"
    writeFile(
      testFile, "[Colors]\nconfigModePopup = { fg = \"#ffffff\", bg = \"#323232\" }\n"
    )
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.configModePopupBg].foreground.rgb.red == 0xff
    check colors[EditorColorPairIndex.configModePopupBg].background.rgb.red == 0x32

  test "Bare string for non-default entry is rejected":
    # Pre-rewrite themes used `key = "#hex"`; the new parser requires inline tables.
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_bare_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nkeyword = \"#0000ff\"\n")
    defer:
      removeFile(testFile)

    var vr = newValidationResult()
    let result = loadThemeFromToml(testFile, vr)
    check result.isOk
    check vr.hasErrors
    check vr.errors[0].kind == iikInvalidValue
    check "keyword" in vr.errors[0].name

  test "Unknown sub-key inside inline table is reported":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_unksub_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nkeyword = { fg = \"#0000ff\", bogus = \"x\" }\n")
    defer:
      removeFile(testFile)

    var vr = newValidationResult()
    let result = loadThemeFromToml(testFile, vr)
    check result.isOk
    # fg is still applied; bogus is reported as unknown
    let colors = result.get
    check colors[EditorColorPairIndex.keyword].foreground.rgb.blue == 255
    check vr.errors.len == 1
    check vr.errors[0].kind == iikUnknownKey
    check "keyword.bogus" in vr.errors[0].name

  test "Empty inline table is reported":
    # `keyword = {}` is a no-op (defaults are already applied) and almost
    # always a typo; surface it as an invalid value rather than silently
    # accepting it.
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_empty_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nkeyword = {}\n")
    defer:
      removeFile(testFile)

    var vr = newValidationResult()
    let result = loadThemeFromToml(testFile, vr)
    check result.isOk
    check vr.errors.len == 1
    check vr.errors[0].kind == iikInvalidValue
    check vr.errors[0].name == "Theme.Colors.keyword"
    check vr.errors[0].val == "{}"

  test "Non-string sub-value is reported":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_nonstr_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nkeyword = { fg = 123 }\n")
    defer:
      removeFile(testFile)

    var vr = newValidationResult()
    let result = loadThemeFromToml(testFile, vr)
    check result.isOk
    check vr.errors.len == 1
    check vr.errors[0].kind == iikInvalidValue
    check vr.errors[0].name == "Theme.Colors.keyword.fg"
    # The error message should mention "string" so the user knows the value
    # type is wrong (not just the format).
    check "string" in vr.errors[0].expected

  test "termDefault color is processed (rgb.red == -1)":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_td_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"termDefault\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.default].foreground.rgb.red == -1

  test "Unknown color key is ignored and returns Ok":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_unk_" & $testFileCounter & ".toml"
    writeFile(
      testFile, "[Colors]\nforeground = \"#ffffff\"\nnonExistentKey = \"#123456\"\n"
    )
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk

  test "Unknown color key is reported in ValidationResult":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_unk_vr_" & $testFileCounter & ".toml"
    writeFile(
      testFile, "[Colors]\nforeground = \"#ffffff\"\nnonExistentKey = \"#123456\"\n"
    )
    defer:
      removeFile(testFile)

    var vr = newValidationResult()
    let result = loadThemeFromToml(testFile, vr)
    check result.isOk
    check vr.hasErrors
    check vr.errors.len == 1
    check vr.errors[0].kind == iikUnknownKey
    check "nonExistentKey" in vr.errors[0].name

  test "Invalid color value is reported in ValidationResult":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_theme_badcolor_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nkeyword = { fg = \"notacolor\" }\n")
    defer:
      removeFile(testFile)

    var vr = newValidationResult()
    let result = loadThemeFromToml(testFile, vr)
    check result.isOk
    check vr.hasErrors
    check vr.errors.len == 1
    check vr.errors[0].kind == iikInvalidValue
    check "keyword.fg" in vr.errors[0].name
    check vr.errors[0].val == "notacolor"

  test "Invalid foreground/background values are reported":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_theme_badfgbg_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"badfg\"\nbackground = \"badbg\"\n")
    defer:
      removeFile(testFile)

    var vr = newValidationResult()
    let result = loadThemeFromToml(testFile, vr)
    check result.isOk
    check vr.errors.len == 2
    let names = vr.errors.mapIt(it.name)
    check names.anyIt("foreground" in it)
    check names.anyIt("background" in it)

  test "Valid theme produces no validation errors":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_theme_valid_vr_" & $testFileCounter & ".toml"
    writeFile(
      testFile, "[Colors]\nforeground = \"#ffffff\"\nkeyword = { fg = \"#0000ff\" }\n"
    )
    defer:
      removeFile(testFile)

    var vr = newValidationResult()
    let result = loadThemeFromToml(testFile, vr)
    check result.isOk
    check not vr.hasErrors

suite "Config - loadTheme":
  test "tkDefault returns DefaultColors":
    var config = newEditorConfig()
    config.theme.kind = tkDefault
    let result = loadTheme(config)
    check result.isOk
    let colors = result.get
    check colors == DefaultColors

  test "tkConfig with valid file returns Ok":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_loadtheme_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"#aabbcc\"\n")
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = testFile
    let result = loadTheme(config)
    check result.isOk

  test "tkConfig with non-existent file returns error":
    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = "/nonexistent/theme.toml"
    let result = loadTheme(config)
    check result.isErr

suite "Config - initTheme":
  test "tkDefault does not crash":
    var config = newEditorConfig()
    config.theme.kind = tkDefault
    initTheme(config)

  test "Bootstrap: missing tkConfig file is seeded with DefaultColors":
    inc testFileCounter
    let themeFile =
      getTempDir() / "moe_test_inittheme_bootstrap_" & $testFileCounter & ".toml"
    defer:
      if fileExists(themeFile):
        removeFile(themeFile)

    check not fileExists(themeFile)

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = themeFile
    var vr = newValidationResult()
    initTheme(config, vr)

    check not vr.hasErrors
    check fileExists(themeFile)
    check themeColorsFromFile

    let loaded = loadThemeFromToml(themeFile)
    check loaded.isOk

  test "Bootstrap failure (unwritable path) falls back to default":
    inc testFileCounter
    let notADir = getTempDir() / "moe_test_inittheme_boot_notadir_" & $testFileCounter
    writeFile(notADir, "sentinel")
    defer:
      removeFile(notADir)
    let themeFile = notADir / "theme.toml"

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = themeFile
    initTheme(config)

  test "Bootstrap failure (unwritable path) is reported in ValidationResult":
    inc testFileCounter
    let notADir = getTempDir() / "moe_test_inittheme_boot_report_" & $testFileCounter
    writeFile(notADir, "sentinel")
    defer:
      removeFile(notADir)
    let themeFile = notADir / "theme.toml"

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = themeFile
    var vr = newValidationResult()
    initTheme(config, vr)
    check vr.hasErrors
    check vr.errors.anyIt("Theme.path" in it.name)

  test "Invalid keys in theme file are reported via initTheme":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_inittheme_bad_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"#ffffff\"\nbogusKey = \"#abcdef\"\n")
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = testFile
    var vr = newValidationResult()
    initTheme(config, vr)
    check vr.hasErrors
    check vr.errors.anyIt(it.kind == iikUnknownKey and "bogusKey" in it.name)
    # Should not crash; falls back to default theme

suite "Config - saveConfigToToml":
  test "Save default config to file":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    let result = saveConfigToToml(config, testFile)
    check result.isOk
    check fileExists(testFile)

  test "Saved config is valid TOML and can be reloaded":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_reload_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk

  test "tabStop value round-trips":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_tabstop_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.standard.tabStop = 8
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.standard.tabStop == 8

  test "shiftWidth value round-trips":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_sw_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.standard.shiftWidth = 4
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.standard.shiftWidth == 4

  test "softTabStop value round-trips":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_sts_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.standard.softTabStop = 4
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.standard.softTabStop == 4

  test "Boolean setting round-trips":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_bool_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.standard.number = false
    config.standard.syntax = false
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.standard.number == false
    check loaded.standard.syntax == false

  test "Parent directory is created automatically":
    inc testFileCounter
    let testDir = getTempDir() / "moe_test_save_dir_" & $testFileCounter
    let testFile = testDir / "subdir" / "config.toml"
    defer:
      removeDir(testDir)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    let result = saveConfigToToml(config, testFile)
    check result.isOk
    check fileExists(testFile)

  test "Output contains expected section headers":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_sections_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    let result = saveConfigToToml(config, testFile)
    check result.isOk

    let content = readFile(testFile)
    check "[Standard]" in content
    check "[Clipboard]" in content
    check "[StatusLine]" in content
    check "[Highlight]" in content
    check "[AutoBackup]" in content
    check "[Notification]" in content
    check "[Lsp]" in content

  test "bookmarkMarker containing a double quote round-trips":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_quote_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.standard.bookmarkMarker = "a\"b"
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.standard.bookmarkMarker == "a\"b"

  test "bookmarkMarker containing a backslash round-trips":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_save_backslash_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.standard.bookmarkMarker = "a\\b"
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.standard.bookmarkMarker == "a\\b"

  test "bookmarkMarker containing a newline and tab round-trips":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_newline_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.standard.bookmarkMarker = "a\n\tb"
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.standard.bookmarkMarker == "a\n\tb"

  test "Saved config with special chars in string is still valid TOML":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_special_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    # A pathological value mixing every character class that needs escaping.
    config.standard.bookmarkMarker = "\"\\\t\n\r"
    config.theme.kind = tkDefault
    config.theme.path = ""
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    # The whole file must still parse back without errors.
    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.standard.bookmarkMarker == "\"\\\t\n\r"

suite "Config - escapeTomlBasicString":
  test "Leaves ordinary characters untouched":
    check escapeTomlBasicString("hello world") == "hello world"
    check escapeTomlBasicString("♥ ") == "♥ "

  test "Escapes double quote and backslash":
    check escapeTomlBasicString("a\"b") == "a\\\"b"
    check escapeTomlBasicString("a\\b") == "a\\\\b"

  test "Escapes common control characters":
    check escapeTomlBasicString("\t") == "\\t"
    check escapeTomlBasicString("\n") == "\\n"
    check escapeTomlBasicString("\r") == "\\r"
    check escapeTomlBasicString("\b") == "\\b"
    check escapeTomlBasicString("\f") == "\\f"

  test "Escapes other control characters as \\uXXXX":
    check escapeTomlBasicString("\x00") == "\\u0000"
    check escapeTomlBasicString("\x01") == "\\u0001"
    check escapeTomlBasicString("\x7f") == "\\u007F"

suite "Config - saveConfigToToml round-trip completeness":
  # Recursively modify all fields to non-default values via fieldPairs.
  # When a new field is added to any config type, fieldPairs automatically
  # includes it, so if saveConfigToToml doesn't save it, the round-trip
  # comparison will fail.
  template modifyAllFields(obj: typed) =
    for name, value in fieldPairs(obj):
      when value is bool:
        value = not value
      elif value is int:
        value += 1
      elif value is float:
        value += 1.0
      elif value is string:
        value = value & "_test"
      elif value is Option[string]:
        value = some("test_value")
      elif value is seq[string]:
        value.add("test_entry")
      elif value is Table[string, LspServerConfig]:
        discard # handled separately
      elif value is enum:
        if ord(value) < ord(high(typeof(value))):
          value = succ(value)
        else:
          value = pred(value)
      elif value is object:
        modifyAllFields(value)

  test "All config fields round-trip through save/load":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_roundtrip_all_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()

    # Modify all fields to non-default values
    modifyAllFields(config.standard)
    modifyAllFields(config.clipboard)
    modifyAllFields(config.buildOnSave)
    modifyAllFields(config.tabLine)
    modifyAllFields(config.statusLine)
    modifyAllFields(config.highlight)
    modifyAllFields(config.autoBackup)
    modifyAllFields(config.quickRun)
    modifyAllFields(config.notification)
    modifyAllFields(config.filer)
    modifyAllFields(config.fileTree)
    modifyAllFields(config.autocomplete)
    modifyAllFields(config.autoSave)
    modifyAllFields(config.persist)
    modifyAllFields(config.git)
    modifyAllFields(config.syntaxChecker)
    modifyAllFields(config.smoothScroll)
    modifyAllFields(config.startUpFileOpen)
    modifyAllFields(config.startUpFileTree)
    modifyAllFields(config.editorConfig)
    modifyAllFields(config.log)
    modifyAllFields(config.debug)
    modifyAllFields(config.theme)
    modifyAllFields(config.lsp)

    # Override Option[string] dir paths with real directories
    # (loadOptionDirPath validates directory existence)
    config.buildOnSave.workspaceRoot = some("/tmp")
    config.autoBackup.backupDir = some("/tmp")

    # popupPosition is validated against allowed values on load
    config.notification.popupPosition = "topLeft"

    # Theme: kind = tkDefault keeps `initTheme` from bootstrapping a file at
    # the round-trip test path.
    config.theme.kind = tkDefault
    config.theme.path = "test_theme_path"

    # Add a test LSP server
    config.lsp.servers["testLang"] = LspServerConfig(
      extensions: @[".test"],
      command: "test-lsp",
      trace: ltMessages,
      rustAnalyzerRunSingle: true,
      rustAnalyzerDebugSingle: true,
    )

    # Add command aliases and shell commands
    config.commandAliases["x"] = UserCommandEntry(command: "quit")
    config.shellCommands["nimbuild"] = UserCommandEntry(command: "nimble build")
    config.disabledCommandAliases = @["q"]

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, _) = loadResult.get

    check config.standard == loaded.standard
    check config.clipboard == loaded.clipboard
    check config.buildOnSave == loaded.buildOnSave
    check config.tabLine == loaded.tabLine
    check config.statusLine == loaded.statusLine
    check config.highlight == loaded.highlight
    check config.autoBackup == loaded.autoBackup
    check config.quickRun == loaded.quickRun
    check config.notification == loaded.notification
    check config.filer == loaded.filer
    check config.fileTree == loaded.fileTree
    check config.autocomplete == loaded.autocomplete
    check config.autoSave == loaded.autoSave
    check config.persist == loaded.persist
    check config.git == loaded.git
    check config.syntaxChecker == loaded.syntaxChecker
    check config.smoothScroll == loaded.smoothScroll
    check config.startUpFileOpen == loaded.startUpFileOpen
    check config.startUpFileTree == loaded.startUpFileTree
    check config.editorConfig == loaded.editorConfig
    check config.log == loaded.log
    check config.debug == loaded.debug
    check config.theme == loaded.theme
    check config.lsp == loaded.lsp
    check config.commandAliases == loaded.commandAliases
    check config.shellCommands == loaded.shellCommands
    check config.disabledCommandAliases == loaded.disabledCommandAliases

suite "Config - saveConfig":
  test "Default config does not crash":
    withTempHome(tmpDir):
      let config = newEditorConfig()
      let result = saveConfig(config)
      check result.isOk

suite "Config Validation - Unknown keys":
  test "Unknown top-level section is detected":
    let tomlStr = """
[Standard]
number = true

[Standrd]
number = false
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "Standrd":
        found = true
    check found

  test "Scalar value where a top-level section is expected is reported":
    ## A known section name bound to a scalar passes the unknown-key check, so
    ## the section dispatch has to reject the kind itself.
    let tomlStr = """
Standard = 5
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.errors.anyIt(
      it.kind == iikInvalidValue and it.name == "Standard" and it.expected == "table"
    )
    check config.standard.tabStop == 2 # Default kept

  test "Unknown key in Standard section is detected":
    let tomlStr = """
[Standard]
number = true
tabStp = 4
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "Standard.tabStp":
        found = true
    check found

  test "Unknown key in Highlight section is detected":
    let tomlStr = """
[Highlight]
currentLine = true
colorCodse = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "Highlight.colorCodse":
        found = true
    check found

  test "Unknown key in Clipboard section is detected":
    let tomlStr = """
[Clipboard]
enable = true
unknownKey = "value"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "Clipboard.unknownKey":
        found = true
    check found

  test "Unknown key in Notification section is detected":
    let tomlStr = """
[Notification]
screenNotifications = true
typoKey = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "Notification.typoKey":
        found = true
    check found

  test "Lsp dynamic language server (Table type) is not an error":
    let tomlStr = """
[Lsp]
enable = true

[Lsp.nim]
extensions = [".nim"]
command = "nimlsp"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.lsp.servers.hasKey("nim")

  test "Lsp non-Table unknown key is detected":
    let tomlStr = """
[Lsp]
enable = true
unknownFlag = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "Lsp.unknownFlag":
        found = true
    check found

  test "Unknown Debug sub-section is detected":
    let tomlStr = """
[Debug.WindowNode]
enable = true

[Debug.UnknownSection]
enable = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "Debug.UnknownSection":
        found = true
    check found

  test "Unknown key in Debug.WindowNode is detected":
    let tomlStr = """
[Debug.WindowNode]
enable = true
unknownField = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "Debug.WindowNode.unknownField":
        found = true
    check found

  test "Unknown key in StartUp section is detected":
    let tomlStr = """
[StartUp.FileOpen]
autoSplit = true

[StartUp.UnknownSub]
key = true
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    var found = false
    for e in vr.errors:
      if e.kind == iikUnknownKey and e.name == "StartUp.UnknownSub":
        found = true
    check found

  test "Valid full config has no unknown key errors":
    let tomlStr = """
[Standard]
number = true
tabStop = 4

[Clipboard]
enable = true
tool = "xsel"

[StatusLine]
multipleStatusLine = true

[Git]
showChangedLine = true
updateInterval = 500

[Lsp]
enable = true

[Lsp.Completion]
enable = true

[Lsp.nim]
extensions = [".nim"]
command = "nimlsp"

[Debug.WindowNode]
enable = true

[StartUp.FileOpen]
autoSplit = true
splitType = "vertical"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors

  test "toErrorMessage for unknown key":
    let item = InvalidItem(kind: iikUnknownKey, name: "Standard.typo")
    let msg = item.toErrorMessage
    check "Unknown key" in msg
    check "Standard.typo" in msg

  test "toErrorMessage for invalid value (backward compat)":
    let item = InvalidItem(
      kind: iikInvalidValue,
      name: "Standard.tabStop",
      val: "0",
      expected: "integer >= 1",
    )
    let msg = item.toErrorMessage
    check "Invalid value" in msg
    check "Standard.tabStop" in msg

suite "Config - saveThemeToToml":
  test "Save DefaultColors to file":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_theme_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let result = saveThemeToToml(DefaultColors, testFile)
    check result.isOk
    check fileExists(testFile)

  test "Saved theme file contains [Colors] section":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_save_theme_section_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let result = saveThemeToToml(DefaultColors, testFile)
    check result.isOk

    let content = readFile(testFile)
    check "[Colors]" in content
    check "foreground = " in content
    check "background = " in content

  test "Saved theme can be reloaded":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_save_theme_reload_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let saveResult = saveThemeToToml(DefaultColors, testFile)
    check saveResult.isOk

    let loadResult = loadThemeFromToml(testFile)
    check loadResult.isOk

  test "Color values round-trip":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_theme_rt_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let saveResult = saveThemeToToml(DefaultColors, testFile)
    check saveResult.isOk

    let loadResult = loadThemeFromToml(testFile)
    check loadResult.isOk
    let loaded = loadResult.get

    # Check all color pairs match
    for index in EditorColorPairIndex:
      check DefaultColors[index].foreground.rgb == loaded[index].foreground.rgb
      check DefaultColors[index].background.rgb == loaded[index].background.rgb

  test "Custom colors round-trip":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_save_theme_custom_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var colors = DefaultColors
    colors[EditorColorPairIndex.keyword].foreground =
      ThemeColor(rgb: Rgb(red: 0x12, green: 0x34, blue: 0x56))
    colors[EditorColorPairIndex.keyword].background =
      ThemeColor(rgb: Rgb(red: 0xab, green: 0xcd, blue: 0xef))

    let saveResult = saveThemeToToml(colors, testFile)
    check saveResult.isOk

    let loadResult = loadThemeFromToml(testFile)
    check loadResult.isOk
    let loaded = loadResult.get

    check loaded[EditorColorPairIndex.keyword].foreground.rgb ==
      Rgb(red: 0x12, green: 0x34, blue: 0x56)
    check loaded[EditorColorPairIndex.keyword].background.rgb ==
      Rgb(red: 0xab, green: 0xcd, blue: 0xef)

  test "termDefault color round-trip":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_save_theme_td_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var colors = DefaultColors
    colors[EditorColorPairIndex.default].foreground =
      ThemeColor(rgb: TerminalDefaultRgb)
    colors[EditorColorPairIndex.default].background =
      ThemeColor(rgb: TerminalDefaultRgb)

    let saveResult = saveThemeToToml(colors, testFile)
    check saveResult.isOk

    let content = readFile(testFile)
    check "\"termDefault\"" in content

    let loadResult = loadThemeFromToml(testFile)
    check loadResult.isOk
    let loaded = loadResult.get
    check loaded[EditorColorPairIndex.default].foreground.rgb == TerminalDefaultRgb
    check loaded[EditorColorPairIndex.default].background.rgb == TerminalDefaultRgb

  test "Parent directory is created automatically":
    inc testFileCounter
    let testDir = getTempDir() / "moe_test_save_theme_dir_" & $testFileCounter
    let testFile = testDir / "subdir" / "theme.toml"
    defer:
      removeDir(testDir)

    let result = saveThemeToToml(DefaultColors, testFile)
    check result.isOk
    check fileExists(testFile)

  test "Backup file is created when original exists":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_save_theme_bac_" & $testFileCounter & ".toml"
    let backupFile = testFile & ".bac"
    defer:
      removeFile(testFile)
      removeFile(backupFile)

    # Write initial theme file
    let firstResult = saveThemeToToml(DefaultColors, testFile)
    check firstResult.isOk
    check fileExists(testFile)
    check not fileExists(backupFile)

    let originalContent = readFile(testFile)

    # Save again with different colors - should create backup
    var colors = DefaultColors
    colors[EditorColorPairIndex.keyword].foreground =
      ThemeColor(rgb: Rgb(red: 0xff, green: 0x00, blue: 0x00))

    let secondResult = saveThemeToToml(colors, testFile)
    check secondResult.isOk
    check fileExists(backupFile)

    # Backup should contain the original content
    check readFile(backupFile) == originalContent
    # New file should differ
    check readFile(testFile) != originalContent

  test "No backup file when original does not exist":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_save_theme_nobac_" & $testFileCounter & ".toml"
    let backupFile = testFile & ".bac"
    defer:
      removeFile(testFile)
      if fileExists(backupFile):
        removeFile(backupFile)

    let result = saveThemeToToml(DefaultColors, testFile)
    check result.isOk
    check fileExists(testFile)
    check not fileExists(backupFile)

suite "Config - saveConfigToToml saves theme file":
  test "Theme file is saved when kind is tkConfig with path":
    inc testFileCounter
    let configFile =
      getTempDir() / "moe_test_save_cfg_theme_" & $testFileCounter & ".toml"
    let themeFile =
      getTempDir() / "moe_test_save_cfg_theme_colors_" & $testFileCounter & ".toml"
    defer:
      removeFile(configFile)
      removeFile(themeFile)

    # Set up global themeColors
    setThemeColors(DefaultColors)

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = themeFile

    let result = saveConfigToToml(config, configFile)
    check result.isOk
    check fileExists(themeFile)

    # Verify the theme file can be loaded
    let loadResult = loadThemeFromToml(themeFile)
    check loadResult.isOk

  test "Theme file is not saved when kind is tkDefault":
    inc testFileCounter
    let configFile =
      getTempDir() / "moe_test_save_cfg_no_theme_" & $testFileCounter & ".toml"
    let themeFile =
      getTempDir() / "moe_test_save_cfg_no_theme_colors_" & $testFileCounter & ".toml"
    defer:
      removeFile(configFile)
      if fileExists(themeFile):
        removeFile(themeFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = themeFile

    let result = saveConfigToToml(config, configFile)
    check result.isOk
    check not fileExists(themeFile)

  test "Theme file is not saved when path is empty":
    inc testFileCounter
    let configFile =
      getTempDir() / "moe_test_save_cfg_empty_path_" & $testFileCounter & ".toml"
    defer:
      removeFile(configFile)

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = ""

    let result = saveConfigToToml(config, configFile)
    check result.isOk

  test "Existing theme file is preserved when initTheme fell back to defaults":
    # Regression: pre-fix, saveConfigToToml unconditionally overwrote the
    # user's theme file with DefaultColors after any tkConfig load failure.
    inc testFileCounter
    let configFile =
      getTempDir() / "moe_test_save_cfg_theme_survive_" & $testFileCounter & ".toml"
    let themeFile =
      getTempDir() / "moe_test_save_cfg_theme_survive_colors_" & $testFileCounter &
      ".toml"
    defer:
      removeFile(configFile)
      removeFile(themeFile)
      if fileExists(themeFile & ".bac"):
        removeFile(themeFile & ".bac")

    let userThemeToml = """
[Colors]
foreground = "#abcdef"
background = "#123456"
"""
    writeFile(themeFile, userThemeToml)

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = themeFile

    setThemeColors(DefaultColors)
    themeColorsFromFile = false

    let result = saveConfigToToml(config, configFile)
    check result.isOk
    check readFile(themeFile) == userThemeToml

  test "Bootstrap: theme file is written when it doesn't exist yet":
    inc testFileCounter
    let configFile =
      getTempDir() / "moe_test_save_cfg_theme_bootstrap_" & $testFileCounter & ".toml"
    let themeFile =
      getTempDir() / "moe_test_save_cfg_theme_bootstrap_colors_" & $testFileCounter &
      ".toml"
    defer:
      removeFile(configFile)
      if fileExists(themeFile):
        removeFile(themeFile)

    check not fileExists(themeFile)

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = themeFile

    setThemeColors(DefaultColors)
    themeColorsFromFile = false

    let result = saveConfigToToml(config, configFile)
    check result.isOk
    check fileExists(themeFile)
    check loadThemeFromToml(themeFile).isOk

suite "Config Validation - KeyMapping section":
  test "Normal key mappings":
    let toml = """
[KeyMapping.Normal]
"C-s" = "save"
"jj" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal].len == 2
    check config.keyMapping.perMode[Normal]["C-s"].rhs == "save"
    check config.keyMapping.perMode[Normal]["jj"].rhs == "Escape"

  test "QuickRun/BookmarkManager/FileTree modes are mappable (parity)":
    # These three modes were mappable via the old keybindings.toml [[keybinding]]
    # surface; the unified [KeyMapping] surface must accept them too.
    let toml = """
[KeyMapping.QuickRun]
"q" = "Escape"

[KeyMapping.BookmarkManager]
"d" = "Escape"

[KeyMapping.FileTree]
"r" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[QuickRun]["q"].rhs == "Escape"
    check config.keyMapping.perMode[BookmarkManager]["d"].rhs == "Escape"
    check config.keyMapping.perMode[FileTree]["r"].rhs == "Escape"

  test "All modes":
    let toml = """
[KeyMapping.Normal]
"C-s" = "save"

[KeyMapping.Insert]
"jj" = "Escape"

[KeyMapping.Visual]
"C-c" = "Escape"

[KeyMapping.VisualAll]
"C-a" = "Escape"

[KeyMapping.VisualLine]
"C-c" = "Escape"

[KeyMapping.VisualBlock]
"C-c" = "Escape"

[KeyMapping.Replace]
"C-c" = "Escape"

[KeyMapping.Command]
"C-a" = "Home"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal].len == 1
    check config.keyMapping.perMode[Insert].len == 1
    check config.keyMapping.perMode[Visual].len == 1
    check config.keyMapping.visualAll.len == 1
    check config.keyMapping.perMode[VisualLine].len == 1
    check config.keyMapping.perMode[VisualBlock].len == 1
    check config.keyMapping.perMode[Replace].len == 1
    check config.keyMapping.perMode[Command].len == 1
    check config.keyMapping.perMode[Normal]["C-s"].rhs == "save"
    check config.keyMapping.perMode[Insert]["jj"].rhs == "Escape"
    check config.keyMapping.perMode[Visual]["C-c"].rhs == "Escape"
    check config.keyMapping.visualAll["C-a"].rhs == "Escape"
    check config.keyMapping.perMode[VisualLine]["C-c"].rhs == "Escape"
    check config.keyMapping.perMode[VisualBlock]["C-c"].rhs == "Escape"
    check config.keyMapping.perMode[Replace]["C-c"].rhs == "Escape"
    check config.keyMapping.perMode[Command]["C-a"].rhs == "Home"

  test "Empty KeyMapping section":
    let toml = """
[KeyMapping]
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.all.len == 0
    check config.keyMapping.perMode[Normal].len == 0
    check config.keyMapping.perMode[Insert].len == 0
    check config.keyMapping.perMode[Visual].len == 0
    check config.keyMapping.visualAll.len == 0
    check config.keyMapping.perMode[VisualLine].len == 0
    check config.keyMapping.perMode[VisualBlock].len == 0
    check config.keyMapping.perMode[Replace].len == 0
    check config.keyMapping.perMode[Command].len == 0

  test "No KeyMapping section uses defaults":
    let toml = """
[Standard]
number = true
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.all.len == 0
    check config.keyMapping.perMode[Normal].len == 0
    check config.keyMapping.perMode[Insert].len == 0
    check config.keyMapping.perMode[Visual].len == 0
    check config.keyMapping.visualAll.len == 0
    check config.keyMapping.perMode[VisualLine].len == 0
    check config.keyMapping.perMode[VisualBlock].len == 0
    check config.keyMapping.perMode[Replace].len == 0
    check config.keyMapping.perMode[Command].len == 0
    check config.keyMapping.perMode[Filer].len == 0
    check config.keyMapping.perMode[LogViewer].len == 0
    check config.keyMapping.perMode[Help].len == 0
    check config.keyMapping.perMode[BufferManager].len == 0
    check config.keyMapping.perMode[BackupManager].len == 0
    check config.keyMapping.perMode[DiffViewer].len == 0
    check config.keyMapping.perMode[Config].len == 0
    check config.keyMapping.perMode[References].len == 0
    check config.keyMapping.perMode[DocumentSymbol].len == 0
    check config.keyMapping.perMode[CallHierarchy].len == 0
    check config.keyMapping.perMode[RecentFile].len == 0
    check config.keyMapping.perMode[Debug].len == 0
    check config.keyMapping.perMode[Terminal].len == 0

  test "Unknown mode name reports error":
    let toml = """
[KeyMapping.Unknown]
"C-s" = "save"
"""
    let (_, vr) = loadFromTomlString(toml)
    check vr.hasErrors
    let errorNames = vr.errors.mapIt(it.name)
    check "KeyMapping.Unknown" in errorNames

  test "Non-string value reports error":
    let toml = """
[KeyMapping.Normal]
"C-s" = 42
"""
    let (_, vr) = loadFromTomlString(toml)
    check vr.hasErrors
    let errorNames = vr.errors.mapIt(it.name)
    check "KeyMapping.Normal.C-s" in errorNames

  test "Invalid LHS key reports error":
    let toml = """
[KeyMapping.Normal]
"C-1" = "save"
"""
    let (_, vr) = loadFromTomlString(toml)
    check vr.hasErrors
    let errorNames = vr.errors.mapIt(it.name)
    check "KeyMapping.Normal.C-1" in errorNames

  test "Bare unknown RHS is accepted (validated at apply time)":
    # Command existence is no longer checked at load; the RHS is stored verbatim
    # and resolved against the real registry when applyKeyMappings runs.
    let toml = """
[KeyMapping.Normal]
"C-s" = "not-a-command"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal]["C-s"].rhs == "not-a-command"

  test "Valid command name RHS passes validation":
    let toml = """
[KeyMapping.Normal]
"C-s" = "save"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal]["C-s"].rhs == "save"

  test "Valid key sequence RHS passes validation":
    let toml = """
[KeyMapping.Insert]
"jj" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Insert]["jj"].rhs == "Escape"

  test "S-j to bnext passes validation (#2597)":
    let toml = """
[KeyMapping.Normal]
"S-j" = "bnext"
"S-k" = "bprev"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal]["S-j"].rhs == "bnext"
    check config.keyMapping.perMode[Normal]["S-k"].rhs == "bprev"

  test "J to bnext passes validation (#2597)":
    let toml = """
[KeyMapping.Normal]
"J" = "bnext"
"K" = "bprev"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal]["J"].rhs == "bnext"
    check config.keyMapping.perMode[Normal]["K"].rhs == "bprev"

  test "Unknown identifier-like RHS is accepted verbatim (#2597 policy)":
    # The load-time vim-concat heuristic was removed: an unknown identifier-like
    # RHS such as "bnxt" is stored as-is and resolved at apply time (where it
    # falls through to a key sequence) rather than rejected here.
    let toml = """
[KeyMapping.Normal]
"S-j" = "bnxt"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal]["S-j"].rhs == "bnxt"

  test "Vim-style 2-char concat (jj/gd) still allowed as key sequence":
    let toml = """
[KeyMapping.Insert]
"C-a" = "jj"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Insert]["C-a"].rhs == "jj"

  test "Short Command mode command aliases bd/q/wq pass validation (#2597)":
    # PR #2598 had registered only bnext/bprev/bprevious, so 1-2 char aliases
    # like `bd`, `q`, `wq` silently fell through to Vim concat. They are now
    # registered as Commands and must be accepted as command-name targets.
    let toml = """
[KeyMapping.Normal]
"D" = "bd"
"Q" = "q"
"F2" = "wq"
"X" = "bdelete"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal]["D"].rhs == "bd"
    check config.keyMapping.perMode[Normal]["Q"].rhs == "q"
    check config.keyMapping.perMode[Normal]["F2"].rhs == "wq"
    check config.keyMapping.perMode[Normal]["X"].rhs == "bdelete"

  test "Unknown 2-char RHS is still accepted as key sequence (#2597 policy)":
    # Policy decision: 2-char Vim concat (`jj`, `gd` etc.) is preserved for
    # backwards compat. Unknown 2-char tokens like `bx` therefore still pass
    # validation as a key sequence (`b` then `x`). Only 3+ char identifier-
    # like unknown tokens are rejected so users notice command typos.
    let toml = """
[KeyMapping.Normal]
"K" = "bx"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Normal]["K"].rhs == "bx"

  test "All key mappings":
    let toml = """
[KeyMapping.All]
"C-s" = "save"
"C-q" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.all.len == 2
    check config.keyMapping.all["C-s"].rhs == "save"
    check config.keyMapping.all["C-q"].rhs == "Escape"

  test "All with mode-specific coexistence":
    let toml = """
[KeyMapping.All]
"C-s" = "save"

[KeyMapping.Normal]
"C-n" = "Escape"

[KeyMapping.Insert]
"jj" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.all.len == 1
    check config.keyMapping.all["C-s"].rhs == "save"
    check config.keyMapping.perMode[Normal].len == 1
    check config.keyMapping.perMode[Normal]["C-n"].rhs == "Escape"
    check config.keyMapping.perMode[Insert].len == 1
    check config.keyMapping.perMode[Insert]["jj"].rhs == "Escape"

  test "Empty All section":
    let toml = """
[KeyMapping.All]
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.all.len == 0

  test "VisualLine key mappings":
    let toml = """
[KeyMapping.VisualLine]
"C-c" = "Escape"
"C-y" = "visual-yank"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[VisualLine].len == 2
    check config.keyMapping.perMode[VisualLine]["C-c"].rhs == "Escape"
    check config.keyMapping.perMode[VisualLine]["C-y"].rhs == "visual-yank"

  test "VisualBlock key mappings":
    let toml = """
[KeyMapping.VisualBlock]
"C-c" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[VisualBlock].len == 1
    check config.keyMapping.perMode[VisualBlock]["C-c"].rhs == "Escape"

  test "VisualAll key mappings":
    let toml = """
[KeyMapping.VisualAll]
"C-c" = "Escape"
"C-y" = "visual-yank"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.visualAll.len == 2
    check config.keyMapping.visualAll["C-c"].rhs == "Escape"
    check config.keyMapping.visualAll["C-y"].rhs == "visual-yank"

  test "VisualAll with mode-specific coexistence":
    let toml = """
[KeyMapping.VisualAll]
"C-c" = "Escape"

[KeyMapping.Visual]
"C-v" = "save"

[KeyMapping.VisualLine]
"C-l" = "Escape"

[KeyMapping.VisualBlock]
"C-b" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.visualAll.len == 1
    check config.keyMapping.visualAll["C-c"].rhs == "Escape"
    check config.keyMapping.perMode[Visual].len == 1
    check config.keyMapping.perMode[Visual]["C-v"].rhs == "save"
    check config.keyMapping.perMode[VisualLine].len == 1
    check config.keyMapping.perMode[VisualLine]["C-l"].rhs == "Escape"
    check config.keyMapping.perMode[VisualBlock].len == 1
    check config.keyMapping.perMode[VisualBlock]["C-b"].rhs == "Escape"

  test "Bare unknown RHS is accepted in VisualAll/VisualLine/VisualBlock":
    # Like Normal, command existence is not checked at load for these modes.
    let toml = """
[KeyMapping.VisualAll]
"C-s" = "not-a-command"

[KeyMapping.VisualLine]
"C-l" = "not-a-command"

[KeyMapping.VisualBlock]
"C-b" = "not-a-command"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.visualAll["C-s"].rhs == "not-a-command"
    check config.keyMapping.perMode[VisualLine]["C-l"].rhs == "not-a-command"
    check config.keyMapping.perMode[VisualBlock]["C-b"].rhs == "not-a-command"

  test "Filer key mappings":
    let toml = """
[KeyMapping.Filer]
"C-s" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Filer].len == 1
    check config.keyMapping.perMode[Filer]["C-s"].rhs == "Escape"

  test "Multiple special mode key mappings":
    let toml = """
[KeyMapping.Filer]
"C-s" = "Escape"

[KeyMapping.LogViewer]
"C-c" = "Escape"

[KeyMapping.Help]
"C-c" = "Escape"

[KeyMapping.BufferManager]
"C-c" = "Escape"

[KeyMapping.BackupManager]
"C-c" = "Escape"

[KeyMapping.DiffViewer]
"C-c" = "Escape"

[KeyMapping.Config]
"C-c" = "Escape"

[KeyMapping.References]
"C-c" = "Escape"

[KeyMapping.DocumentSymbol]
"C-c" = "Escape"

[KeyMapping.CallHierarchy]
"C-c" = "Escape"

[KeyMapping.RecentFile]
"C-c" = "Escape"

[KeyMapping.Debug]
"C-c" = "Escape"

[KeyMapping.Terminal]
"C-c" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Filer].len == 1
    check config.keyMapping.perMode[LogViewer].len == 1
    check config.keyMapping.perMode[Help].len == 1
    check config.keyMapping.perMode[BufferManager].len == 1
    check config.keyMapping.perMode[BackupManager].len == 1
    check config.keyMapping.perMode[DiffViewer].len == 1
    check config.keyMapping.perMode[Config].len == 1
    check config.keyMapping.perMode[References].len == 1
    check config.keyMapping.perMode[DocumentSymbol].len == 1
    check config.keyMapping.perMode[CallHierarchy].len == 1
    check config.keyMapping.perMode[RecentFile].len == 1
    check config.keyMapping.perMode[Debug].len == 1
    check config.keyMapping.perMode[Terminal].len == 1

  test "Empty special mode KeyMapping section":
    let toml = """
[KeyMapping]
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Filer].len == 0
    check config.keyMapping.perMode[LogViewer].len == 0
    check config.keyMapping.perMode[Help].len == 0
    check config.keyMapping.perMode[BufferManager].len == 0
    check config.keyMapping.perMode[BackupManager].len == 0
    check config.keyMapping.perMode[DiffViewer].len == 0
    check config.keyMapping.perMode[Config].len == 0
    check config.keyMapping.perMode[References].len == 0
    check config.keyMapping.perMode[DocumentSymbol].len == 0
    check config.keyMapping.perMode[CallHierarchy].len == 0
    check config.keyMapping.perMode[RecentFile].len == 0
    check config.keyMapping.perMode[Debug].len == 0
    check config.keyMapping.perMode[Terminal].len == 0

  test "Bare unknown RHS is accepted in special modes":
    let toml = """
[KeyMapping.Filer]
"C-s" = "not-a-command"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Filer]["C-s"].rhs == "not-a-command"

  test "Valid command name RHS in special mode":
    let toml = """
[KeyMapping.Filer]
"C-s" = "save"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Filer]["C-s"].rhs == "save"

  test "Valid key sequence RHS in special mode":
    let toml = """
[KeyMapping.Terminal]
"jj" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Terminal]["jj"].rhs == "Escape"

  test "Special mode does not affect editing modes":
    let toml = """
[KeyMapping.Filer]
"C-s" = "save"

[KeyMapping.Normal]
"C-n" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.perMode[Filer].len == 1
    check config.keyMapping.perMode[Normal].len == 1
    check config.keyMapping.perMode[Insert].len == 0
    check config.keyMapping.perMode[Visual].len == 0
    check config.keyMapping.perMode[LogViewer].len == 0

  test "Terse string entry defaults (noremap, no forceKeySeq, no args)":
    let toml = """
[KeyMapping.Insert]
"jj" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    let e = config.keyMapping.perMode[Insert]["jj"]
    check e.rhs == "Escape"
    check e.noremap == true
    check e.forceKeySeq == false
    check e.args.len == 0

  test "Inline table: forced key sequence with noremap = false":
    let toml = """
[KeyMapping.Normal]
"x" = { keys = "dd", noremap = false }
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    let e = config.keyMapping.perMode[Normal]["x"]
    check e.rhs == "dd"
    check e.forceKeySeq == true
    check e.noremap == false

  test "Inline table: command with spaced args":
    let toml = """
[KeyMapping.Normal]
"C-s" = { command = "save", args = ["a b"] }
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    let e = config.keyMapping.perMode[Normal]["C-s"]
    check e.rhs == "save"
    check e.args == @["a b"]
    check e.forceKeySeq == false

  test "Inline table: command + keys is mutually exclusive":
    let toml = """
[KeyMapping.Normal]
"x" = { command = "save", keys = "dd" }
"""
    let (_, vr) = loadFromTomlString(toml)
    check vr.hasErrors

  test "Inline table: non-bool noremap reports error":
    let toml = """
[KeyMapping.Normal]
"x" = { keys = "dd", noremap = 1 }
"""
    let (_, vr) = loadFromTomlString(toml)
    check vr.hasErrors

  test "Inline table: keys + args is rejected":
    let toml = """
[KeyMapping.Normal]
"x" = { keys = "dd", args = ["a"] }
"""
    let (_, vr) = loadFromTomlString(toml)
    check vr.hasErrors

suite "Config - saveConfigToToml with KeyMapping":
  test "KeyMapping round-trip":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_keymap_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.keyMapping.perMode[Normal]["C-s"] =
      KeyMappingEntry(rhs: "save", noremap: true)
    config.keyMapping.perMode[Insert]["jj"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[Command]["C-a"] =
      KeyMappingEntry(rhs: "Home", noremap: true)

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.keyMapping.all.len == 0
    check loaded.keyMapping.perMode[Normal].len == 1
    check loaded.keyMapping.perMode[Normal]["C-s"].rhs == "save"
    check loaded.keyMapping.perMode[Insert].len == 1
    check loaded.keyMapping.perMode[Insert]["jj"].rhs == "Escape"
    check loaded.keyMapping.perMode[Visual].len == 0
    check loaded.keyMapping.visualAll.len == 0
    check loaded.keyMapping.perMode[VisualLine].len == 0
    check loaded.keyMapping.perMode[VisualBlock].len == 0
    check loaded.keyMapping.perMode[Replace].len == 0
    check loaded.keyMapping.perMode[Command].len == 1
    check loaded.keyMapping.perMode[Command]["C-a"].rhs == "Home"

  test "KeyMapping.All round-trip":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_keymap_all_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.keyMapping.all["C-s"] = KeyMappingEntry(rhs: "save", noremap: true)
    config.keyMapping.perMode[Normal]["C-n"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.keyMapping.all.len == 1
    check loaded.keyMapping.all["C-s"].rhs == "save"
    check loaded.keyMapping.perMode[Normal].len == 1
    check loaded.keyMapping.perMode[Normal]["C-n"].rhs == "Escape"

  test "VisualAll/VisualLine/VisualBlock round-trip":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_keymap_visual_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.keyMapping.visualAll["C-c"] = KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[Visual]["C-v"] =
      KeyMappingEntry(rhs: "save", noremap: true)
    config.keyMapping.perMode[VisualLine]["C-l"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[VisualBlock]["C-b"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.keyMapping.visualAll.len == 1
    check loaded.keyMapping.visualAll["C-c"].rhs == "Escape"
    check loaded.keyMapping.perMode[Visual].len == 1
    check loaded.keyMapping.perMode[Visual]["C-v"].rhs == "save"
    check loaded.keyMapping.perMode[VisualLine].len == 1
    check loaded.keyMapping.perMode[VisualLine]["C-l"].rhs == "Escape"
    check loaded.keyMapping.perMode[VisualBlock].len == 1
    check loaded.keyMapping.perMode[VisualBlock]["C-b"].rhs == "Escape"

  test "Special mode KeyMapping round-trip":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_keymap_special_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.keyMapping.perMode[Filer]["C-s"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[LogViewer]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[Help]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[BufferManager]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[BackupManager]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[DiffViewer]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[Config]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[References]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[DocumentSymbol]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[CallHierarchy]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[RecentFile]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[Debug]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)
    config.keyMapping.perMode[Terminal]["C-c"] =
      KeyMappingEntry(rhs: "Escape", noremap: true)

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.keyMapping.perMode[Filer].len == 1
    check loaded.keyMapping.perMode[Filer]["C-s"].rhs == "Escape"
    check loaded.keyMapping.perMode[LogViewer].len == 1
    check loaded.keyMapping.perMode[Help].len == 1
    check loaded.keyMapping.perMode[BufferManager].len == 1
    check loaded.keyMapping.perMode[BackupManager].len == 1
    check loaded.keyMapping.perMode[DiffViewer].len == 1
    check loaded.keyMapping.perMode[Config].len == 1
    check loaded.keyMapping.perMode[References].len == 1
    check loaded.keyMapping.perMode[DocumentSymbol].len == 1
    check loaded.keyMapping.perMode[CallHierarchy].len == 1
    check loaded.keyMapping.perMode[RecentFile].len == 1
    check loaded.keyMapping.perMode[Debug].len == 1
    check loaded.keyMapping.perMode[Terminal].len == 1

  test "Inline entry round-trip (forceKeySeq + noremap=false)":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_keymap_inline_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.keyMapping.perMode[Normal]["x"] =
      KeyMappingEntry(rhs: "dd", forceKeySeq: true, noremap: false)

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    let e = loaded.keyMapping.perMode[Normal]["x"]
    check e.rhs == "dd"
    check e.forceKeySeq == true
    check e.noremap == false

  test "Empty KeyMapping not saved":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_keymap_empty_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let content = readFile(testFile)
    check "KeyMapping" notin content

suite "Config Validation - CommandAliases section":
  test "Valid CommandAliases config":
    let tomlStr = """
[CommandAliases]
x = { command = "quit" }
ww = { command = "saveall" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.commandAliases["x"].command == "quit"
    check config.commandAliases["ww"].command == "saveall"

  test "With description":
    let tomlStr = """
[CommandAliases]
x = { command = "quit", description = "Exit editor" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.commandAliases["x"].command == "quit"
    check config.commandAliases["x"].description == "Exit editor"

  test "Without description":
    let tomlStr = """
[CommandAliases]
x = { command = "quit" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.commandAliases["x"].description == ""

  test "Invalid command name is detected":
    let tomlStr = """
[CommandAliases]
x = { command = "nonexistent" }
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "CommandAliases.x" in vr.errors[0].name

  test "Non-table value is detected":
    let tomlStr = """
[CommandAliases]
x = 42
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "CommandAliases.x" in vr.errors[0].name

  test "Missing command key is detected":
    let tomlStr = """
[CommandAliases]
x = { description = "test" }
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "CommandAliases.x" in vr.errors[0].name

  test "Keys are lowercased":
    let tomlStr = """
[CommandAliases]
MyAlias = { command = "quit" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check "myalias" in config.commandAliases
    check config.commandAliases["myalias"].command == "quit"

  test "Command values are case-insensitive":
    let tomlStr = """
[CommandAliases]
x = { command = "Quit" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.commandAliases["x"].command == "quit"

suite "Config Validation - ShellCommands section":
  test "Valid ShellCommands config":
    let tomlStr = """
[ShellCommands]
nimbuild = { command = "nimble build" }
nimtest = { command = "nimble test" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.shellCommands["nimbuild"].command == "nimble build"
    check config.shellCommands["nimtest"].command == "nimble test"

  test "With description":
    let tomlStr = """
[ShellCommands]
nimbuild = { command = "nimble build", description = "Build project" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.shellCommands["nimbuild"].command == "nimble build"
    check config.shellCommands["nimbuild"].description == "Build project"

  test "Without description":
    let tomlStr = """
[ShellCommands]
nimbuild = { command = "nimble build" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.shellCommands["nimbuild"].description == ""

  test "Non-table value is detected":
    let tomlStr = """
[ShellCommands]
cmd = 42
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "ShellCommands.cmd" in vr.errors[0].name

  test "Missing command key is detected":
    let tomlStr = """
[ShellCommands]
cmd = { description = "test" }
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "ShellCommands.cmd" in vr.errors[0].name

  test "Keys are lowercased":
    let tomlStr = """
[ShellCommands]
NimBuild = { command = "nimble build" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check "nimbuild" in config.shellCommands

  test "Empty command string is rejected":
    let tomlStr = """
[ShellCommands]
cmd = { command = "" }
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "ShellCommands.cmd.command" in vr.errors[0].name

  test "Shell command value is preserved as-is":
    let tomlStr = """
[ShellCommands]
cmd = { command = "Make -C /opt/project BUILD_TYPE=Release" }
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.shellCommands["cmd"].command ==
      "Make -C /opt/project BUILD_TYPE=Release"

suite "Config Validation - DisabledCommandAliases section":
  test "Valid DisabledCommandAliases config":
    let tomlStr = """
[DisabledCommandAliases]
aliases = ["q", "w"]
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.disabledCommandAliases == @["q", "w"]

  test "Names are lowercased":
    let tomlStr = """
[DisabledCommandAliases]
aliases = ["Q"]
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.disabledCommandAliases == @["q"]

  test "Unknown key is detected":
    let tomlStr = """
[DisabledCommandAliases]
unknown = ["q"]
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "DisabledCommandAliases.unknown" in vr.errors[0].name

  test "Non-array value is detected":
    let tomlStr = """
[DisabledCommandAliases]
aliases = "q"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "DisabledCommandAliases.aliases" in vr.errors[0].name

  test "Non-string element is detected":
    let tomlStr = """
[DisabledCommandAliases]
aliases = [42]
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "DisabledCommandAliases.aliases[0]" in vr.errors[0].name

  test "Non-default alias name is detected":
    let tomlStr = """
[DisabledCommandAliases]
aliases = ["nosuchalias"]
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "DisabledCommandAliases.aliases[0]" in vr.errors[0].name

  test "Duplicate entries are loaded once":
    let tomlStr = """
[DisabledCommandAliases]
aliases = ["q", "q"]
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.disabledCommandAliases == @["q"]

suite "Config - saveConfigToToml with CommandAliases and ShellCommands":
  test "CommandAliases round-trip":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_aliases_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.commandAliases["x"] = UserCommandEntry(command: "quit")
    config.commandAliases["ww"] = UserCommandEntry(command: "saveall")

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.commandAliases.len == 2
    check loaded.commandAliases["x"].command == "quit"
    check loaded.commandAliases["ww"].command == "saveall"

  test "CommandAliases round-trip with description":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_aliases_desc_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.commandAliases["x"] =
      UserCommandEntry(command: "quit", description: "Exit editor")

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.commandAliases["x"].command == "quit"
    check loaded.commandAliases["x"].description == "Exit editor"

  test "ShellCommands round-trip":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_shellcmds_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.shellCommands["nimbuild"] = UserCommandEntry(command: "nimble build")
    config.shellCommands["gitlog"] = UserCommandEntry(command: "git log --oneline -20")

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.shellCommands.len == 2
    check loaded.shellCommands["nimbuild"].command == "nimble build"
    check loaded.shellCommands["gitlog"].command == "git log --oneline -20"

  test "ShellCommands round-trip with description":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_shellcmds_desc_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.shellCommands["nimbuild"] =
      UserCommandEntry(command: "nimble build", description: "Build project")

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.shellCommands["nimbuild"].command == "nimble build"
    check loaded.shellCommands["nimbuild"].description == "Build project"

  test "DisabledCommandAliases round-trip":
    inc testFileCounter
    let testFile =
      getTempDir() / "moe_test_disabled_aliases_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.disabledCommandAliases = @["w", "q"]

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    # Serialized in sorted order
    check loaded.disabledCommandAliases == @["q", "w"]

  test "Empty CommandAliases and ShellCommands not saved":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_empty_cmds_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let content = readFile(testFile)
    check "CommandAliases" notin content
    check "ShellCommands" notin content
    check "DisabledCommandAliases" notin content

suite "Config - Lsp feature tables round-trip":
  test "Every feature sub-table is written and reloads unchanged":
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_lsp_features_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    # Flip every feature away from its default so a table dropped by the
    # serializer shows up as a value reverting on reload.
    for name, value in fieldPairs(config.lsp):
      when value is LspFeatureConfig or value is LspOpenWindowConfig or
          value is LspDiagnosticsConfig:
        value.enable = not value.enable
    config.lsp.definition.openWindow = true
    config.lsp.diagnostics.autoHoverDelay = 42

    check saveConfigToToml(config, testFile).isOk

    let content = readFile(testFile)
    for name in LspFeatureTableNames:
      check "[Lsp." & name & "]" in content

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    for name, saved, reloaded in fieldPairs(config.lsp, loaded.lsp):
      when saved is LspFeatureConfig or saved is LspOpenWindowConfig or
          saved is LspDiagnosticsConfig:
        if saved != reloaded:
          echo "Lsp feature table did not round-trip: " & name
        check saved == reloaded

suite "Config - Lsp server settings round-trip":
  proc roundTripSettings(settingsJson: string): string =
    inc testFileCounter
    let testFile = getTempDir() / "moe_test_lsp_settings_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.theme.kind = tkDefault
    config.theme.path = ""
    config.lsp.servers["nim"] = LspServerConfig(
      extensions: @[".nim"],
      command: "nimlsp",
      trace: ltOff,
      settings: settingsJson,
      rustAnalyzerRunSingle: false,
      rustAnalyzerDebugSingle: false,
    )

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.lsp.servers.hasKey("nim")
    return loaded.lsp.servers["nim"].settings

  test "Bare keys round-trip unchanged":
    let result = roundTripSettings("""{"rust": {"analyzer": true}}""")
    check parseJson(result) == parseJson("""{"rust": {"analyzer": true}}""")

  test "Keys with spaces are quoted and preserved":
    let result = roundTripSettings("""{"foo bar": 1}""")
    check parseJson(result) == parseJson("""{"foo bar": 1}""")

  test "Keys with dots stay flat instead of becoming nested tables":
    let result = roundTripSettings("""{"foo.bar": 1}""")
    check parseJson(result) == parseJson("""{"foo.bar": 1}""")

  test "Null-valued keys are omitted on save":
    let result = roundTripSettings("""{"keep": 1, "drop": null}""")
    let parsed = parseJson(result)
    check parsed{"keep"} == newJInt(1)
    check parsed{"drop"} == nil
