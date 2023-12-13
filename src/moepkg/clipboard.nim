#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[os, osproc, strformat, strutils]
import pkg/results
import independentutils, settings, unicodeext

proc linesToString(lines: Runes | seq[Runes]): string =
  result = lines.toString
  result.stripLineEnd

proc genHereDocument(cmd, delimiterStr, buf: string): string {.inline.} =
  cmd &
  " <<" &
  "'" &
  delimiterStr &
  "'" &
  "\n" &
  buf &
  "\n" &
  delimiterStr &
  "\n"

proc xselCopyCommand(delimiterStr, buf: string): string {.inline.} =
  genHereDocument("xsel", delimiterStr, buf)

proc xclipCopyCommand(delimiterStr, buf: string): string {.inline.} =
  genHereDocument("xclip", delimiterStr, buf)

proc wlClipboardCopyComand(delimiterStr, buf: string): string {.inline.} =
  genHereDocument("wl-copy", delimiterStr, buf)

proc wslDefaultCopyCommand(delimiterStr, buf: string): string {.inline.} =
  genHereDocument("clip.exe", delimiterStr, buf)

proc macOsDefaultCopyCommand(delimiterStr, buf: string): string {.inline.} =
 genHereDocument("pbcopy", delimiterStr, buf)

proc xselPasteCommand(): string {.inline.} = "xsel -o"

proc xclipPasteCommand(): string {.inline.} = "xclip -o"

proc wlClipboardPasteCommand(): string {.inline.} = "wl-paste"

proc wslDefaultPasteCommand(): string {.inline.} =
  "powershell.exe -Command Get-Clipboard"

proc macOsDefaultPasteCommand(): string {.inline.} = "pbpaste"

proc sendToClipboard*(
  buffer: Runes | seq[Runes],
  tool: ClipboardTool): Result[(), string] =
    ## Send the buffer to the OS clipboard (xclip, xsel, etc).

    if buffer.isEmpty: return

    let
      buf = linesToString(buffer)
      delimiterStr = genDelimiterStr(buf)
      cmd =
        case tool:
          of xsel: xselCopyCommand(delimiterStr, buf)
          of xclip: xclipCopyCommand(delimiterStr, buf)
          of wlClipboard: wlClipboardCopyComand(delimiterStr, buf)
          of wslDefault: wslDefaultCopyCommand(delimiterStr, buf)
          of macOsDefault: macOsDefaultCopyCommand(delimiterStr, buf)

    if execShellCmd(cmd) != 0:
      return Result[(), string].err "Error: Clipboard: copy failed"

    return Result[(), string].ok ()

proc getFromClipboard*(tool: ClipboardTool): Result[Runes, string] =
  ## Return the buffer from the OS clipboard.

  let cmd =
    case tool:
      of xsel: xselPasteCommand()
      of xclip: xclipPasteCommand()
      of wlClipboard: wlClipboardPasteCommand()
      of wslDefault: wslDefaultPasteCommand()
      of macOsDefault: macOsDefaultPasteCommand()

  let cmdResult = execCmdEx(cmd)
  if cmdResult.exitCode != 0:
    return Result[Runes, string].err fmt"Error: Clipboard: Failed to get clipboard buffer: {$cmdResult}"

  var buf = cmdResult.output
  case tool:
    of wlClipboard, wslDefault:
      # Remove two newlines.
      for i in 0 .. 1: buf.stripLineEnd
    else:
      buf.stripLineEnd

  return Result[Runes, string].ok buf.toRunes
