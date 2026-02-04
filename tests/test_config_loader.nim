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

import std/[unittest, os, strutils, tables, options]
import pkg/results
import ../src/moepkg/[config_loader, config]

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
    check config.clipboard.tool == cbtXsel

  test "Invalid clipboard tool is detected":
    let tomlStr =
      """
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
    let tomlStr =
      """
[BuildOnSave]
enable = true
command = "make build"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.buildOnSave.enable == true
    check config.buildOnSave.command == some("make build")

  test "Invalid enable type is detected":
    let tomlStr =
      """
[BuildOnSave]
enable = "true"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "BuildOnSave.enable" in vr.errors[0].name

  test "Invalid command type is detected":
    let tomlStr =
      """
[BuildOnSave]
command = 123
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "BuildOnSave.command" in vr.errors[0].name

suite "Config Validation - StatusLine section":
  test "Valid StatusLine config passes validation":
    let tomlStr =
      """
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
    let tomlStr =
      """
[StatusLine]
setupText = 123
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "StatusLine.setupText" in vr.errors[0].name

suite "Config Validation - Git section":
  test "Valid Git config passes validation":
    let tomlStr =
      """
[Git]
showChangedLine = true
updateInterval = 500
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.git.showChangedLine == true
    check config.git.updateInterval == 500

  test "Invalid updateInterval (zero) is detected":
    let tomlStr =
      """
[Git]
updateInterval = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Git.updateInterval" in vr.errors[0].name
    check config.git.updateInterval == 1000 # Default value

  test "Invalid updateInterval (negative) is detected":
    let tomlStr =
      """
[Git]
updateInterval = -1
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Git.updateInterval" in vr.errors[0].name
    check config.git.updateInterval == 1000 # Default value

suite "Config Validation - SyntaxChecker section":
  test "Valid SyntaxChecker config passes validation":
    let tomlStr =
      """
[SyntaxChecker]
enable = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.syntaxChecker.enable == true

  test "Invalid enable type is detected":
    let tomlStr =
      """
[SyntaxChecker]
enable = "yes"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "SyntaxChecker.enable" in vr.errors[0].name

suite "Config Validation - Theme section":
  test "Valid Theme config with default kind passes validation":
    let tomlStr =
      """
[Theme]
kind = "default"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.theme.kind == tkDefault

  test "Invalid theme kind is detected":
    let tomlStr =
      """
[Theme]
kind = "invalid"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Theme.kind" in vr.errors[0].name
    check config.theme.kind == tkConfig # Default value

suite "Config Validation - AutoSave section":
  test "Valid AutoSave config passes validation":
    let tomlStr =
      """
[AutoSave]
enable = true
interval = 10
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.autoSave.enable == true
    check config.autoSave.interval == 10

  test "Invalid interval (zero) is detected":
    let tomlStr =
      """
[AutoSave]
interval = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "AutoSave.interval" in vr.errors[0].name
    check config.autoSave.interval == 5 # Default value

suite "Config Validation - Notification section":
  test "Valid Notification config passes validation":
    let tomlStr =
      """
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
    let tomlStr =
      """
[Notification]
screenNotifications = "yes"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Notification.screenNotifications" in vr.errors[0].name

suite "Config Validation - Filer section":
  test "Valid Filer config passes validation":
    let tomlStr =
      """
[Filer]
showIcons = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.filer.showIcons == true

  test "Invalid showIcons type is detected":
    let tomlStr =
      """
[Filer]
showIcons = "yes"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Filer.showIcons" in vr.errors[0].name

suite "Config Validation - Autocomplete section":
  test "Valid Autocomplete config passes validation":
    let tomlStr =
      """
[Autocomplete]
enable = true
windowBorder = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.autocomplete.enable == true
    check config.autocomplete.windowBorder == false

  test "Invalid enable type is detected":
    let tomlStr =
      """
[Autocomplete]
enable = 1
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Autocomplete.enable" in vr.errors[0].name

suite "Config Validation - Persist section":
  test "Valid Persist config passes validation":
    let tomlStr =
      """
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
    let tomlStr =
      """
[Persist]
exCommandHistoryLimit = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Persist.exCommandHistoryLimit" in vr.errors[0].name
    check config.persist.exCommandHistoryLimit == 1000 # Default value

  test "Invalid searchHistoryLimit (negative) is detected":
    let tomlStr =
      """
[Persist]
searchHistoryLimit = -10
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Persist.searchHistoryLimit" in vr.errors[0].name
    check config.persist.searchHistoryLimit == 1000 # Default value

suite "Config Validation - QuickRun section":
  test "Valid QuickRun config passes validation":
    let tomlStr =
      """
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
    let tomlStr =
      """
[QuickRun]
timeout = 0
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "QuickRun.timeout" in vr.errors[0].name
    check config.quickRun.timeout == 30 # Default value

  test "Invalid command type is detected":
    let tomlStr =
      """
[QuickRun]
command = 123
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "QuickRun.command" in vr.errors[0].name

suite "Config Validation - TabLine section":
  test "Valid TabLine config passes validation":
    let tomlStr =
      """
[TabLine]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.tabLine.enable == false

  test "Invalid enable type is detected":
    let tomlStr =
      """
[TabLine]
enable = "no"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "TabLine.enable" in vr.errors[0].name

suite "Config Validation - StartUp.FileOpen section":
  test "Valid StartUp.FileOpen config passes validation":
    let tomlStr =
      """
[StartUp.FileOpen]
autoSplit = true
splitType = "horizontal"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.startUpFileOpen.autoSplit == true
    check config.startUpFileOpen.splitType == stHorizontal

  test "Invalid splitType is detected":
    let tomlStr =
      """
[StartUp.FileOpen]
splitType = "diagonal"
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "StartUp.FileOpen.splitType" in vr.errors[0].name
    check config.startUpFileOpen.splitType == stVertical # Default value

suite "Config Validation - Debug section":
  test "Valid Debug.WindowNode config passes validation":
    let tomlStr =
      """
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
    let tomlStr =
      """
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
    let tomlStr =
      """
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
    let tomlStr =
      """
[Debug.Search]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.search.enable == false

  test "Valid Debug.MacroState config passes validation":
    let tomlStr =
      """
[Debug.MacroState]
enable = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.macroState.enable == true

  test "Valid Debug.Visual config passes validation":
    let tomlStr =
      """
[Debug.Visual]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.visual.enable == false

  test "Valid Debug.JumpList config passes validation":
    let tomlStr =
      """
[Debug.JumpList]
enable = true
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.jumpList.enable == true

  test "Valid Debug.Lsp config passes validation":
    let tomlStr =
      """
[Debug.Lsp]
enable = false
"""
    let (config, vr) = loadFromTomlString(tomlStr)
    check not vr.hasErrors
    check config.debug.lsp.enable == false

  test "Invalid Debug.WindowNode bool type is detected":
    let tomlStr =
      """
[Debug.WindowNode]
enable = "yes"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Debug.WindowNode.enable" in vr.errors[0].name

suite "Config Validation - Standard section extended":
  test "Valid cursor types pass validation":
    let tomlStr =
      """
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
    let tomlStr =
      """
[Standard]
tabStop = "four"
"""
    let (_, vr) = loadFromTomlString(tomlStr)
    check vr.hasErrors
    check "Standard.tabStop" in vr.errors[0].name
