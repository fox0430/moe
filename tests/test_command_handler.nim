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

import std/[unittest, options, strutils]
import pkg/results
import ../src/moepkg/[buffer, command_line, command_config, command_registry, modes]
import ../src/moepkg/command_handlers/command_handler

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
  buf.modified = false
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
    buffer.modified = false

    let result = handler.executeQuit(buffer, force = false)
    check result.kind == cmrCloseWindow
    check result.forceClose == false

  test "Quit modified buffer without force returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuit(buffer, force = false)
    check result.kind == cmrError
    check result.errorMessage == "No write since last change (add ! to override)"

  test "Quit modified buffer with force":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuit(buffer, force = true)
    check result.kind == cmrCloseWindow
    check result.forceClose == true

  test "Quit shared buffer skips modification check":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuit(buffer, force = false, isSharedBuffer = true)
    check result.kind == cmrCloseWindow
    check result.forceClose == false

suite "CommandModeHandler - executeSave":
  test "Save without filename":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSave(buffer, none(string), force = false)
    check result.kind == cmrSave
    check result.saveFilename.isNone
    check result.forceSave == false

  test "Save with filename":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSave(buffer, some("test.txt"), force = false)
    check result.kind == cmrSave
    check result.saveFilename.isSome
    check result.saveFilename.get == "test.txt"

  test "Force save":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSave(buffer, none(string), force = true)
    check result.kind == cmrSave
    check result.forceSave == true

suite "CommandModeHandler - executeSaveAndQuit":
  test "Save and quit without filename":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSaveAndQuit(buffer, none(string), force = false)
    check result.kind == cmrSaveAndQuit
    check result.saveAndQuitFilename.isNone
    check result.forceSaveAndQuit == false

  test "Save and quit with filename":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeSaveAndQuit(buffer, some("test.txt"), force = true)
    check result.kind == cmrSaveAndQuit
    check result.saveAndQuitFilename.get == "test.txt"
    check result.forceSaveAndQuit == true

suite "CommandModeHandler - executeQuitAll":
  test "Quit all with unmodified buffer":
    let handler = setupHandler()
    let buffer = setupBuffer()
    buffer.modified = false

    let result = handler.executeQuitAll(buffer, force = false)
    check result.kind == cmrQuit
    check result.forceQuit == false

  test "Quit all with modified buffer without force":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuitAll(buffer, force = false)
    check result.kind == cmrError
    check result.errorMessage == "No write since last change (add ! to override)"

  test "Quit all with modified buffer with force":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeQuitAll(buffer, force = true)
    check result.kind == cmrQuit
    check result.forceQuit == true

suite "CommandModeHandler - executeEdit":
  test "Edit existing file":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeEdit(buffer, "test.nim")
    check result.kind == cmrEdit
    check result.editFilename.endsWith("test.nim")

  test "Edit directory opens filer":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.executeEdit(buffer, "/tmp")
    check result.kind == cmrFiler
    check result.filerPath.isSome
    check result.filerPath.get == "/tmp"

suite "CommandModeHandler - executeGotoLine":
  test "Goto valid line number":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line 1", "Line 2", "Line 3"])

    let result = handler.executeGotoLine(buffer, 2)
    check result.kind == cmrGotoLine
    check result.lineNumber == 2

  test "Goto line 0 returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line 1"])

    let result = handler.executeGotoLine(buffer, 0)
    check result.kind == cmrError
    check result.errorMessage == "Invalid line number"

  test "Goto line beyond buffer length returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line 1", "Line 2"])

    let result = handler.executeGotoLine(buffer, 100)
    check result.kind == cmrError
    check result.errorMessage == "Line number exceeds buffer length"

suite "CommandModeHandler - executeSet Boolean Options":
  test "Set number on":
    let handler = setupHandler()
    let result = handler.executeSet("number", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoNumber
    check result.boolValue == true

  test "Set number off (nonumber)":
    let handler = setupHandler()
    let result = handler.executeSet("nonumber", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoNumber
    check result.boolValue == false

  test "Set number with abbreviation (nu)":
    let handler = setupHandler()
    let result = handler.executeSet("nu", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoNumber
    check result.boolValue == true

  test "Set cursorline on":
    let handler = setupHandler()
    let result = handler.executeSet("cursorline", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoCursorLine
    check result.boolValue == true

  test "Set syntax on":
    let handler = setupHandler()
    let result = handler.executeSet("syntax", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoSyntax
    check result.boolValue == true

  test "Set autoindent on":
    let handler = setupHandler()
    let result = handler.executeSet("autoindent", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoAutoIndent
    check result.boolValue == true

  test "Set hlsearch on":
    let handler = setupHandler()
    let result = handler.executeSet("hlsearch", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoHlSearch
    check result.boolValue == true

  test "Set ignorecase on":
    let handler = setupHandler()
    let result = handler.executeSet("ignorecase", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoIgnoreCase
    check result.boolValue == true

  test "Set statusline on":
    let handler = setupHandler()
    let result = handler.executeSet("statusline", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoStatusLine
    check result.boolValue == true

  test "Set indentationlines on":
    let handler = setupHandler()
    let result = handler.executeSet("indentationlines", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoIndentationLines
    check result.boolValue == true

  test "Set autocloseparen on":
    let handler = setupHandler()
    let result = handler.executeSet("autocloseparen", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoAutoCloseParen
    check result.boolValue == true

  test "Set autodeleteparen on":
    let handler = setupHandler()
    let result = handler.executeSet("autodeleteparen", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoAutoDeleteParen
    check result.boolValue == true

  test "Set clipboard on":
    let handler = setupHandler()
    let result = handler.executeSet("clipboard", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoClipboard
    check result.boolValue == true

  test "Set smoothscroll on":
    let handler = setupHandler()
    let result = handler.executeSet("smoothscroll", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoSmoothScroll
    check result.boolValue == true

  test "Set livereload on":
    let handler = setupHandler()
    let result = handler.executeSet("livereload", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoLiveReloadOfConf
    check result.boolValue == true

  test "Set icon on":
    let handler = setupHandler()
    let result = handler.executeSet("icon", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoShowIcons
    check result.boolValue == true

  test "Set highlightcurrentline on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightcurrentline", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoHighlightCurrentLine
    check result.boolValue == true

  test "Set highlightcurrentword on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightcurrentword", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoHighlightCurrentWord
    check result.boolValue == true

  test "Set highlightfullspace on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightfullspace", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoHighlightFullWidthSpace
    check result.boolValue == true

  test "Set highlightparen on":
    let handler = setupHandler()
    let result = handler.executeSet("highlightparen", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoHighlightPairOfParen
    check result.boolValue == true

  test "Set multistatusline on":
    let handler = setupHandler()
    let result = handler.executeSet("multistatusline", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoMultipleStatusLine
    check result.boolValue == true

  test "Set smartcase on":
    let handler = setupHandler()
    let result = handler.executeSet("smartcase", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoSmartCase
    check result.boolValue == true

  test "Set incsearch on":
    let handler = setupHandler()
    let result = handler.executeSet("incsearch", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoIncSearch
    check result.boolValue == true

  test "Set buildonsave on":
    let handler = setupHandler()
    let result = handler.executeSet("buildonsave", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoBuildOnSave
    check result.boolValue == true

  test "Set showgitinactive on":
    let handler = setupHandler()
    let result = handler.executeSet("showgitinactive", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoShowGitInactive
    check result.boolValue == true

  test "Set wrap on":
    let handler = setupHandler()
    let result = handler.executeSet("wrap", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoLineWrap
    check result.boolValue == true

  test "Set nowrap off":
    let handler = setupHandler()
    let result = handler.executeSet("nowrap", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoLineWrap
    check result.boolValue == false

  # Test 'no' prefix versions (disable options)
  test "Set nostatusline off":
    let handler = setupHandler()
    let result = handler.executeSet("nostatusline", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoStatusLine
    check result.boolValue == false

  test "Set nocursorline off":
    let handler = setupHandler()
    let result = handler.executeSet("nocursorline", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoCursorLine
    check result.boolValue == false

  test "Set nosyntax off":
    let handler = setupHandler()
    let result = handler.executeSet("nosyntax", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoSyntax
    check result.boolValue == false

  test "Set noautoindent off":
    let handler = setupHandler()
    let result = handler.executeSet("noautoindent", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoAutoIndent
    check result.boolValue == false

  test "Set nohlsearch off":
    let handler = setupHandler()
    let result = handler.executeSet("nohlsearch", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoHlSearch
    check result.boolValue == false

  test "Set noignorecase off":
    let handler = setupHandler()
    let result = handler.executeSet("noignorecase", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoIgnoreCase
    check result.boolValue == false

  test "Set nosmartcase off":
    let handler = setupHandler()
    let result = handler.executeSet("nosmartcase", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoSmartCase
    check result.boolValue == false

  test "Set noincsearch off":
    let handler = setupHandler()
    let result = handler.executeSet("noincsearch", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoIncSearch
    check result.boolValue == false

  # Test abbreviations
  test "Set cursorline with abbreviation (cul)":
    let handler = setupHandler()
    let result = handler.executeSet("cul", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoCursorLine
    check result.boolValue == true

  test "Set statusline with abbreviation (stl)":
    let handler = setupHandler()
    let result = handler.executeSet("stl", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoStatusLine
    check result.boolValue == true

  test "Set syntax with abbreviation (syn)":
    let handler = setupHandler()
    let result = handler.executeSet("syn", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoSyntax
    check result.boolValue == true

  test "Set autoindent with abbreviation (ai)":
    let handler = setupHandler()
    let result = handler.executeSet("ai", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoAutoIndent
    check result.boolValue == true

  test "Set hlsearch with abbreviation (hls)":
    let handler = setupHandler()
    let result = handler.executeSet("hls", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoHlSearch
    check result.boolValue == true

  test "Set ignorecase with abbreviation (ic)":
    let handler = setupHandler()
    let result = handler.executeSet("ic", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoIgnoreCase
    check result.boolValue == true

  test "Set smartcase with abbreviation (scs)":
    let handler = setupHandler()
    let result = handler.executeSet("scs", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoSmartCase
    check result.boolValue == true

  test "Set incsearch with abbreviation (is)":
    let handler = setupHandler()
    let result = handler.executeSet("is", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoIncSearch
    check result.boolValue == true

  test "Set smoothscroll with abbreviation (sms)":
    let handler = setupHandler()
    let result = handler.executeSet("sms", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoSmoothScroll
    check result.boolValue == true

  test "Set clipboard with abbreviation (cb)":
    let handler = setupHandler()
    let result = handler.executeSet("cb", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoClipboard
    check result.boolValue == true

  # Test 'no' prefix with abbreviations
  test "Set nocursorline with abbreviation (nocul)":
    let handler = setupHandler()
    let result = handler.executeSet("nocul", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoCursorLine
    check result.boolValue == false

  test "Set nostatusline with abbreviation (nostl)":
    let handler = setupHandler()
    let result = handler.executeSet("nostl", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoStatusLine
    check result.boolValue == false

  test "Set noautoindent with abbreviation (noai)":
    let handler = setupHandler()
    let result = handler.executeSet("noai", none(string))
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoAutoIndent
    check result.boolValue == false

  test "Set unknown option returns error":
    let handler = setupHandler()
    let result = handler.executeSet("unknownoption", none(string))
    check result.kind == cmrError
    check result.errorMessage == "Unknown option: unknownoption"

suite "CommandModeHandler - executeSet Integer Options":
  test "Set tabstop":
    let handler = setupHandler()
    let result = handler.executeSet("tabstop", some("4"))
    check result.kind == cmrSetIntOption
    check result.intOption == isoTabStop
    check result.intValue == 4

  test "Set tabstop with abbreviation (ts)":
    let handler = setupHandler()
    let result = handler.executeSet("ts", some("8"))
    check result.kind == cmrSetIntOption
    check result.intOption == isoTabStop
    check result.intValue == 8

  test "Set tabstop without value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("tabstop", none(string))
    check result.kind == cmrError
    check result.errorMessage == "tabstop requires a value (e.g., tabstop=4)"

  test "Set tabstop with invalid value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("tabstop", some("abc"))
    check result.kind == cmrError
    check result.errorMessage == "Invalid value for tabstop"

  test "Set tabstop with zero returns error":
    let handler = setupHandler()
    let result = handler.executeSet("tabstop", some("0"))
    check result.kind == cmrError
    check result.errorMessage == "tabstop must be positive"

suite "CommandModeHandler - executeSet Float Options":
  test "Set scrollfriction":
    let handler = setupHandler()
    let result = handler.executeSet("scrollfriction", some("80.0"))
    check result.kind == cmrSetFloatOption
    check result.floatOption == fsoScrollFriction
    check result.floatValue == 80.0

  test "Set scrollairdrag":
    let handler = setupHandler()
    let result = handler.executeSet("scrollairdrag", some("2.5"))
    check result.kind == cmrSetFloatOption
    check result.floatOption == fsoScrollAirDrag
    check result.floatValue == 2.5

  test "Set scrollfriction without value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("scrollfriction", none(string))
    check result.kind == cmrError
    check "requires a value" in result.errorMessage

  test "Set scrollairdrag with negative value returns error":
    let handler = setupHandler()
    let result = handler.executeSet("scrollairdrag", some("-1.0"))
    check result.kind == cmrError
    check "non-negative" in result.errorMessage

suite "CommandModeHandler - executeHelp":
  test "Execute help command":
    let handler = setupHandler()
    let result = handler.executeHelp(none(string))
    check result.kind == cmrHelpViewer

  test "Execute help with topic":
    let handler = setupHandler()
    let result = handler.executeHelp(some("commands"))
    check result.kind == cmrHelpViewer

suite "CommandModeHandler - executeVSplit and executeHSplit":
  test "Vertical split without filename":
    let handler = setupHandler()
    let result = handler.executeVSplit(none(string))
    check result.kind == cmrVSplit
    check result.vsplitFilename.isNone

  test "Vertical split with filename":
    let handler = setupHandler()
    let result = handler.executeVSplit(some("test.nim"))
    check result.kind == cmrVSplit
    check result.vsplitFilename.isSome
    check result.vsplitFilename.get == "test.nim"

  test "Vertical split with directory":
    let handler = setupHandler()
    let result = handler.executeVSplit(some("/tmp"))
    check result.kind == cmrVSplit
    check result.vsplitFilename == some("/tmp")

  test "Horizontal split without filename":
    let handler = setupHandler()
    let result = handler.executeHSplit(none(string))
    check result.kind == cmrHSplit
    check result.hsplitFilename.isNone

  test "Horizontal split with filename":
    let handler = setupHandler()
    let result = handler.executeHSplit(some("test.nim"))
    check result.kind == cmrHSplit
    check result.hsplitFilename.isSome

  test "Horizontal split with directory":
    let handler = setupHandler()
    let result = handler.executeHSplit(some("/tmp"))
    check result.kind == cmrHSplit
    check result.hsplitFilename == some("/tmp")

suite "CommandModeHandler - executeNew/executeVnew/executeEnew":
  test "Execute new":
    let handler = setupHandler()
    let result = handler.executeNew()
    check result.kind == cmrNew

  test "Execute vnew":
    let handler = setupHandler()
    let result = handler.executeVnew()
    check result.kind == cmrVnew

  test "Execute enew":
    let handler = setupHandler()
    let result = handler.executeEnew()
    check result.kind == cmrEnew

suite "CommandModeHandler - Buffer Navigation":
  test "Execute buffer next":
    let handler = setupHandler()
    let result = handler.executeBufferNext()
    check result.kind == cmrBufferNext

  test "Execute buffer prev":
    let handler = setupHandler()
    let result = handler.executeBufferPrev()
    check result.kind == cmrBufferPrev

  test "Execute buffer first":
    let handler = setupHandler()
    let result = handler.executeBufferFirst()
    check result.kind == cmrBufferFirst

  test "Execute buffer last":
    let handler = setupHandler()
    let result = handler.executeBufferLast()
    check result.kind == cmrBufferLast

  test "Execute buffer by number":
    let handler = setupHandler()
    let result = handler.executeBuffer("3")
    check result.kind == cmrBuffer
    check result.bufferArg == "3"

  test "Execute buffer by name":
    let handler = setupHandler()
    let result = handler.executeBuffer("test.nim")
    check result.kind == cmrBuffer
    check result.bufferArg == "test.nim"

suite "CommandModeHandler - executeBufferDelete":
  test "Delete unmodified buffer":
    let handler = setupHandler()
    let buffer = setupBuffer()
    buffer.modified = false

    let result = handler.executeBufferDelete(buffer, force = false)
    check result.kind == cmrBufferDelete
    check result.forceBufferDelete == false

  test "Delete modified buffer without force returns error":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeBufferDelete(buffer, force = false)
    check result.kind == cmrError
    check result.errorMessage == "No write since last change (add ! to override)"

  test "Delete modified buffer with force":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.executeBufferDelete(buffer, force = true)
    check result.kind == cmrBufferDelete
    check result.forceBufferDelete == true

suite "CommandModeHandler - executeStripWhitespace":
  test "Strip whitespace from lines":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "Hello   ")
    discard buffer.insert(1, "World  ")
    discard buffer.insert(2, "NoTrailing")

    let result = handler.executeStripWhitespace(buffer)
    check result.kind == cmrStripWhitespace
    check result.strippedLineCount == 2
    check buffer.getLine(0) == "Hello"
    check buffer.getLine(1) == "World"
    check buffer.getLine(2) == "NoTrailing"

  test "Strip whitespace with no trailing spaces":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line1", "Line2"])

    let result = handler.executeStripWhitespace(buffer)
    check result.kind == cmrStripWhitespace
    check result.strippedLineCount == 0

suite "CommandModeHandler - executeQuickRun":
  test "Execute quickrun":
    let handler = setupHandler()
    let result = handler.executeQuickRun()
    check result.kind == cmrQuickRun

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
    check result.kind == cmrSubstitute
    check result.substitutePattern == "hello"
    check result.substituteReplacement == "hi"
    check result.substituteCount == 1
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
    check result.kind == cmrSubstitute
    check result.substituteGlobal == true
    check result.substituteCount == 3
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
    check result.kind == cmrSubstitute
    check result.substituteGlobal == false
    check result.substituteCount == 1
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
    check result.kind == cmrSubstitute
    check result.substituteCount == 3
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
    check result.kind == cmrSubstitute
    check result.substituteCount == 2
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
    check result.kind == cmrError
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
    check result.kind == cmrError
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
    check result.kind == cmrSubstitute
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
    check result.kind == cmrError
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
    check result.kind == cmrSubstitute
    check result.substituteCount == 1
    check buffer.getLine(0) == "world"

suite "CommandModeHandler - handleCommandModeInput":
  test "Empty command returns to normal mode":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":")
    check result.kind == cmrModeSwitch
    check result.targetMode == EditorMode.Normal

  test "Handle :q command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":q")
    check result.kind == cmrCloseWindow

  test "Handle :q! command":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Hello"])
    # Modify buffer to set isModified flag
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "!")

    let result = handler.handleCommandModeInput(buffer, ":q!")
    check result.kind == cmrCloseWindow
    check result.forceClose == true

  test "Handle :w command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":w")
    check result.kind == cmrSave

  test "Handle :w filename command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":w test.txt")
    check result.kind == cmrSave
    check result.saveFilename.isSome
    check result.saveFilename.get == "test.txt"

  test "Handle :wq command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":wq")
    check result.kind == cmrSaveAndQuit

  test "Handle :qa command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":qa")
    check result.kind == cmrQuit

  test "Handle :123 (goto line)":
    let handler = setupHandler()
    let buffer = setupBuffer(@["Line 1", "Line 2", "Line 3"])

    let result = handler.handleCommandModeInput(buffer, ":2")
    check result.kind == cmrGotoLine
    check result.lineNumber == 2

  test "Handle :set number":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":set number")
    check result.kind == cmrSetBoolOption
    check result.boolOption == bsoNumber
    check result.boolValue == true

  test "Handle :help command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":help")
    check result.kind == cmrHelpViewer

  test "Handle :vs command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":vs")
    check result.kind == cmrVSplit

  test "Handle :sp command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":sp")
    check result.kind == cmrHSplit

  test "Handle :new command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":new")
    check result.kind == cmrNew

  test "Handle :vnew command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":vnew")
    check result.kind == cmrVnew

  test "Handle :enew command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":enew")
    check result.kind == cmrEnew

  test "Handle :bn command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bn")
    check result.kind == cmrBufferNext

  test "Handle :bp command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bp")
    check result.kind == cmrBufferPrev

  test "Handle :bd command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bd")
    check result.kind == cmrBufferDelete

  test "Handle :Filer command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":Filer")
    check result.kind == cmrFiler

  test "Handle :log command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":log")
    check result.kind == cmrLogViewer

  test "Handle :run command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":run")
    check result.kind == cmrQuickRun

  test "Handle :buffers command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":buffers")
    check result.kind == cmrBufferManager

  test "Handle :nohlsearch command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":nohlsearch")
    check result.kind == cmrClearSearchHighlight

  test "Handle :! shell command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":!ls -la")
    check result.kind == cmrShellCommand
    check result.shellCommand == "ls -la"

  test "Handle :bg command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bg")
    check result.kind == cmrBackground

  test "Handle :build command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":build")
    check result.kind == cmrBuild

  test "Handle :debug command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":debug")
    check result.kind == cmrDebug

  test "Handle :config command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":config")
    check result.kind == cmrConfig

  test "Handle :lsplog command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lsplog")
    check result.kind == cmrLspLog

  test "Handle :lspformat command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspformat")
    check result.kind == cmrLspFormat

  test "Handle :lsprestart command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lsprestart")
    check result.kind == cmrLspRestart

  test "Handle :jump command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":jump")
    check result.kind == cmrJumpList

  test "Handle :man command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":man test")
    check result.kind == cmrMan
    check result.manPage == "test"

  test "Handle :recent command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":recent")
    when defined(macosx):
      check result.kind == cmrError
      check result.errorMessage == ":recent is not supported on macOS"
    else:
      check result.kind == cmrRecentFile

  test "Handle :backup command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":backup")
    check result.kind == cmrBackupManager

  test "Handle :theme command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":theme dark")
    check result.kind == cmrTheme
    check result.themeName == "dark"

  test "Handle :stripws command":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello   ")

    let result = handler.handleCommandModeInput(buffer, ":stripws")
    check result.kind == cmrStripWhitespace
    check result.strippedLineCount == 1

  test "Handle :lspfold command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspfold")
    check result.kind == cmrLspFold

  test "Handle :lspexecommand command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspexecommand mycommand arg1")
    check result.kind == cmrLspExecuteCommand
    check result.lspCommand == "mycommand"

  test "Handle :lspcallhierarchyincoming command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspcallhierarchyincoming")
    check result.kind == cmrLspCallHierarchyIncoming

  test "Handle :lspcallhierarchyoutgoing command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":lspcallhierarchyoutgoing")
    check result.kind == cmrLspCallHierarchyOutgoing

  test "Handle :e filename command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":e test.nim")
    check result.kind == cmrEdit
    check result.editFilename.endsWith("test.nim")

  test "Handle :b buffer number command":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":b 2")
    check result.kind == cmrBuffer
    check result.bufferArg == "2"

  test "Handle :%s substitute command":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
    discard buffer.insert(1, "foo")

    let result = handler.handleCommandModeInput(buffer, ":%s/foo/bar/")
    check result.kind == cmrSubstitute
    check result.substitutePattern == "foo"
    check result.substituteReplacement == "bar"

  test "Handle :s substitute command on current line":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let result = handler.handleCommandModeInput(buffer, ":s/hello/hi/", currentLine = 0)
    check result.kind == cmrSubstitute
    check result.substituteCount == 1

  test "Handle :filer command (lowercase)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":filer")
    check result.kind == cmrFiler

  # Command aliases
  test "Handle :x command (alias for :wq)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":x")
    check result.kind == cmrSaveAndQuit

  test "Handle :xit command (alias for :wq)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":xit")
    check result.kind == cmrSaveAndQuit

  test "Handle :quit command (alias for :q)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":quit")
    check result.kind == cmrCloseWindow

  test "Handle :write command (alias for :w)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":write")
    check result.kind == cmrSave

  test "Handle :edit command (alias for :e)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":edit test.nim")
    check result.kind == cmrEdit

  test "Handle :bnext command (alias for :bn)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bnext")
    check result.kind == cmrBufferNext

  test "Handle :bprev command (alias for :bp)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bprev")
    check result.kind == cmrBufferPrev

  test "Handle :bfirst command (alias for :bf)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bfirst")
    check result.kind == cmrBufferFirst

  test "Handle :blast command (alias for :bl)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":blast")
    check result.kind == cmrBufferLast

  test "Handle :bdelete command (alias for :bd)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":bdelete")
    check result.kind == cmrBufferDelete

  test "Handle :vsplit command (alias for :vs)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":vsplit")
    check result.kind == cmrVSplit

  test "Handle :split command (alias for :sp)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":split")
    check result.kind == cmrHSplit

  test "Handle :qall command (alias for :qa)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":qall")
    check result.kind == cmrQuit

  test "Handle :ls command (alias for :buffers)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":ls")
    check result.kind == cmrBufferManager

  test "Handle :messages command (alias for :log)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":messages")
    check result.kind == cmrLogViewer

  test "Handle :quickrun command (alias for :run)":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":quickrun")
    check result.kind == cmrQuickRun

  # Range substitute commands
  test "Handle :1,10s/foo/bar/ range substitute command":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
    discard buffer.insert(1, "foo")
    discard buffer.insert(2, "foo")

    let result = handler.handleCommandModeInput(buffer, ":1,2s/foo/bar/")
    check result.kind == cmrSubstitute

  test "Handle :5s/foo/bar/ single line substitute command":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    for i in 0 .. 5:
      if i == 0:
        discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo")
      else:
        discard buffer.insert(i, "foo")

    let result = handler.handleCommandModeInput(buffer, ":3s/foo/bar/")
    check result.kind == cmrSubstitute

  test "Handle :%s/foo/bar/g global substitute with g flag":
    let handler = setupHandler()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo foo")
    discard buffer.insert(1, "foo foo")

    let result = handler.handleCommandModeInput(buffer, ":%s/foo/bar/g")
    check result.kind == cmrSubstitute
    check result.substituteGlobal == true
    check result.substituteCount == 4

  test "Handle unknown command returns error":
    let handler = setupHandler()
    let buffer = setupBuffer()

    let result = handler.handleCommandModeInput(buffer, ":unknowncommand")
    check result.kind == cmrError

suite "CommandModeHandler - Result Helper Functions":
  test "shouldQuit returns true for quit result":
    let result = CommandModeResult(kind: cmrQuit, forceQuit: false)
    check shouldQuit(result) == true

  test "shouldQuit returns false for non-quit result":
    let result =
      CommandModeResult(kind: cmrSave, saveFilename: none(string), forceSave: false)
    check shouldQuit(result) == false

  test "shouldSwitchMode returns true for mode switch result":
    let result = CommandModeResult(kind: cmrModeSwitch, targetMode: EditorMode.Insert)
    check shouldSwitchMode(result) == true

  test "shouldSwitchMode returns false for non-mode switch result":
    let result =
      CommandModeResult(kind: cmrSave, saveFilename: none(string), forceSave: false)
    check shouldSwitchMode(result) == false

  test "getTargetMode returns target mode":
    let result = CommandModeResult(kind: cmrModeSwitch, targetMode: EditorMode.Insert)
    check getTargetMode(result) == EditorMode.Insert

  test "getTargetMode returns Normal for non-mode switch result":
    let result =
      CommandModeResult(kind: cmrSave, saveFilename: none(string), forceSave: false)
    check getTargetMode(result) == EditorMode.Normal

  test "hasError returns true for error result":
    let result = CommandModeResult(kind: cmrError, errorMessage: "Test error")
    check hasError(result) == true

  test "hasError returns false for non-error result":
    let result =
      CommandModeResult(kind: cmrSave, saveFilename: none(string), forceSave: false)
    check hasError(result) == false

  test "getMessage returns message for message result":
    let result = CommandModeResult(kind: cmrMessage, message: "Test message")
    check getMessage(result) == "Test message"

  test "getMessage returns error message for error result":
    let result = CommandModeResult(kind: cmrError, errorMessage: "Test error")
    check getMessage(result) == "Test error"

  test "getMessage returns empty string for other results":
    let result =
      CommandModeResult(kind: cmrSave, saveFilename: none(string), forceSave: false)
    check getMessage(result) == ""
