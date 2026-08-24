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

import std/[options, os, osproc, streams]

import pkg/results

import config, encoding

type
  ClipboardOperation = enum
    read
    write

  ClipboardError* = object of CatchableError ## Error type for clipboard operations

const WriteTimeoutMs = 10_000
  ## Timeout for blocking on a hung clipboard tool. wl-copy is exempt:
  ## it is polled briefly instead and may keep serving the selection.

proc getClipboardCommand*(
    tool: ClipboardTool, operation: ClipboardOperation
): Option[seq[string]] =
  ## Get the command to execute for clipboard operations
  ## operation can be "read" or "write"
  ## Note: Tool availability is checked at runtime, not here
  case tool
  of cbtXclip:
    case operation
    of read:
      return some(@["xclip", "-selection", "clipboard", "-o"])
    of write:
      return some(@["xclip", "-selection", "clipboard", "-i"])
  of cbtXsel:
    case operation
    of read:
      return some(@["xsel", "--clipboard", "--output"])
    of write:
      return some(@["xsel", "--clipboard", "--input"])
  of cbtWlClipboard:
    case operation
    of read:
      return some(@["wl-paste", "-n"])
    of write:
      return some(@["wl-copy"])
  of cbtWin32yank:
    case operation
    of read:
      return some(@["win32yank.exe", "-o", "--lf"])
    of write:
      return some(@["win32yank.exe", "-i", "--crlf"])
  of cbtPbcopy:
    # macOS pbcopy/pbpaste
    case operation
    of read:
      return some(@["pbpaste"])
    of write:
      return some(@["pbcopy"])

proc getPrimarySelectionReadCommand*(tool: ClipboardTool): Option[seq[string]] =
  ## Get the command to read from X11 PRIMARY selection (middle-click paste).
  ## PRIMARY selection holds text selected by mouse highlighting.
  case tool
  of cbtXclip:
    return some(@["xclip", "-selection", "primary", "-o"])
  of cbtXsel:
    # xsel reads from PRIMARY by default (no --clipboard flag)
    return some(@["xsel", "--output"])
  of cbtWlClipboard:
    return some(@["wl-paste", "-n", "--primary"])
  of cbtWin32yank, cbtPbcopy:
    # Windows/macOS don't have PRIMARY selection; fall back to clipboard
    return getClipboardCommand(tool, read)

proc readFromPrimarySelectionSync*(tool: ClipboardTool): Result[string, string] =
  ## Read text from X11 PRIMARY selection synchronously.
  ## PRIMARY selection is what middle-click paste uses in X11.
  let cmdOpt = getPrimarySelectionReadCommand(tool)
  if cmdOpt.isNone:
    return Result[string, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  var process: Process = nil
  try:
    process =
      startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath, poStdErrToStdOut})
    let output = process.outputStream.readAll()
    let exitCode = process.waitForExit()

    if exitCode == 0:
      return Result[string, string].ok(sanitizeInvalidUtf8(output))
    else:
      return Result[string, string].err(
        "Failed to read from primary selection: exit code " & $exitCode
      )
  except CatchableError as e:
    return Result[string, string].err("Failed to read from primary selection: " & e.msg)
  finally:
    if not process.isNil:
      try:
        process.close()
      except CatchableError:
        discard

proc getPrimarySelectionWriteCommand*(tool: ClipboardTool): Option[seq[string]] =
  ## Get the command to write to X11 PRIMARY selection.
  case tool
  of cbtXclip:
    return some(@["xclip", "-selection", "primary", "-i"])
  of cbtXsel:
    # xsel writes to PRIMARY by default (no --clipboard flag)
    return some(@["xsel", "--input"])
  of cbtWlClipboard:
    return some(@["wl-copy", "--primary"])
  of cbtWin32yank, cbtPbcopy:
    return getClipboardCommand(tool, write)

proc wlCopyExitedEarly(process: Process): Option[int] =
  ## Exit code if wl-copy exits right after startup, none if it keeps running.
  ## On wl-clipboard 2.x the parent exits once the write landed and a
  ## background child keeps serving the selection.
  var i = 0
  while i < 5:
    let exitCode = process.peekExitCode()
    if exitCode != -1:
      return some(exitCode)
    sleep(10)
    inc i
  return none(int)

proc writeToPrimarySelectionSync*(
    tool: ClipboardTool, text: string
): Result[bool, string] =
  ## Write text to X11 PRIMARY selection synchronously.
  ## ok(true) means the tool terminated (the write landed); ok(false) means
  ## it keeps running (the write may not be reflected yet).
  let cmdOpt = getPrimarySelectionWriteCommand(tool)
  if cmdOpt.isNone:
    return Result[bool, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  var process: Process = nil
  try:
    if tool == cbtWlClipboard:
      # wl-copy's parent exits once the write landed; an early non-zero exit
      # means the write failed, no observed exit that it is unconfirmed.
      process = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})
      process.inputStream.write(text)
      process.inputStream.close()
      let earlyExit = process.wlCopyExitedEarly()
      if earlyExit.isSome and earlyExit.get != 0:
        return Result[bool, string].err(
          "Failed to write to primary selection: exit code " & $earlyExit.get
        )
      return Result[bool, string].ok(earlyExit.isSome)
    else:
      process = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})
      process.inputStream.write(text)
      process.inputStream.close()
      let exitCode = process.waitForExit(WriteTimeoutMs)
      if exitCode == 0:
        return Result[bool, string].ok(true)
      elif exitCode == 128 + 9:
        # 128 + SIGKILL: the WriteTimeoutMs timeout terminated the tool
        return Result[bool, string].err(
          "Failed to write to primary selection: the tool did not exit within " &
            $WriteTimeoutMs & "ms and was killed"
        )
      else:
        return Result[bool, string].err(
          "Failed to write to primary selection: exit code " & $exitCode
        )
  except CatchableError as e:
    return Result[bool, string].err("Failed to write to primary selection: " & e.msg)
  finally:
    if not process.isNil:
      try:
        process.close()
      except CatchableError:
        discard

proc readFromClipboardSync*(tool: ClipboardTool): Result[string, string] =
  ## Read text from system clipboard synchronously
  ## Returns the clipboard content as a string, or an error message
  let cmdOpt = getClipboardCommand(tool, read)
  if cmdOpt.isNone:
    return Result[string, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  var process: Process = nil
  try:
    process =
      startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath, poStdErrToStdOut})
    let output = process.outputStream.readAll()
    let exitCode = process.waitForExit()

    if exitCode == 0:
      return Result[string, string].ok(sanitizeInvalidUtf8(output))
    else:
      return Result[string, string].err(
        "Failed to read from clipboard: exit code " & $exitCode
      )
  except CatchableError as e:
    return Result[string, string].err("Failed to read from clipboard: " & e.msg)
  finally:
    if not process.isNil:
      try:
        process.close()
      except CatchableError:
        discard

proc writeToClipboardSync*(tool: ClipboardTool, text: string): Result[bool, string] =
  ## Write text to system clipboard synchronously.
  ## ok(true) means the tool terminated (the write landed); ok(false) means
  ## it keeps running (the write may not be reflected yet).
  let cmdOpt = getClipboardCommand(tool, write)
  if cmdOpt.isNone:
    return Result[bool, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  var process: Process = nil
  try:
    if tool == cbtWlClipboard:
      # wl-copy's parent exits once the write landed; an early non-zero exit
      # means the write failed, no observed exit that it is unconfirmed.
      process = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})
      process.inputStream.write(text)
      process.inputStream.close()
      let earlyExit = process.wlCopyExitedEarly()
      if earlyExit.isSome and earlyExit.get != 0:
        return Result[bool, string].err(
          "Failed to write to clipboard: exit code " & $earlyExit.get
        )
      return Result[bool, string].ok(earlyExit.isSome)
    else:
      # Other tools (xclip, xsel, pbcopy, win32yank) use stdin
      process = startProcess(cmd[0], args = cmd[1 ..^ 1], options = {poUsePath})
      process.inputStream.write(text)
      process.inputStream.close()
      let exitCode = process.waitForExit(WriteTimeoutMs)

      if exitCode == 0:
        return Result[bool, string].ok(true)
      elif exitCode == 128 + 9:
        # 128 + SIGKILL: the WriteTimeoutMs timeout terminated the tool
        return Result[bool, string].err(
          "Failed to write to clipboard: the tool did not exit within " & $WriteTimeoutMs &
            "ms and was killed"
        )
      else:
        return Result[bool, string].err(
          "Failed to write to clipboard: exit code " & $exitCode
        )
  except CatchableError as e:
    return Result[bool, string].err("Failed to write to clipboard: " & e.msg)
  finally:
    if not process.isNil:
      try:
        process.close()
      except CatchableError:
        discard
