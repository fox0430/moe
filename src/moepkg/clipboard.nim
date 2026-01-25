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

import std/[options, osproc, streams]

import pkg/results
import pkg/chronos

import config

type
  ClipboardOperation = enum
    read
    write

  ClipboardError* = object of CatchableError ## Error type for clipboard operations

proc getClipboardCommand*(tool: ClipboardTool, operation: ClipboardOperation): Option[seq[string]] =
  ## Get the command to execute for clipboard operations
  ## operation can be "read" or "write"
  ## Note: Tool availability is checked at runtime, not here
  case tool
  of ctXclip:
    case operation
    of read:
      return some(@["xclip", "-selection", "clipboard", "-o"])
    of write:
      return some(@["xclip", "-selection", "clipboard", "-i"])
  of ctXsel:
    case operation
    of read:
      return some(@["xsel", "--clipboard", "--output"])
    of write:
      return some(@["xsel", "--clipboard", "--input"])
  of ctWlClipboard:
    case operation
    of read:
      return some(@["wl-paste", "-n"])
    of write:
      return some(@["wl-copy"])
  of ctWin32yank:
    case operation
    of read:
      return some(@["win32yank.exe", "-o", "--lf"])
    of write:
      return some(@["win32yank.exe", "-i", "--crlf"])
  of ctPbcopy:
    # macOS pbcopy/pbpaste
    case operation
    of read:
      return some(@["pbpaste"])
    of write:
      return some(@["pbcopy"])

proc readFromClipboardSync*(tool: ClipboardTool): Result[string, string] =
  ## Read text from system clipboard synchronously
  ## Returns the clipboard content as a string, or an error message
  let cmdOpt = getClipboardCommand(tool, read)
  if cmdOpt.isNone:
    return Result[string, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  try:
    let process =
      startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath, poStdErrToStdOut})
    let output = process.outputStream.readAll()
    let exitCode = process.waitForExit()
    process.close()

    if exitCode == 0:
      return Result[string, string].ok(output)
    else:
      return Result[string, string].err(
        "Failed to read from clipboard: exit code " & $exitCode
      )
  except CatchableError as e:
    return Result[string, string].err("Failed to read from clipboard: " & e.msg)

proc writeToClipboardSync*(tool: ClipboardTool, text: string): Result[void, string] =
  ## Write text to system clipboard synchronously using osproc
  ## Returns ok() on success, or an error message
  let cmdOpt = getClipboardCommand(tool, write)
  if cmdOpt.isNone:
    return Result[void, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  try:
    # wl-copy accepts text as positional argument
    if tool == ctWlClipboard:
      var args = cmd[1 ..^ 1]
      args.add(text)
      let process = startProcess(cmd[0], args = args, options = {poUsePath})
      let exitCode = process.waitForExit()
      process.close()
      if exitCode == 0:
        return Result[void, string].ok()
      else:
        return Result[void, string].err(
          "Failed to write to clipboard: exit code " & $exitCode
        )
    else:
      # Other tools (xclip, xsel, pbcopy, win32yank) use stdin
      let process = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})
      process.inputStream.write(text)
      process.inputStream.close()
      let exitCode = process.waitForExit()
      process.close()

      if exitCode == 0:
        return Result[void, string].ok()
      else:
        return Result[void, string].err(
          "Failed to write to clipboard: exit code " & $exitCode
        )
  except CatchableError as e:
    return Result[void, string].err("Failed to write to clipboard: " & e.msg)

proc readFromClipboard*(
    tool: ClipboardTool
): Future[Result[string, string]] {.async: (raises: []).} =
  ## Read text from system clipboard (async wrapper)
  return readFromClipboardSync(tool)

proc writeToClipboard*(
    tool: ClipboardTool, text: string
): Future[Result[void, string]] {.async: (raises: []).} =
  ## Write text to system clipboard (async wrapper)
  return writeToClipboardSync(tool, text)

# Internal async wrapper that discards the result
proc writeToClipboardInternal(
    tool: ClipboardTool, text: string
): Future[void] {.async: (raises: []).} =
  discard await writeToClipboard(tool, text)

# Fire-and-forget wrapper for clipboard write
proc writeToClipboardAsync*(tool: ClipboardTool, text: string) =
  ## Write text to clipboard in the background (fire-and-forget)
  ## This does not block and errors are silently ignored
  asyncSpawn writeToClipboardInternal(tool, text)
