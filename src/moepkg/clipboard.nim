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
import independentutils, settings, unicodeext, platform

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

template xselCopyCommand(delimiterStr, buf: string): string =
  genHereDocument("xsel", delimiterStr, buf)

template xclipCopyCommand(delimiterStr, buf: string): string =
  genHereDocument("xclip", delimiterStr, buf)

template wlClipboardCopyCommand(delimiterStr, buf: string): string =
  genHereDocument("wl-copy", delimiterStr, buf)

template wslDefaultCopyCommand(delimiterStr, buf: string): string =
  genHereDocument("clip.exe", delimiterStr, buf)

template macOsDefaultCopyCommand(delimiterStr, buf: string): string =
  genHereDocument("pbcopy", delimiterStr, buf)

template xselPasteCommand(): string = "xsel -o"

template xclipPasteCommand(): string = "xclip -o"

template wlClipboardPasteCommand(): string = "wl-paste"

template wslDefaultPasteCommand(): string =
  "powershell.exe -Command Get-Clipboard"

template macOsDefaultPasteCommand(): string = "pbpaste"

template isXAvailable*(): bool =
  getEnv("XDG_SESSION_TYPE") == "x11"

template isWaylandAvailable*(): bool =
  getEnv("XDG_SESSION_TYPE") == "wayland"

template isXselAvailable*(): bool =
  isXAvailable() and execCmdEx("xsel --version").exitCode == 0

template isXclipAvailable*(): bool =
  isXAvailable() and execCmdEx("xclip -version").exitCode == 0

template isWlClipboardAvailable*(): bool =
  isWaylandAvailable() and execCmdEx("wl-paste --version").exitCode == 0

template isToolAvailable*(tool: ClipboardTool): bool =
  case tool:
    of xsel: isXselAvailable()
    of xclip: isXclipAvailable()
    of wlClipboard: isWlClipboardAvailable()
    of wslDefault: getPlatform() == Platform.wsl
    else: false

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
          of wlClipboard: wlClipboardCopyCommand(delimiterStr, buf)
          of wslDefault: wslDefaultCopyCommand(delimiterStr, buf)
          of macOsDefault: macOsDefaultCopyCommand(delimiterStr, buf)

    if not isToolAvailable(tool):
      return Result[(), string].err fmt"Error: Clipboard: {tool} not found"

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
