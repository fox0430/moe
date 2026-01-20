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

## System clipboard integration using external tools
##
## This module provides clipboard read/write functionality using external
## clipboard tools like xclip, xsel, wl-clipboard, etc.

import std/[osproc, options, streams]

import pkg/results

import config, buffer, types

type ClipboardError* = object of CatchableError ## Error type for clipboard operations

proc isToolAvailable*(toolCommand: string): bool =
  ## Check if a command-line tool is available in PATH
  ## Returns true if the tool can be found, false otherwise
  let checkResult = execCmdEx("command -v " & toolCommand)
  return checkResult.exitCode == 0

proc getClipboardCommand*(tool: ClipboardTool, operation: string): Option[seq[string]] =
  ## Get the command to execute for clipboard operations
  ## operation can be "read" or "write"
  ## Returns none if tool is not available or unsupported
  case tool
  of ctXclip:
    if not isToolAvailable("xclip"):
      return none(seq[string])
    case operation
    of "read":
      return some(@["xclip", "-selection", "clipboard", "-o"])
    of "write":
      return some(@["xclip", "-selection", "clipboard", "-i"])
    else:
      return none(seq[string])
  of ctXsel:
    if not isToolAvailable("xsel"):
      return none(seq[string])
    case operation
    of "read":
      return some(@["xsel", "--clipboard", "--output"])
    of "write":
      return some(@["xsel", "--clipboard", "--input"])
    else:
      return none(seq[string])
  of ctWlClipboard:
    if not isToolAvailable("wl-copy"):
      return none(seq[string])
    case operation
    of "read":
      return some(@["wl-paste", "-n"])
    of "write":
      return some(@["wl-copy"])
    else:
      return none(seq[string])
  of ctWin32yank:
    if not isToolAvailable("win32yank.exe"):
      return none(seq[string])
    case operation
    of "read":
      return some(@["win32yank.exe", "-o", "--lf"])
    of "write":
      return some(@["win32yank.exe", "-i", "--crlf"])
    else:
      return none(seq[string])
  of ctPbcopy:
    # macOS pbcopy/pbpaste
    if not isToolAvailable("pbcopy"):
      return none(seq[string])
    case operation
    of "read":
      return some(@["pbpaste"])
    of "write":
      return some(@["pbcopy"])
    else:
      return none(seq[string])

proc readFromClipboard*(tool: ClipboardTool): Result[string, string] =
  ## Read text from system clipboard
  ## Returns the clipboard content as a string, or an error message
  let cmdOpt = getClipboardCommand(tool, "read")
  if cmdOpt.isNone:
    return Result[string, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  try:
    # Use startProcess instead of execCmdEx to avoid shell adding newline
    let p = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})
    let output = p.outputStream.readAll()
    let exitCode = p.waitForExit()
    p.close()

    if exitCode == 0:
      return Result[string, string].ok(output)
    else:
      return Result[string, string].err(
        "Failed to read from clipboard: exit code " & $exitCode
      )
  except OSError as e:
    return Result[string, string].err("Failed to execute clipboard command: " & e.msg)
  except IOError as e:
    return Result[string, string].err("Failed to read clipboard output: " & e.msg)

proc writeToClipboard*(tool: ClipboardTool, text: string): Result[(), string] =
  ## Write text to system clipboard
  ## Returns ok() on success, or an error message
  let cmdOpt = getClipboardCommand(tool, "write")
  if cmdOpt.isNone:
    return Result[(), string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  try:
    # Create a temporary pipe to feed text to the clipboard command
    let process = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})

    # Write text to stdin using streams
    let inputStream = process.inputStream
    inputStream.write(text)
    inputStream.close()

    let exitCode = process.waitForExit()
    process.close()

    if exitCode == 0:
      return Result[(), string].ok ()
    else:
      return
        Result[(), string].err("Failed to write to clipboard: exit code " & $exitCode)
  except OSError as e:
    return Result[(), string].err("Failed to execute clipboard command: " & e.msg)
  except IOError as e:
    return Result[(), string].err("Failed to write to clipboard: " & e.msg)

proc getSelectedText*(state: EditorState, buffer: TextBuffer): string =
  ## Get the currently selected text in visual mode
  ## Returns empty string if no active selection
  if not state.visualSelection.active:
    return ""

  # Normalize selection range (ensure start <= end)
  let (selStart, selEnd) =
    if state.visualSelection.start.line < state.visualSelection.current.line:
      (state.visualSelection.start, state.visualSelection.current)
    elif state.visualSelection.start.line > state.visualSelection.current.line:
      (state.visualSelection.current, state.visualSelection.start)
    else:
      # Same line - compare columns
      if state.visualSelection.start.column <= state.visualSelection.current.column:
        (state.visualSelection.start, state.visualSelection.current)
      else:
        (state.visualSelection.current, state.visualSelection.start)

  return buffer.getTextInRange(selStart, selEnd)

proc getCurrentLineText*(state: EditorState, buffer: TextBuffer): string =
  ## Get the text of the current line (where cursor is positioned)
  ## Returns the full line content including trailing newline if present
  if state.cursor.line < 0 or state.cursor.line >= buffer.len:
    return ""

  return buffer.getLine(state.cursor.line)
