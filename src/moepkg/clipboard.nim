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
## This module provides async clipboard read/write functionality using external
## clipboard tools like xclip, xsel, wl-clipboard, etc.

import std/[options]

import pkg/results
import pkg/chronos
import pkg/chronos/asyncproc

import config

type ClipboardError* = object of CatchableError ## Error type for clipboard operations

proc getClipboardCommand*(tool: ClipboardTool, operation: string): Option[seq[string]] =
  ## Get the command to execute for clipboard operations
  ## operation can be "read" or "write"
  ## Note: Tool availability is checked at runtime, not here
  case tool
  of ctXclip:
    case operation
    of "read":
      return some(@["xclip", "-selection", "clipboard", "-o"])
    of "write":
      return some(@["xclip", "-selection", "clipboard", "-i"])
    else:
      return none(seq[string])
  of ctXsel:
    case operation
    of "read":
      return some(@["xsel", "--clipboard", "--output"])
    of "write":
      return some(@["xsel", "--clipboard", "--input"])
    else:
      return none(seq[string])
  of ctWlClipboard:
    case operation
    of "read":
      return some(@["wl-paste", "-n"])
    of "write":
      return some(@["wl-copy"])
    else:
      return none(seq[string])
  of ctWin32yank:
    case operation
    of "read":
      return some(@["win32yank.exe", "-o", "--lf"])
    of "write":
      return some(@["win32yank.exe", "-i", "--crlf"])
    else:
      return none(seq[string])
  of ctPbcopy:
    # macOS pbcopy/pbpaste
    case operation
    of "read":
      return some(@["pbpaste"])
    of "write":
      return some(@["pbcopy"])
    else:
      return none(seq[string])

proc readFromClipboard*(
    tool: ClipboardTool
): Future[Result[string, string]] {.async: (raises: []).} =
  ## Read text from system clipboard asynchronously
  ## Returns the clipboard content as a string, or an error message
  let cmdOpt = getClipboardCommand(tool, "read")
  if cmdOpt.isNone:
    return Result[string, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  try:
    const
      WorkingDir = ""
      Env = nil
    let opts: set[AsyncProcessOption] = {UsePath}

    let process = await startProcess(
      cmd[0], WorkingDir, cmd[1 ..^ 1], Env, opts,
      stdoutHandle = AsyncProcess.Pipe,
      stdinHandle = AsyncProcess.Pipe,
    )

    # Read all output from stdout
    var output = ""
    while true:
      var buf = newSeq[byte](4096)
      let bytesRead = await process.stdoutStream.readOnce(addr buf[0], buf.len)
      if bytesRead == 0:
        break
      output.add(cast[string](buf[0 ..< bytesRead]))

    let exitCode = await process.waitForExit()

    if exitCode == 0:
      return Result[string, string].ok(output)
    else:
      return Result[string, string].err(
        "Failed to read from clipboard: exit code " & $exitCode
      )
  except CancelledError:
    return Result[string, string].err("Clipboard read cancelled")
  except CatchableError as e:
    return Result[string, string].err("Failed to read from clipboard: " & e.msg)

proc writeToClipboard*(
    tool: ClipboardTool, text: string
): Future[Result[void, string]] {.async: (raises: []).} =
  ## Write text to system clipboard asynchronously
  ## Returns ok() on success, or an error message
  let cmdOpt = getClipboardCommand(tool, "write")
  if cmdOpt.isNone:
    return Result[void, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  try:
    const
      WorkingDir = ""
      Env = nil
    let opts: set[AsyncProcessOption] = {UsePath}

    let process = await startProcess(
      cmd[0], WorkingDir, cmd[1 ..^ 1], Env, opts,
      stdoutHandle = AsyncProcess.Pipe,
      stdinHandle = AsyncProcess.Pipe,
    )

    # Write text to stdin and close to signal EOF
    let textBytes = cast[seq[byte]](text)
    if textBytes.len > 0:
      await process.stdinStream.write(textBytes)
    await process.stdinStream.closeWait()

    let exitCode = await process.waitForExit()

    if exitCode == 0:
      return Result[void, string].ok()
    else:
      return Result[void, string].err(
        "Failed to write to clipboard: exit code " & $exitCode
      )
  except CancelledError:
    return Result[void, string].err("Clipboard write cancelled")
  except CatchableError as e:
    return Result[void, string].err("Failed to write to clipboard: " & e.msg)

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

# Synchronous wrapper for clipboard read with timeout
proc readFromClipboardSync*(
    tool: ClipboardTool, timeoutMs: int = 1000
): Result[string, string] =
  ## Read from clipboard synchronously with timeout
  ## Uses async internally with waitFor, but has a timeout to prevent long blocks
  let future = readFromClipboard(tool)
  try:
    let completed = waitFor withTimeout(future, milliseconds(timeoutMs))
    if not completed:
      return Result[string, string].err("Clipboard read timeout")
    return future.read()
  except CatchableError as e:
    return Result[string, string].err("Clipboard read failed: " & e.msg)

