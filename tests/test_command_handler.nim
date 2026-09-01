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

import std/[unittest, options, strutils, sets, os]
import pkg/results
import ../src/moepkg/[buffer, command_line, command_config, command_registry, modes]
import ../src/moepkg/command_handlers/[command_handler, handler_result]

proc setupHandler(): CommandModeHandler =
  ## Create a handler with default configuration
  let parser = newCommandLineParser()
  let config = newCommandConfig()
  config.loadDefaultConfig()
  config.applyToParser(parser)
  let registry = newCommandRegistry()
  return newCommandModeHandler(parser, config, registry)

proc setupBuffer(lines: seq[string] = @[""]): TextBuffer =
  ## Create a buffer with optional initial content
  let buf = newTextBuffer()
  for i, line in lines:
    if i == 0:
      if line.len > 0:
        discard buf.insertText(BufferPosition(line: 0, column: 0), line)
    else:
      discard buf.insert(i, line)
  buf.markSaved()
  return buf

suite "CommandModeHandler - newCommandModeHandler":
  test "Create handler with default configuration":
    let handler = setupHandler()
    check handler != nil
    check handler.parser != nil
    check handler.config != nil
    check handler.commandRegistry != nil

suite "CommandModeHandler - executeQuit":
  test "Quit unmodified buffer":
    let handler = setupHandler()
    let buffer = setupBuffer()
    buffer.markSaved()

    let result = handler.executeQuit(buffer, force = false)
    check result.kind == hrCloseWindow
    check result.forceClose == false

  test "Quit modified buffer without force returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuit(buffer, force = false)
    check result.kind == hrError
    check result.errorMessage == "No write since last change (add ! to override)"

  test "Quit modified buffer with force":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuit(buffer, force = true)
    check result.kind == hrCloseWindow
    check result.forceClose == true

  test "Quit shared buffer skips modification check":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuit(buffer, force = false, isSharedBuffer = true)
    check result.kind == hrCloseWindow
    check result.forceClose == false

suite "CommandModeHandler - executeSave":
  test "Save without filename":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSave(buffer, none(string), force = false)
    check result.kind == hrSave
    check result.saveFilename.isNone
    check result.forceSave == false

  test "Save with filename":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSave(buffer, some("test.txt"), force = false)
    check result.kind == hrSave
    check result.saveFilename.isSome
    check result.saveFilename.get == "test.txt"

  test "Force save":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSave(buffer, none(string), force = true)
    check result.kind == hrSave
    check result.forceSave == true

suite "CommandModeHandler - executeSaveAll":
  test "Save all without force":
    let handler = setupHandler()

    let result = handler.executeSaveAll(force = false)
    check result.kind == hrSaveAll
    check result.forceSaveAll == false

  test "Save all with force":
    let handler = setupHandler()

    let result = handler.executeSaveAll(force = true)
    check result.kind == hrSaveAll
    check result.forceSaveAll == true

suite "CommandModeHandler - executeSaveAllAndQuit":
  test "Save all and quit without force":
    let handler = setupHandler()

    let result = handler.executeSaveAllAndQuit(force = false)
    check result.kind == hrSaveAllAndQuit
    check result.forceSaveAllAndQuitAfter == false

  test "Save all and quit with force":
    let handler = setupHandler()

    let result = handler.executeSaveAllAndQuit(force = true)
    check result.kind == hrSaveAllAndQuit
    check result.forceSaveAllAndQuitAfter == true

suite "CommandModeHandler - executeSaveAndQuit":
  test "Save and quit without filename":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSaveAndQuit(buffer, none(string), force = false)
    check result.kind == hrSaveAndQuit
    check result.saveAndQuitFilename.isNone
    check result.forceQuitAfterSave == false

  test "Save and quit with filename":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSaveAndQuit(buffer, some("test.txt"), force = true)
    check result.kind == hrSaveAndQuit
    check result.saveAndQuitFilename.get == "test.txt"
    check result.forceQuitAfterSave == true

suite "CommandModeHandler - executeSaveIfModifiedAndQuit":
  test "Clean buffer quits without entering the save path":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])

    let result =
      handler.executeSaveIfModifiedAndQuit(buffer, none(string), force = false)

    check result.kind == hrQuit

  test "Modified buffer uses the existing save-and-quit path":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result =
      handler.executeSaveIfModifiedAndQuit(buffer, some("test.txt"), force = true)

    check result.kind == hrSaveAndQuit
    check result.saveAndQuitFilename == some("test.txt")
    check result.forceQuitAfterSave == true

  test "Clean :wq still enters the save path":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])

    let result = handler.executeSaveAndQuit(buffer, none(string), force = false)

    check result.kind == hrSaveAndQuit

suite "CommandModeHandler - executeQuitAll":
  test "Quit all with unmodified buffer":
    let handler = setupHandler()
    let buffer = setupBuffer()
    buffer.markSaved()

    let result = handler.executeQuitAll(buffer, force = false)
    check result.kind == hrQuit

  test "Quit all with modified buffer without force":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuitAll(buffer, force = false)
    check result.kind == hrError
    check result.errorMessage == "No write since last change (add ! to override)"

  test "Quit all with modified buffer with force":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuitAll(buffer, force = true)
    check result.kind == hrQuit

  test "Quit all refuses when another buffer is modified":
    let handler = setupHandler()
    let buffer = setupBuffer()
    buffer.markSaved()

    let result = handler.executeQuitAll(buffer, force = false, otherModifiedCount = 1)
    check result.kind == hrError
    check result.errorMessage == "No write since last change (add ! to override)"

  test "Quit all reports total count when several buffers are modified":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuitAll(buffer, force = false, otherModifiedCount = 2)
    check result.kind == hrError
    check result.errorMessage ==
      "No write since last change: 3 buffers modified (add ! to override)"

  test "Quit all force overrides other modified buffers":
    let handler = setupHandler()
    let buffer = setupBuffer()
    buffer.markSaved()

    let result = handler.executeQuitAll(buffer, force = true, otherModifiedCount = 3)
    check result.kind == hrQuit

suite "CommandModeHandler - executeEdit":
  test "Edit existing file":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeEdit(buffer, some("test.nim"), false)
    check result.kind == hrEdit
    check result.editFilename.get.endsWith("test.nim")

  test "Edit directory opens filer":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeEdit(buffer, some("/tmp"), false)
    check result.kind == hrEnterFiler
    check result.enterFilerPath.isSome
    check result.enterFilerPath.get == "/tmp"

  test "Edit with tilde expands to home directory":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeEdit(buffer, some("~/test.nim"), false)
    check result.kind == hrEdit
    check result.editFilename.get == getHomeDir() / "test.nim"
    check not result.editFilename.get.contains("~")

  test "Edit directory with tilde opens filer":
    let handler = setupHandler()
    let buffer = setupBuffer()

    # Home directory always exists
    let result = handler.executeEdit(buffer, some("~"), false)
    check result.kind == hrEnterFiler
    check result.enterFilerPath.isSome
    check result.enterFilerPath.get == getHomeDir().absolutePath

  test "Edit without filename and no unsaved changes reloads":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeEdit(buffer, none(string), false)
    check result.kind == hrEdit
    check result.editFilename.isNone

  test "Edit without filename and unsaved changes returns error":
    let handler = setupHandler()
    let buffer = setupBuffer()
    discard buffer.insert(0, "change")

    let result = handler.executeEdit(buffer, none(string), false)
    check result.kind == hrError
    check "No write since last change" in result.errorMessage

  test "Force edit without filename ignores unsaved changes":
    let handler = setupHandler()
    let buffer = setupBuffer()
    discard buffer.insert(0, "change")

    let result = handler.executeEdit(buffer, none(string), true)
    check result.kind == hrEdit
    check result.editFilename.isNone
    check result.forceEdit == true

suite "CommandModeHandler - executeGotoLine":
  test "Goto valid line number":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line 1", "Line 2", "Line 3"])

    let result = handler.executeGotoLine(buffer, 2)
    check result.kind == hrGotoLine
    check result.lineNumber == 2

  test "Goto line 0 returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line 1"])

    let result = handler.executeGotoLine(buffer, 0)
    check result.kind == hrError
    check result.errorMessage == "Invalid line number"

  test "Goto line beyond buffer length clamps to last line":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line 1", "Line 2"])

    let result = handler.executeGotoLine(buffer, 100)
    check result.kind == hrGotoLine
    check result.lineNumber == 2

suite "CommandModeHandler - executeSet Boolean Options":
  test "Set number on":
    let handler = setupHandler()
    let result = handler.executeSet("number", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoNumber
    check result.boolValue == true

  test "Set number off (nonumber)":
    let handler = setupHandler()
    let result = handler.executeSet("nonumber", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoNumber
    check result.boolValue == false

  test "Set number with abbreviation (nu)":
    let handler = setupHandler()
    let result = handler.executeSet("nu", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoNumber
    check result.boolValue == true

  test "Set relativenumber on":
    let handler = setupHandler()
    let result = handler.executeSet("relativenumber", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoRelativeNumber
    check result.boolValue == true

  test "Set relativenumber off (norelativenumber)":
    let handler = setupHandler()
    let result = handler.executeSet("norelativenumber", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoRelativeNumber
    check result.boolValue == false

  test "Set relativenumber with abbreviation (rnu)":
    let handler = setupHandler()
    let result = handler.executeSet("rnu", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoRelativeNumber
    check result.boolValue == true

  test "Set relativenumber off with abbreviation (nornu)":
    let handler = setupHandler()
    let result = handler.executeSet("nornu", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoRelativeNumber
    check result.boolValue == false

  test "Set cursorline on":
    let handler = setupHandler()
    let result = handler.executeSet("cursorline", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoCursorLine
    check result.boolValue == true

  test "Set cursorcolumn on":
    let handler = setupHandler()
    let result = handler.executeSet("cursorcolumn", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoCursorColumn
    check result.boolValue == true

  test "Set syntax on":
    let handler = setupHandler()
    let result = handler.executeSet("syntax", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoSyntax
    check result.boolValue == true

  test "Set autoindent on":
    let handler = setupHandler()
    let result = handler.executeSet("autoindent", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoAutoIndent
    check result.boolValue == true

  test "Set hlsearch on":
    let handler = setupHandler()
    let result = handler.executeSet("hlsearch", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHlSearch
    check result.boolValue == true

  test "Set ignorecase on":
    let handler = setupHandler()
    let result = handler.executeSet("ignorecase", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoIgnoreCase
    check result.boolValue == true

  test "Set statusline on":
    let handler = setupHandler()
    let result = handler.executeSet("statusline", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoStatusLine
    check result.boolValue == true

  test "Set indentationlines on":
    let handler = setupHandler()
    let result = handler.executeSet("indentationlines", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoIndentationLines
    check result.boolValue == true

  test "Set autocloseparen on":
    let handler = setupHandler()
    let result = handler.executeSet("autocloseparen", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoAutoCloseParen
    check result.boolValue == true

  test "Set autodeleteparen on":
    let handler = setupHandler()
    let result = handler.executeSet("autodeleteparen", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoAutoDeleteParen
    check result.boolValue == true

  test "Set clipboard on":
    let handler = setupHandler()
    let result = handler.executeSet("clipboard", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoClipboard
    check result.boolValue == true

  test "Set smoothscroll on":
    let handler = setupHandler()
    let result = handler.executeSet("smoothscroll", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoSmoothScroll
    check result.boolValue == true

  test "Set livereload on":
    let handler = setupHandler()
    let result = handler.executeSet("livereload", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoLiveReloadOfConf
    check result.boolValue == true

  test "Set icon on":
    let handler = setupHandler()
    let result = handler.executeSet("icon", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoShowIcons
    check result.boolValue == true

  test "Set highlightcurrentline on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightcurrentline", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightCurrentLine
    check result.boolValue == true

  test "Set highlightcurrentword on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightcurrentword", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightCurrentWord
    check result.boolValue == true

  test "Set highlightfullspace on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightfullspace", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightFullWidthSpace
    check result.boolValue == true

  test "Set highlightparen on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightparen", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightPairOfParen
    check result.boolValue == true

  test "Set highlightfindchar on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightfindchar", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightFindChar
    check result.boolValue == true

  test "Set hfc on (abbreviation)":
    let handler = setupHandler()
    let result = handler.executeSet("hfc", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightFindChar
    check result.boolValue == true

  test "Set nohighlightfindchar off":
    let handler = setupHandler()
    let result = handler.executeSet("nohighlightfindchar", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightFindChar
    check result.boolValue == false

  test "Set nohfc off (abbreviation)":
    let handler = setupHandler()
    let result = handler.executeSet("nohfc", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightFindChar
    check result.boolValue == false

  test "Set highlightcolorcode on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightcolorcode", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightColorCode
    check result.boolValue == true

  test "Set hcc on (abbreviation)":
    let handler = setupHandler()
    let result = handler.executeSet("hcc", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightColorCode
    check result.boolValue == true

  test "Set nohighlightcolorcode off":
    let handler = setupHandler()
    let result = handler.executeSet("nohighlightcolorcode", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightColorCode
    check result.boolValue == false

  test "Set nohcc off (abbreviation)":
    let handler = setupHandler()
    let result = handler.executeSet("nohcc", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHighlightColorCode
    check result.boolValue == false

  test "Set multistatusline on":
    let handler = setupHandler()
    let result = handler.executeSet("multistatusline", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoMultipleStatusLine
    check result.boolValue == true

  test "Set smartcase on":
    let handler = setupHandler()
    let result = handler.executeSet("smartcase", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoSmartCase
    check result.boolValue == true

  test "Set incsearch on":
    let handler = setupHandler()
    let result = handler.executeSet("incsearch", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoIncSearch
    check result.boolValue == true

  test "Set buildonsave on":
    let handler = setupHandler()
    let result = handler.executeSet("buildonsave", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoBuildOnSave
    check result.boolValue == true

  test "Set showgitinactive on":
    let handler = setupHandler()
    let result = handler.executeSet("showgitinactive", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoShowGitInactive
    check result.boolValue == true

  test "Set wrap on":
    let handler = setupHandler()
    let result = handler.executeSet("wrap", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoLineWrap
    check result.boolValue == true

  test "Set nowrap off":
    let handler = setupHandler()
    let result = handler.executeSet("nowrap", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoLineWrap
    check result.boolValue == false

  # Test 'no' prefix versions (disable options)
  test "Set nostatusline off":
    let handler = setupHandler()
    let result = handler.executeSet("nostatusline", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoStatusLine
    check result.boolValue == false

  test "Set nocursorline off":
    let handler = setupHandler()
    let result = handler.executeSet("nocursorline", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoCursorLine
    check result.boolValue == false

  test "Set nocursorcolumn off":
    let handler = setupHandler()
    let result = handler.executeSet("nocursorcolumn", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoCursorColumn
    check result.boolValue == false

  test "Set nosyntax off":
    let handler = setupHandler()
    let result = handler.executeSet("nosyntax", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoSyntax
    check result.boolValue == false

  test "Set noautoindent off":
    let handler = setupHandler()
    let result = handler.executeSet("noautoindent", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoAutoIndent
    check result.boolValue == false

  test "Set nohlsearch off":
    let handler = setupHandler()
    let result = handler.executeSet("nohlsearch", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHlSearch
    check result.boolValue == false

  test "Set noignorecase off":
    let handler = setupHandler()
    let result = handler.executeSet("noignorecase", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoIgnoreCase
    check result.boolValue == false

  test "Set nosmartcase off":
    let handler = setupHandler()
    let result = handler.executeSet("nosmartcase", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoSmartCase
    check result.boolValue == false

  test "Set noincsearch off":
    let handler = setupHandler()
    let result = handler.executeSet("noincsearch", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoIncSearch
    check result.boolValue == false

  # Test abbreviations
  test "Set cursorline with abbreviation (cul)":
    let handler = setupHandler()
    let result = handler.executeSet("cul", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoCursorLine
    check result.boolValue == true

  test "Set cursorcolumn with abbreviation (cuc)":
    let handler = setupHandler()
    let result = handler.executeSet("cuc", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoCursorColumn
    check result.boolValue == true

  test "Set statusline with abbreviation (stl)":
    let handler = setupHandler()
    let result = handler.executeSet("stl", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoStatusLine
    check result.boolValue == true

  test "Set syntax with abbreviation (syn)":
    let handler = setupHandler()
    let result = handler.executeSet("syn", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoSyntax
    check result.boolValue == true

  test "Set autoindent with abbreviation (ai)":
    let handler = setupHandler()
    let result = handler.executeSet("ai", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoAutoIndent
    check result.boolValue == true

  test "Set hlsearch with abbreviation (hls)":
    let handler = setupHandler()
    let result = handler.executeSet("hls", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoHlSearch
    check result.boolValue == true

  test "Set ignorecase with abbreviation (ic)":
    let handler = setupHandler()
    let result = handler.executeSet("ic", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoIgnoreCase
    check result.boolValue == true

  test "Set smartcase with abbreviation (scs)":
    let handler = setupHandler()
    let result = handler.executeSet("scs", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoSmartCase
    check result.boolValue == true

  test "Set incsearch with abbreviation (is)":
    let handler = setupHandler()
    let result = handler.executeSet("is", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoIncSearch
    check result.boolValue == true

  test "Set smoothscroll with abbreviation (sms)":
    let handler = setupHandler()
    let result = handler.executeSet("sms", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoSmoothScroll
    check result.boolValue == true

  test "Set clipboard with abbreviation (cb)":
    let handler = setupHandler()
    let result = handler.executeSet("cb", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoClipboard
    check result.boolValue == true

  # Test 'no' prefix with abbreviations
  test "Set nocursorline with abbreviation (nocul)":
    let handler = setupHandler()
    let result = handler.executeSet("nocul", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoCursorLine
    check result.boolValue == false

  test "Set nocursorcolumn with abbreviation (nocuc)":
    let handler = setupHandler()
    let result = handler.executeSet("nocuc", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoCursorColumn
    check result.boolValue == false

  test "Set nostatusline with abbreviation (nostl)":
    let handler = setupHandler()
    let result = handler.executeSet("nostl", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoStatusLine
    check result.boolValue == false

  test "Set noautoindent with abbreviation (noai)":
    let handler = setupHandler()
    let result = handler.executeSet("noai", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoAutoIndent
    check result.boolValue == false

  test "Set unknown option returns error":
    let handler = setupHandler()
    let result = handler.executeSet("unknownoption", none(string))
    check result.kind == hrError
    check result.errorMessage == "Unknown option: unknownoption"

suite "CommandModeHandler - executeSet Integer Options":
  test "Set tabstop":
    let handler = setupHandler()
    let result = handler.executeSet("tabstop", some("4"))
    check result.kind == hrSetIntOption
    check result.intOption == isoTabStop
    check result.intValue == 4

  test "Set tabstop with abbreviation (ts)":
    let handler = setupHandler()
    let result = handler.executeSet("ts", some("8"))
    check result.kind == hrSetIntOption
    check result.intOption == isoTabStop
    check result.intValue == 8

  test "Set tabstop without value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("tabstop", none(string))
    check result.kind == hrError
    check result.errorMessage == "tabstop requires a value (e.g., tabstop=4)"

  test "Set tabstop with invalid value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("tabstop", some("abc"))
    check result.kind == hrError
    check result.errorMessage == "Invalid value for tabstop"

  test "Set tabstop with zero returns error":
    let handler = setupHandler()
    let result = handler.executeSet("tabstop", some("0"))
    check result.kind == hrError
    check result.errorMessage == "tabstop must be positive"

suite "CommandModeHandler - executeSet shiftWidth":
  test "Set shiftwidth":
    let handler = setupHandler()
    let result = handler.executeSet("shiftwidth", some("4"))
    check result.kind == hrSetIntOption
    check result.intOption == isoShiftWidth
    check result.intValue == 4

  test "Set shiftwidth with abbreviation (sw)":
    let handler = setupHandler()
    let result = handler.executeSet("sw", some("8"))
    check result.kind == hrSetIntOption
    check result.intOption == isoShiftWidth
    check result.intValue == 8

  test "Set shiftwidth to zero (use tabStop)":
    let handler = setupHandler()
    let result = handler.executeSet("sw", some("0"))
    check result.kind == hrSetIntOption
    check result.intOption == isoShiftWidth
    check result.intValue == 0

  test "Set shiftwidth without value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("shiftwidth", none(string))
    check result.kind == hrError

  test "Set shiftwidth with invalid value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("shiftwidth", some("abc"))
    check result.kind == hrError

  test "Set shiftwidth with negative returns error":
    let handler = setupHandler()
    let result = handler.executeSet("sw", some("-1"))
    check result.kind == hrError

suite "CommandModeHandler - executeSet softTabStop":
  test "Set softtabstop":
    let handler = setupHandler()
    let result = handler.executeSet("softtabstop", some("4"))
    check result.kind == hrSetIntOption
    check result.intOption == isoSoftTabStop
    check result.intValue == 4

  test "Set softtabstop with abbreviation (sts)":
    let handler = setupHandler()
    let result = handler.executeSet("sts", some("8"))
    check result.kind == hrSetIntOption
    check result.intOption == isoSoftTabStop
    check result.intValue == 8

  test "Set softtabstop to zero (use tabStop)":
    let handler = setupHandler()
    let result = handler.executeSet("sts", some("0"))
    check result.kind == hrSetIntOption
    check result.intOption == isoSoftTabStop
    check result.intValue == 0

  test "Set softtabstop without value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("softtabstop", none(string))
    check result.kind == hrError

  test "Set softtabstop with invalid value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("softtabstop", some("abc"))
    check result.kind == hrError

  test "Set softtabstop with negative returns error":
    let handler = setupHandler()
    let result = handler.executeSet("sts", some("-1"))
    check result.kind == hrError

suite "CommandModeHandler - executeSet Scrollbar":
  test "Set scrollbar on":
    let handler = setupHandler()
    let result = handler.executeSet("scrollbar", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoScrollbar
    check result.boolValue == true

  test "Set noscrollbar off":
    let handler = setupHandler()
    let result = handler.executeSet("noscrollbar", none(string))
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoScrollbar
    check result.boolValue == false

  test "Set scrollbarwidth":
    let handler = setupHandler()
    let result = handler.executeSet("scrollbarwidth", some("2"))
    check result.kind == hrSetIntOption
    check result.intOption == isoScrollbarWidth
    check result.intValue == 2

  test "Set scrollbarwidth to 0":
    let handler = setupHandler()
    let result = handler.executeSet("scrollbarwidth", some("0"))
    check result.kind == hrSetIntOption
    check result.intOption == isoScrollbarWidth
    check result.intValue == 0

  test "Set scrollbarwidth without value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("scrollbarwidth", none(string))
    check result.kind == hrError
    check "requires a value" in result.errorMessage

  test "Set scrollbarwidth with invalid value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("scrollbarwidth", some("abc"))
    check result.kind == hrError
    check "Invalid value" in result.errorMessage

  test "Set scrollbarwidth with negative value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("scrollbarwidth", some("-1"))
    check result.kind == hrError
    check "must be non-negative" in result.errorMessage

suite "CommandModeHandler - executeSet Float Options":
  test "Set scrollfriction":
    let handler = setupHandler()
    let result = handler.executeSet("scrollfriction", some("80.0"))
    check result.kind == hrSetFloatOption
    check result.floatOption == fsoScrollFriction
    check result.floatValue == 80.0

  test "Set scrollairdrag":
    let handler = setupHandler()
    let result = handler.executeSet("scrollairdrag", some("2.5"))
    check result.kind == hrSetFloatOption
    check result.floatOption == fsoScrollAirDrag
    check result.floatValue == 2.5

  test "Set scrollfriction without value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("scrollfriction", none(string))
    check result.kind == hrError
    check "requires a value" in result.errorMessage

  test "Set scrollairdrag with negative value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("scrollairdrag", some("-1.0"))
    check result.kind == hrError
    check "non-negative" in result.errorMessage

suite "CommandModeHandler - executeHelp":
  test "Execute help command":
    let handler = setupHandler()
    let result = handler.executeHelp(none(string))
    check result.kind == hrEnterHelpViewer

  test "Execute help with topic":
    let handler = setupHandler()
    let result = handler.executeHelp(some("commands"))
    check result.kind == hrEnterHelpViewer

suite "CommandModeHandler - executeVSplit and executeHSplit":
  test "Vertical split without filename":
    let handler = setupHandler()
    let result = handler.executeVSplit(none(string))
    check result.kind == hrVSplit
    check result.vsplitFilename.isNone

  test "Vertical split with filename":
    let handler = setupHandler()
    let result = handler.executeVSplit(some("test.nim"))
    check result.kind == hrVSplit
    check result.vsplitFilename.isSome
    check result.vsplitFilename.get == "test.nim"

  test "Vertical split with directory":
    let handler = setupHandler()
    let result = handler.executeVSplit(some("/tmp"))
    check result.kind == hrVSplit
    check result.vsplitFilename == some("/tmp")

  test "Horizontal split without filename":
    let handler = setupHandler()
    let result = handler.executeHSplit(none(string))
    check result.kind == hrHSplit
    check result.hsplitFilename.isNone

  test "Horizontal split with filename":
    let handler = setupHandler()
    let result = handler.executeHSplit(some("test.nim"))
    check result.kind == hrHSplit
    check result.hsplitFilename.isSome

  test "Horizontal split with directory":
    let handler = setupHandler()
    let result = handler.executeHSplit(some("/tmp"))
    check result.kind == hrHSplit
    check result.hsplitFilename == some("/tmp")

suite "CommandModeHandler - executeNew/executeVnew/executeEnew":
  test "Execute new":
    let handler = setupHandler()
    let result = handler.executeNew()
    check result.kind == hrNew

  test "Execute vnew":
    let handler = setupHandler()
    let result = handler.executeVnew()
    check result.kind == hrVnew

  test "Execute enew":
    let handler = setupHandler()
    let result = handler.executeEnew()
    check result.kind == hrEnew

suite "CommandModeHandler - Buffer Navigation":
  test "Execute buffer next":
    let handler = setupHandler()
    let result = handler.executeBufferNext()
    check result.kind == hrBufferNext

  test "Execute buffer prev":
    let handler = setupHandler()
    let result = handler.executeBufferPrev()
    check result.kind == hrBufferPrev

  test "Execute buffer first":
    let handler = setupHandler()
    let result = handler.executeBufferFirst()
    check result.kind == hrBufferFirst

  test "Execute buffer last":
    let handler = setupHandler()
    let result = handler.executeBufferLast()
    check result.kind == hrBufferLast

  test "Execute buffer by number":
    let handler = setupHandler()
    let result = handler.executeBuffer("3")
    check result.kind == hrBuffer
    check result.bufferArg == "3"

  test "Execute buffer by name":
    let handler = setupHandler()
    let result = handler.executeBuffer("test.nim")
    check result.kind == hrBuffer
    check result.bufferArg == "test.nim"

suite "CommandModeHandler - executeBufferDelete":
  test "Delete unmodified buffer":
    let handler = setupHandler()
    let buffer = setupBuffer()
    buffer.markSaved()

    let result = handler.executeBufferDelete(buffer, force = false)
    check result.kind == hrBufferDelete
    check result.forceBufferDelete == false

  test "Delete modified buffer without force returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeBufferDelete(buffer, force = false)
    check result.kind == hrError
    check result.errorMessage == "No write since last change (add ! to override)"

  test "Delete modified buffer with force":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeBufferDelete(buffer, force = true)
    check result.kind == hrBufferDelete
    check result.forceBufferDelete == true

suite "CommandModeHandler - raw buffer gates":
  test "stripwhitespace refuses a raw buffer":
    # strip removes any trailing 0x09/0x20, which in UTF-16 can be half of a
    # code unit; the rest of the line then shifts by an odd number of bytes.
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "Hello   ")
    buffer.keepRaw = true

    let result = handler.executeStripWhitespace(buffer)

    check result.kind == hrError
    check "raw undecodable bytes" in result.errorMessage
    check buffer.getLine(0) == "Hello   "

  test "substitute refuses a raw buffer":
    # The pattern is matched byte-wise, so it can land inside a code unit.
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "Hello")
    buffer.keepRaw = true

    let result = handler.executeSubstitute(buffer, "l", "L", "g")

    check result.kind == hrError
    check "raw undecodable bytes" in result.errorMessage
    check buffer.getLine(0) == "Hello"

suite "CommandModeHandler - executeStripWhitespace":
  test "Strip whitespace from lines":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "Hello   ")
    discard buffer.insert(1, "World  ")
    discard buffer.insert(2, "NoTrailing")

    let result = handler.executeStripWhitespace(buffer)
    check result.kind == hrStripWhitespace
    check result.strippedLineCount == 2
    check buffer.getLine(0) == "Hello"
    check buffer.getLine(1) == "World"
    check buffer.getLine(2) == "NoTrailing"

  test "Strip whitespace with no trailing spaces":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line1", "Line2"])

    let result = handler.executeStripWhitespace(buffer)
    check result.kind == hrStripWhitespace
    check result.strippedLineCount == 0

  test "Strip whitespace on read-only buffer reports error and leaves buffer intact":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello   ", "World  "])
    buffer.readOnly = true

    let result = handler.executeStripWhitespace(buffer)
    check result.kind == hrError
    check result.errorMessage == "Buffer is read-only"
    check buffer.getLine(0) == "Hello   "
    check buffer.getLine(1) == "World  "

suite "CommandModeHandler - executeQuickRun":
  test "Execute quickrun":
    let handler = setupHandler()
    let result = handler.executeQuickRun()
    check result.kind == hrQuickRun

suite "CommandModeHandler - executeSubstitute":
  test "Substitute on current line":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let result = handler.executeSubstitute(
      buffer,
      "hello",
      "hi",
      "",
      hasRange = false,
      isGlobalRange = false,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check result.hrSubstituteCount == 1
    check buffer.getLine(0) == "hi world"

  test "Substitute all occurrences with g flag":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello hello hello")

    let result = handler.executeSubstitute(
      buffer,
      "hello",
      "hi",
      "g",
      hasRange = false,
      isGlobalRange = false,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check result.hrSubstituteCount == 3
    check buffer.getLine(0) == "hi hi hi"

  test "Substitute first occurrence without g flag":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello hello hello")

    let result = handler.executeSubstitute(
      buffer,
      "hello",
      "hi",
      "",
      hasRange = false,
      isGlobalRange = false,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check result.hrSubstituteCount == 1
    check buffer.getLine(0) == "hi hello hello"

  test "Substitute on all lines with global range":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
    discard buffer.insert(1, "foo")
    discard buffer.insert(2, "foo")

    let result = handler.executeSubstitute(
      buffer,
      "foo",
      "bar",
      "",
      hasRange = false,
      isGlobalRange = true,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check result.hrSubstituteCount == 3
    check buffer.getLine(0) == "bar"
    check buffer.getLine(1) == "bar"
    check buffer.getLine(2) == "bar"

  test "Substitute on line range":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
    discard buffer.insert(1, "foo")
    discard buffer.insert(2, "foo")
    discard buffer.insert(3, "foo")

    let result = handler.executeSubstitute(
      buffer,
      "foo",
      "bar",
      "",
      hasRange = true,
      isGlobalRange = false,
      startLine = 2,
      endLine = 3,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check result.hrSubstituteCount == 2
    check buffer.getLine(0) == "foo"
    check buffer.getLine(1) == "bar"
    check buffer.getLine(2) == "bar"
    check buffer.getLine(3) == "foo"

  test "Substitute with empty pattern returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["hello"])

    let result = handler.executeSubstitute(
      buffer,
      "",
      "replacement",
      "",
      hasRange = false,
      isGlobalRange = false,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrError
    check result.errorMessage == "Pattern required"

  test "Substitute with no matches returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["hello world"])

    let result = handler.executeSubstitute(
      buffer,
      "xyz",
      "replacement",
      "",
      hasRange = false,
      isGlobalRange = false,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrError
    check "Pattern not found" in result.errorMessage

  test "Substitute with escape sequences":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")

    let result = handler.executeSubstitute(
      buffer,
      "hello",
      "hi\\nworld",
      "",
      hasRange = false,
      isGlobalRange = false,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check buffer.getLine(0) == "hi\nworld"

  test "Substitute with invalid range (start > end) returns error":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
    discard buffer.insert(1, "bar")
    discard buffer.insert(2, "baz")

    let result = handler.executeSubstitute(
      buffer,
      "foo",
      "replaced",
      "",
      hasRange = true,
      isGlobalRange = false,
      startLine = 3,
      endLine = 1,
      currentLine = 0,
    )
    check result.kind == hrError
    check "Invalid range" in result.errorMessage

  test "Substitute with empty replacement (delete pattern)":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let result = handler.executeSubstitute(
      buffer,
      "hello ",
      "",
      "",
      hasRange = false,
      isGlobalRange = false,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check result.hrSubstituteCount == 1
    check buffer.getLine(0) == "world"

  test "Substitute on read-only buffer reports error and leaves buffer intact":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    buffer.readOnly = true

    let result = handler.executeSubstitute(
      buffer,
      "hello",
      "hi",
      "",
      hasRange = false,
      isGlobalRange = false,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrError
    check result.errorMessage == "Buffer is read-only"
    check buffer.getLine(0) == "hello world"

suite "CommandModeHandler - handleCommandModeInput":
  test "Empty command returns to normal mode":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":")
    check result.kind == hrHandled
    check result.modeTransition == some(EditorMode.Normal)

  test "Handle :q command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":q")
    check result.kind == hrCloseWindow

  test "Handle :q! command":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.handleCommandModeInput(buffer, ":q!")
    check result.kind == hrCloseWindow
    check result.forceClose == true

  test "Handle :w command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":w")
    check result.kind == hrSave

  test "Handle :w filename command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":w test.txt")
    check result.kind == hrSave
    check result.saveFilename.isSome
    check result.saveFilename.get == "test.txt"

  test "Handle :wq command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":wq")
    check result.kind == hrSaveAndQuit

  test "Handle :x and :xit on a clean buffer":
    let handler = setupHandler()
    let buffer = setupBuffer()

    check handler.handleCommandModeInput(buffer, ":x").kind == hrQuit
    check handler.handleCommandModeInput(buffer, ":xit").kind == hrQuit

  test "Handle :x on a modified buffer":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.handleCommandModeInput(buffer, ":x")

    check result.kind == hrSaveAndQuit

  test "Handle :wa command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":wa")
    check result.kind == hrSaveAll
    check result.forceSaveAll == false

  test "Handle :wa! command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":wa!")
    check result.kind == hrSaveAll
    check result.forceSaveAll == true

  test "Handle :wqa command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":wqa")
    check result.kind == hrSaveAllAndQuit
    check result.forceSaveAllAndQuitAfter == false

  test "Handle :wqa! command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":wqa!")
    check result.kind == hrSaveAllAndQuit
    check result.forceSaveAllAndQuitAfter == true

  test "Handle :qa command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":qa")
    check result.kind == hrQuit

  test "Handle :cq command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":cq")
    check result.kind == hrCquit

  test "Handle :cq with modified buffer":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.handleCommandModeInput(buffer, ":cq")
    check result.kind == hrCquit

  test "Handle :123 (goto line)":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line 1", "Line 2", "Line 3"])

    let result = handler.handleCommandModeInput(buffer, ":2")
    check result.kind == hrGotoLine
    check result.lineNumber == 2

  test "Handle :set number":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":set number")
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoNumber
    check result.boolValue == true

  test "Handle :set relativenumber":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":set relativenumber")
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoRelativeNumber
    check result.boolValue == true

  test "Handle :set nornu":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":set nornu")
    check result.kind == hrSetBoolOption
    check result.boolOption == bsoRelativeNumber
    check result.boolValue == false

  test "Handle :help command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":help")
    check result.kind == hrEnterHelpViewer

  test "Handle :undo and :redo commands":
    let handler = setupHandler()
    let buffer = setupBuffer()

    check handler.handleCommandModeInput(buffer, ":u").kind == hrUndo
    check handler.handleCommandModeInput(buffer, ":undo").kind == hrUndo
    check handler.handleCommandModeInput(buffer, ":redo").kind == hrRedo

  test "Handle :vs command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":vs")
    check result.kind == hrVSplit

  test "Handle :sp command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":sp")
    check result.kind == hrHSplit

  test "Handle :new command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":new")
    check result.kind == hrNew

  test "Handle :vnew command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":vnew")
    check result.kind == hrVnew

  test "Handle :only command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":only")
    check result.kind == hrOnlyWindow

  test "Handle :bn command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bn")
    check result.kind == hrBufferNext

  test "Handle :bp command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bp")
    check result.kind == hrBufferPrev

  test "Handle :bd command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bd")
    check result.kind == hrBufferDelete

  test "Handle :log command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":log")
    check result.kind == hrEnterLogViewer

  test "Handle :! shell command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":!ls -la")
    check result.kind == hrShellCommand
    check result.shellCommand == "ls -la"

  test "Handle :bg command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bg")
    check result.kind == hrBackground

  test "Handle :build command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":build")
    check result.kind == hrBuild

  test "Handle :debug command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":debug")
    check result.kind == hrDebug

  test "Handle :config command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":config")
    check result.kind == hrConfig

  test "Handle :lsplog command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lsplog")
    check result.kind == hrLspLog

  test "Handle :lspformat command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspformat")
    check result.kind == hrLspFormat

  test "Handle :lsprestart command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lsprestart")
    check result.kind == hrLspRestart

  test "Handle :jump command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":jump")
    check result.kind == hrJumpList

  test "Handle :changes command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":changes")
    check result.kind == hrChanges

  test "Handle :man command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":man test")
    check result.kind == hrMan
    check result.hrManPage == "test"

  test "Handle :recent command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":recent")
    when defined(macosx):
      check result.kind == hrError
      check result.errorMessage == ":recent is not supported on macOS"
    else:
      check result.kind == hrRecentFile

  test "Handle :backup command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":backup")
    check result.kind == hrEnterBackupManager

  test "Handle :theme command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":theme dark")
    check result.kind == hrTheme
    check result.hrThemeName == "dark"

  test "Handle :lspfold command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspfold")
    check result.kind == hrLspFold

  test "Handle :lspexecommand command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspexecommand mycommand arg1")
    check result.kind == hrLspExecuteCommand
    check result.hrLspCommand == "mycommand"

  test "Handle :lspcallhierarchyincoming command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspcallhierarchyincoming")
    check result.kind == hrLspCallHierarchyIncoming

  test "Handle :lspcallhierarchyoutgoing command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspcallhierarchyoutgoing")
    check result.kind == hrLspCallHierarchyOutgoing

  test "Handle :e filename command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":e test.nim")
    check result.kind == hrEdit
    check result.editFilename.get.endsWith("test.nim")

  test "Handle :b buffer number command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":b 2")
    check result.kind == hrBuffer
    check result.bufferArg == "2"

  test "Handle :%s substitute command":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
    discard buffer.insert(1, "foo")

    let result = handler.handleCommandModeInput(buffer, ":%s/foo/bar/")
    check result.kind == hrSubstitute

  test "Handle :s substitute command on current line":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let result = handler.handleCommandModeInput(buffer, ":s/hello/hi/", currentLine = 0)
    check result.kind == hrSubstitute
    check result.hrSubstituteCount == 1

  test "Handle :bnext command (alias for :bn)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bnext")
    check result.kind == hrBufferNext

  test "Handle :bprev command (alias for :bp)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bprev")
    check result.kind == hrBufferPrev

  test "Handle :bfirst command (alias for :bf)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bfirst")
    check result.kind == hrBufferFirst

  test "Handle :blast command (alias for :bl)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":blast")
    check result.kind == hrBufferLast

  test "Handle :bdelete command (alias for :bd)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bdelete")
    check result.kind == hrBufferDelete

  test "Handle :ls command (alias for :buffers)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":ls")
    check result.kind == hrEnterBufferManager

  test "Handle :messages command (alias for :log)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":messages")
    check result.kind == hrEnterLogViewer

  test "Handle :quickrun command (alias for :run)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":quickrun")
    check result.kind == hrQuickRun

  # Range substitute commands
  test "Handle :1,10s/foo/bar/ range substitute command":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
    discard buffer.insert(1, "foo")
    discard buffer.insert(2, "foo")

    let result = handler.handleCommandModeInput(buffer, ":1,2s/foo/bar/")
    check result.kind == hrSubstitute

  test "Handle :5s/foo/bar/ single line substitute command":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    for i in 0 .. 5:
      if i == 0:
        discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
      else:
        discard buffer.insert(i, "foo")

    let result = handler.handleCommandModeInput(buffer, ":3s/foo/bar/")
    check result.kind == hrSubstitute

  test "Handle :%s/foo/bar/g global substitute with g flag":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo foo")
    discard buffer.insert(1, "foo foo")

    let result = handler.handleCommandModeInput(buffer, ":%s/foo/bar/g")
    check result.kind == hrSubstitute
    check result.hrSubstituteCount == 4

  test "Handle unknown command returns error":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":unknowncommand")
    check result.kind == hrError

suite "CommandModeHandler - handleCommandModeInput map commands":
  test "Handle :nmap returns hrMapAdd":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":nmap C-s Escape")
    check result.kind == hrMapAdd
    check result.mapAddLhs == "C-s"
    check result.mapAddRhs == "Escape"
    check EditorMode.Normal in result.mapAddModes
    check result.mapAddModes.len == 1

  test "Handle :imap returns hrMapAdd for Insert":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":imap jj Escape")
    check result.kind == hrMapAdd
    check result.mapAddLhs == "jj"
    check result.mapAddRhs == "Escape"
    check EditorMode.Insert in result.mapAddModes

  test "Handle :vmap returns hrMapAdd for Visual modes":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":vmap C-c Escape")
    check result.kind == hrMapAdd
    check EditorMode.Visual in result.mapAddModes
    check EditorMode.VisualBlock in result.mapAddModes
    check EditorMode.VisualLine in result.mapAddModes

  test "Handle :rmap returns hrMapAdd for Replace":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":rmap C-a Escape")
    check result.kind == hrMapAdd
    check EditorMode.Replace in result.mapAddModes

  test "Handle :map returns hrMapAdd for all modes":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":map C-a Escape")
    check result.kind == hrMapAdd
    check result.mapAddModes.len == 6

  test "Handle :nunmap returns hrMapRemove":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":nunmap C-s")
    check result.kind == hrMapRemove
    check result.mapRemoveLhs == "C-s"
    check EditorMode.Normal in result.mapRemoveModes

  test "Handle :unmap returns hrMapRemove for all modes":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":unmap C-s")
    check result.kind == hrMapRemove
    check result.mapRemoveModes.len == 6

  test "Handle :nmapclear returns hrMapClear":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":nmapclear")
    check result.kind == hrMapClear
    check EditorMode.Normal in result.mapClearModes

  test "Handle :mapclear returns hrMapClear for all modes":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":mapclear")
    check result.kind == hrMapClear
    check result.mapClearModes.len == 6

  test "Handle :nnoremap alias":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":nnoremap C-a g g")
    check result.kind == hrMapAdd
    check result.mapAddLhs == "C-a"
    check result.mapAddRhs == "g g"
    check EditorMode.Normal in result.mapAddModes

  test "Handle :nmap without args returns hrMapList":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":nmap")
    check result.kind == hrMapList
    check result.mapListModes == @[EditorMode.Normal]

  test "Handle :map without args returns hrMapList for all modes":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":map")
    check result.kind == hrMapList
    check result.mapListModes.len == 6

  test "Handle :nmap with only LHS returns hrMapList with prefix":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":nmap C-s")
    check result.kind == hrMapList
    check result.mapListModes == @[EditorMode.Normal]
    check result.mapListPrefix == "C-s"

  test "Handle :map with only LHS returns hrMapList with prefix for all modes":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":map C-s")
    check result.kind == hrMapList
    check result.mapListModes.len == 6
    check result.mapListPrefix == "C-s"

suite "CommandModeHandler - executeSet enum coverage":
  ## Verify that every setting enum value is reachable from executeSet.
  ## If a new enum value is added but no :set option string maps to it,
  ## these tests will fail.

  test "Every BoolSettingOption is reachable via executeSet":
    let handler = setupHandler()

    # Map from primary option name to the enum value it produces.
    const boolOptions: seq[(string, BoolSettingOption)] = @[
      ("number", bsoNumber),
      ("relativenumber", bsoRelativeNumber),
      ("cursorline", bsoCursorLine),
      ("cursorcolumn", bsoCursorColumn),
      ("statusline", bsoStatusLine),
      ("syntax", bsoSyntax),
      ("indentationlines", bsoIndentationLines),
      ("autoindent", bsoAutoIndent),
      ("autocloseparen", bsoAutoCloseParen),
      ("autodeleteparen", bsoAutoDeleteParen),
      ("clipboard", bsoClipboard),
      ("smoothscroll", bsoSmoothScroll),
      ("livereload", bsoLiveReloadOfConf),
      ("icon", bsoShowIcons),
      ("highlightcurrentline", bsoHighlightCurrentLine),
      ("highlightcurrentword", bsoHighlightCurrentWord),
      ("highlightfullspace", bsoHighlightFullWidthSpace),
      ("highlightparen", bsoHighlightPairOfParen),
      ("highlightfindchar", bsoHighlightFindChar),
      ("highlightcolorcode", bsoHighlightColorCode),
      ("highlightgitconflict", bsoHighlightGitConflict),
      ("highlightgitconflicttwocolor", bsoHighlightGitConflictTwoColor),
      ("multistatusline", bsoMultipleStatusLine),
      ("ignorecase", bsoIgnoreCase),
      ("smartcase", bsoSmartCase),
      ("incsearch", bsoIncSearch),
      ("hlsearch", bsoHlSearch),
      ("buildonsave", bsoBuildOnSave),
      ("showgitinactive", bsoShowGitInactive),
      ("wrap", bsoLineWrap),
      ("expandtab", bsoExpandTab),
      ("scrollbar", bsoScrollbar),
    ]

    # Verify each option returns the expected enum value
    var coveredValues: HashSet[BoolSettingOption]
    for (name, expected) in boolOptions:
      let r = handler.executeSet(name, none(string))
      check r.kind == hrSetBoolOption
      check r.boolOption == expected
      coveredValues.incl(r.boolOption)

    # Verify all enum values are covered
    for v in BoolSettingOption:
      check v in coveredValues

  test "Every IntSettingOption is reachable via executeSet":
    let handler = setupHandler()

    const intOptions: seq[(string, IntSettingOption)] = @[
      ("tabstop", isoTabStop),
      ("shiftwidth", isoShiftWidth),
      ("softtabstop", isoSoftTabStop),
      ("scrollbarwidth", isoScrollbarWidth),
    ]

    var coveredValues: HashSet[IntSettingOption]
    for (name, expected) in intOptions:
      let r = handler.executeSet(name, some("1"))
      check r.kind == hrSetIntOption
      check r.intOption == expected
      coveredValues.incl(r.intOption)

    for v in IntSettingOption:
      check v in coveredValues

  test "Every FloatSettingOption is reachable via executeSet":
    let handler = setupHandler()

    const floatOptions: seq[(string, FloatSettingOption)] =
      @[("scrollfriction", fsoScrollFriction), ("scrollairdrag", fsoScrollAirDrag)]

    var coveredValues: HashSet[FloatSettingOption]
    for (name, expected) in floatOptions:
      let r = handler.executeSet(name, some("1.0"))
      check r.kind == hrSetFloatOption
      check r.floatOption == expected
      coveredValues.incl(r.floatOption)

    for v in FloatSettingOption:
      check v in coveredValues

suite "CommandModeHandler - executeDelete":
  test "Delete current line":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")
    discard buffer.insert(2, "line3")

    let result = handler.executeDelete(
      buffer, hasRange = false, isGlobalRange = false, currentLine = 1
    )
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 1
    check result.hrDeletedText == "line2\n"
    check buffer.len == 2
    check buffer.getLine(0) == "line1"
    check buffer.getLine(1) == "line3"

  test "Delete all lines with :%d":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")
    discard buffer.insert(2, "line3")

    let result = handler.executeDelete(buffer, hasRange = false, isGlobalRange = true)
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 3
    check result.hrDeletedText == "line1\nline2\nline3\n"
    check buffer.len == 1
    check buffer.getLine(0) == ""

  test "Delete line range":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")
    discard buffer.insert(2, "line3")
    discard buffer.insert(3, "line4")

    let result = handler.executeDelete(
      buffer, hasRange = true, isGlobalRange = false, startLine = 2, endLine = 3
    )
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 2
    check result.hrDeletedText == "line2\nline3\n"
    check buffer.len == 2
    check buffer.getLine(0) == "line1"
    check buffer.getLine(1) == "line4"

  test "Delete with invalid range returns error":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")

    let result = handler.executeDelete(
      buffer, hasRange = true, isGlobalRange = false, startLine = 3, endLine = 1
    )
    check result.kind == hrError

  test "Delete single line by range":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")
    discard buffer.insert(2, "line3")

    let result = handler.executeDelete(
      buffer, hasRange = true, isGlobalRange = false, startLine = 2, endLine = 2
    )
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 1
    check buffer.len == 2
    check buffer.getLine(0) == "line1"
    check buffer.getLine(1) == "line3"

  test "Delete on single-line buffer leaves one empty line":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "only line")

    let result = handler.executeDelete(
      buffer, hasRange = false, isGlobalRange = false, currentLine = 0
    )
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 1
    check result.hrDeletedText == "only line\n"
    check buffer.len == 1
    check buffer.getLine(0) == ""

  test "Delete first line":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")
    discard buffer.insert(2, "line3")

    let result = handler.executeDelete(
      buffer, hasRange = false, isGlobalRange = false, currentLine = 0
    )
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 1
    check result.hrDeletedText == "line1\n"
    check buffer.len == 2
    check buffer.getLine(0) == "line2"
    check buffer.getLine(1) == "line3"

  test "Delete last line":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")
    discard buffer.insert(2, "line3")

    let result = handler.executeDelete(
      buffer, hasRange = false, isGlobalRange = false, currentLine = 2
    )
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 1
    check result.hrDeletedText == "line3\n"
    check buffer.len == 2
    check buffer.getLine(0) == "line1"
    check buffer.getLine(1) == "line2"

  test "Delete with dot range (currentLine resolution)":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")
    discard buffer.insert(2, "line3")
    discard buffer.insert(3, "line4")

    # startLine=0 means current line, endLine=3 means line 3 (1-based)
    let result = handler.executeDelete(
      buffer,
      hasRange = true,
      isGlobalRange = false,
      startLine = 0,
      endLine = 3,
      currentLine = 1,
    )
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 2
    check result.hrDeletedText == "line2\nline3\n"
    check buffer.len == 2
    check buffer.getLine(0) == "line1"
    check buffer.getLine(1) == "line4"

  test "Delete with endLine beyond buffer is clamped":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")

    let result = handler.executeDelete(
      buffer, hasRange = true, isGlobalRange = false, startLine = 1, endLine = 100
    )
    check result.kind == hrDeleteLines
    check result.hrDeletedLineCount == 2
    check result.hrDeletedText == "line1\nline2\n"
    check buffer.len == 1
    check buffer.getLine(0) == ""

  test "Delete with startLine beyond buffer returns error":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")

    let result = handler.executeDelete(
      buffer, hasRange = true, isGlobalRange = false, startLine = 10, endLine = 20
    )
    check result.kind == hrError

  test "Delete on read-only buffer reports error and does not populate deleted text":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buffer.insert(1, "line2")
    buffer.readOnly = true

    let result = handler.executeDelete(
      buffer, hasRange = false, isGlobalRange = false, currentLine = 0
    )
    # hrError instead of hrDeleteLines guarantees result_processor's
    # setDeletedRegister branch never fires -- the register cannot be polluted.
    check result.kind == hrError
    check result.errorMessage == "Buffer is read-only"
    check buffer.len == 2
    check buffer.getLine(0) == "line1"
    check buffer.getLine(1) == "line2"

suite "CommandModeHandler - fold auto-expand on edit":
  test "substitute reveals a collapsed fold on a modified line":
    let handler = setupHandler()
    let buffer = setupBuffer(@["aaa", "foo", "bbb", "ccc"])
    check buffer.foldState.addFold(1, 3, collapsed = true)
    # :2s/foo/bar/  -> 1-based line 2 == index 1 (the fold start, hidden text)
    let result = handler.executeSubstitute(
      buffer,
      "foo",
      "bar",
      "",
      hasRange = true,
      isGlobalRange = false,
      startLine = 2,
      endLine = 2,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check buffer.getLine(1) == "bar"
    check buffer.foldState.getFoldAt(1).get.collapsed == false

  test "substitute leaves a fold without a match closed":
    let handler = setupHandler()
    let buffer = setupBuffer(@["foo", "bbb", "ccc", "ddd"])
    check buffer.foldState.addFold(1, 3, collapsed = true) # no 'foo' inside
    # :%s/foo/bar/ matches only line 0
    let result = handler.executeSubstitute(
      buffer,
      "foo",
      "bar",
      "",
      hasRange = false,
      isGlobalRange = true,
      startLine = 0,
      endLine = 0,
      currentLine = 0,
    )
    check result.kind == hrSubstitute
    check buffer.getLine(0) == "bar"
    check buffer.foldState.getFoldAt(1).get.collapsed == true

  test "delete reveals a collapsed fold overlapping the range":
    let handler = setupHandler()
    let buffer = setupBuffer(@["a", "b", "c", "d", "e", "f"])
    check buffer.foldState.addFold(2, 4, collapsed = true)
    # :3d -> 1-based line 3 == index 2
    let result = handler.executeDelete(
      buffer,
      hasRange = true,
      isGlobalRange = false,
      startLine = 3,
      endLine = 3,
      currentLine = 0,
    )
    check result.kind == hrDeleteLines
    let f = buffer.foldState.getFoldAt(2)
    check f.isSome
    check f.get.collapsed == false

  test "stripwhitespace reveals a fold on a stripped line":
    let handler = setupHandler()
    let buffer = setupBuffer(@["aaa", "bbb   ", "ccc", "ddd"])
    check buffer.foldState.addFold(1, 3, collapsed = true)
    let result = handler.executeStripWhitespace(buffer)
    check result.kind == hrStripWhitespace
    check buffer.getLine(1) == "bbb"
    check buffer.foldState.getFoldAt(1).get.collapsed == false
