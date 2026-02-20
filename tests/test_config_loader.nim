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

import std/[unittest, os, strutils, tables, options, sequtils]

import pkg/results

import ../src/moepkg/[config_loader, config, color, theme]

import config_test_helper

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
    check config.standard.colorMode == cm24bit # Default value

  test "Invalid cursorType enum is detected":
    let tomlStr = """
[Standard]
defaultCursor = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.defaultCursor" in vr.errors[0].name
    check config.standard.defaultCursor == ctTerminalDefault # Default value

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

  test "Invalid reservedWord (not array) is detected":
    let tomlStr = """
[Highlight]
reservedWord = "TODO"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Highlight.reservedWord" in vr.errors[0].name

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
    check config.lsp.timeout == 5000 # Default value

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
    check config.clipboard.tool == cbtXsel

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
exCommand = true
exCommandHistoryLimit = 500
search = true
searchHistoryLimit = 500
cursorPosition = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.persist.exCommand == true
    check config.persist.exCommandHistoryLimit == 500
    check config.persist.search == true
    check config.persist.searchHistoryLimit == 500
    check config.persist.cursorPosition == true

  test "Invalid exCommandHistoryLimit (zero) is detected":
    let tomlStr = """
[Persist]
exCommandHistoryLimit = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Persist.exCommandHistoryLimit" in vr.errors[0].name
    check config.persist.exCommandHistoryLimit == 1000 # Default value

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

  test "Invalid timeout (zero) is detected":
    let tomlStr = """
[QuickRun]
timeout = 0
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
    let testFile = "/tmp/moe_test_theme_invalid_" & $testFileCounter & ".toml"
    writeFile(testFile, "this is not valid = = = toml [[[")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isErr
    check "parse" in result.error.toLowerAscii

  test "Missing [Colors] section returns error":
    inc testFileCounter
    let testFile = "/tmp/moe_test_theme_nocolor_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Other]\nkey = \"value\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isErr
    check "Colors" in result.error

  test "Valid [Colors] section returns Ok":
    inc testFileCounter
    let testFile = "/tmp/moe_test_theme_valid_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"#ff0000\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk

  test "Foreground color override":
    inc testFileCounter
    let testFile = "/tmp/moe_test_theme_fg_" & $testFileCounter & ".toml"
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
    let testFile = "/tmp/moe_test_theme_bg_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nbackground = \"#00ff00\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.default].background.rgb.green == 255

  test "Keyword foreground color":
    inc testFileCounter
    let testFile = "/tmp/moe_test_theme_kw_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"#ffffff\"\nkeyword = \"#0000ff\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.keyword].foreground.rgb.blue == 255
    check colors[EditorColorPairIndex.keyword].foreground.rgb.red == 0

  test "Keyword background color via Bg suffix":
    inc testFileCounter
    let testFile = "/tmp/moe_test_theme_kwbg_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nkeywordBg = \"#112233\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.keyword].background.rgb.red == 0x11
    check colors[EditorColorPairIndex.keyword].background.rgb.green == 0x22
    check colors[EditorColorPairIndex.keyword].background.rgb.blue == 0x33

  test "termDefault color is processed (rgb.red == -1)":
    inc testFileCounter
    let testFile = "/tmp/moe_test_theme_td_" & $testFileCounter & ".toml"
    writeFile(testFile, "[Colors]\nforeground = \"termDefault\"\n")
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk
    let colors = result.get
    check colors[EditorColorPairIndex.default].foreground.rgb.red == -1

  test "Unknown color key is ignored and returns Ok":
    inc testFileCounter
    let testFile = "/tmp/moe_test_theme_unk_" & $testFileCounter & ".toml"
    writeFile(
      testFile, "[Colors]\nforeground = \"#ffffff\"\nnonExistentKey = \"#123456\"\n"
    )
    defer:
      removeFile(testFile)

    let result = loadThemeFromToml(testFile)
    check result.isOk

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
    let testFile = "/tmp/moe_test_loadtheme_" & $testFileCounter & ".toml"
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

  test "Non-existent theme file falls back to default":
    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = "/nonexistent/theme.toml"
    initTheme(config)
    # Should not crash; falls back to default theme

suite "Config - saveConfigToToml":
  test "Save default config to file":
    inc testFileCounter
    let testFile = "/tmp/moe_test_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let config = newEditorConfig()
    let result = saveConfigToToml(config, testFile)
    check result.isOk
    check fileExists(testFile)

  test "Saved config is valid TOML and can be reloaded":
    inc testFileCounter
    let testFile = "/tmp/moe_test_save_reload_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let config = newEditorConfig()
    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk

  test "tabStop value round-trips":
    inc testFileCounter
    let testFile = "/tmp/moe_test_save_tabstop_" & $testFileCounter & ".toml"
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

  test "Boolean setting round-trips":
    inc testFileCounter
    let testFile = "/tmp/moe_test_save_bool_" & $testFileCounter & ".toml"
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
    let testDir = "/tmp/moe_test_save_dir_" & $testFileCounter
    let testFile = testDir / "subdir" / "config.toml"
    defer:
      removeDir(testDir)

    let config = newEditorConfig()
    let result = saveConfigToToml(config, testFile)
    check result.isOk
    check fileExists(testFile)

  test "Output contains expected section headers":
    inc testFileCounter
    let testFile = "/tmp/moe_test_save_sections_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let config = newEditorConfig()
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
    let testFile = "/tmp/moe_test_roundtrip_all_" & $testFileCounter & ".toml"
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
    modifyAllFields(config.autocomplete)
    modifyAllFields(config.autoSave)
    modifyAllFields(config.persist)
    modifyAllFields(config.git)
    modifyAllFields(config.syntaxChecker)
    modifyAllFields(config.smoothScroll)
    modifyAllFields(config.startUpFileOpen)
    modifyAllFields(config.debug)
    modifyAllFields(config.theme)
    modifyAllFields(config.lsp)

    # Override Option[string] dir paths with real directories
    # (loadOptionDirPath validates directory existence)
    config.buildOnSave.workspaceRoot = some("/tmp")
    config.autoBackup.backupDir = some("/tmp")

    # Theme: ensure kind != tkConfig so loadFilePath is not used for path
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
    check config.autocomplete == loaded.autocomplete
    check config.autoSave == loaded.autoSave
    check config.persist == loaded.persist
    check config.git == loaded.git
    check config.syntaxChecker == loaded.syntaxChecker
    check config.smoothScroll == loaded.smoothScroll
    check config.startUpFileOpen == loaded.startUpFileOpen
    check config.debug == loaded.debug
    check config.theme == loaded.theme
    check config.lsp == loaded.lsp

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
    let testFile = "/tmp/moe_test_save_theme_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let result = saveThemeToToml(DefaultColors, testFile)
    check result.isOk
    check fileExists(testFile)

  test "Saved theme file contains [Colors] section":
    inc testFileCounter
    let testFile = "/tmp/moe_test_save_theme_section_" & $testFileCounter & ".toml"
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
    let testFile = "/tmp/moe_test_save_theme_reload_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    let saveResult = saveThemeToToml(DefaultColors, testFile)
    check saveResult.isOk

    let loadResult = loadThemeFromToml(testFile)
    check loadResult.isOk

  test "Color values round-trip":
    inc testFileCounter
    let testFile = "/tmp/moe_test_save_theme_rt_" & $testFileCounter & ".toml"
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
    let testFile = "/tmp/moe_test_save_theme_custom_" & $testFileCounter & ".toml"
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
    let testFile = "/tmp/moe_test_save_theme_td_" & $testFileCounter & ".toml"
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
    let testDir = "/tmp/moe_test_save_theme_dir_" & $testFileCounter
    let testFile = testDir / "subdir" / "theme.toml"
    defer:
      removeDir(testDir)

    let result = saveThemeToToml(DefaultColors, testFile)
    check result.isOk
    check fileExists(testFile)

  test "Backup file is created when original exists":
    inc testFileCounter
    let testFile = "/tmp/moe_test_save_theme_bac_" & $testFileCounter & ".toml"
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
    let testFile = "/tmp/moe_test_save_theme_nobac_" & $testFileCounter & ".toml"
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
    let configFile = "/tmp/moe_test_save_cfg_theme_" & $testFileCounter & ".toml"
    let themeFile = "/tmp/moe_test_save_cfg_theme_colors_" & $testFileCounter & ".toml"
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
    let configFile = "/tmp/moe_test_save_cfg_no_theme_" & $testFileCounter & ".toml"
    let themeFile =
      "/tmp/moe_test_save_cfg_no_theme_colors_" & $testFileCounter & ".toml"
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
    let configFile = "/tmp/moe_test_save_cfg_empty_path_" & $testFileCounter & ".toml"
    defer:
      removeFile(configFile)

    var config = newEditorConfig()
    config.theme.kind = tkConfig
    config.theme.path = ""

    let result = saveConfigToToml(config, configFile)
    check result.isOk

suite "Config Validation - KeyMapping section":
  test "Normal key mappings":
    let toml = """
[KeyMapping.Normal]
"C-s" = "save"
"jj" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.normal.len == 2
    check config.keyMapping.normal["C-s"] == "save"
    check config.keyMapping.normal["jj"] == "Escape"

  test "All four modes":
    let toml = """
[KeyMapping.Normal]
"C-s" = "save"

[KeyMapping.Insert]
"jj" = "Escape"

[KeyMapping.Visual]
"C-c" = "Escape"

[KeyMapping.Replace]
"C-c" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.normal.len == 1
    check config.keyMapping.insert.len == 1
    check config.keyMapping.visual.len == 1
    check config.keyMapping.replace.len == 1
    check config.keyMapping.normal["C-s"] == "save"
    check config.keyMapping.insert["jj"] == "Escape"
    check config.keyMapping.visual["C-c"] == "Escape"
    check config.keyMapping.replace["C-c"] == "Escape"

  test "Empty KeyMapping section":
    let toml = """
[KeyMapping]
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.normal.len == 0
    check config.keyMapping.insert.len == 0
    check config.keyMapping.visual.len == 0
    check config.keyMapping.replace.len == 0

  test "No KeyMapping section uses defaults":
    let toml = """
[Standard]
number = true
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.normal.len == 0
    check config.keyMapping.insert.len == 0
    check config.keyMapping.visual.len == 0
    check config.keyMapping.replace.len == 0

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

  test "Invalid RHS (not a command name or key sequence) reports error":
    let toml = """
[KeyMapping.Normal]
"C-s" = "not-a-command"
"""
    let (_, vr) = loadFromTomlString(toml)
    check vr.hasErrors
    let errorNames = vr.errors.mapIt(it.name)
    check "KeyMapping.Normal.C-s" in errorNames

  test "Valid command name RHS passes validation":
    let toml = """
[KeyMapping.Normal]
"C-s" = "save"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.normal["C-s"] == "save"

  test "Valid key sequence RHS passes validation":
    let toml = """
[KeyMapping.Insert]
"jj" = "Escape"
"""
    let (config, vr) = loadFromTomlString(toml)
    check not vr.hasErrors
    check config.keyMapping.insert["jj"] == "Escape"

suite "Config - saveConfigToToml with KeyMapping":
  test "KeyMapping round-trip":
    inc testFileCounter
    let testFile = "/tmp/moe_test_keymap_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()
    config.keyMapping.normal["C-s"] = "save"
    config.keyMapping.insert["jj"] = "Escape"

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loaded, vr) = loadResult.get
    check not vr.hasErrors
    check loaded.keyMapping.normal.len == 1
    check loaded.keyMapping.normal["C-s"] == "save"
    check loaded.keyMapping.insert.len == 1
    check loaded.keyMapping.insert["jj"] == "Escape"
    check loaded.keyMapping.visual.len == 0
    check loaded.keyMapping.replace.len == 0

  test "Empty KeyMapping not saved":
    inc testFileCounter
    let testFile = "/tmp/moe_test_keymap_empty_save_" & $testFileCounter & ".toml"
    defer:
      removeFile(testFile)

    var config = newEditorConfig()

    let saveResult = saveConfigToToml(config, testFile)
    check saveResult.isOk

    let content = readFile(testFile)
    check "KeyMapping" notin content
